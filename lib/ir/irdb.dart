import 'dart:convert';
import 'dart:io' show gzip;

import 'package:flutter/services.dart';

import 'ir_file.dart';

/// One IR remote from the bundled DB (assets/irdb/<Category>.json.gz).
class IrRemote {
  IrRemote({
    required this.id,
    required this.category,
    required this.brand,
    required this.model,
    required this.provenance,
    required this.keys,
    required this.signals,
  });

  final String id;
  final String category;
  final String brand;
  final String model;

  /// Source tag of the record ("kk", "xm", "mx", "other") – see NOTICE.md.
  final String provenance;

  /// Standard key id (PWR, VOL_UP, CH_DOWN, OK…) -> index in [signals].
  final Map<String, int> keys;
  final List<IrSignal> signals;

  IrSignal? key(String std) {
    final i = keys[std];
    return i == null || i >= signals.length ? null : signals[i];
  }

  IrSignal? get power => key('PWR') ?? _guessPower();

  IrSignal? _guessPower() {
    for (final s in signals) {
      final n = s.name.toLowerCase();
      if (n.contains('power') || n == 'pwr' || n.contains('on/off')) return s;
    }
    return signals.isEmpty ? null : signals.first;
  }
}

/// A set of remotes that share the same power code: one probe step.
class ProbeGroup {
  ProbeGroup(this.power, this.remotes);
  final IrSignal power;
  final List<IrRemote> remotes;

  /// Remote with the most mapped keys = best default for the group.
  IrRemote get best =>
      remotes.reduce((a, b) => b.keys.length > a.keys.length ? b : a);
}

class IrDb {
  static final Map<String, List<IrRemote>> _cache = {};

  static Future<List<IrRemote>> category(String cat) async {
    final c = _cache[cat];
    if (c != null) return c;
    final bytes = await rootBundle.load('assets/irdb/$cat.json.gz');
    final text = utf8.decode(gzip.decode(bytes.buffer.asUint8List(
        bytes.offsetInBytes, bytes.lengthInBytes)));
    final j = jsonDecode(text) as Map<String, dynamic>;
    final list = <IrRemote>[];
    for (final r in (j['remotes'] as List)) {
      final m = r as Map<String, dynamic>;
      list.add(IrRemote(
        id: m['id'] as String,
        category: cat,
        brand: m['brand'] as String,
        model: m['model'] as String,
        provenance: m['prov'] as String,
        keys: (m['keys'] as Map<String, dynamic>)
            .map((k, v) => MapEntry(k, (v as num).toInt())),
        signals: [for (final s in (m['s'] as List)) _signal(s as List)],
      ));
    }
    return _cache[cat] = list;
  }

  static IrSignal _signal(List s) {
    if (s[1] is String) {
      return IrSignal.parsed(
        name: s[0] as String,
        protocol: s[1] as String,
        address: (s[2] as num).toInt(),
        command: (s[3] as num).toInt(),
      );
    }
    return IrSignal.raw(
      name: s[0] as String,
      frequency: (s[1] as num).toInt(),
      data: [for (final v in (s[2] as List)) (v as num).toInt()],
    );
  }

  static Future<IrRemote?> byId(String cat, String id) async {
    for (final r in await category(cat)) {
      if (r.id == id) return r;
    }
    return null;
  }

  static List<String> brands(List<IrRemote> remotes) {
    final count = <String, int>{};
    for (final r in remotes) {
      count[r.brand] = (count[r.brand] ?? 0) + 1;
    }
    return count.keys.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  /// Groups a brand's remotes by identical power code, most common first,
  /// so the probe flow tries the likeliest code first and never repeats one.
  static List<ProbeGroup> probeGroups(List<IrRemote> remotes, String brand) {
    final groups = <String, ProbeGroup>{};
    for (final r in remotes.where((r) => r.brand == brand)) {
      final p = r.power;
      if (p == null) continue;
      final sig = signature(p);
      final g = groups[sig];
      if (g == null) {
        groups[sig] = ProbeGroup(p, [r]);
      } else {
        g.remotes.add(r);
      }
    }
    return groups.values.toList()
      ..sort((a, b) => b.remotes.length.compareTo(a.remotes.length));
  }

  static String signature(IrSignal s) {
    if (!s.isRaw) return '${s.protocol}:${s.address}:${s.command}';
    final head = s.data.take(40).map((d) => (d / 150).round()).join(',');
    return 'raw:${(s.frequency / 1000).round()}:$head';
  }
}

/// Popular brands shown first in the brand picker.
const popularBrands = [
  'Samsung', 'LG', 'Sony', 'TCL', 'Xiaomi', 'Panasonic', 'Sharp', 'Toshiba',
  'Hisense', 'Philips', 'Skyworth', 'Midea', 'Senko', 'KDK', 'Epson', 'BenQ',
  'ViewSonic', 'Optoma', 'Yamaha', 'Denon', 'Pioneer', 'JBL',
];
