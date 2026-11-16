import 'dart:convert';

import 'package:flutter/services.dart';

import 'ir_file.dart';

/// One remote (one `.ir` file) in the bundled code library.
class IrRemoteEntry {
  IrRemoteEntry({
    required this.category,
    required this.brand,
    required this.model,
    required this.asset,
  });

  factory IrRemoteEntry.fromJson(Map<String, dynamic> j) => IrRemoteEntry(
        category: j['category'] as String,
        brand: j['brand'] as String,
        model: j['model'] as String,
        asset: j['asset'] as String,
      );

  final String category;
  final String brand;
  final String model;
  final String asset;
}

class IrLibrary {
  IrLibrary._(this.entries);
  final List<IrRemoteEntry> entries;

  static IrLibrary? _cache;

  static Future<IrLibrary> load() async {
    final c = _cache;
    if (c != null) return c;
    final text = await rootBundle.loadString('assets/ir/index.json');
    final list = (jsonDecode(text) as List)
        .map((e) => IrRemoteEntry.fromJson(e as Map<String, dynamic>))
        .toList();
    return _cache = IrLibrary._(list);
  }

  List<String> categories() =>
      entries.map((e) => e.category).toSet().toList()..sort();

  List<String> brands(String category) => entries
      .where((e) => e.category == category)
      .map((e) => e.brand)
      .toSet()
      .toList()
    ..sort();

  List<IrRemoteEntry> remotes(String category, String brand) => entries
      .where((e) => e.category == category && e.brand == brand)
      .toList();

  static final Map<String, List<IrSignal>> _signals = {};

  static Future<List<IrSignal>> signalsOf(IrRemoteEntry e) async {
    final c = _signals[e.asset];
    if (c != null) return c;
    final text = await rootBundle.loadString(e.asset);
    return _signals[e.asset] = parseIrFile(text);
  }
}

/// Picks the most likely "power" button of a remote.
IrSignal? findPowerSignal(List<IrSignal> signals) {
  int score(IrSignal s) {
    final n = s.name.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    if (n == 'power' || n == 'pwr' || n == 'tvpwr' || n == 'onoff') return 3;
    if (n.contains('power') || n.contains('pwr')) return 2;
    if (n == 'on' || n.startsWith('on') || n.contains('cool')) return 1;
    return 0;
  }

  IrSignal? best;
  var bestScore = 0;
  for (final s in signals) {
    final sc = score(s);
    if (sc > bestScore) {
      best = s;
      bestScore = sc;
    }
  }
  return best;
}
