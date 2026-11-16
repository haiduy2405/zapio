import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum DeviceKind { ir, samsung, lg, roku }

/// A device the user added to "My devices".
class SavedDevice {
  SavedDevice({
    required this.id,
    required this.name,
    required this.kind,
    required this.category,
    this.remoteId,
    this.ip,
  });

  factory SavedDevice.fromJson(Map<String, dynamic> j) => SavedDevice(
        id: j['id'] as String,
        name: j['name'] as String,
        kind: DeviceKind.values.byName(j['kind'] as String),
        category: j['category'] as String,
        remoteId: j['remoteId'] as String?,
        ip: j['ip'] as String?,
      );

  final String id;
  String name;
  final DeviceKind kind;

  /// Cat.* id (TV, Fan, …).
  final String category;

  /// IR devices: id of the IrRemote in the bundled DB.
  String? remoteId;

  /// Wi-Fi devices: IP address on the LAN.
  String? ip;

  bool get isWifi => kind != DeviceKind.ir;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kind': kind.name,
        'category': category,
        if (remoteId != null) 'remoteId': remoteId,
        if (ip != null) 'ip': ip,
      };
}

class DeviceStore extends ChangeNotifier {
  DeviceStore._();
  static final instance = DeviceStore._();

  static const _key = 'devices_v1';
  final List<SavedDevice> devices = [];
  bool loaded = false;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    devices.clear();
    if (raw != null) {
      try {
        devices.addAll((jsonDecode(raw) as List)
            .map((e) => SavedDevice.fromJson(e as Map<String, dynamic>)));
      } catch (_) {}
    }
    loaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(devices.map((d) => d.toJson()).toList()));
    notifyListeners();
  }

  String newId() => DateTime.now().microsecondsSinceEpoch.toRadixString(36);

  Future<void> add(SavedDevice d) async {
    devices.add(d);
    await _save();
  }

  Future<void> update(SavedDevice d) => _save();

  Future<void> remove(SavedDevice d) async {
    devices.removeWhere((e) => e.id == d.id);
    await _save();
  }

  /// Wi-Fi device already saved for this IP + kind?
  SavedDevice? findWifi(DeviceKind kind, String ip) {
    for (final d in devices) {
      if (d.kind == kind && d.ip == ip) return d;
    }
    return null;
  }
}
