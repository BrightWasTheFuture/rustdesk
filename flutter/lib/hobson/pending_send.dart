/// Files dropped on a device tile, or shared from another Android app,
/// waiting for that device's file-transfer session to finish logging in.
class HobsonPendingSend {
  static final Map<String, List<String>> _paths = {};

  static void queue(String id, List<String> paths) {
    if (id.isEmpty || paths.isEmpty) return;
    _paths[id] = List<String>.from(paths);
  }

  static List<String> take(String id) {
    return _paths.remove(id) ?? const [];
  }
}
