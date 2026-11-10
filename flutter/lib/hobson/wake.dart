import 'dart:io';
import 'dart:typed_data';

import 'devices.dart';

/// Broadcast a Wake-on-LAN magic packet. This only works when the sender is
/// on the same LAN as the target (the PC is on 192.168.0.x) and the PC's BIOS
/// and NIC have Wake-on-LAN enabled.
Future<void> sendWakeOnLan(HobsonDevice device) async {
  final mac = _parseMac(device.mac);
  if (mac == null) {
    throw FormatException('MAC address is not 6 bytes: ${device.mac}');
  }
  final packet = Uint8List(6 + 16 * 6);
  for (var i = 0; i < 6; i++) {
    packet[i] = 0xff;
  }
  for (var repeat = 0; repeat < 16; repeat++) {
    packet.setRange(6 + repeat * 6, 12 + repeat * 6, mac);
  }
  final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  socket.broadcastEnabled = true;
  final targets = <InternetAddress>[InternetAddress('255.255.255.255')];
  if (device.lanPrefix.isNotEmpty) {
    targets.add(InternetAddress('${device.lanPrefix}255'));
  }
  for (final address in targets) {
    socket.send(packet, address, 9);
    socket.send(packet, address, 7);
  }
  socket.close();
}

Future<void> lockThisWindowsPc() async {
  if (!Platform.isWindows) return;
  await Process.run('rundll32.exe', ['user32.dll,LockWorkStation']);
}

/// Free bytes on C:, or null when this is not Windows or the query fails.
Future<int?> windowsFreeBytes() async {
  if (!Platform.isWindows) return null;
  final result = await Process.run('powershell', [
    '-NoProfile',
    '-Command',
    '(Get-CimInstance Win32_LogicalDisk -Filter "DeviceID=\'C:\'").FreeSpace',
  ]);
  return int.tryParse(result.stdout.toString().trim());
}

List<int>? _parseMac(String mac) {
  final parts = mac.split(RegExp(r'[-:]'));
  if (parts.length != 6) return null;
  final bytes = <int>[];
  for (final part in parts) {
    final value = int.tryParse(part, radix: 16);
    if (value == null || value > 255) return null;
    bytes.add(value);
  }
  return bytes;
}
