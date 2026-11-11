package ai.beyondmarks.blindway

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger

/** Buffer a complete short reply so mobile-network gaps cannot interrupt words. */
class PcmPlayback(messenger: BinaryMessenger, private val debug: Boolean, private val prepareOutput: () -> Unit, private val event: (Map<String,Any>) -> Unit) {
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val epoch = AtomicInteger()
    @Volatile private var turn = -1
    @Volatile private var track: AudioTrack? = null
    private var pending = ByteArrayOutputStream()
    private var written = 0L
    init {
        MethodChannel(messenger,"blindway/live-audio").setMethodCallHandler { call,result ->
            when(call.method) {
                "start" -> {
                    stop(); turn=(call.arguments as Number).toInt(); val generation=epoch.get()
                    worker.execute { if(generation==epoch.get()) { pending=ByteArrayOutputStream();written=0 } }
                    result.success(null)
                }
                "chunk" -> {
                    val args=call.arguments as Map<*,*>;val id=(args["turn"] as Number).toInt();val bytes=args["pcm"] as ByteArray
                    val generation=epoch.get()
                    if(id==turn) worker.execute {
                        if(generation==epoch.get() && id==turn) {
                            // Bound memory to 120 seconds of 24 kHz mono audio.
                            if(bytes.size>262144 || bytes.size%2!=0 || pending.size()+bytes.size>5760000) reportError(generation)
                            else pending.write(bytes)
                        }
                    }
                    result.success(null)
                }
                "end" -> {
                    val id=(call.arguments as Number).toInt();val generation=epoch.get()
                    worker.execute {
                        if(generation!=epoch.get() || id!=turn) return@execute
                        try {
                            val bytes=pending.toByteArray();pending=ByteArrayOutputStream()
                            if(bytes.isEmpty()) {reportError(generation);return@execute}
                            prepareOutput()
                            val output=AudioTrack.Builder()
                                .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION).setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
                                .setAudioFormat(AudioFormat.Builder().setSampleRate(24000).setChannelMask(AudioFormat.CHANNEL_OUT_MONO).setEncoding(AudioFormat.ENCODING_PCM_16BIT).build())
                                .setTransferMode(AudioTrack.MODE_STATIC).setBufferSizeInBytes(bytes.size).build()
                            if(generation!=epoch.get()) {output.release();return@execute}
                            track=output
                            val count=output.write(bytes,0,bytes.size,AudioTrack.WRITE_BLOCKING)
                            if(count!=bytes.size) {reportError(generation);return@execute}
                            written=count.toLong()/2
                            if(generation!=epoch.get() || id!=turn) return@execute
                            output.play()
                            val started=SystemClock.elapsedRealtime()
                            if(debug) Log.d("BlindWayAudio","first_pcm turn=$id route=${output.routedDevice?.type} buffered_frames=$written")
                            var lastPosition=-1L;var progressAt=started
                            while(generation==epoch.get() && id==turn) {
                                val position=output.playbackHeadPosition.toLong().and(0xffffffffL)
                                if(position>=written) break
                                if(position!=lastPosition) {lastPosition=position;progressAt=SystemClock.elapsedRealtime()}
                                if(SystemClock.elapsedRealtime()-progressAt>10000) {reportError(generation);return@execute}
                                Thread.sleep(20)
                            }
                            if(generation==epoch.get() && id==turn) {
                                if(debug) Log.d("BlindWayAudio","playback_done turn=$id frames=$written elapsed_ms=${SystemClock.elapsedRealtime()-started}")
                                event(mapOf("type" to "playbackDone","captureId" to id))
                            }
                        } catch(_:Exception) {reportError(generation)}
                    }
                    result.success(null)
                }
                "stop" -> {stop();result.success(null)}
                else -> result.notImplemented()
            }
        }
    }
    private fun reportError(generation:Int) {
        val failedTurn=turn
        main.post {if(generation==epoch.get() && failedTurn==turn) event(mapOf("type" to "playbackError","captureId" to failedTurn))}
    }
    fun stop() {
        epoch.incrementAndGet();val oldTurn=turn;turn=-1;val old=track;track=null
        try {old?.pause();old?.flush();old?.release()}catch(_:Exception){}
        if(debug && old!=null) Log.d("BlindWayAudio","playback_stopped turn=$oldTurn frames=$written")
    }
    fun dispose() {stop();worker.shutdownNow()}
}
