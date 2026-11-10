import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_hbb/models/platform_model.dart';

import 'shots.dart';

Future<void> showHobsonMonitors(BuildContext context, FFI ffi) {
  final displays = ffi.ffiModel.pi.displays.toList();
  if (displays.isEmpty) return Future.value();
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => _MonitorSheet(ffi: ffi, displays: displays),
  );
}

class _MonitorSheet extends StatefulWidget {
  const _MonitorSheet({required this.ffi, required this.displays});

  final FFI ffi;
  final List<Display> displays;

  @override
  State<_MonitorSheet> createState() => _MonitorSheetState();
}

class _MonitorSheetState extends State<_MonitorSheet> {
  late final List<Uint8List?> _shots = List<Uint8List?>.filled(widget.displays.length, null);

  @override
  void initState() {
    super.initState();
    _fill();
  }

  Future<void> _fill() async {
    for (var i = 0; i < widget.displays.length; i++) {
      if (!mounted) return;
      final pending = Completer<Uint8List?>();
      HobsonShots.pending = pending;
      await bind.sessionTakeScreenshot(sessionId: widget.ffi.sessionId, display: i);
      Uint8List? bytes;
      try {
        bytes = await pending.future.timeout(const Duration(seconds: 8));
      } catch (_) {
        if (!pending.isCompleted) pending.complete(null);
        if (identical(HobsonShots.pending, pending)) HobsonShots.pending = null;
      }
      if (!mounted) return;
      setState(() => _shots[i] = bytes);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Monitors'),
      content: SizedBox(
        width: 420,
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < widget.displays.length; i++)
              InkWell(
                onTap: () {
                  bind.sessionSwitchDisplay(
                    isDesktop: isDesktop,
                    sessionId: widget.ffi.sessionId,
                    value: Int32List.fromList([i]),
                  );
                  Navigator.pop(context);
                },
                child: SizedBox(
                  width: 180,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: 100,
                        width: 180,
                        child: _shots[i] == null
                            ? const ColoredBox(
                                color: Color(0x11000000),
                                child: Center(child: Text('…')),
                              )
                            : Image.memory(_shots[i]!, fit: BoxFit.cover),
                      ),
                      Text('${widget.displays[i].width}×${widget.displays[i].height}'),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
