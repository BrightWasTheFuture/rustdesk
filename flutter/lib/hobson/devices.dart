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
    required this.enabled,
    required this.role,
    required this.profile,
    required this.qualityFromPhone,
    required this.qualityFromDesktop,
  });

  final String slot;
  final String name;
  final String hostname;
  final String id;
  final String os;
  final String mac;
  final String lanPrefix;
  final bool enabled;
  final String role;
  final String profile;
  final String qualityFromPhone;
  final String qualityFromDesktop;

  bool get hasId => id.isNotEmpty && enabled;
  bool get canWake => mac.isNotEmpty;
  bool get isHelper => role == 'helper';

  static HobsonDevice fromJson(Map<String, dynamic> json) {
    return HobsonDevice(
      slot: (json['slot'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      hostname: (json['hostname'] ?? '').toString(),
      id: (json['id'] ?? '').toString().replaceAll(' ', ''),
      os: (json['os'] ?? '').toString(),
      mac: (json['mac'] ?? '').toString(),
      lanPrefix: (json['lan_prefix'] ?? '').toString(),
      enabled: json['enabled'] != false,
      role: (json['role'] ?? '').toString(),
      profile: (json['profile'] ?? '').toString(),
      qualityFromPhone: (json['quality_from_phone'] ?? '').toString(),
      qualityFromDesktop: (json['quality_from_desktop'] ?? '').toString(),
    );
  }
}

class HobsonDevices {
  HobsonDevices({
    required this.displayName,
    required this.relayByDefault,
    required this.privacyByDefault,
    required this.idleMinutes,
    required this.freeSpaceGb,
    required this.clipboardHistory,
    required this.devices,
  });

  final String displayName;
  final bool relayByDefault;
  final bool privacyByDefault;
  final int idleMinutes;
  final int freeSpaceGb;
  final int clipboardHistory;
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
      idleMinutes: int.tryParse('${json['idle_disconnect_minutes']}') ?? 0,
      freeSpaceGb: int.tryParse('${json['free_space_gb']}') ?? 10,
      clipboardHistory: int.tryParse('${json['clipboard_history']}') ?? 10,
      devices: list,
    );
  }
}
