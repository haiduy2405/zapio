import 'package:flutter/services.dart';

import 'tv_link.dart';

class AndroidTvLink extends TvLink {
  AndroidTvLink(super.ip, super.onState);

  static const _channel = MethodChannel('zapio/android_tv');
  static var _nextSession = 0;
  int? _session;

  static const port = 6466;
  static const _keyCodes = {
    TvKey.power: 26, TvKey.volUp: 24, TvKey.volDown: 25, TvKey.mute: 164,
    TvKey.chUp: 166, TvKey.chDown: 167, TvKey.up: 19, TvKey.down: 20,
    TvKey.left: 21, TvKey.right: 22, TvKey.ok: 23, TvKey.back: 4,
    TvKey.home: 3, TvKey.menu: 82, TvKey.play: 126, TvKey.pause: 127,
    TvKey.source: 178,
  };

  @override
  Future<void> connect() async {
    final session = ++_nextSession;
    _session = session;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'disconnected' && call.arguments == _session) {
        onState(TvLinkState.closed, '');
      }
    });
    onState(TvLinkState.connecting, '');
    try {
      final needsCode = await _channel.invokeMethod<bool>(
        'connect', {'ip': ip, 'session': session},
      );
      if (_session == session) {
        onState(needsCode == true ? TvLinkState.waitingApproval : TvLinkState.connected, '');
      }
    } catch (_) {
      if (_session == session) onState(TvLinkState.error, '');
    }
  }

  Future<bool> pair(String code) async {
    final session = _session;
    if (session == null) return false;
    try {
      await _channel.invokeMethod<void>('pair', {'session': session, 'code': code});
      if (_session != session) return false;
      onState(TvLinkState.connected, '');
      return true;
    } on PlatformException catch (error) {
      if (_session == session && error.code != 'INVALID_PIN') {
        onState(TvLinkState.error, '');
      }
      return false;
    }
  }

  @override
  Future<void> send(TvKey key) async {
    final session = _session;
    if (session == null) return;
    try {
      await _channel.invokeMethod<void>('send', {'session': session, 'key': _keyCodes[key]});
    } catch (_) {
      if (_session == session) onState(TvLinkState.closed, '');
    }
  }

  @override
  Future<void> close() async {
    final session = _session;
    _session = null;
    _channel.setMethodCallHandler(null);
    if (session == null) return;
    try {
      await _channel.invokeMethod<void>('close', {'session': session});
    } on PlatformException {
      // The native session can already be closed.
    } on MissingPluginException {
      // Android TV control is available on Android.
    }
  }
}
