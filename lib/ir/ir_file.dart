import 'dart:convert';

/// One button/signal from a Flipper-format `.ir` file.
class IrSignal {
  IrSignal.parsed({
    required this.name,
    required this.protocol,
    required this.address,
    required this.command,
  })  : isRaw = false,
        frequency = 0,
        data = const [];

  IrSignal.raw({
    required this.name,
    required this.frequency,
    required this.data,
  })  : isRaw = true,
        protocol = null,
        address = 0,
        command = 0;

  final String name;
  final bool isRaw;

  /// Parsed signals: protocol name as written by Flipper (NEC, NECext,
  /// Samsung32, SIRC, SIRC15, SIRC20, RC5, RC5X, RC6...).
  final String? protocol;
  final int address;
  final int command;

  /// Raw signals: carrier frequency (Hz) and mark/space durations (µs),
  /// starting with a mark.
  final int frequency;
  final List<int> data;

  @override
  String toString() => isRaw
      ? 'IrSignal($name, raw ${data.length} @ $frequency)'
      : 'IrSignal($name, $protocol a=0x${address.toRadixString(16)} c=0x${command.toRadixString(16)})';
}

/// Parses the Flipper Zero "IR signals file" text format.
List<IrSignal> parseIrFile(String text) {
  final signals = <IrSignal>[];
  Map<String, String>? cur;

  void flush() {
    final c = cur;
    if (c != null) {
      final s = _build(c);
      if (s != null) signals.add(s);
    }
    cur = null;
  }

  for (final rawLine in const LineSplitter().convert(text)) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final i = line.indexOf(':');
    if (i < 0) continue;
    final key = line.substring(0, i).trim();
    final value = line.substring(i + 1).trim();
    if (key == 'name') {
      flush();
      cur = <String, String>{};
    }
    final c = cur;
    if (c == null) continue;
    if (key == 'data' && c.containsKey('data')) {
      c['data'] = '${c['data']} $value';
    } else {
      c[key] = value;
    }
  }
  flush();
  return signals;
}

IrSignal? _build(Map<String, String> m) {
  final name = m['name'];
  final type = m['type'];
  if (name == null || type == null) return null;
  try {
    if (type == 'raw') {
      final data = m['data']!
          .split(RegExp(r'\s+'))
          .where((e) => e.isNotEmpty)
          .map((e) => int.parse(e).abs())
          .toList();
      if (data.isEmpty) return null;
      return IrSignal.raw(
        name: name,
        frequency: int.tryParse(m['frequency'] ?? '') ?? 38000,
        data: data,
      );
    }
    if (type == 'parsed') {
      return IrSignal.parsed(
        name: name,
        protocol: m['protocol']!,
        address: hexLittleEndian(m['address']!),
        command: hexLittleEndian(m['command']!),
      );
    }
  } catch (_) {
    return null;
  }
  return null;
}

/// "07 00 00 00" -> 0x00000007 (Flipper stores values as little-endian bytes).
int hexLittleEndian(String s) {
  final bytes = s
      .split(RegExp(r'\s+'))
      .where((e) => e.isNotEmpty)
      .map((e) => int.parse(e, radix: 16))
      .toList();
  var v = 0;
  for (var i = bytes.length - 1; i >= 0; i--) {
    v = (v << 8) | (bytes[i] & 0xFF);
  }
  return v;
}
