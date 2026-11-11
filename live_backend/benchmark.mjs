import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {VertexSession} from './vertex.mjs';
const folder=process.argv[2];
const image=(await readFile(process.argv[3])).toString('base64');
await mkdir(folder,{recursive:true});
for(const model of ['gemini-3.8-live','gemini-live-2.5-flash-native-audio']) {
 const events=[]; let setupAt=Date.now(); let endedAt=0; let firstAt=0; const chunks=[];
 await new Promise((resolve,reject)=>{
  const timer=setTimeout(()=>{session.close();reject(new Error('Live benchmark timeout'))},40000);
  const session=new VertexSession({project:process.env.GOOGLE_CLOUD_PROJECT,model,token:process.env.VERTEX_TEST_TOKEN,
   onEvent: async event=>{
    if(event.type==='ready') {
      events.push({setupMs:Date.now()-setupAt});session.frame(image);session.begin(1);
      const wav=await readFile(process.argv[4]);
      // Fixtures are WAV PCM; find their data chunk (not all WAV headers are 44 bytes).
      const dataAt=wav.indexOf(Buffer.from('data'),12)+8;
      for(let i=dataAt;i<wav.length;i+=2560) {session.audio(wav.subarray(i,i+2560).toString('base64'));await new Promise(r=>setTimeout(r,80));}
      endedAt=Date.now();session.end();
    } else if(event.type==='audio') {if(!firstAt) firstAt=Date.now();chunks.push(Buffer.from(event.data,'base64'));}
    else if(event.type==='end') {
      clearTimeout(timer);
      const result={model,firstAudioAfterSpeechMs:firstAt-endedAt,completedAfterSpeechMs:Date.now()-endedAt,events};
      await writeFile(`${folder}/${model}.pcm`,Buffer.concat(chunks));
      await writeFile(`${folder}/${model}.json`,JSON.stringify(result,null,2));console.log(JSON.stringify(result));session.close();resolve();
    } else if(['transcript','answer'].includes(event.type)) events.push(event);
    else if(['error','closed'].includes(event.type)&&!chunks.length) {clearTimeout(timer);console.log(event);session.close();reject(new Error('Vertex benchmark failed'));}
   }});
 });
}
