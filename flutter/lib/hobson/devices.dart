import 'dart:convert';

import 'package:flutter/services.dart';

import 'config.dart';

/// One row of [kHobsonDevicesAsset]. Edit that JSON, then rebuild.
class HobsonDevice {
  HobsonDevice({
    required this.slot,
    required this.name,
    required this.hostname,
    required this.id,
    required this.os,
    required this.mac,
    required this.lanPrefix,
  });

  final String slot;
  final String name;
  final String hostname;
  final String id;
  final String os;
  final String mac;
  final String lanPrefix;

  bool get hasId => id.isNotEmpty;
  bool get canWake => mac.isNotEmpty;

  static HobsonDevice fromJson(Map<String, dynamic> json) {
    return HobsonDevice(
      slot: (json['slot'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      hostname: (json['hostname'] ?? '').toString(),
      id: (json['id'] ?? '').toString().replaceAll(' ', ''),
      os: (json['os'] ?? '').toString(),
      mac: (json['mac'] ?? '').toString(),
      lanPrefix: (json['lan_prefix'] ?? '').toString(),
    );
  }
}

class HobsonDevices {
  HobsonDevices({
    required this.displayName,
    required this.relayByDefault,
    required this.privacyByDefault,
    required this.devices,
  });

  final String displayName;
  final bool relayByDefault;
  final bool privacyByDefault;
  final List<HobsonDevice> devices;

  static const asset = 'assets/hobson_devices.json';

  static Future<HobsonDevices> load() async {
    final raw = await rootBundle.loadString(asset);
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final list = (json['devices'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(HobsonDevice.fromJson)
        .toList();
    return HobsonDevices(
      displayName: (json['display_name'] ?? kHobsonDisplayName).toString(),
      relayByDefault: json['relay_by_default'] != false,
      privacyByDefault: json['privacy_on_trusted_windows'] == true,
      devices: list,
    );
  }
}
