import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'tv_link.dart';

/// Roku player / Roku TV via External Control Protocol (HTTP, port 8060).
/// No pairing needed (the user may have to enable "Control by mobile apps").
class RokuLink extends TvLink {
  RokuLink(super.ip, super.onState);

  final _client = HttpClient()..connectionTimeout = const Duration(seconds: 3);

  /// Returns the Roku's friendly name if [ip] answers ECP, else null.
  static Future<String?> probe(String ip,
      {Duration timeout = const Duration(milliseconds: 900)}) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final req = await client
          .getUrl(Uri.parse('http://$ip:8060/query/device-info'))
          .timeout(timeout);
      final res = await req.close().timeout(timeout);
      if (res.statusCode != 200) return null;
      final body = await res.transform(utf8.decoder).join().timeout(timeout);
      String? tag(String t) =>
          RegExp('<$t>([^<]*)</$t>').firstMatch(body)?.group(1)?.trim();
      final name = tag('user-device-name') ?? tag('friendly-device-name') ??
          tag('model-name') ?? 'Roku';
      return name.isEmpty ? 'Roku' : name;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<void> connect() async {
    onState(TvLinkState.connecting, '');
    final name = await probe(ip, timeout: const Duration(seconds: 3));
    onState(name != null ? TvLinkState.connected : TvLinkState.error, name ?? '');
  }

  static const _keys = {
    TvKey.power: 'Power', TvKey.volUp: 'VolumeUp', TvKey.volDown: 'VolumeDown',
    TvKey.mute: 'VolumeMute', TvKey.chUp: 'ChannelUp', TvKey.chDown: 'ChannelDown',
    TvKey.up: 'Up', TvKey.down: 'Down', TvKey.left: 'Left', TvKey.right: 'Right',
    TvKey.ok: 'Select', TvKey.back: 'Back', TvKey.home: 'Home', TvKey.menu: 'Info',
    TvKey.play: 'Play', TvKey.pause: 'Play', TvKey.source: 'InputTuner',
  };

  @override
  Future<void> send(TvKey key) async {
    final k = _keys[key];
    if (k == null) return;
    try {
      final req = await _client.postUrl(Uri.parse('http://$ip:8060/keypress/$k'));
      req.contentLength = 0;
      final res = await req.close();
      await res.drain<void>();
      if (res.statusCode == 403) {
        onState(TvLinkState.denied, '');
      }
    } catch (e) {
      onState(TvLinkState.error, '$e');
    }
  }

  @override
  Future<void> close() async => _client.close(force: true);
}
