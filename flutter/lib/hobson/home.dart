import 'dart:async';
import 'dart:convert';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/pages/desktop_setting_page.dart';
import 'package:flutter_hbb/mobile/pages/settings_page.dart';
import 'package:flutter_hbb/models/platform_model.dart';

import 'bus.dart';
import 'command.dart';
import 'config.dart';
import 'devices.dart';
import 'log_page.dart';
import 'pending_send.dart';
import 'sync.dart';
import 'wake.dart';

/// Three-device home. The old ID box stays in the tree for advanced settings;
/// this is what opens on launch.
class HobsonHome extends StatefulWidget {
  const HobsonHome({super.key});

  @override
  State<HobsonHome> createState() => _HobsonHomeState();
}

class _HobsonHomeState extends State<HobsonHome> with WidgetsBindingObserver {
  HobsonDevices? _config;
  String _myId = '';
  String _error = '';
  final Map<String, bool?> _online = {};
  Timer? _poll;
  Timer? _syncTimer;
  int _syncSlot = 0;
  bool _relay = true;
  bool _privacy = false;
  final _prompt = TextEditingController();
  List<String> _clips = [];
  String _alert = '';
  String _freeSpace = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    platformFFI.registerEventHandler(
        'callback_query_onlines', 'hobson-home', _onOnlines,
        replace: true);
    _load();
    _poll = Timer.periodic(const Duration(seconds: 15), (_) => _queryOnline());
    HobsonBus.clips.addListener(_onBus);
    HobsonBus.alert.addListener(_onBus);
    HobsonBus.previews.addListener(_onBus);
    HobsonBus.refusedId.addListener(_onBus);
  }

  @override
  void dispose() {
    _prompt.dispose();
    _poll?.cancel();
    _syncTimer?.cancel();
    HobsonBus.clips.removeListener(_onBus);
    HobsonBus.alert.removeListener(_onBus);
    HobsonBus.previews.removeListener(_onBus);
    HobsonBus.refusedId.removeListener(_onBus);
    WidgetsBinding.instance.removeObserver(this);
    platformFFI.unregisterEventHandler('callback_query_onlines', 'hobson-home');
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _queryOnline();
      _takeSharedFiles();
      _takeSharedText();
      _takePanicIntent();
      _noteClipboard();
      _loadAlert();
      _loadRefused();
    }
  }

  Future<void> _load() async {
    try {
      final config = await HobsonDevices.load();
      final myId = await bind.mainGetMyId();
      final relayOption = bind.mainGetLocalOption(key: kHobsonRelayOption);
      final privacyOption = bind.mainGetLocalOption(key: kHobsonPrivacyOption);
      if (!mounted) return;
      setState(() {
        _config = config;
        _myId = myId;
        _relay = relayOption.isEmpty
            ? config.relayByDefault
            : relayOption == 'Y';
        _privacy = privacyOption.isEmpty
            ? config.privacyByDefault
            : privacyOption == 'Y';
        _error = '';
        _clips = _readClips();
      });
      if (_clips.isNotEmpty) HobsonBus.clips.value = _clips;
      _startSync();
      _queryOnline();
      _takeSharedFiles();
      _takeSharedText();
      _takePanicIntent();
      _noteClipboard();
      _loadAlert();
      _loadFreeSpace();
      _loadRefused();
    } catch (err) {
      if (mounted) setState(() => _error = '$err');
    }
  }

  Future<void> _onOnlines(Map<String, dynamic> evt) async {
    final onlines = (evt['onlines'] ?? '').toString().split(',');
    final offlines = (evt['offlines'] ?? '').toString().split(',');
    for (final id in onlines) {
      if (id.isNotEmpty) _online[id] = true;
    }
    for (final id in offlines) {
      if (id.isNotEmpty) _online[id] = false;
    }
    if (mounted) setState(() {});
  }

  void _queryOnline() {
    final ids = _config?.devices
            .where((device) => device.hasId && device.id != _myId)
            .map((device) => device.id)
            .toList() ??
        [];
    if (ids.isEmpty) return;
    bind.queryOnlines(ids: ids);
  }

  Future<void> _takeSharedFiles() async {
    if (!isAndroid || _config == null) return;
    final raw = await gFFI.invokeMethodWithResult<List<dynamic>>(
        'hobson_take_shared');
    if (raw == null || raw.isEmpty || !mounted) return;
    final paths = raw.map((item) => item.toString()).where((p) => p.isNotEmpty).toList();
    if (paths.isEmpty) return;
    final targets = _config!.devices
        .where((device) => device.hasId && device.id != _myId)
        .toList();
    if (targets.isEmpty) {
      _toast('Add a device ID before sending files');
      return;
    }
    final picked = await showDialog<HobsonDevice>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('Send ${paths.length} file${paths.length == 1 ? '' : 's'}'),
        children: [
          for (final device in targets)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, device),
              child: Text('${device.name}  ·  ${device.hostname}'),
            ),
        ],
      ),
    );
    if (picked == null) return;
    _sendFiles(picked, paths);
  }

  Future<void> _connect(HobsonDevice device) async {
    if (!device.hasId || device.id == _myId) return;
    if (_online[device.id] == false && device.canWake) {
      await _wakeThenConnect(device);
      return;
    }
    await _applyProfile(device);
    if (!mounted) return;
    connect(context, device.id);
  }

  Future<void> _wakeThenConnect(HobsonDevice device) async {
    _toast('Waking ${device.name}. Connecting when it comes online.');
    try {
      await sendWakeOnLan(device);
    } catch (err) {
      _toast('Wake failed: $err');
      return;
    }
    for (var i = 0; i < 30; i++) {
      await Future<void>.delayed(const Duration(seconds: 3));
      if (!mounted) return;
      _queryOnline();
      await Future<void>.delayed(const Duration(milliseconds: 800));
      if (_online[device.id] == true) {
        await _applyProfile(device);
        if (!mounted) return;
        connect(context, device.id);
        return;
      }
    }
    _toast('${device.name} did not come online. Try Wake PC again.');
  }

  Future<void> _applyProfile(HobsonDevice device) async {
    final fromPhone = isAndroid;
    final quality = fromPhone
        ? (device.qualityFromPhone.isEmpty ? 'low' : device.qualityFromPhone)
        : (device.qualityFromDesktop.isEmpty
            ? 'best'
            : device.qualityFromDesktop);
    if (fromPhone) {
      await bind.mainSetLocalOption(key: kOptionTouchMode, value: 'Y');
    }
    HobsonCommand.helperActive = device.isHelper;
    HobsonCommand.queue(
        device.id,
        HobsonCommand(
          quality: quality,
          helper: device.isHelper,
        ));
  }

  Future<void> _sendCommand(HobsonDevice device, String chat,
      {bool closeAfter = false}) async {
    HobsonCommand.queue(
        device.id, HobsonCommand(chat: chat, closeAfter: closeAfter));
    if (!mounted) return;
    connect(context, device.id);
  }

  Future<void> _panic() async {
    await bind.mainSetLocalOption(key: 'hobson-panic', value: 'Y');
    final others = _config?.devices
            .where((device) =>
                device.hasId && device.id != _myId && device.os == 'windows')
            .toList() ??
        [];
    for (final device in others) {
      await _sendCommand(device, 'hobson:panic', closeAfter: true);
    }
    await lockThisWindowsPc();
    _toast('Panic lock is on. A listed device must unlock with the trust secret.');
  }

  Future<void> _unlock(HobsonDevice device) async {
    await bind.mainSetLocalOption(key: 'hobson-intent', value: 'unlock');
    if (!mounted) return;
    connect(context, device.id);
  }

  void _sendFiles(HobsonDevice device, List<String> paths) {
    if (!device.hasId || paths.isEmpty) return;
    HobsonPendingSend.queue(device.id, paths);
    connect(context, device.id, isFileTransfer: true);
  }

  Future<void> _wake(HobsonDevice device) async {
    try {
      await sendWakeOnLan(device);
      _toast(
          'Wake packet sent to ${device.name}. It only arrives if this device is on ${device.lanPrefix}x and Wake-on-LAN is enabled on the PC.');
    } catch (err) {
      _toast('Wake failed: $err');
    }
  }

  List<String> _readClips() {
    final raw = bind.mainGetLocalOption(key: 'hobson-clips');
    if (raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.map((item) => item.toString()).where((s) => s.isNotEmpty).toList();
      }
    } catch (_) {}
    return [];
  }

  Future<void> _noteClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty || (_clips.isNotEmpty && _clips.first == text)) return;
    final limit = _config?.clipboardHistory ?? 10;
    final next = [text, ..._clips.where((item) => item != text)]
        .take(limit <= 0 ? 10 : limit)
        .toList();
    await bind.mainSetLocalOption(key: 'hobson-clips', value: jsonEncode(next));
    HobsonBus.clips.value = next;
    if (mounted) setState(() => _clips = next);
    if (_config?.clipboardSync == true) {
      final pc = _pc();
      if (pc != null) {
        unawaited(HobsonSync.one(pc.id, relay: _relay, clips: next));
      }
    }
  }

  Future<void> _loadRefused() async {
    if (HobsonBus.refusedId.value.isNotEmpty) return;
    try {
      final file = await hobsonLogFile();
      if (!await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return;
      for (final item in decoded.reversed) {
        if (item is Map && item['dir'] == 'denied') {
          final id = (item['id'] ?? '').toString();
          if (id.isEmpty) return;
          HobsonBus.refusedId.value = id;
          HobsonBus.refusedName.value = (item['name'] ?? '').toString();
          return;
        }
      }
    } catch (_) {}
  }

  void _onBus() {
    if (!mounted) return;
    setState(() {
      if (HobsonBus.clips.value.isNotEmpty) _clips = HobsonBus.clips.value;
      if (HobsonBus.alert.value.isNotEmpty) _alert = HobsonBus.alert.value;
    });
  }

  void _startSync() {
    final config = _config;
    if (config == null || (!config.clipboardSync && !config.tilePreviews)) {
      return;
    }
    final seconds = config.previewSeconds <= 0 ? 45 : config.previewSeconds;
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(Duration(seconds: seconds), (_) => _syncOne());
  }

  void _syncOne() {
    final config = _config;
    if (config == null || !mounted) return;
    final peers = config.devices
        .where((device) => device.hasId && device.id != _myId && _online[device.id] != false)
        .toList();
    if (peers.isEmpty) return;
    final device = peers[_syncSlot % peers.length];
    _syncSlot += 1;
    unawaited(HobsonSync.one(device.id, relay: _relay, clips: _clips));
  }

  Future<void> _loadAlert() async {
    try {
      final file = await hobsonAlertsFile();
      if (!await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List || decoded.isEmpty) return;
      final last = decoded.last;
      if (last is Map && last['state'] == 'open') {
        final text = (last['text'] ?? '').toString();
        if (mounted && text.isNotEmpty) setState(() => _alert = text);
      }
    } catch (_) {}
  }

  Future<void> _loadFreeSpace() async {
    final config = _config;
    if (!isWindows || config == null || config.freeSpaceGb <= 0) return;
    final bytes = await windowsFreeBytes();
    if (bytes == null || !mounted) return;
    final gb = bytes / (1024 * 1024 * 1024);
    if (gb < config.freeSpaceGb) {
      setState(() => _freeSpace =
          'C: has ${gb.toStringAsFixed(1)} GB free. Threshold is ${config.freeSpaceGb} GB.');
    }
  }

  HobsonDevice? _pc() {
    HobsonDevice? other;
    for (final device in _config?.devices ?? const <HobsonDevice>[]) {
      if (!device.hasId || device.id == _myId || device.os != 'windows') {
        continue;
      }
      if (device.slot == 'pc') return device;
      other ??= device;
    }
    return other;
  }

  Future<void> _pastePrompt() async {
    final text = _prompt.text.trim();
    if (text.isEmpty) return;
    final pc = _pc();
    if (pc == null) {
      _toast('The PC tile has no ID on this device.');
      return;
    }
    final safe = text.replaceAll('\n', ' ');
    await _sendCommand(pc, 'hobson:paste $safe');
  }

  Future<void> _answerAlert(String keys) async {
    final pc = _pc();
    if (pc == null) return;
    setState(() => _alert = '');
    await _sendCommand(pc, 'hobson:keys $keys', closeAfter: true);
  }

  Widget _refusedCard() {
    final id = HobsonBus.refusedId.value;
    final name = HobsonBus.refusedName.value;
    return Card(
      color: Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Refused ID $id',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            if (name.isNotEmpty) Text(name),
            const Text(
                'This ID is not in hobson_devices.json. Add it, then rebuild.'),
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: id));
                _toast('Copied refused ID $id');
              },
              child: const Text('Copy ID'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _alertCard() {
    return Card(
      color: Colors.orange.shade100,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_alert),
            Row(
              children: [
                TextButton(onPressed: () => _answerAlert('y'), child: const Text('Approve')),
                TextButton(onPressed: () => _answerAlert('n'), child: const Text('Deny')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _takeSharedText() async {
    if (!isAndroid || _config == null) return;
    final text = await gFFI.invokeMethodWithResult<String>('hobson_take_text');
    final url = text?.trim() ?? '';
    if (!url.startsWith('http://') && !url.startsWith('https://')) return;
    if (!mounted) return;
    final targets = _config!.devices
        .where((device) => device.hasId && device.id != _myId && device.os == 'windows')
        .toList();
    if (targets.isEmpty) return;
    final picked = await showDialog<HobsonDevice>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Open link on'),
        children: [
          for (final device in targets)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, device),
              child: Text(device.name),
            ),
        ],
      ),
    );
    if (picked == null) return;
    await _sendCommand(picked, 'hobson:open $url', closeAfter: true);
  }

  Future<void> _takePanicIntent() async {
    if (!isAndroid) return;
    final action = await gFFI.invokeMethodWithResult<String>('hobson_take_panic');
    if (action == 'panic') await _panic();
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _openSettings() {
    if (isDesktop) {
      if (DesktopSettingPage.tabKeys.isNotEmpty) {
        DesktopSettingPage.switch2page(DesktopSettingPage.tabKeys.first);
      }
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SettingsPage()),
    );
  }

  void _openLog() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const HobsonLogPage()),
    );
  }

  Future<void> _setRelay(bool value) async {
    await bind.mainSetLocalOption(
        key: kHobsonRelayOption, value: value ? 'Y' : 'N');
    if (mounted) setState(() => _relay = value);
  }

  Future<void> _setPrivacy(bool value) async {
    await bind.mainSetLocalOption(
        key: kHobsonPrivacyOption, value: value ? 'Y' : 'N');
    if (mounted) setState(() => _privacy = value);
  }

  @override
  Widget build(BuildContext context) {
    final body = _body(context);
    if (isDesktop) return body;
    return Scaffold(
      appBar: AppBar(
        title: Text(_config?.displayName ?? kHobsonDisplayName),
        actions: _actions(),
      ),
      body: body,
    );
  }

  List<Widget> _actions() {
    return [
      IconButton(
        tooltip: 'Connections',
        onPressed: _openLog,
        icon: const Icon(Icons.history),
      ),
      IconButton(
        tooltip: 'Settings',
        onPressed: _openSettings,
        icon: const Icon(Icons.settings),
      ),
    ];
  }

  Widget _body(BuildContext context) {
    if (_error.isNotEmpty) {
      return Center(child: Text(_error));
    }
    final config = _config;
    if (config == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (isDesktop)
          Row(
            children: [
              Text(config.displayName,
                  style: Theme.of(context).textTheme.headlineSmall),
              const Spacer(),
              ..._actions(),
            ],
          ),
        const SizedBox(height: 8),
        Text(
          _myId.isEmpty
              ? 'This device has no RustDesk ID yet'
              : 'This device  ·  ID $_myId',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        if (_myId.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _myId));
                _toast('Copied $_myId');
              },
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Copy ID'),
            ),
          ),
        const SizedBox(height: 12),
        if (HobsonBus.refusedId.value.isNotEmpty) _refusedCard(),
        for (final device in config.devices) ...[
          _tile(context, device),
          const SizedBox(height: 12),
        ],
        if (_alert.isNotEmpty) _alertCard(),
        if (_freeSpace.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(_freeSpace, style: const TextStyle(color: Colors.orange)),
          ),
        TextField(
          controller: _prompt,
          decoration: const InputDecoration(
            labelText: 'Prompt for the PC',
            hintText: 'Typed here, pasted into the focused window on the PC',
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: _pastePrompt,
            child: const Text('Paste into PC'),
          ),
        ),
        if (_clips.isNotEmpty) ...[
          Text('Clipboard', style: Theme.of(context).textTheme.titleSmall),
          for (final clip in _clips)
            ListTile(
              dense: true,
              title: Text(clip, maxLines: 2, overflow: TextOverflow.ellipsis),
              onTap: () {
                Clipboard.setData(ClipboardData(text: clip));
                _toast(
                    'Copied. A connected session receives it through clipboard sync.');
              },
            ),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            onPressed: _panic,
            child: const Text('Panic lock'),
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Always use the relay'),
          subtitle: const Text(
              'Direct connections were reset by the server. Turn this off only to try a direct link again.'),
          value: _relay,
          onChanged: (value) {
            _setRelay(value);
          },
        ),
        if (isWindows)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Blank this screen for trusted sessions'),
            subtitle: const Text(
                'When a listed device connects, turn on RustDesk privacy mode so the physical monitor goes black.'),
            value: _privacy,
            onChanged: (value) {
              _setPrivacy(value);
            },
          ),
        const SizedBox(height: 8),
        Text(
          'Device IDs live in flutter/assets/hobson_devices.json. Drag a file onto a tile to send it to that device\'s Downloads folder.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _tile(BuildContext context, HobsonDevice device) {
    final mine = device.hasId && device.id == _myId;
    final online = device.hasId ? _online[device.id] : null;
    final card = Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_iconFor(device), size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(device.name,
                          style: Theme.of(context).textTheme.titleMedium),
                      Text(device.hostname,
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                _status(online, device, mine),
              ],
            ),
            if (_config?.tilePreviews == true && HobsonBus.previews.value[device.id] != null) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.memory(
                  HobsonBus.previews.value[device.id]!,
                  height: 72,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(!device.enabled
                ? 'Disabled until you turn it on in hobson_devices.json'
                : device.hasId
                    ? 'ID ${device.id}'
                    : 'ID not set yet'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: !device.hasId || mine ? null : () => _connect(device),
                  child: Text(mine ? 'This device' : 'Connect'),
                ),
                if (device.canWake)
                  OutlinedButton(
                    onPressed: () => _wake(device),
                    child: const Text('Wake PC'),
                  ),
                if (device.hasId && !mine && device.os == 'windows')
                  TextButton(
                    onPressed: () => _unlock(device),
                    child: const Text('Unlock'),
                  ),
              ],
            ),
            if (isDesktop && device.hasId && !mine)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Drop a file here to send it',
                    style: Theme.of(context).textTheme.bodySmall),
              ),
          ],
        ),
      ),
    );
    if (!isDesktop || !device.hasId || mine) return card;
    return DropTarget(
      onDragDone: (detail) {
        final paths = detail.files.map((file) => file.path).toList();
        _sendFiles(device, paths);
      },
      child: card,
    );
  }

  IconData _iconFor(HobsonDevice device) {
    switch (device.slot) {
      case 'phone':
        return Icons.smartphone;
      case 'laptop':
        return Icons.laptop;
      default:
        return Icons.desktop_windows;
    }
  }

  Widget _status(bool? online, HobsonDevice device, bool mine) {
    if (mine || !device.hasId) return const SizedBox.shrink();
    final color = online == null
        ? Colors.grey
        : online
            ? Colors.green
            : Colors.red;
    final label = online == null
        ? 'Checking'
        : online
            ? 'Online'
            : 'Offline';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, size: 10, color: color),
        const SizedBox(width: 6),
        Text(label),
      ],
    );
  }
}
