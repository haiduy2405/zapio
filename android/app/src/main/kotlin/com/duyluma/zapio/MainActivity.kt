package com.duyluma.zapio

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.hardware.ConsumerIrManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import java.io.File
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Zapio IR bridge: exposes Android's ConsumerIrManager to Dart over the
 * "zapio/ir" method channel.
 */
class MainActivity : FlutterActivity() {

    private var updateChannel: MethodChannel? = null
    private var androidTv: AndroidTvChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        setupUpdateChannel(flutterEngine)
        androidTv = AndroidTvChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        val ir = getSystemService(Context.CONSUMER_IR_SERVICE) as? ConsumerIrManager

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "zapio/ir")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasEmitter" -> result.success(ir?.hasIrEmitter() == true)

                    "carrierFrequencies" -> {
                        val ranges = try {
                            ir?.carrierFrequencies?.map { listOf(it.minFrequency, it.maxFrequency) }
                        } catch (e: Exception) {
                            null
                        }
                        result.success(ranges ?: emptyList<List<Int>>())
                    }

                    "transmit" -> {
                        val freq = call.argument<Int>("frequency")
                        val pattern = call.argument<IntArray>("pattern")
                        if (ir == null || !ir.hasIrEmitter()) {
                            result.error("NO_IR", "This phone has no IR emitter", null)
                        } else if (freq == null || pattern == null || pattern.isEmpty()) {
                            result.error("BAD_ARGS", "Missing frequency or pattern", null)
                        } else {
                            // Many phones only support a few fixed carriers (e.g. vivo: 30/33/36/38/40/56 kHz).
                            val carrier = nearestCarrier(ir, freq)
                            // transmit() blocks until the signal is sent, keep it off the UI thread.
                            Thread {
                                try {
                                    ir.transmit(carrier, pattern)
                                    runOnUiThread { result.success(carrier) }
                                } catch (e: Exception) {
                                    runOnUiThread { result.error("TX_FAIL", e.message, null) }
                                }
                            }.start()
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        androidTv?.dispose()
        androidTv = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun nearestCarrier(ir: ConsumerIrManager, freq: Int): Int {
        val ranges = try { ir.carrierFrequencies } catch (e: Exception) { null }
        if (ranges == null || ranges.isEmpty()) return freq
        var best = freq
        var bestDiff = Int.MAX_VALUE
        for (r in ranges) {
            if (freq in r.minFrequency..r.maxFrequency) return freq
            for (c in intArrayOf(r.minFrequency, r.maxFrequency)) {
                val d = kotlin.math.abs(c - freq)
                if (d < bestDiff) { bestDiff = d; best = c }
            }
        }
        return best
    }

    // ------------------------------------------------------------- updater
    // Test builds (GitHub channel) update themselves: Dart downloads the APK,
    // we stream it into a PackageInstaller session and Android shows the
    // standard "Update this app?" confirmation. Play builds must not ship this
    // (Play policy) and use Play In-App Updates instead.

    private fun setupUpdateChannel(engine: FlutterEngine) {
        val ch = MethodChannel(engine.dartExecutor.binaryMessenger, "zapio/update")
        updateChannel = ch
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "versionCode" -> {
                    val info = packageManager.getPackageInfo(packageName, 0)
                    val code = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode
                               else @Suppress("DEPRECATION") info.versionCode.toLong()
                    result.success(mapOf("code" to code, "name" to (info.versionName ?: "")))
                }
                "cacheDir" -> result.success(cacheDir.absolutePath)
                "canInstall" -> result.success(
                    if (Build.VERSION.SDK_INT >= 26) packageManager.canRequestPackageInstalls() else true
                )
                "openInstallSettings" -> {
                    if (Build.VERSION.SDK_INT >= 26) {
                        startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                            Uri.parse("package:$packageName")))
                    }
                    result.success(true)
                }
                "installApk" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("BAD_ARGS", "path missing", null)
                    } else {
                        Thread {
                            try {
                                installViaSession(File(path))
                                runOnUiThread { result.success(true) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("INSTALL_FAIL", e.message, null) }
                            }
                        }.start()
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun installViaSession(file: File) {
        val installer = packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
        params.setSize(file.length())
        val id = installer.createSession(params)
        installer.openSession(id).use { session ->
            file.inputStream().use { input ->
                session.openWrite("zapio.apk", 0, file.length()).use { out ->
                    input.copyTo(out)
                    session.fsync(out)
                }
            }
            val intent = Intent(this, MainActivity::class.java).setAction(ACTION_INSTALL_STATUS)
            var flags = PendingIntent.FLAG_UPDATE_CURRENT
            if (Build.VERSION.SDK_INT >= 31) flags = flags or PendingIntent.FLAG_MUTABLE
            val pending = PendingIntent.getActivity(this, 0, intent, flags)
            session.commit(pending.intentSender)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.action != ACTION_INSTALL_STATUS) return
        val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, -999)
        if (status == PackageInstaller.STATUS_PENDING_USER_ACTION) {
            val confirm: Intent? = if (Build.VERSION.SDK_INT >= 33)
                intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
            else @Suppress("DEPRECATION") intent.getParcelableExtra(Intent.EXTRA_INTENT)
            if (confirm != null) startActivity(confirm)
        } else if (status != PackageInstaller.STATUS_SUCCESS) {
            val msg = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE) ?: "status $status"
            updateChannel?.invokeMethod("installFailed", msg)
        }
    }

    companion object {
        private const val ACTION_INSTALL_STATUS = "com.duyluma.zapio.INSTALL_STATUS"
    }
}
