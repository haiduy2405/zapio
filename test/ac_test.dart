import 'package:flutter_test/flutter_test.dart';
import 'package:zapio/ac/ac.dart';

String hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join().toUpperCase();

/// Expected values are frames captured from real remotes (decoded in tools/).
void main() {
  group('Gree', () {
    test('cool 22 low, no swing = captured "Swing" frame', () {
      final b = GreeAc.bytes(AcState(mode: AcMode.cool, temp: 22, fan: AcFan.low));
      expect(hex(b), '19066050004000D0');
    });
    test('heat 23 med swing (except vane byte) matches capture', () {
      final b = GreeAc.bytes(AcState(mode: AcMode.heat, temp: 23, fan: AcFan.med, swing: true));
      expect(hex(b.sublist(0, 4)), '6C076050');
    });
    test('checksum matches captured frames', () {
      for (final f in [
        [0x39, 0x09, 0x20, 0x50, 0x00, 0x40, 0x00, 0x00],
        [0x39, 0x07, 0x20, 0x50, 0x00, 0x40, 0x00, 0xE0],
        [0x3C, 0x09, 0x20, 0x50, 0x00, 0x40, 0x00, 0x38],
        [0x6C, 0x07, 0x60, 0x50, 0x0B, 0x40, 0x00, 0x10],
        [0x01, 0x0A, 0x00, 0x50, 0x03, 0x40, 0x00, 0x90],
      ]) {
        expect(GreeAc.checksum(f), f[7] >> 4);
      }
    });
    test('frame shape: two repeats of 2+70+2+64+1', () {
      final f = const GreeAc().encode(AcState(), wasOn: true);
      expect(f.pattern.length, 2 * (2 + 70 + 2 + 64 + 1) + 1);
      expect(f.pattern.length.isOdd, isTrue);
    });
  });

  group('Coolix', () {
    test('captured states', () {
      expect(hex(CoolixAc.bytes(AcState(mode: AcMode.cool, temp: 23))), 'B2BF50');
      expect(hex(CoolixAc.bytes(AcState(mode: AcMode.cool, temp: 17))), 'B2BF00');
      expect(hex(CoolixAc.bytes(AcState(mode: AcMode.heat, temp: 30))), 'B2BFBC');
      expect(hex(CoolixAc.bytes(AcState(mode: AcMode.heat, temp: 23))), 'B2BF5C');
      expect(hex(CoolixAc.bytes(AcState(mode: AcMode.dry, temp: 23))), 'B21F54');
      expect(hex(CoolixAc.bytes(AcState(power: false))), 'B27BE0');
    });
  });

  group('Midea48', () {
    test('captured states + checksum', () {
      expect(hex(MideaAc.bytes(AcState(mode: AcMode.cool, temp: 25, fan: AcFan.low))), 'A18848FFFF5A');
      expect(hex(MideaAc.bytes(AcState(mode: AcMode.cool, temp: 26, fan: AcFan.low))), 'A18849FFFF5B');
      expect(hex(MideaAc.bytes(AcState(mode: AcMode.cool, temp: 24, fan: AcFan.med))), 'A19047FFFF49');
    });
  });

  group('LG', () {
    test('captured states', () {
      expect(
        LgAc.value(AcState(mode: AcMode.cool, temp: 22, fan: AcFan.high), wasOn: true),
        0x8808743,
      );
      expect(
        LgAc.value(AcState(mode: AcMode.cool, temp: 21, fan: AcFan.high), wasOn: false),
        0x880064A,
      );
      expect(LgAc.value(AcState(power: false), wasOn: true), 0x88C0051);
    });
  });

  test('every protocol encodes every state', () {
    for (final p in AcProtocol.all) {
      for (final m in AcMode.values) {
        for (final fan in AcFan.values) {
          for (var t = 16; t <= 30; t++) {
            final f = p.encode(AcState(mode: m, fan: fan, temp: t), wasOn: true);
            expect(f.pattern.every((d) => d > 0), isTrue);
            expect(f.durationUs, lessThan(1900000));
          }
        }
      }
    }
  });
}
