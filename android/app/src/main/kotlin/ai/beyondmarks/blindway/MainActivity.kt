package ai.beyondmarks.blindway

import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Bundle
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions

class MainActivity : FlutterActivity() {
    private var voiceCapture: VoiceCapture? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        voiceCapture = VoiceCapture(this, flutterEngine.dartExecutor.binaryMessenger)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "blindway/text-recognition")
            .setMethodCallHandler { call, result ->
                if (call.method != "recognize") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val jpeg = call.arguments as? ByteArray
                if (jpeg == null || jpeg.isEmpty() || jpeg.size > 5 * 1024 * 1024) {
                    result.error("INVALID_IMAGE", "Invalid reading image.", null)
                    return@setMethodCallHandler
                }
                val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeByteArray(jpeg, 0, jpeg.size, bounds)
                if (bounds.outWidth <= 0 || bounds.outHeight <= 0 ||
                    bounds.outWidth.toLong() * bounds.outHeight > 4_000_000) {
                    result.error("INVALID_IMAGE", "Unsupported reading image dimensions.", null)
                    return@setMethodCallHandler
                }
                val bitmap = BitmapFactory.decodeByteArray(jpeg, 0, jpeg.size)
                if (bitmap == null) {
                    result.error("INVALID_IMAGE", "Could not decode reading image.", null)
                    return@setMethodCallHandler
                }
                val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
                recognizer.process(InputImage.fromBitmap(bitmap, 0))
                    .addOnSuccessListener { text -> result.success(text.text) }
                    .addOnFailureListener { error ->
                        result.error("OCR_FAILED", "Text recognition failed. Try a clearer photo.", error.message)
                    }
                    .addOnCompleteListener {
                        recognizer.close()
                        bitmap.recycle()
                    }
            }
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

    override fun onDestroy() {
        voiceCapture?.dispose()
        super.onDestroy()
    }
}
