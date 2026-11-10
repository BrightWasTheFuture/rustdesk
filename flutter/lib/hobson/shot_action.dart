import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'shots.dart';

/// Saves the cached screenshot. Returns true when Hobson handled it.
Future<bool> hobsonTakeShot(SessionID sessionId) async {
  final pending = HobsonShots.pending;
  if (pending != null) {
    HobsonShots.pending = null;
    final bytes = await _write(sessionId, 'hobson-monitor.png');
    if (!pending.isCompleted) pending.complete(bytes);
    return true;
  }
  if (!HobsonShots.shareNext) return false;
  HobsonShots.shareNext = false;
  final bytes = await _write(
    sessionId,
    'hobson-screenshot.png',
    alsoCopy: Platform.isWindows || Platform.isLinux || Platform.isMacOS,
  );
  if (bytes == null) return true;
  if (Platform.isAndroid) {
    final dir = await getTemporaryDirectory();
    final path = p.join(dir.path, 'hobson-screenshot.png');
    await gFFI.invokeMethod('hobson_share_file', path);
  }
  return true;
}

Future<Uint8List?> _write(SessionID sessionId, String name, {bool alsoCopy = false}) async {
  final dir = await getTemporaryDirectory();
  final path = p.join(dir.path, name);
  final action = alsoCopy ? '3:$path' : '0:$path';
  final error = await bind.sessionHandleScreenshot(sessionId: sessionId, action: action);
  if (error.isNotEmpty) return null;
  final file = File(path);
  if (!await file.exists()) return null;
  return file.readAsBytes();
}
