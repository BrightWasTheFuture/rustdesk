/// One-shot instruction applied when the next Hobson session becomes ready.
class HobsonCommand {
  HobsonCommand({
    this.chat,
    this.quality,
    this.closeAfter = false,
    this.helper = false,
  });

  final String? chat;
  final String? quality;
  final bool closeAfter;
  final bool helper;

  static final Map<String, HobsonCommand> _pending = {};
  static bool helperActive = false;

  static void queue(String peerId, HobsonCommand command) {
    _pending[peerId] = command;
    if (command.helper) helperActive = true;
  }

  static HobsonCommand? take(String peerId) {
    return _pending.remove(peerId);
  }
}
