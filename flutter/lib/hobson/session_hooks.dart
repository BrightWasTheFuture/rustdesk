import 'dart:async';

import 'package:flutter_hbb/models/platform_model.dart';

import 'command.dart';

/// Called once the remote peer info has arrived.
void hobsonOnSessionReady(dynamic sessionId, String peerId) {
  final command = HobsonCommand.take(peerId);
  if (command == null) return;
  final quality = command.quality;
  if (quality != null && quality.isNotEmpty) {
    bind.sessionSetImageQuality(sessionId: sessionId, value: quality);
  }
  final chat = command.chat;
  if (chat != null && chat.isNotEmpty) {
    bind.sessionSendChat(sessionId: sessionId, text: chat);
  }
  if (command.closeAfter) {
    Timer(const Duration(seconds: 2), () {
      bind.sessionClose(sessionId: sessionId);
    });
  }
}
