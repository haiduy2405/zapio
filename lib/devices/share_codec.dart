import 'dart:convert';
import 'dart:io' show gzip;

import 'package:shared_preferences/shared_preferences.dart';

import 'device_store.dart';

/// Packs saved devices into a compact text for a QR code, so a remote set up
/// on one phone can be copied to another phone running Zapio.
///
/// Format: "ZAPIO1:" + base64url(gzip(json)). The JSON holds each device
/// (name, kind, category, remote id or IP) and, for air conditioners, the
/// last state. Wi-Fi pairing tokens are never shared: the new phone pairs
/// with the TV itself.
class ShareCodec {
  static const prefix = 'ZAPIO1:';

  static Future<String> encode(List<SavedDevice> devices) async {
    final prefs = await SharedPreferences.getInstance();
    final list = [
      for (final d in devices)
        {
          'n': d.name,
          'k': d.kind.name,
          'c': d.category,
          if (d.remoteId != null) 'r': d.remoteId,
          if (d.ip != null) 'i': d.ip,
          if (prefs.getString('ac_state_${d.id}') != null)
            'a': prefs.getString('ac_state_${d.id}'),
        }
    ];
    final bytes = gzip.encode(utf8.encode(jsonEncode({'v': 1, 'd': list})));
    return prefix + base64Url.encode(bytes).replaceAll('=', '');
  }

  /// Returns the devices in [text] (with fresh ids), or null if it is not a
  /// Zapio share code. AC states are returned keyed by the new device id.
  static (List<SavedDevice>, Map<String, String>)? decode(String text, String Function() newId) {
    final t = text.trim();
    if (!t.startsWith(prefix)) return null;
    try {
      var b64 = t.substring(prefix.length);
      while (b64.length % 4 != 0) {
        b64 += '=';
      }
      final j = jsonDecode(utf8.decode(gzip.decode(base64Url.decode(b64)))) as Map<String, dynamic>;
      final devices = <SavedDevice>[];
      final states = <String, String>{};
      for (final e in (j['d'] as List)) {
        final m = e as Map<String, dynamic>;
        final kind = DeviceKind.values.asNameMap()[m['k']];
        if (kind == null) continue; // made by a newer Zapio
        final d = SavedDevice(
          id: newId(),
          name: m['n'] as String,
          kind: kind,
          category: m['c'] as String,
          remoteId: m['r'] as String?,
          ip: m['i'] as String?,
        );
        devices.add(d);
        final a = m['a'] as String?;
        if (a != null) states[d.id] = a;
      }
      return (devices, states);
    } catch (_) {
      return null;
    }
  }

  /// Adds imported devices (and AC states) to the store.
  static Future<void> import(List<SavedDevice> devices, Map<String, String> states) async {
    final prefs = await SharedPreferences.getInstance();
    for (final e in states.entries) {
      await prefs.setString('ac_state_${e.key}', e.value);
    }
    for (final d in devices) {
      await DeviceStore.instance.add(d);
    }
  }

  /// Copy of [d] with a new id (and its AC state), saved right away.
  static Future<SavedDevice> duplicate(SavedDevice d, String name) async {
    final store = DeviceStore.instance;
    final copy = SavedDevice(
      id: store.newId(),
      name: name,
      kind: d.kind,
      category: d.category,
      remoteId: d.remoteId,
      ip: d.ip,
    );
    final prefs = await SharedPreferences.getInstance();
    final ac = prefs.getString('ac_state_${d.id}');
    if (ac != null) await prefs.setString('ac_state_${copy.id}', ac);
    await store.add(copy);
    return copy;
  }
}
