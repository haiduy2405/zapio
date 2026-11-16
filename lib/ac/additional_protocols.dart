part of 'ac.dart';

// Wire format references: IRremoteESP8266 (Samsung, Mitsubishi,
// MitsubishiHeavy and Sharp protocol documentation and tests).

const _standardModes = {
  AcMode.auto: 0, AcMode.cool: 1, AcMode.dry: 2, AcMode.fan: 3, AcMode.heat: 4,
};

class SamsungAc extends AcProtocol {
  const SamsungAc();

  @override
  String get id => 'samsung';
  @override
  String get label => 'Samsung';

  static int _ones(int byte) {
    var count = 0;
    for (; byte != 0; byte &= byte - 1) {
      count++;
    }
    return count;
  }

  @override
  IrFrame encode(AcState s, {required bool wasOn}) {
    final power = s.power ? 0xF0 : 0xC0;
    final fan = s.mode == AcMode.auto ? 6 : const [0, 2, 4, 5][s.fan.index];
    final sections = [
      [2, 2, 0, 0, 0, 0, power],
      if (wasOn != s.power) [1, 2, 0, 0, 0, 0, 0],
      [
        1, 2, s.swing ? 0xA0 : 0xF0, 0x71,
        (s.temp.clamp(minTemp, maxTemp) - minTemp) << 4,
        (_standardModes[s.mode]! << 4) | (fan << 1) | 1,
        power,
      ],
    ];
    final pulses = [690, 17844];
    for (final section in sections) {
      final checksum = 255 - section.fold<int>(0, (sum, b) => sum + _ones(b));
      section[1] |= (checksum & 15) << 4;
      section[2] |= checksum >> 4;
      pulses.addAll([3086, 8864]);
      _pd(pulses, _bitsLsb(section), 586, 1432, 436);
      pulses.addAll([586, 2886]);
    }
    pulses.removeLast();
    return IrFrame(38000, pulses);
  }
}

class MitsubishiElectricAc extends AcProtocol {
  const MitsubishiElectricAc();

  @override
  String get id => 'mitsubishi_electric';
  @override
  String get label => 'Mitsubishi Electric (144-bit)';
  @override
  int get maxTemp => 31;

  @override
  IrFrame encode(AcState s, {required bool wasOn}) {
    const modes = {
      AcMode.auto: (4, 0x30), AcMode.cool: (3, 0x36), AcMode.dry: (2, 0x32),
      AcMode.fan: (7, 0x37), AcMode.heat: (1, 0x30),
    };
    final (mode, vane) = modes[s.mode]!;
    final bytes = [
      0x23, 0xCB, 0x26, 1, 0, s.power ? 0x20 : 0, mode << 3,
      s.temp.clamp(minTemp, maxTemp) - minTemp, vane,
      (s.fan == AcFan.auto ? 0x80 : s.fan.index) | (s.swing ? 0x78 : 0x40),
      0x67, 0, 0, 0, 0, 0, 0,
    ];
    bytes.add(bytes.fold<int>(0, (sum, b) => sum + b) & 255);
    final frame = [3400, 1750];
    _pd(frame, _bitsLsb(bytes), 450, 1300, 420);
    frame.add(440);
    return IrFrame(38000, [...frame, 15500, ...frame]);
  }
}

class MitsubishiHeavyAc extends AcProtocol {
  const MitsubishiHeavyAc();

  @override
  String get id => 'mitsubishi_heavy';
  @override
  String get label => 'Mitsubishi Heavy (152-bit)';
  @override
  int get minTemp => 17;
  @override
  int get maxTemp => 31;

  @override
  IrFrame encode(AcState s, {required bool wasOn}) {
    final bytes = [0xAD, 0x51, 0x3C, 0xE5, 0x1A];
    for (final b in [
      _standardModes[s.mode]! | (s.power ? 8 : 0),
      s.temp.clamp(minTemp, maxTemp) - minTemp,
      s.fan.index, s.swing ? 0 : 0xC0, 8, 0, 0x80,
    ]) {
      bytes.addAll([b, b ^ 255]);
    }
    final pulses = [3140, 1630];
    _pd(pulses, _bitsLsb(bytes), 370, 420, 1220);
    return IrFrame(38000, pulses..add(370));
  }
}

enum SharpModel { a907, a705, a903 }

class SharpAc extends AcProtocol {
  const SharpAc({this.model = SharpModel.a907});

  final SharpModel model;

  @override
  String get id => model == SharpModel.a907 ? 'sharp' : 'sharp_${model.name}';
  @override
  String get label => 'Sharp ${model.name.toUpperCase()}';
  @override
  int get minTemp => 15;

  @override
  IrFrame encode(AcState s, {required bool wasOn}) =>
      encodeChange(s, wasOn: wasOn, wasSwing: false);

  @override
  IrFrame encodeChange(AcState s, {required bool wasOn, required bool wasSwing}) {
    final a907 = model == SharpModel.a907;
    final mode = switch (s.mode) {
      AcMode.cool => 2,
      AcMode.dry => 3,
      AcMode.heat when a907 => 1,
      _ => 0,
    };
    final fan = mode == 0 || mode == 3
        ? 2
        : (a907 ? const [2, 4, 3, 5] : const [2, 3, 5, 7])[s.fan.index];
    final temperature = mode == 0 || mode == 3
        ? 0
        : (model == SharpModel.a705 ? 0xD0 : 0xC0) |
            (s.temp.clamp(minTemp, maxTemp) - minTemp);
    final swingChanged = s.power && (s.swing != wasSwing || (!wasOn && s.swing));
    final bytes = [
      0xAA, 0x5A, 0xCF, 0x10, temperature,
      !s.power ? 0x21 : (wasOn ? 0x31 : 0x11),
      (fan << 4) | mode, 0, swingChanged ? (s.swing ? 0x0F : 0x0A) : 0x08,
      0x80, swingChanged && wasOn ? 6 : 0,
      a907 ? 0xE0 : 0xF0, 1,
    ];
    final checksum = bytes.fold<int>(0, (sum, b) => sum ^ b);
    bytes.last |= ((checksum ^ (checksum >> 4)) & 15) << 4;
    final pulses = [3800, 1900];
    _pd(pulses, _bitsLsb(bytes), 470, 1400, 500);
    return IrFrame(38000, pulses..add(470));
  }
}
