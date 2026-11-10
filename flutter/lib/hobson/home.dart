import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/desktop/pages/desktop_setting_page.dart';
import 'package:flutter_hbb/mobile/pages/settings_page.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:get/get.dart';

import 'config.dart';
import 'devices.dart';
import 'log_page.dart';
import 'pending_send.dart';
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
  bool _relay = true;
  bool _privacy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    platformFFI.registerEventHandler(
        'callback_query_onlines', 'hobson-home', _onOnlines,
        replace: true);
    _load();
    _poll = Timer.periodic(const Duration(seconds: 15), (_) => _queryOnline());
  }

  @override
  void dispose() {
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    platformFFI.unregisterEventHandler('callback_query_onlines', 'hobson-home');
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _queryOnline();
      _takeSharedFiles();
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
      });
      _queryOnline();
      _takeSharedFiles();
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

  void _connect(HobsonDevice device) {
    if (!device.hasId || device.id == _myId) return;
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
        for (final device in config.devices) ...[
          _tile(context, device),
          const SizedBox(height: 12),
        ],
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
            const SizedBox(height: 8),
            Text(device.hasId ? 'ID ${device.id}' : 'ID not set yet'),
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
