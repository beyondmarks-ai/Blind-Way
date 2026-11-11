"""Check the Android pipeline's tensor contract with real bundled ONNX models.
Run with numpy/onnxruntime; optional 16 kHz WAV argument checks a wake sample.
"""
import pathlib, sys, wave
import numpy as np
import onnxruntime as ort

root = pathlib.Path(__file__).resolve().parents[1] / 'android/app/src/main/assets/openwakeword'
models = [ort.InferenceSession(str(root / name), providers=['CPUExecutionProvider']) for name in
          ['melspectrogram.onnx','embedding_model.onnx','hey_jarvis_v0.1.onnx']]
def run(model, values):
    return model.run(None,{model.get_inputs()[0].name:values})[0]
audio = np.zeros(16000*3,dtype=np.int16)
if len(sys.argv)>1:
    with wave.open(sys.argv[1]) as source:
        assert source.getframerate()==16000 and source.getnchannels()==1
        audio=np.concatenate([audio,np.frombuffer(source.readframes(source.getnframes()),dtype='<i2'),np.zeros(16000*2,dtype=np.int16)])
overlap=np.zeros(480,dtype=np.float32)
spec=np.ones((76,32),dtype=np.float32)
features=np.zeros((16,96),dtype=np.float32)
scores=[]
for n in range(0,len(audio)-1280+1,1280):
    chunk=np.concatenate([overlap,audio[n:n+1280].astype(np.float32)])
    overlap=chunk[-480:]
    mel=run(models[0],chunk[None]).reshape(-1,32)
    assert mel.shape==(8,32),mel.shape
    spec=np.concatenate([spec[8:],mel/10+2])
    embedding=run(models[1],spec[None,:,:,None]).reshape(-1)
    assert embedding.shape==(96,),embedding.shape
    features=np.concatenate([features[1:],embedding[None]])
    score=float(run(models[2],features[None]).flatten()[0]) if n//1280>=19 else 0
    scores.append(score)
print({'frames':len(scores),'silence_max':max(scores[:35]),'max_score':max(scores),
       'two_frame_detection':any(a>=.55 and b>=.55 for a,b in zip(scores,scores[1:]))})
assert max(scores[:35])<.55,'Silence falsely activated wake phrase'
if len(sys.argv)>1:
    assert any(a>=.55 and b>=.55 for a,b in zip(scores,scores[1:])),'Wake sample not detected'
