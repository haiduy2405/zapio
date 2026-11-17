import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zapio/devices/device_store.dart';
import 'package:zapio/devices/share_codec.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('share code round-trips devices and AC state', () async {
    SharedPreferences.setMockInitialValues({'ac_state_a1': '{"p":true,"m":"cool","t":24,"f":"auto","s":false}'});
    final devices = [
      SavedDevice(id: 'a1', name: 'Điều hòa phòng ngủ', kind: DeviceKind.ir, category: 'AC', remoteId: 'ac:daikin'),
      SavedDevice(id: 't1', name: 'TV Samsung', kind: DeviceKind.samsung, category: 'TV', ip: '192.168.1.20'),
    ];
    final code = await ShareCodec.encode(devices);
    expect(code.startsWith(ShareCodec.prefix), isTrue);
    var n = 0;
    final r = ShareCodec.decode(code, () => 'new${n++}');
    expect(r, isNotNull);
    final (list, states) = r!;
    expect(list.length, 2);
    expect(list[0].name, 'Điều hòa phòng ngủ');
    expect(list[0].remoteId, 'ac:daikin');
    expect(list[1].ip, '192.168.1.20');
    expect(list[1].kind, DeviceKind.samsung);
    expect(states['new0'], contains('"t":24'));
  });

  test('rejects foreign text', () {
    expect(ShareCodec.decode('hello', () => 'x'), isNull);
    expect(ShareCodec.decode('ZAPIO1:!!!', () => 'x'), isNull);
  });
}
