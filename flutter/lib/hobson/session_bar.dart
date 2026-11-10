import 'package:flutter/material.dart';

import 'command.dart';

/// Session controls kept for this private build. Callers supply the actions
/// so this file does not import the shared client library (that library
/// already imports the toolbar).
class HobsonSessionBar extends StatelessWidget {
  const HobsonSessionBar({
    super.key,
    required this.privacyOn,
    required this.onFullscreen,
    required this.onFile,
    required this.onClipboard,
    required this.onCad,
    required this.onPrivacy,
    this.showPrivacy = true,
    required this.onClose,
    required this.onScreenshot,
    required this.onMonitors,
    required this.onLowData,
    required this.onWindow,
  });

  final bool privacyOn;
  final VoidCallback onFullscreen;
  final VoidCallback onFile;
  final VoidCallback onClipboard;
  final VoidCallback onCad;
  final VoidCallback onPrivacy;
  final bool showPrivacy;
  final VoidCallback onClose;
  final VoidCallback onScreenshot;
  final VoidCallback onMonitors;
  final VoidCallback onLowData;
  final VoidCallback onWindow;

  @override
  Widget build(BuildContext context) {
    final helper = HobsonCommand.helperActive;
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(8),
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (helper)
              TextButton(
                onPressed: () {
                  HobsonCommand.helperActive = false;
                  onClose();
                },
                child: const Text('Helper has control · Take back'),
              ),
            _button(
              tooltip: 'Fullscreen',
              icon: Icons.fullscreen,
              onPressed: onFullscreen,
            ),
            _button(
              tooltip: 'Transfer file',
              icon: Icons.drive_folder_upload_outlined,
              onPressed: onFile,
            ),
            _button(
              tooltip: 'Clipboard',
              icon: Icons.content_paste,
              onPressed: onClipboard,
            ),
            _button(
              tooltip: 'Ctrl + Alt + Del',
              icon: Icons.keyboard,
              onPressed: onCad,
            ),
            if (showPrivacy)
              _button(
                tooltip: privacyOn ? 'Privacy screen on' : 'Blank physical screen',
                icon: privacyOn ? Icons.visibility_off : Icons.visibility,
                onPressed: onPrivacy,
              ),
            _button(
              tooltip: 'Screenshot',
              icon: Icons.photo_camera_outlined,
              onPressed: onScreenshot,
            ),
            PopupMenuButton<String>(
              tooltip: 'More',
              onSelected: (value) {
                if (value == 'monitors') onMonitors();
                if (value == 'low') onLowData();
                if (value == 'window') onWindow();
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'monitors', child: Text('Monitors')),
                PopupMenuItem(value: 'low', child: Text('Low data')),
                PopupMenuItem(value: 'window', child: Text('One window')),
              ],
            ),
            _button(
              tooltip: 'Disconnect',
              icon: Icons.close,
              color: Colors.red,
              onPressed: onClose,
            ),
          ],
        ),
      ),
    );
  }

  Widget _button({
    required String tooltip,
    required IconData icon,
    required VoidCallback onPressed,
    Color? color,
  }) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, color: color, size: 20),
    );
  }
}
