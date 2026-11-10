import 'dart:async';
import 'dart:convert';

import 'package:flutter_hbb/generated_bridge.dart'
    if (dart.library.html) 'package:flutter_hbb/web/bridge.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:uuid/uuid.dart';

import 'bus.dart';

/// One short chat-only session. The peer sees `hobson-sync:` and does not
/// start a video stream. Used for clipboard history, alerts, and tile previews.
class HobsonSync {
  static bool _running = false;

  static Future<void> one(
    String id, {
    required bool relay,
    required List<String> clips,
  }) async {
    if (_running || id.isEmpty) return;
    _running = true;
    StreamSubscription<EventToUI>? sub;
    final sid = Uuid().v4obj();
    try {
      await bind.mainSetLocalOption(key: 'hobson-intent', value: 'sync');
      final err = bind.sessionAddSync(
        sessionId: sid,
        id: id,
        isFileTransfer: false,
        isViewCamera: false,
        isPortForward: false,
        isRdp: false,
        isTerminal: false,
        switchUuid: '',
        forceRelay: relay,
        password: '',
        isSharedPassword: false,
        connToken: null,
        loginMethod: '',
      );
      if (err.isNotEmpty) return;
      final ready = Completer<void>();
      sub = bind.sessionStart(sessionId: sid, id: id).listen((message) {
        if (message is! EventToUI_Event) return;
        Map<String, dynamic>? event;
        try {
          final decoded = jsonDecode(message.field0);
          if (decoded is Map<String, dynamic>) event = decoded;
        } catch (_) {}
        if (event == null) return;
        final name = event['name'];
        if (name == 'peer_info' && !ready.isCompleted) {
          ready.complete();
        }
        if (name == 'chat_client_mode') {
          HobsonBus.ingest(id, (event['text'] ?? '').toString());
        }
        if (name == 'msgbox' && !ready.isCompleted) {
          ready.complete();
        }
      });
      await ready.future.timeout(const Duration(seconds: 12));
      final payload = jsonEncode(clips.take(10).toList());
      await bind.sessionSendChat(sessionId: sid, text: 'hobson:clips $payload');
      await Future<void>.delayed(const Duration(seconds: 2));
    } catch (_) {
    } finally {
      await sub?.cancel();
      try {
        await bind.sessionClose(sessionId: sid);
      } catch (_) {}
      _running = false;
    }
  }
}
