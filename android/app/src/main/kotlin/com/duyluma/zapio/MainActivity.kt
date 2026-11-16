package com.duyluma.zapio

import android.content.Context
import android.hardware.ConsumerIrManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Zapio IR bridge: exposes Android's ConsumerIrManager to Dart over the
 * "zapio/ir" method channel.
 */
class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
                            // transmit() blocks until the signal is sent, keep it off the UI thread.
                            Thread {
                                try {
                                    ir.transmit(freq, pattern)
                                    runOnUiThread { result.success(true) }
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
}
