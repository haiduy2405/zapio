import 'package:flutter_test/flutter_test.dart';
import 'package:zapio/ir/encoders.dart';
import 'package:zapio/ir/ir_file.dart';

const sample = '''
Filetype: IR signals file
Version: 1
#
name: TV_PWR
type: parsed
protocol: Samsung32
address: 07 00 00 00
command: 02 00 00 00
#
name: Vol_up
type: parsed
protocol: NEC
address: 04 00 00 00
command: 02 00 00 00
#
name: Sony_Power
type: parsed
protocol: SIRC
address: 01 00 00 00
command: 15 00 00 00
#
name: Raw_one
type: raw
frequency: 38000
duty_cycle: 0.330000
data: 9000 4500 560 560
data: 560 1690 560
#
name: Rc5
type: parsed
protocol: RC5
address: 00 00 00 00
command: 0C 00 00 00
''';

void main() {
  final sigs = parseIrFile(sample);

  test('parses all signals', () {
    expect(sigs.length, 5);
    expect(sigs[0].address, 7);
    expect(sigs[0].command, 2);
    expect(sigs[3].isRaw, isTrue);
    expect(sigs[3].data, [9000, 4500, 560, 560, 560, 1690, 560]);
  });

  test('little-endian hex', () {
    expect(hexLittleEndian('0B F4 00 00'), 0xF40B);
  });

  test('Samsung32 frame', () {
    final f = encodeSignal(sigs[0]);
    expect(f.frequency, 38000);
    expect(f.pattern.length, 2 + 64 + 1);
    expect(f.pattern.take(2), [4500, 4500]);
    // address 0x07 LSB-first => bits 1,1,1,0... => first space is a "one".
    expect(f.pattern[3], 1690);
    expect(f.pattern[9], 560); // bit 3 of 0x07 is 0
  });

  test('NEC frame has inverted bytes', () {
    final f = encodeSignal(sigs[1]);
    expect(f.pattern.length, 67);
    final spaces = [for (var i = 3; i < 66; i += 2) f.pattern[i]];
    final bits = spaces.map((s) => s > 1000 ? 1 : 0).toList();
    int byteAt(int k) {
      var v = 0;
      for (var i = 0; i < 8; i++) {
        v |= bits[k * 8 + i] << i;
      }
      return v;
    }

    expect(byteAt(0), 0x04);
    expect(byteAt(1), 0xFB);
    expect(byteAt(2), 0x02);
    expect(byteAt(3), 0xFD);
  });

  test('SIRC repeats 3 times and ends on a mark', () {
    final f = encodeSignal(sigs[2]);
    expect(f.frequency, 40000);
    expect(f.pattern.length, 3 * 26 - 1);
    expect(f.pattern.length.isOdd, isTrue);
  });

  test('raw passthrough', () {
    final f = encodeSignal(sigs[3]);
    expect(f.pattern, [9000, 4500, 560, 560, 560, 1690, 560]);
  });

  test('RC5 starts and ends with a mark, all durations are half-bit multiples', () {
    final f = encodeSignal(sigs[4]);
    expect(f.frequency, 36000);
    expect(f.pattern.length.isOdd, isTrue);
    for (final d in f.pattern) {
      expect(d % 889, 0);
    }
  });

  test('Kaseikyo is 48 bits with header', () {
    final f = encodeSignal(IrSignal.parsed(
        name: 'p', protocol: 'Kaseikyo', address: 0x00200280, command: 0x3D));
    expect(f.frequency, 37000);
    expect(f.pattern.length, 2 + 96 + 1);
    expect(f.pattern.take(2), [3456, 1728]);
  });

  test('RCA and Pioneer encode', () {
    final rca = encodeSignal(IrSignal.parsed(name: 'r', protocol: 'RCA', address: 0xF, command: 0x54));
    expect(rca.frequency, 56000);
    expect(rca.pattern.length, 2 + 48 + 1);
    final pio = encodeSignal(IrSignal.parsed(name: 'p', protocol: 'Pioneer', address: 0xA5, command: 0x1C));
    expect(pio.pattern.length, 67);
  });
}
