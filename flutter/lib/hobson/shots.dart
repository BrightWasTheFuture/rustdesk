import 'dart:async';
import 'dart:typed_data';

/// Screenshot follow-up for the Hobson session button and the monitor sheet.
class HobsonShots {
  static bool shareNext = false;
  static Completer<Uint8List?>? pending;
}
