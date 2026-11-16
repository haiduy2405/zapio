import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zapio/wifi/android_tv.dart';
import 'package:zapio/wifi/tv_link.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Android TV pairs with a PIN and sends a remote key', () async {
    const channel = MethodChannel('zapio/android_tv');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'connect' ? true : null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final states = <TvLinkState>[];
    final link = AndroidTvLink('192.168.1.12', (state, _) => states.add(state));
    await link.connect();
    expect(states, [TvLinkState.connecting, TvLinkState.waitingApproval]);
    expect(await link.pair('12AB34'), isTrue);
    expect(states.last, TvLinkState.connected);
    await link.send(TvKey.ok);
    await link.close();
    expect(calls.map((call) => call.method), ['connect', 'pair', 'send', 'close']);
    expect(calls[1].arguments['code'], '12AB34');
    expect(calls[2].arguments['key'], 23);
  });
}
