package ai.beyondmarks.blindway

import android.content.Context
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioDeviceInfo
import android.media.AudioDeviceCallback
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.content.pm.ApplicationInfo
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.sqrt

/** Owns the microphone; wake detection and question capture never compete. */
class VoiceCapture(private val context: Context, messenger: BinaryMessenger) {
    private val main = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    @Volatile private var running = false
    @Volatile private var recordQuestion = false
    @Volatile private var muted = false
    @Volatile private var captureId = 0
    @Volatile private var liveCapture = false
    private val debug = context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0
    private val playback = PcmPlayback(messenger, debug, { selectAudioRoute() }) { emit(it) }
    private var worker: Thread? = null
    private var recorder: AudioRecord? = null
    @Suppress("DEPRECATION", "MissingPermission")
    private fun selectAudioRoute() {
        val manager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        manager.mode = AudioManager.MODE_IN_COMMUNICATION
        if (Build.VERSION.SDK_INT >= 31) {
            val devices = manager.availableCommunicationDevices
            val preferred = devices.firstOrNull {
                it.type == AudioDeviceInfo.TYPE_BLE_HEADSET || it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO
            } ?: devices.firstOrNull {
                it.type == AudioDeviceInfo.TYPE_WIRED_HEADSET || it.type == AudioDeviceInfo.TYPE_USB_HEADSET ||
                    it.type == AudioDeviceInfo.TYPE_WIRED_HEADPHONES
            } ?: devices.firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER }
            check(preferred != null && manager.setCommunicationDevice(preferred)) { "Voice output route unavailable" }
            if(debug) Log.d("BlindWayAudio", "output_route=${preferred.type}")
        } else {
            val devices = manager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
            val bluetooth = devices.any { it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO }
            val wired = devices.any { it.type == AudioDeviceInfo.TYPE_WIRED_HEADSET || it.type == AudioDeviceInfo.TYPE_WIRED_HEADPHONES || it.type == AudioDeviceInfo.TYPE_USB_HEADSET }
            if(bluetooth) { manager.startBluetoothSco(); manager.isBluetoothScoOn=true }
            else { manager.stopBluetoothSco(); manager.isBluetoothScoOn=false }
            manager.isSpeakerphoneOn = !bluetooth && !wired
        }
    }
    init {
        EventChannel(messenger, "blindway/voice-events").setStreamHandler(object: EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) { sink = events }
            override fun onCancel(arguments: Any?) { sink = null; stop() }
        })
        MethodChannel(messenger, "blindway/voice").setMethodCallHandler { call, result ->
            when(call.method) {
                "start" -> start(result)
                "record", "recordLive" -> { liveCapture=call.method=="recordLive"; captureId = (call.arguments as Number).toInt(); recordQuestion = true; muted = false; result.success(null) }
                "mute" -> { muted = call.arguments == true; result.success(null) }
                "cancel" -> { recordQuestion = false; muted = true; result.success(null) }
                "stop" -> { stop(); result.success(null) }
                else -> result.notImplemented()
            }
        }
    }
    private fun emit(data: Map<String,Any>) {
        if(debug && data["type"] in setOf("wake","listening","liveEnd","noSpeech","error"))
            Log.d("BlindWayAudio", "event=${data["type"]} turn=${data["captureId"] ?: -1}")
        main.post { sink?.success(data) }
    }
    @Suppress("MissingPermission", "DEPRECATION")
    private fun start(result: MethodChannel.Result) {
        if (running) { result.success(null); return }
        if (worker?.isAlive == true) { result.error("MIC_BUSY", "Microphone is stopping. Try again.", null); return }
        running = true; recordQuestion = false; muted = false
        worker = Thread {
            var started = false
            val manager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val oldMode = manager.mode
            val oldSpeaker = manager.isSpeakerphoneOn
            val routeChanges = object : AudioDeviceCallback() {
                override fun onAudioDevicesAdded(added: Array<out AudioDeviceInfo>) { updateRoute() }
                override fun onAudioDevicesRemoved(removed: Array<out AudioDeviceInfo>) { updateRoute() }
                private fun updateRoute() {
                    if(running) try { selectAudioRoute() } catch(_:Exception) {
                        emit(mapOf("type" to "error", "message" to "Audio output disconnected. Restart voice listening."))
                    }
                }
            }
            try {
                OpenWakeWordEngine(context.assets).use { engine ->
                    selectAudioRoute()
                    val minimum = AudioRecord.getMinBufferSize(16000, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
                    val input = AudioRecord(MediaRecorder.AudioSource.VOICE_COMMUNICATION, 16000,
                        AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, maxOf(minimum, 1280*8))
                    recorder = input
                    check(input.state == AudioRecord.STATE_INITIALIZED) { "Microphone unavailable" }
                    input.startRecording(); started = true
                    manager.registerAudioDeviceCallback(routeChanges, main)
                    main.post { result.success(null) }
                    val frame = ShortArray(1280)
                    var offset = 0
                    var recording: ByteArrayOutputStream? = null
                    var total = 0; var voiced = 0; var silence = 0; var consecutive = 0
                    var wasMuted = false
                    var recordingId = -1
                    while(running) {
                        val count = input.read(frame, offset, frame.size-offset)
                        if(count <= 0) { if(running) error("Microphone read failed"); break }
                        offset += count
                        if(offset != frame.size) continue
                        offset = 0
                        if(muted || recordQuestion) {
                            if(!wasMuted) engine.reset()
                            wasMuted=true
                        } else if(wasMuted) { engine.reset(); wasMuted=false }
                        if(recordQuestion) {
                            if(recording == null || recordingId != captureId) { recordingId=captureId; recording = ByteArrayOutputStream(); total=0; voiced=0; silence=0; emit(mapOf("type" to "listening", "captureId" to recordingId)) }
                            val buffer = ByteBuffer.allocate(frame.size*2).order(ByteOrder.LITTLE_ENDIAN)
                            frame.forEach { buffer.putShort(it) }
                            if(liveCapture) emit(mapOf("type" to "liveAudio","captureId" to recordingId,"pcm" to buffer.array()))
                            else recording.write(buffer.array())
                            val rms = sqrt(frame.sumOf { it.toDouble()*it } / frame.size)
                            total++
                            if(rms > 350) { voiced++; silence=0 } else silence++
                            if((voiced >= 4 && silence >= (if(liveCapture) 8 else 9)) || total >= 150 || (voiced == 0 && total >= 63)) {
                                val pcm = recording.toByteArray(); recording = null
                                recordQuestion = false; muted = true
                                if(voiced < 4) emit(mapOf("type" to "noSpeech", "captureId" to recordingId))
                                else if(liveCapture) emit(mapOf("type" to "liveEnd", "captureId" to recordingId))
                                else emit(mapOf("type" to "audio", "wav" to wav(pcm), "captureId" to recordingId))
                            }
                        } else {
                            recording = null
                            if(!muted) {
                                consecutive = if(engine.predict(frame) >= 0.55f) consecutive+1 else 0
                                if(consecutive >= 2) { consecutive=0; muted=true; emit(mapOf("type" to "wake")) }
                            } else consecutive=0
                        }
                    }
                }
            } catch(error: Exception) {
                if(!started) main.post { result.error("VOICE_START_FAILED", "Could not start local wake-word listening.", null) }
                else if(running) emit(mapOf("type" to "error", "message" to "Microphone interrupted. Restart voice listening."))
            } finally {
                running=false; recordQuestion=false
                try { recorder?.stop() } catch(_:Exception) {}
                recorder?.release(); recorder=null
                manager.unregisterAudioDeviceCallback(routeChanges)
                try { if(Build.VERSION.SDK_INT >= 31) manager.clearCommunicationDevice()
                else { manager.stopBluetoothSco(); manager.isBluetoothScoOn=false } } catch (_: SecurityException) {}
                manager.mode=oldMode
                if(Build.VERSION.SDK_INT < 31) manager.isSpeakerphoneOn=oldSpeaker
            }
        }.apply { name="BlindWayVoice"; start() }
    }
    fun stop() {
        playback.stop()
        running=false; recordQuestion=false
        try { recorder?.stop() } catch(_:Exception) {}
        worker?.join(400)
    }
    fun dispose() {stop();playback.dispose()}
    private fun wav(pcm: ByteArray): ByteArray = ByteBuffer.allocate(44+pcm.size).order(ByteOrder.LITTLE_ENDIAN).apply {
        put("RIFF".toByteArray()); putInt(36+pcm.size); put("WAVEfmt ".toByteArray()); putInt(16)
        putShort(1); putShort(1); putInt(16000); putInt(32000); putShort(2); putShort(16)
        put("data".toByteArray()); putInt(pcm.size); put(pcm)
    }.array()
}
