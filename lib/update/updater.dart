import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// Distribution channel, set at build time:
///   flutter build apk --dart-define=CHANNEL=github   (test builds, self-update)
///   flutter build appbundle --dart-define=CHANNEL=play (store, no self-update)
const updateChannel = String.fromEnvironment('CHANNEL', defaultValue: 'github');

class AppRelease {
  AppRelease({required this.build, required this.name, required this.apkUrl, required this.notes});
  final int build;
  final String name;
  final String apkUrl;
  final String notes;
}

/// Checks GitHub Releases for a newer build and installs it in-app.
class Updater {
  Updater._();
  static final instance = Updater._();

  static const _repo = 'haiduy2405/zapio';
  static const _ch = MethodChannel('zapio/update');

  final _installErrors = StreamController<String>.broadcast();
  Stream<String> get installErrors => _installErrors.stream;

  bool _wired = false;
  void _wire() {
    if (_wired) return;
    _wired = true;
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'installFailed') _installErrors.add('${call.arguments}');
    });
  }

  Future<(int, String)> currentVersion() async {
    try {
      final m = await _ch.invokeMapMethod<String, dynamic>('versionCode');
      return ((m?['code'] as num?)?.toInt() ?? 0, (m?['name'] as String?) ?? '');
    } on MissingPluginException {
      return (0, '');
    }
  }

  /// Returns the newer release, or null if up to date / offline / Play build.
  Future<AppRelease?> check() async {
    if (updateChannel != 'github') return null;
    _wire();
    final (current, _) = await currentVersion();
    if (current <= 0) return null;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final req = await client
          .getUrl(Uri.parse('https://api.github.com/repos/$_repo/releases/latest'))
          .timeout(const Duration(seconds: 8));
      req.headers.set('Accept', 'application/vnd.github+json');
      req.headers.set('Cache-Control', 'no-cache');
      final res = await req.close().timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final j = jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>;
      final tag = (j['tag_name'] ?? '').toString(); // build-N
      final build = int.tryParse(tag.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      if (build <= current) return null;
      String? apk;
      for (final a in (j['assets'] as List? ?? const [])) {
        final url = (a as Map<String, dynamic>)['browser_download_url']?.toString() ?? '';
        if (url.endsWith('.apk')) apk = url;
      }
      if (apk == null) return null;
      return AppRelease(
        build: build,
        name: (j['name'] ?? tag).toString(),
        apkUrl: apk,
        notes: _cleanNotes((j['body'] ?? '').toString()),
      );
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static String _cleanNotes(String body) => body
      .split('\n')
      .where((l) =>
          !l.startsWith('Co-Authored-By') &&
          !l.startsWith('Claude-Session') &&
          l.trim().isNotEmpty)
      .take(12)
      .join('\n')
      .trim();

  /// Downloads the APK, reporting progress 0..1, and returns the file path.
  Future<String> download(AppRelease r, void Function(double p) onProgress) async {
    final dir = await _ch.invokeMethod<String>('cacheDir');
    final file = File('$dir/zapio-update-${r.build}.apk');
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(r.apkUrl));
      final res = await req.close();
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
      final total = res.contentLength;
      var got = 0;
      final sink = file.openWrite();
      await for (final chunk in res) {
        sink.add(chunk);
        got += chunk.length;
        if (total > 0) onProgress(got / total);
      }
      await sink.close();
      return file.path;
    } finally {
      client.close(force: true);
    }
  }

  Future<bool> canInstall() async => await _ch.invokeMethod<bool>('canInstall') ?? false;
  Future<void> openInstallSettings() => _ch.invokeMethod('openInstallSettings');
  Future<void> install(String path) => _ch.invokeMethod('installApk', {'path': path});
}
