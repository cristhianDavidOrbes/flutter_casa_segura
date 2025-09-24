package com.example.flutter_seguridad_en_casa

import android.content.Context
import android.net.wifi.WifiManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private var multicastLock: WifiManager.MulticastLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "lan_discovery"                     // <- mismo nombre que usamos en Dart
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "acquireMulticast" -> {
                    try {
                        val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                        multicastLock = wifi.createMulticastLock("mdns_lock").apply {
                            setReferenceCounted(true)
                            acquire()
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("LOCK_ERROR", e.message, null)
                    }
                }
                "releaseMulticast" -> {
                    try {
                        multicastLock?.let { if (it.isHeld) it.release() }
                        multicastLock = null
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("LOCK_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        multicastLock?.let { if (it.isHeld) it.release() }
        multicastLock = null
        super.onDestroy()
    }
}
