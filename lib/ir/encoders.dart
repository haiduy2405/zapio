import 'dart:math' as math;

import 'ir_file.dart';

/// A ready-to-send IR burst: carrier frequency + alternating mark/space
/// durations in microseconds, starting with a mark.
class IrFrame {
  const IrFrame(this.frequency, this.pattern);
  final int frequency;
  final List<int> pattern;

  int get durationUs => pattern.fold(0, (a, b) => a + b);
}

class UnsupportedProtocol implements Exception {
  UnsupportedProtocol(this.protocol);
  final String protocol;
  @override
  String toString() => 'Unsupported IR protocol: $protocol';
}

/// Protocols the encoder can turn into timings.
const supportedProtocols = {
  'NEC', 'NECext', 'NEC42', 'Samsung32', 'SIRC', 'SIRC15', 'SIRC20',
  'RC5', 'RC5X', 'RC6',
};

IrFrame encodeSignal(IrSignal s) {
  if (s.isRaw) {
    return IrFrame(s.frequency, s.data.where((e) => e > 0).toList());
  }
  final a = s.address;
  final c = s.command;
  switch (s.protocol) {
    case 'NEC':
      return IrFrame(38000, _nec([
        ..._lsb(a & 0xFF, 8),
        ..._lsb(~a & 0xFF, 8),
        ..._lsb(c & 0xFF, 8),
        ..._lsb(~c & 0xFF, 8),
      ]));
    case 'NECext':
      return IrFrame(38000, _nec([
        ..._lsb(a & 0xFFFF, 16),
        ..._lsb(c & 0xFFFF, 16),
      ]));
    case 'NEC42':
      // 13-bit address, inverted address, 8-bit command, inverted command.
      return IrFrame(38000, _nec([
        ..._lsb(a & 0x1FFF, 13),
        ..._lsb(~a & 0x1FFF, 13),
        ..._lsb(c & 0xFF, 8),
        ..._lsb(~c & 0xFF, 8),
      ]));
    case 'Samsung32':
      return IrFrame(38000, _pulseDistance(
        hdrMark: 4500, hdrSpace: 4500, bitMark: 560,
        oneSpace: 1690, zeroSpace: 560,
        bits: [
          ..._lsb(a & 0xFF, 8),
          ..._lsb(a & 0xFF, 8),
          ..._lsb(c & 0xFF, 8),
          ..._lsb(~c & 0xFF, 8),
        ],
      ));
    case 'SIRC':
      return IrFrame(40000, _sirc(c, a, 5));
    case 'SIRC15':
      return IrFrame(40000, _sirc(c, a, 8));
    case 'SIRC20':
      return IrFrame(40000, _sirc(c, a, 13));
    case 'RC5':
      return IrFrame(36000, _rc5(a, c, extended: false));
    case 'RC5X':
      return IrFrame(36000, _rc5(a, c, extended: true));
    case 'RC6':
      return IrFrame(36000, _rc6(a, c));
    default:
      throw UnsupportedProtocol(s.protocol ?? '?');
  }
}

// ---------------------------------------------------------------- helpers

List<int> _lsb(int value, int count) =>
    [for (var i = 0; i < count; i++) (value >> i) & 1];

List<int> _msb(int value, int count) =>
    [for (var i = count - 1; i >= 0; i--) (value >> i) & 1];

List<int> _pulseDistance({
  required int hdrMark,
  required int hdrSpace,
  required int bitMark,
  required int oneSpace,
  required int zeroSpace,
  required List<int> bits,
}) {
  final p = <int>[hdrMark, hdrSpace];
  for (final b in bits) {
    p
      ..add(bitMark)
      ..add(b == 1 ? oneSpace : zeroSpace);
  }
  p.add(bitMark);
  return p;
}

List<int> _nec(List<int> bits) => _pulseDistance(
      hdrMark: 9000, hdrSpace: 4500, bitMark: 560,
      oneSpace: 1690, zeroSpace: 560, bits: bits,
    );

/// Sony SIRC: 7-bit command then [addrBits] of address, LSB first,
/// pulse-width coded. Sent 3 times on a 45 ms frame period.
List<int> _sirc(int command, int address, int addrBits) {
  final bits = [
    ..._lsb(command & 0x7F, 7),
    ..._lsb(address & ((1 << addrBits) - 1), addrBits),
  ];
  final frame = <int>[2400, 600];
  for (final b in bits) {
    frame
      ..add(b == 1 ? 1200 : 600)
      ..add(600);
  }
  final frameLen = frame.fold<int>(0, (s, v) => s + v);
  final out = <int>[];
  for (var r = 0; r < 3; r++) {
    final f = List<int>.of(frame);
    if (r < 2) {
      f[f.length - 1] += math.max(0, 45000 - frameLen);
    } else {
      f.removeLast(); // end on a mark
    }
    out.addAll(f);
  }
  return out;
}

/// Converts a list of (isMark, durationUs) half-bit segments into a
/// mark/space pattern: merges equal neighbours, drops leading/trailing space.
List<int> levelsToPattern(List<(bool, int)> segs) {
  final out = <int>[];
  bool? last;
  for (final (on, d) in segs) {
    if (out.isEmpty && !on) continue;
    if (last == on) {
      out[out.length - 1] += d;
    } else {
      out.add(d);
      last = on;
    }
  }
  if (last == false) out.removeLast();
  return out;
}

/// Philips RC5 (Manchester, 889 µs half-bit). '1' = space→mark.
List<int> _rc5(int address, int command, {required bool extended}) {
  const t = 889;
  final field = extended ? ((command >> 6) & 1) ^ 1 : 1;
  final bits = [
    1, // start
    field,
    0, // toggle
    ..._msb(address & 0x1F, 5),
    ..._msb(command & 0x3F, 6),
  ];
  final segs = <(bool, int)>[];
  for (final b in bits) {
    if (b == 1) {
      segs..add((false, t))..add((true, t));
    } else {
      segs..add((true, t))..add((false, t));
    }
  }
  return levelsToPattern(segs);
}

/// Philips RC6 mode 0 (Manchester, 444 µs unit). '1' = mark→space.
List<int> _rc6(int address, int command) {
  const t = 444;
  final segs = <(bool, int)>[(true, 2666), (false, 889)];
  void bit(int b, [int len = t]) {
    if (b == 1) {
      segs..add((true, len))..add((false, len));
    } else {
      segs..add((false, len))..add((true, len));
    }
  }

  bit(1); // start bit
  bit(0);
  bit(0);
  bit(0); // mode 000
  bit(0, 2 * t); // toggle (double width)
  for (final b in _msb(address & 0xFF, 8)) {
    bit(b);
  }
  for (final b in _msb(command & 0xFF, 8)) {
    bit(b);
  }
  return levelsToPattern(segs);
}
