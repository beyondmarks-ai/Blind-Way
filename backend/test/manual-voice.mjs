// Opt-in live service verification; uses a synthetic question WAV, never logs keys.
// npm run build first. Set SARVAM_API_KEY and AZURE_OPENAI_ENDPOINT; az login.
import {readFile,writeFile} from 'node:fs/promises';
import {transcribeQuestion,answerQuestion,sarvamSpeech,speechLanguage} from '../dist/voice.js';
const wav=await readFile(process.argv[2]);
const start=performance.now();
const transcript=await transcribeQuestion(wav);
const recognitionMs=Math.round(performance.now()-start);
const language=speechLanguage(transcript.detectedLanguage);
const image=process.argv[3] ? await readFile(process.argv[3]) : undefined;
const answer=await answerQuestion(transcript.question,image,language);
const answerMs=Math.round(performance.now()-start);
const response=await sarvamSpeech(answer,language);
const reader=response.body.getReader();
const first=await reader.read();
if(first.done || !first.value.length) throw new Error('Empty speech stream');
const firstAudioMs=Math.round(performance.now()-start);
const result={language,question:transcript.question,recognitionMs,answerMs,firstAudioMs,firstChunkBytes:first.value.length,answer};
if (process.argv[4]) {
  const chunks=[Buffer.from(first.value)];
  while(true) {
    const next=await reader.read();
    if(next.done) break;
    chunks.push(Buffer.from(next.value));
  }
  const audio=Buffer.concat(chunks);
  result.audioBytes=audio.length;
  result.completeAudioMs=Math.round(performance.now()-start);
  await writeFile(`${process.argv[4]}.mp3`,audio);
  await writeFile(`${process.argv[4]}.json`,JSON.stringify(result,null,2));
} else { await reader.cancel(); }
console.log(JSON.stringify(result));
