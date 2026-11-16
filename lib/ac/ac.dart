import '../ir/encoders.dart';

part 'additional_protocols.dart';

/// Air-conditioner state. AC remotes send the whole state on every press,
/// so the app keeps it and re-encodes it each time.
enum AcMode { cool, dry, fan, auto, heat }

enum AcFan { auto, low, med, high }

class AcState {
  AcState({
    this.power = true,
    this.mode = AcMode.cool,
    this.temp = 26,
    this.fan = AcFan.auto,
    this.swing = false,
  });

  bool power;
  AcMode mode;
  int temp; // °C, 16..30
  AcFan fan;
  bool swing;

  AcState copy() => AcState(power: power, mode: mode, temp: temp, fan: fan, swing: swing);

  Map<String, dynamic> toJson() =>
      {'p': power, 'm': mode.name, 't': temp, 'f': fan.name, 's': swing};

  factory AcState.fromJson(Map<String, dynamic> j) => AcState(
        power: j['p'] as bool? ?? true,
        mode: AcMode.values.asNameMap()[j['m']] ?? AcMode.cool,
        temp: (j['t'] as num?)?.toInt() ?? 26,
        fan: AcFan.values.asNameMap()[j['f']] ?? AcFan.auto,
        swing: j['s'] as bool? ?? false,
      );
}

/// One AC IR protocol family.
abstract class AcProtocol {
  const AcProtocol();
  String get id;
  String get label;
  int get minTemp => 16;
  int get maxTemp => 30;

  /// Full-state frame. [wasOn] = power state before this command.
  IrFrame encode(AcState s, {required bool wasOn});

  IrFrame encodeChange(AcState s, {required bool wasOn, required bool wasSwing}) =>
      encode(s, wasOn: wasOn);

  static const all = <AcProtocol>[
    SamsungAc(), MitsubishiElectricAc(), MitsubishiHeavyAc(),
    SharpAc(), SharpAc(model: SharpModel.a705), SharpAc(model: SharpModel.a903),
    DaikinAc(), PanasonicAc(), PanasonicAc(modelByte: 0x89),
    GreeAc(), CoolixAc(), MideaAc(), LgAc(), LgAc(variant2: true),
  ];

  static AcProtocol? byId(String id) {
    for (final p in all) {
      if (p.id == id) return p;
    }
    return null;
  }
}

// ------------------------------------------------------------------ helpers

List<int> _bitsLsb(List<int> bytes) => [
      for (final b in bytes)
        for (var i = 0; i < 8; i++) (b >> i) & 1
    ];

List<int> _bitsMsb(List<int> bytes) => [
      for (final b in bytes)
        for (var i = 7; i >= 0; i--) (b >> i) & 1
    ];

void _pd(List<int> out, List<int> bits, int mark, int one, int zero) {
  for (final b in bits) {
    out
      ..add(mark)
      ..add(b == 1 ? one : zero);
  }
}

// ------------------------------------------------------------------- Gree
// Gree / Tosot / Sinclair / Kelvinator / Cooper&Hunter (YAW1F, YB1F…).
// 8 bytes, LSB first, sent as 4 bytes + "010" footer + 20 ms gap + 4 bytes.
// Checksum = (10 + low nibbles of b0..b3 + high nibbles of b4..b6) & 0xF in
// the high nibble of b7 — verified against 21 captured frames.

class GreeAc extends AcProtocol {
  const GreeAc();
  @override
  String get id => 'gree';
  @override
  String get label => 'Gree';

  static List<int> bytes(AcState s) {
    const modeCode = {
      AcMode.auto: 0, AcMode.cool: 1, AcMode.dry: 2, AcMode.fan: 3, AcMode.heat: 4,
    };
    final b = List<int>.filled(8, 0);
    b[0] = modeCode[s.mode]! |
        (s.power ? 0x08 : 0) |
        (s.fan.index << 4) |
        (s.swing ? 0x40 : 0);
    b[1] = (s.temp.clamp(16, 30) - 16) & 0x0F;
    b[2] = 0x20 | (s.power ? 0x40 : 0); // light on, power mirror
    b[3] = 0x50;
    b[4] = s.swing ? 0x01 : 0x00;
    b[5] = 0x40;
    b[6] = 0x00;
    b[7] = checksum(b) << 4;
    return b;
  }

  static int checksum(List<int> b) {
    var sum = 10;
    for (var i = 0; i < 4; i++) {
      sum += b[i] & 0x0F;
    }
    for (var i = 4; i < 7; i++) {
      sum += b[i] >> 4;
    }
    return sum & 0x0F;
  }

  @override
  IrFrame encode(AcState s, {required bool wasOn}) {
    final b = bytes(s);
    const mark = 620, one = 1600, zero = 540;
    final frame = <int>[9000, 4500];
    _pd(frame, _bitsLsb(b.sublist(0, 4)), mark, one, zero);
    _pd(frame, const [0, 1, 0], mark, one, zero);
    frame
      ..add(mark)
      ..add(19980);
    _pd(frame, _bitsLsb(b.sublist(4, 8)), mark, one, zero);
    frame.add(mark);
    return IrFrame(38000, [...frame, 40000, ...frame]);
  }
}

// ------------------------------------------------------------------ Coolix
// Midea R51 family: Midea, Electrolux, Carrier, Beko, Ballu, Royal Clima,
// Timberk, York, Kenmore… 3 bytes, each followed by its inverse, MSB first,
// whole 48-bit frame sent twice. Temperature uses a Gray-like table.

class CoolixAc extends AcProtocol {
  const CoolixAc();
  @override
  String get id => 'coolix';
  @override
  String get label => 'Coolix (Midea R51)';
  @override
  int get minTemp => 17;

  static const _tempCode = [0x0, 0x1, 0x3, 0x2, 0x6, 0x7, 0x5, 0x4, 0xC, 0xD, 0x9, 0x8, 0xA, 0xB];
  static const offCode = [0xB2, 0x7B, 0xE0];

  static List<int> bytes(AcState s) {
    if (!s.power) return offCode;
    final fanBits = (s.mode == AcMode.dry || s.mode == AcMode.auto)
        ? 0x0
        : const {AcFan.auto: 0x5, AcFan.low: 0x4, AcFan.med: 0x2, AcFan.high: 0x1}[s.fan]!;
    final modeBits = const {
      AcMode.cool: 0, AcMode.dry: 1, AcMode.fan: 1, AcMode.auto: 2, AcMode.heat: 3,
    }[s.mode]!;
    final t = s.mode == AcMode.fan ? 0xE : _tempCode[s.temp.clamp(17, 30) - 17];
    return [0xB2, (fanBits << 5) | 0x1F, (t << 4) | (modeBits << 2)];
  }

  @override
  IrFrame encode(AcState s, {required bool wasOn}) {
    final b = bytes(s);
    final data = [for (final x in b) ...[x, (~x) & 0xFF]];
    final frame = <int>[4480, 4480];
    _pd(frame, _bitsMsb(data), 560, 1680, 560);
    frame.add(560);
    return IrFrame(38000, [...frame, 5040, ...frame]);
  }
}

// ------------------------------------------------------------------ Midea48
// Midea 48-bit (Comfee, some Midea/Pioneer/Toshiba portables). Frame then
// bit-inverted frame. Checksum: bit-reverse sum of bytes 0..4, negated,
// bit-reversed — verified against 16 captured frames.

class MideaAc extends AcProtocol {
  const MideaAc();
  @override
  String get id => 'midea48';
  @override
  String get label => 'Midea 48-bit';
  @override
  int get minTemp => 17;

  static int _rev(int b) {
    var r = 0;
    for (var i = 0; i < 8; i++) {
      r = (r << 1) | ((b >> i) & 1);
    }
    return r;
  }

  static int checksum(List<int> b) {
    var sum = 0;
    for (var i = 0; i < 5; i++) {
      sum += _rev(b[i]);
    }
    return _rev((256 - (sum & 0xFF)) & 0xFF);
  }

  static List<int> bytes(AcState s) {
    final mode = const {
      AcMode.cool: 0, AcMode.dry: 1, AcMode.auto: 2, AcMode.heat: 3, AcMode.fan: 4,
    }[s.mode]!;
    final b = [
      0xA1,
      (s.power ? 0x80 : 0) | (s.fan.index << 3) | mode,
      0x40 | (s.temp.clamp(17, 30) - 17),
      0xFF,
      0xFF,
      0,
    ];
    b[5] = checksum(b);
    return b;
  }

  @override
  IrFrame encode(AcState s, {required bool wasOn}) {
    final b = bytes(s);
    final inv = [for (final x in b) (~x) & 0xFF];
    final p = <int>[4480, 4480];
    _pd(p, _bitsMsb(b), 560, 1680, 560);
    p
      ..add(560)
      ..add(5600)
      ..add(4480)
      ..add(4480);
    _pd(p, _bitsMsb(inv), 560, 1680, 560);
    p.add(560);
    return IrFrame(38000, p);
  }
}

// ---------------------------------------------------------------------- LG
// LG 28-bit: 0x88 signature, power, mode, temp-15, fan, nibble checksum
// (sum of the 6 upper nibbles) — verified against 10 captured frames.
// variant2 = newer remotes with a 3.2 ms / 9.9 ms header.

class LgAc extends AcProtocol {
  const LgAc({this.variant2 = false});
  final bool variant2;

  @override
  String get id => variant2 ? 'lg2' : 'lg';
  @override
  String get label => variant2 ? 'LG (new)' : 'LG';

  static const offCode = 0x88C0051;

  static int value(AcState s, {required bool wasOn}) {
    if (!s.power) return offCode;
    final mode = const {
      AcMode.cool: 0, AcMode.dry: 1, AcMode.fan: 2, AcMode.auto: 3, AcMode.heat: 4,
    }[s.mode]!;
    final fan = const {AcFan.low: 0, AcFan.med: 2, AcFan.high: 4, AcFan.auto: 5}[s.fan]!;
    final temp = s.temp.clamp(16, 30) - 15;
    var v = (0x88 << 20) | (((wasOn ? 8 : 0) | mode) << 12) | (temp << 8) | (fan << 4);
    var sum = 0;
    for (var k = 1; k < 7; k++) {
      sum += (v >> (4 * k)) & 0xF;
    }
    v |= sum & 0xF;
    return v;
  }

  @override
  IrFrame encode(AcState s, {required bool wasOn}) {
    final v = value(s, wasOn: wasOn);
    final bits = [for (var i = 27; i >= 0; i--) (v >> i) & 1];
    final p = variant2 ? <int>[3200, 9900] : <int>[8500, 4250];
    _pd(p, bits, 550, 1580, 550);
    p.add(550);
    return IrFrame(38000, p);
  }
}

// ------------------------------------------------------------------ Daikin
// Daikin ARC4xx remotes (FTKC/FTKB/FTXS/FTXM…): 5-bit preamble, two fixed
// 8-byte frames and a 19-byte state frame, LSB first. Each frame ends with a
// byte-sum checksum — verified against 12 captured frames.

class DaikinAc extends AcProtocol {
  const DaikinAc();
  @override
  String get id => 'daikin';
  @override
  String get label => 'Daikin';
  @override
  int get minTemp => 18;

  static int sum(List<int> b) => b.fold(0, (a, x) => a + x) & 0xFF;

  static const _modeCode = {
    AcMode.auto: 0, AcMode.dry: 2, AcMode.cool: 3, AcMode.heat: 4, AcMode.fan: 6,
  };
  static const _fanCode = {AcFan.auto: 0xA, AcFan.low: 0x3, AcFan.med: 0x5, AcFan.high: 0x7};

  static List<int> frame1() => _withSum([0x11, 0xDA, 0x27, 0x00, 0xC5, 0x00, 0x00]);
  static List<int> frame2() => _withSum([0x11, 0xDA, 0x27, 0x00, 0x42, 0x00, 0x00]);

  static List<int> _withSum(List<int> b) => [...b, sum(b)];

  static List<int> state(AcState s) {
    final temp = switch (s.mode) {
      AcMode.dry => 0xC0,
      AcMode.fan => 0x32,
      _ => s.temp.clamp(18, 30) * 2,
    };
    return _withSum([
      0x11, 0xDA, 0x27, 0x00, 0x00,
      (_modeCode[s.mode]! << 4) | 0x08 | (s.power ? 0x01 : 0x00),
      temp,
      0x00,
      (_fanCode[s.fan]! << 4) | (s.swing ? 0x0F : 0x00),
      0x00,
      0x00, 0x06, 0x60, // timers off
      0x00, 0x00,
      0xC1, 0x80, 0x00,
    ]);
  }

  @override
  IrFrame encode(AcState s, {required bool wasOn}) {
    const mark = 430, one = 1300, zero = 430;
    final p = <int>[];
    for (var i = 0; i < 5; i++) {
      p..add(mark)..add(zero);
    }
    p..add(mark)..add(25000);
    for (final f in [frame1(), frame2(), state(s)]) {
      p..add(3500)..add(1720);
      _pd(p, _bitsLsb(f), mark, one, zero);
      p.add(mark);
      p.add(35000);
    }
    p.removeLast(); // end on the final mark
    return IrFrame(38000, p);
  }
}

// --------------------------------------------------------------- Panasonic
// Panasonic 216-bit (CS-/CU- inverter series): fixed 8-byte frame, 10 ms
// gap, 19-byte state frame, LSB first, byte-sum checksum — verified against
// 8 captured frames. [modelByte] differs between remote families.

class PanasonicAc extends AcProtocol {
  const PanasonicAc({this.modelByte = 0x81});
  final int modelByte;

  @override
  String get id => modelByte == 0x81 ? 'panasonic' : 'panasonic_${modelByte.toRadixString(16)}';
  @override
  String get label => modelByte == 0x81 ? 'Panasonic' : 'Panasonic (B)';

  static const header = [0x02, 0x20, 0xE0, 0x04, 0x00, 0x00, 0x00, 0x06];
  static const _modeCode = {
    AcMode.auto: 0, AcMode.dry: 2, AcMode.cool: 3, AcMode.heat: 4, AcMode.fan: 6,
  };
  static const _fanCode = {AcFan.auto: 0xA, AcFan.low: 0x3, AcFan.med: 0x5, AcFan.high: 0x7};

  List<int> state(AcState s) {
    final b = [
      0x02, 0x20, 0xE0, 0x04, 0x00,
      (_modeCode[s.mode]! << 4) | 0x08 | (s.power ? 0x01 : 0x00),
      s.temp.clamp(16, 30) * 2,
      0x80,
      (_fanCode[s.fan]! << 4) | (s.swing ? 0x0F : 0x03),
      0x00, // horizontal vane: unit default
      0x00, 0x0E, 0xE0, 0x00, 0x00,
      modelByte,
      0x00, 0x00,
    ];
    return [...b, b.fold<int>(0, (a, x) => a + x) & 0xFF];
  }

  @override
  IrFrame encode(AcState s, {required bool wasOn}) {
    const mark = 435, one = 1300, zero = 435;
    final p = <int>[3500, 1750];
    _pd(p, _bitsLsb(header), mark, one, zero);
    p..add(mark)..add(10000)..add(3500)..add(1750);
    _pd(p, _bitsLsb(state(s)), mark, one, zero);
    p.add(mark);
    return IrFrame(36700, p);
  }
}

/// AC brands shown in the picker, with the protocols to try in order.
/// Brands we cannot encode yet fall back to trying every family.
class AcBrands {
  static const _generic = [
    'gree', 'coolix', 'midea48', 'daikin', 'panasonic', 'lg', 'lg2',
    'samsung', 'mitsubishi_electric', 'mitsubishi_heavy', 'sharp',
    'sharp_a705', 'sharp_a903',
  ];

  static const map = <String, List<String>>{
    'Samsung': ['samsung'],
    'Mitsubishi': ['mitsubishi_electric', 'mitsubishi_heavy'],
    'Mitsubishi Electric': ['mitsubishi_electric'],
    'Mitsubishi Heavy Industries': ['mitsubishi_heavy'],
    'Sharp': ['sharp', 'sharp_a705', 'sharp_a903'],
    'Gree': ['gree'],
    'Tosot': ['gree'],
    'Sinclair': ['gree'],
    'Kelvinator': ['gree', 'coolix'],
    'Midea': ['coolix', 'midea48'],
    'Comfee': ['midea48', 'coolix'],
    'Electrolux': ['coolix', 'gree'],
    'Carrier': ['coolix', 'midea48'],
    'Beko': ['coolix'],
    'LG': ['lg', 'lg2'],
    'Daikin': ['daikin'],
    'Panasonic': ['panasonic', 'panasonic_89'],
    'National': ['panasonic', 'panasonic_89'],
    'Casper': _generic,
    'Funiki': _generic,
    'Nagakawa': _generic,
    'Sumikura': _generic,
    'TCL': _generic,
    'Hisense': _generic,
    'Aqua': _generic,
    'Toshiba': ['coolix', 'midea48', 'gree'],
  };

  static List<String> protocolsFor(String brand) => map[brand] ?? _generic;

  static const otherBrands = '__other__';
}
