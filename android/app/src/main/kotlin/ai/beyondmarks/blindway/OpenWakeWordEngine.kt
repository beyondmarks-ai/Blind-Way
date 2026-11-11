package ai.beyondmarks.blindway

import android.content.res.AssetManager
import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import java.nio.FloatBuffer

/** Streaming feature pipeline from openWakeWord (Apache-2.0).
 * Models and attribution: assets/openwakeword/NOTICE.md.
 * One call consumes exactly 80 ms of 16 kHz signed PCM.
 */
class OpenWakeWordEngine(private val assets: AssetManager) : AutoCloseable {
    private val env = OrtEnvironment.getEnvironment()
    private val options = OrtSession.SessionOptions().apply { setIntraOpNumThreads(1) }
    private fun load(name: String) = assets.open("openwakeword/$name").use {
        env.createSession(it.readBytes(), options)
    }
    private val mel = load("melspectrogram.onnx")
    private val embedding = load("embedding_model.onnx")
    private val wake = load("hey_jarvis_v0.1.onnx")
    private val overlap = FloatArray(480)
    private val spectrogram = FloatArray(76 * 32) { 1f }
    private val features = FloatArray(16 * 96)
    private var frames = 0
    fun reset() { overlap.fill(0f); spectrogram.fill(1f); features.fill(0f); frames=0 }
    private fun run(model: OrtSession, values: FloatArray, shape: LongArray): FloatArray {
        OnnxTensor.createTensor(env, FloatBuffer.wrap(values), shape).use { tensor ->
            model.run(mapOf(model.inputNames.first() to tensor)).use { result ->
                val buffer = (result[0] as OnnxTensor).floatBuffer
                return FloatArray(buffer.remaining()).also { buffer.get(it) }
            }
        }
    }
    fun predict(pcm: ShortArray): Float {
        require(pcm.size == 1280)
        val audio = FloatArray(1760)
        overlap.copyInto(audio)
        pcm.forEachIndexed { i, value -> audio[i + 480] = value.toFloat() }
        audio.copyInto(overlap, 0, 1280, 1760)
        val next = run(mel, audio, longArrayOf(1, 1760))
        require(next.size == 8 * 32) { "Unexpected mel shape" }
        spectrogram.copyInto(spectrogram, 0, next.size)
        next.forEachIndexed { i, value -> spectrogram[spectrogram.size-next.size+i] = value / 10f + 2f }
        val vector = run(embedding, spectrogram, longArrayOf(1,76,32,1))
        require(vector.size == 96)
        features.copyInto(features, 0, 96)
        vector.copyInto(features, features.size-96)
        frames++
        return if (frames < 20) 0f else run(wake, features, longArrayOf(1,16,96))[0]
    }
    override fun close() { wake.close(); embedding.close(); mel.close(); options.close() }
}
