import 'package:flutter_test/flutter_test.dart';
import 'package:zapio/ac/ac.dart';

List<int> _bytes(List<int> pulses, int start, int length, int one) => [
      for (var byte = 0; byte < length; byte++)
        List.generate(8, (bit) => pulses[start + (byte * 8 + bit) * 2 + 1] == one ? 1 << bit : 0)
            .fold<int>(0, (value, bit) => value | bit),
    ];

void main() {
  test('Samsung sends an extra section only for power transitions', () {
    const protocol = SamsungAc();
    final state = AcState();
    final normal = protocol.encode(state, wasOn: true).pattern;
    final turningOn = protocol.encode(state, wasOn: false).pattern;
    expect(normal.take(4), [690, 17844, 3086, 8864]);
    expect(turningOn.length - normal.length, 116);
    expect(_bytes(turningOn, 120, 7, 1432), [1, 0xD2, 0x0F, 0, 0, 0, 0]);
    expect(_bytes(normal, 4, 7, 1432), [2, 0x92, 0x0F, 0, 0, 0, 0xF0]);
  });

  test('Mitsubishi Electric repeats its 144-bit frame and checksum', () {
    final pulses = const MitsubishiElectricAc().encode(AcState(), wasOn: false).pattern;
    final payload = _bytes(pulses, 2, 18, 1300);
    expect(payload.take(10), [0x23, 0xCB, 0x26, 1, 0, 0x20, 0x18, 10, 0x36, 0xC0]);
    expect(payload.last, payload.take(17).reduce((a, b) => a + b) & 255);
    expect(_bytes(pulses, 294, 18, 1300), payload);
  });

  test('Mitsubishi Heavy 152-bit frame has its own header and inverse bytes', () {
    final pulses = const MitsubishiHeavyAc().encode(AcState(), wasOn: false).pattern;
    final payload = _bytes(pulses, 2, 19, 420);
    expect(payload.take(9), [0xAD, 0x51, 0x3C, 0xE5, 0x1A, 9, 0xF6, 9, 0xF6]);
    for (var offset = 3; offset < payload.length; offset += 2) {
      expect(payload[offset] ^ payload[offset + 1], 255);
    }
  });

  test('Sharp power-on matches the A907 auto-mode reference', () {
    const protocol = SharpAc();
    final pulses = protocol.encode(AcState(mode: AcMode.auto), wasOn: false).pattern;
    expect(_bytes(pulses, 2, 13, 1400), [0xAA, 0x5A, 0xCF, 0x10, 0, 0x11, 0x20, 0, 8, 0x80, 0, 0xE0, 1]);
  });

  test('Sharp does not send the swing toggle again on a temperature change', () {
    const protocol = SharpAc();
    final state = AcState(swing: true);
    final toggle = protocol.encodeChange(state, wasOn: true, wasSwing: false);
    final temperature = protocol.encodeChange(state, wasOn: true, wasSwing: true);
    expect(_bytes(toggle.pattern, 2, 13, 1400)[8] & 7, 7);
    expect(_bytes(temperature.pattern, 2, 13, 1400)[8] & 7, 0);
  });
}
