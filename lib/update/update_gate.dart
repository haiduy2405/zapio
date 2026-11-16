import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n.dart';
import '../ui/theme.dart';
import 'updater.dart';

/// Wraps the app: checks for a newer build on launch and every time the app
/// returns to the foreground, then shows a blocking "Update now" dialog.
class UpdateGate extends StatefulWidget {
  const UpdateGate({super.key, required this.navigatorKey, required this.child});
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  State<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<UpdateGate> with WidgetsBindingObserver {
  bool _showing = false;
  DateTime _lastCheck = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    if (_showing) return;
    // At most one network check every 20 s (resume can fire repeatedly).
    if (DateTime.now().difference(_lastCheck) < const Duration(seconds: 20)) return;
    _lastCheck = DateTime.now();
    final r = await Updater.instance.check();
    final ctx = widget.navigatorKey.currentContext;
    if (r == null || ctx == null || !ctx.mounted || _showing) return;
    _showing = true;
    await showGeneralDialog<void>(
      context: ctx,
      barrierDismissible: false,
      barrierColor: const Color(0xCC000000),
      pageBuilder: (_, __, ___) => UpdateDialog(release: r),
      transitionBuilder: (_, a, __, child) => FadeTransition(
        opacity: a,
        child: ScaleTransition(scale: Tween(begin: 0.94, end: 1.0).animate(a), child: child),
      ),
    );
    _showing = false;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class UpdateDialog extends StatefulWidget {
  const UpdateDialog({super.key, required this.release});
  final AppRelease release;

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

enum _Phase { ready, downloading, installing, needPermission, failed }

class _UpdateDialogState extends State<UpdateDialog> with WidgetsBindingObserver {
  _Phase _phase = _Phase.ready;
  double _progress = 0;
  String _error = '';
  String? _apkPath;
  StreamSubscription<String>? _sub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sub = Updater.instance.installErrors.listen((e) {
      if (mounted) {
        setState(() {
          _phase = _Phase.failed;
          _error = e;
        });
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from the system installer / settings without updating: allow retry.
    if (state == AppLifecycleState.resumed &&
        (_phase == _Phase.installing || _phase == _Phase.needPermission)) {
      setState(() => _phase = _Phase.ready);
    }
  }

  Future<void> _start() async {
    final u = Updater.instance;
    try {
      if (_apkPath == null) {
        setState(() => _phase = _Phase.downloading);
        _apkPath = await u.download(widget.release, (p) {
          if (mounted) setState(() => _progress = p);
        });
      }
      if (!await u.canInstall()) {
        setState(() => _phase = _Phase.needPermission);
        return;
      }
      setState(() => _phase = _Phase.installing);
      await u.install(_apkPath!);
    } catch (e) {
      if (mounted) {
        setState(() {
          _phase = _Phase.failed;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _phase == _Phase.downloading || _phase == _Phase.installing;
    return PopScope(
      canPop: false,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Material(
            color: Colors.transparent,
            child: LuxCard(
              highlight: true,
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 68,
                  height: 68,
                  decoration: const BoxDecoration(shape: BoxShape.circle, gradient: Lux.goldGradient),
                  child: const Icon(Icons.auto_awesome_rounded, color: Color(0xFF1A1407), size: 32),
                ),
                const SizedBox(height: 18),
                GoldText(
                  tr(context, 'New version available', 'Đã có phiên bản mới'),
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  tr(context, 'Build ${widget.release.build} • update to keep using Zapio',
                      'Bản ${widget.release.build} • cập nhật để tiếp tục dùng Zapio'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Lux.muted, fontSize: 13),
                ),
                if (widget.release.notes.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 140),
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0x0DFFFFFF),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: SingleChildScrollView(
                      child: Text(widget.release.notes,
                          style: const TextStyle(fontSize: 13, height: 1.45, color: Lux.text)),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                if (_phase == _Phase.downloading) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(value: _progress == 0 ? null : _progress, minHeight: 8),
                  ),
                  const SizedBox(height: 8),
                  Text('${(_progress * 100).round()}%', style: const TextStyle(color: Lux.muted)),
                  const SizedBox(height: 8),
                ],
                if (_phase == _Phase.needPermission)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      tr(context,
                          'Allow Zapio to install updates, then come back and tap Update again.',
                          'Hãy cho phép Zapio cài đặt bản cập nhật, rồi quay lại bấm Cập nhật lần nữa.'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Lux.goldLight, fontSize: 13),
                    ),
                  ),
                if (_phase == _Phase.failed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      '${tr(context, 'Update failed', 'Cập nhật lỗi')}: $_error',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Lux.ruby, fontSize: 13),
                    ),
                  ),
                SizedBox(
                  width: double.infinity,
                  child: _phase == _Phase.needPermission
                      ? Row(children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: Updater.instance.openInstallSettings,
                              child: Text(tr(context, 'Open settings', 'Mở cài đặt')),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton(
                              onPressed: _start,
                              child: Text(tr(context, 'Update', 'Cập nhật')),
                            ),
                          ),
                        ])
                      : FilledButton(
                          onPressed: busy ? null : _start,
                          child: Text(busy
                              ? (_phase == _Phase.installing
                                  ? tr(context, 'Installing…', 'Đang cài đặt…')
                                  : tr(context, 'Downloading…', 'Đang tải…'))
                              : _phase == _Phase.failed
                                  ? tr(context, 'Try again', 'Thử lại')
                                  : tr(context, 'Update now', 'Cập nhật ngay')),
                        ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
