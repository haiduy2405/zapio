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
  static const _timeout = Duration(seconds: 7);
  static final _buildTag = RegExp(r'^build-([1-9][0-9]*)$');

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

  /// Returns the newer release or null if up to date. Network failures throw.
  Future<AppRelease?> check() async {
    if (updateChannel != 'github') return null;
    _wire();
    final (current, _) = await currentVersion();
    if (current <= 0) throw StateError('Could not read the installed ZAPIO build number');
    final client = HttpClient()
      ..connectionTimeout = _timeout
      ..userAgent = 'Zapio';
    try {
      AppRelease latest;
      try {
        latest = await _checkApi(client);
      } catch (_) {
        latest = await _checkReleasePage(client);
      }
      return latest.build > current ? latest : null;
    } finally {
      client.close(force: true);
    }
  }

  static String _apkUrl(int build) =>
      'https://github.com/$_repo/releases/download/build-$build/zapio-build-$build.apk';

  Future<AppRelease> _checkApi(HttpClient client) async {
    final endpoint = Uri.https('api.github.com', '/repos/$_repo/releases/latest');
    final request = await client.getUrl(endpoint).timeout(_timeout);
    request.headers.set('Accept', 'application/vnd.github+json');
    request.headers.set('Cache-Control', 'no-cache');
    final response = await request.close().timeout(_timeout);
    if (response.statusCode != 200) throw HttpException('GitHub API HTTP ${response.statusCode}');
    final body = await response.transform(utf8.decoder).join().timeout(_timeout);
    final data = jsonDecode(body) as Map<String, dynamic>;
    final build = int.parse(_buildTag.firstMatch(data['tag_name'] as String)!.group(1)!);
    final url = _apkUrl(build);
    final assets = data['assets'] as List;
    if (!assets.any((asset) => asset is Map && asset['browser_download_url'] == url)) {
      throw const FormatException('The latest release has no ZAPIO APK');
    }
    return AppRelease(
      build: build,
      name: data['name']?.toString() ?? 'Zapio build $build',
      apkUrl: url,
      notes: _cleanNotes(data['body']?.toString() ?? ''),
    );
  }

  Future<AppRelease> _checkReleasePage(HttpClient client) async {
    final endpoint = Uri.https('github.com', '/$_repo/releases/latest');
    final request = await client.getUrl(endpoint).timeout(_timeout);
    request.followRedirects = false;
    request.headers.set('Cache-Control', 'no-cache');
    final response = await request.close().timeout(_timeout);
    final location = response.headers.value(HttpHeaders.locationHeader);
    if (!response.isRedirect || location == null) {
      throw HttpException('GitHub Releases HTTP ${response.statusCode}');
    }
    final target = endpoint.resolve(location);
    const prefix = '/$_repo/releases/tag/';
    if (target.scheme != 'https' || target.host != endpoint.host ||
        !target.path.startsWith(prefix)) {
      throw const FormatException('GitHub did not return a ZAPIO release');
    }
    final match = _buildTag.firstMatch(target.path.substring(prefix.length));
    if (match == null) throw const FormatException('Unrecognized ZAPIO build tag');
    final build = int.parse(match.group(1)!);
    return AppRelease(build: build, name: 'Zapio build $build', apkUrl: _apkUrl(build), notes: '');
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
