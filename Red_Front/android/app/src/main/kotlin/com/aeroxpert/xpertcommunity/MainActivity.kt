package com.aeroxpert.xpertcommunity

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.GnssStatus
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import androidx.core.app.ActivityCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicBoolean

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "xpertcommunity/gnss")
            .setMethodCallHandler { call, result ->
                if (call.method != "getStatus") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                if (ActivityCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) !=
                    PackageManager.PERMISSION_GRANTED
                ) {
                    result.error("PERMISSION", "Location permission is required", null)
                    return@setMethodCallHandler
                }
                val manager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
                val completed = AtomicBoolean(false)
                lateinit var callback: GnssStatus.Callback
                val locationListener = object : LocationListener {
                    override fun onLocationChanged(location: Location) = Unit
                    @Deprecated("Deprecated in Android")
                    override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) = Unit
                    override fun onProviderEnabled(provider: String) = Unit
                    override fun onProviderDisabled(provider: String) = Unit
                }
                fun finish(payload: Map<String, Any>?) {
                    if (!completed.compareAndSet(false, true)) return
                    manager.unregisterGnssStatusCallback(callback)
                    manager.removeUpdates(locationListener)
                    if (payload == null) result.success(null) else result.success(payload)
                }
                callback = object : GnssStatus.Callback() {
                    override fun onSatelliteStatusChanged(status: GnssStatus) {
                        var used = 0
                        for (index in 0 until status.satelliteCount) {
                            if (status.usedInFix(index)) used++
                        }
                        finish(mapOf("visible" to status.satelliteCount, "used" to used))
                    }
                }
                manager.registerGnssStatusCallback(callback, Handler(Looper.getMainLooper()))
                manager.requestLocationUpdates(
                    LocationManager.GPS_PROVIDER,
                    1_000L,
                    0f,
                    locationListener,
                    Looper.getMainLooper(),
                )
                Handler(Looper.getMainLooper()).postDelayed({ finish(null) }, 12_000)
            }
    }
}
