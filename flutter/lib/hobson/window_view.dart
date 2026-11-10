import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_hbb/models/platform_model.dart';

import 'bus.dart';

/// Low-frame stills of one remote window. The desktop video subscription is
/// dropped on the controlled PC while this is running.
Future<void> showHobsonWindow(BuildContext context, FFI ffi) async {
  HobsonBus.windows.value = const [];
  HobsonBus.windowFrame.value = null;
  await bind.sessionSendChat(sessionId: ffi.sessionId, text: 'hobson:windows');
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('One window'),
        content: SizedBox(
          width: 420,
          child: ValueListenableBuilder<Uint8List?>(
            valueListenable: HobsonBus.windowFrame,
            builder: (context, frame, _) {
              return ValueListenableBuilder<List<String>>(
                valueListenable: HobsonBus.windows,
                builder: (context, titles, _) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (frame != null)
                        Image.memory(frame, height: 180, fit: BoxFit.contain),
                      SizedBox(
                        height: 220,
                        child: ListView(
                          children: [
                            for (final title in titles)
                              ListTile(
                                dense: true,
                                title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                                onTap: () {
                                  bind.sessionSendChat(
                                    sessionId: ffi.sessionId,
                                    text: 'hobson:window $title',
                                  );
                                },
                              ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              bind.sessionSendChat(sessionId: ffi.sessionId, text: 'hobson:window stop');
              Navigator.pop(dialogContext);
            },
            child: const Text('Back to desktop'),
          ),
        ],
      );
    },
  );
}
