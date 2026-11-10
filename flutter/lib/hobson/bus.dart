import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Messages the controlled PC sends back on the Hobson chat channel.
class HobsonBus {
  static final clips = ValueNotifier<List<String>>(const []);
  static final alert = ValueNotifier<String>('');
  static final previews = ValueNotifier<Map<String, Uint8List>>(const {});
  static final windows = ValueNotifier<List<String>>(const []);
  static final windowFrame = ValueNotifier<Uint8List?>(null);
  static final refusedId = ValueNotifier<String>('');
  static final refusedName = ValueNotifier<String>('');

  static bool ingest(String peerId, String text) {
    if (!text.startsWith('hobson:')) return false;
    if (text.startsWith('hobson:clips ')) {
      final raw = text.substring('hobson:clips '.length);
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          clips.value = decoded.map((item) => item.toString()).where((s) => s.isNotEmpty).toList();
        }
      } catch (_) {}
      return true;
    }
    if (text.startsWith('hobson:alert ')) {
      alert.value = text.substring('hobson:alert '.length).trim();
      return true;
    }
    if (text.startsWith('hobson:frame ')) {
      final bytes = _decode(text.substring('hobson:frame '.length));
      if (bytes != null && peerId.isNotEmpty) {
        previews.value = {...previews.value, peerId: bytes};
      }
      return true;
    }
    if (text.startsWith('hobson:windows ')) {
      final body = text.substring('hobson:windows '.length);
      windows.value = body
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
      return true;
    }
    if (text.startsWith('hobson:winframe ')) {
      windowFrame.value = _decode(text.substring('hobson:winframe '.length));
      return true;
    }
    return true;
  }

  static Uint8List? _decode(String body) {
    try {
      final bytes = base64Decode(body.trim());
      if (bytes.isEmpty) return null;
      return bytes;
    } catch (_) {
      return null;
    }
  }
}
