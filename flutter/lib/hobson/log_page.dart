import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'config.dart';

/// Same file the Rust side writes. Desktop paths follow the `directories`
/// crate (`ProjectDirs::config_dir` for app name `JCBRemote`). Android
/// uses the documents directory passed to `mainInit` as `APP_DIR`.
Future<File> hobsonAlertsFile() async {
  final log = await hobsonLogFile();
  return File(p.join(log.parent.path, 'hobson-alerts.json'));
}

Future<File> hobsonLogFile() async {
  if (Platform.isAndroid) {
    final docs = await getApplicationDocumentsDirectory();
    return File(p.join(docs.path, kHobsonLogFileName));
  }
  final home = Platform.environment['HOME'] ?? '';
  if (Platform.isWindows) {
    final roaming = Platform.environment['APPDATA'] ??
        p.join(home, 'AppData', 'Roaming');
    return File(p.join(roaming, kHobsonAppName, 'config', kHobsonLogFileName));
  }
  if (Platform.isMacOS) {
    return File(p.join(home, 'Library', 'Application Support', kHobsonAppName,
        kHobsonLogFileName));
  }
  final xdg = Platform.environment['XDG_CONFIG_HOME'];
  final base = (xdg != null && xdg.isNotEmpty) ? xdg : p.join(home, '.config');
  return File(p.join(base, kHobsonAppName, kHobsonLogFileName));
}

class HobsonLogEntry {
  HobsonLogEntry(this.json);

  final Map<String, dynamic> json;

  DateTime get time {
    final ms = int.tryParse('${json['t']}') ?? 0;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  String get direction => (json['dir'] ?? '').toString();
  String get id => (json['id'] ?? '').toString();
  String get name => (json['name'] ?? '').toString();
  String get event => (json['ev'] ?? '').toString();
  int get seconds => int.tryParse('${json['secs']}') ?? 0;
  String get ip => (json['ip'] ?? '').toString();

  String get title {
    final who = name.isNotEmpty ? name : (id.isNotEmpty ? id : 'Unknown');
    switch (direction) {
      case 'in':
        return event == 'end' ? 'Incoming ended · $who' : 'Incoming · $who';
      case 'out':
        return event == 'end' ? 'Outgoing ended · $who' : 'Outgoing · $who';
      case 'denied':
        return id.isEmpty ? 'Refused connection' : 'Refused ID $id';
      case 'unlisted':
        return 'Unlisted ID $id connected';
      default:
        return who;
    }
  }

  String get subtitle {
    final clock =
        '${time.year.toString().padLeft(4, '0')}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')} '
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    final bits = <String>[clock];
    if (direction == 'denied') {
      bits.add('Connection refused');
    } else if (id.isNotEmpty) bits.add('ID $id');
    if (event == 'end') bits.add(_formatDuration(seconds));
    if (ip.isNotEmpty) bits.add(ip);
    return bits.join('  ·  ');
  }
}

String _formatDuration(int seconds) {
  if (seconds < 60) return '${seconds}s';
  final minutes = seconds ~/ 60;
  final rest = seconds % 60;
  if (minutes < 60) return '${minutes}m ${rest}s';
  return '${minutes ~/ 60}h ${minutes % 60}m';
}

class HobsonLogPage extends StatefulWidget {
  const HobsonLogPage({super.key});

  @override
  State<HobsonLogPage> createState() => _HobsonLogPageState();
}

class _HobsonLogPageState extends State<HobsonLogPage> {
  List<HobsonLogEntry> _entries = [];
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final file = await hobsonLogFile();
      if (!await file.exists()) {
        if (mounted) {
          setState(() {
            _entries = [];
            _error = '';
          });
        }
        return;
      }
      final decoded = jsonDecode(await file.readAsString());
      final list = (decoded as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .map(HobsonLogEntry.new)
          .toList()
          .reversed
          .toList();
      if (mounted) {
        setState(() {
          _entries = list;
          _error = '';
        });
      }
    } catch (err) {
      if (mounted) setState(() => _error = '$err');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: kJcbBlue,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Connections'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _error.isNotEmpty
          ? Center(child: Text(_error))
          : _entries.isEmpty
              ? const Center(child: Text('No connections yet'))
              : ListView.separated(
                  itemCount: _entries.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final entry = _entries[index];
                    final blocked = entry.direction == 'denied';
                    return ListTile(
                      leading: Icon(
                        blocked
                            ? Icons.block
                            : entry.direction == 'in'
                                ? Icons.call_received
                                : Icons.call_made,
                        color: blocked ? Colors.red : null,
                      ),
                      title: Text(entry.title),
                      subtitle: Text(entry.subtitle),
                    );
                  },
                ),
    );
  }
}
