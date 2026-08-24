package ai.beyondmarks.blindway

import android.content.Context
import android.content.Intent
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Bundle
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "blindway/system")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openBluetoothSettings" -> {
                        startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS))
                        result.success(null)
                    }
                    "hasBluetoothAudio" -> {
                        val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                        val connected = audio.getDevices(AudioManager.GET_DEVICES_OUTPUTS).any {
                            it.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP ||
                                it.type == AudioDeviceInfo.TYPE_BLE_HEADSET ||
                                it.type == AudioDeviceInfo.TYPE_BLE_SPEAKER
                        }
                        result.success(connected)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
