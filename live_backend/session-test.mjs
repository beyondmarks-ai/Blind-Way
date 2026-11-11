// Real Vertex test: one connection, continuous frames, successive language changes.
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {VertexSession} from './vertex.mjs';
const folder=process.argv[2],image=(await readFile(process.argv[3])).toString('base64');
await mkdir(folder,{recursive:true});
let resolveReady,rejectReady,finishTurn,rejectTurn,current,frames=0,frameBusy=false;
const ready=new Promise((r,j)=>{resolveReady=r;rejectReady=j});
const started=Date.now();
const session=new VertexSession({project:process.env.GOOGLE_CLOUD_PROJECT,token:process.env.VERTEX_TEST_TOKEN,onEvent:event=>{
 if(event.type==='ready'){resolveReady();return;}
 if(event.type==='error'||event.type==='closed'){rejectReady(new Error(event.message??'Closed'));rejectTurn?.(new Error(event.message??'Closed'));return;}
 if(!current||event.turn!==current.turn)return;
 if(event.type==='audio'){current.first??=Date.now();current.audio.push(Buffer.from(event.data,'base64'));}
 if(event.type==='answer')current.answer+=event.text;
 if(event.type==='transcript')current.question+=event.text;
 if(event.type==='sos')current.sos=true;
 if(event.type==='end')finishTurn();
}});
let frameTimer;
try {
 await Promise.race([ready,new Promise((_,j)=>setTimeout(()=>j(new Error('Setup timeout')),20000).unref())]);
 const setupMs=Date.now()-started;
 const frame=async()=>{
  if(frameBusy)return;frameBusy=true;
  try {
   let data=image;
   if(process.env.CAMERA_TEST_URL){
    const response=await fetch(`${process.env.CAMERA_TEST_URL}/capture`,{signal:AbortSignal.timeout(1500)});
    if(!response.ok)throw new Error('Camera unavailable');
    const jpeg=Buffer.from(await response.arrayBuffer());data=jpeg.toString('base64');
    await writeFile(`${folder}/camera-${frames}.jpg`,jpeg);
   }
   session.frame(data);frames++;
  } catch(error){rejectTurn?.(error);} finally {frameBusy=false;}
 };await frame();frameTimer=setInterval(frame,1000);
 const results=[];
 for(const [index,path] of process.argv.slice(4).entries()){
  current={turn:index+1,question:'',answer:'',audio:[],sos:false};
  const done=new Promise((r,j)=>{finishTurn=r;rejectTurn=j});
  session.begin(current.turn);
  const wav=await readFile(path);const start=wav.indexOf(Buffer.from('data'),12)+8;
  for(let i=start;i<wav.length;i+=2560){session.audio(wav.subarray(i,i+2560).toString('base64'));await new Promise(r=>setTimeout(r,80));}
  const speechEnd=Date.now();session.end();
  await Promise.race([done,new Promise((_,j)=>setTimeout(()=>j(new Error('Turn timeout')),25000).unref())]);
  const result={turn:current.turn,question:current.question,answer:current.answer,sos:current.sos,firstAudioAfterSpeechMs:current.first-speechEnd,completeAfterSpeechMs:Date.now()-speechEnd};
  await writeFile(`${folder}/turn-${current.turn}.pcm`,Buffer.concat(current.audio));
  results.push(result);console.log(JSON.stringify(result));
 }
 await writeFile(`${folder}/session-results.json`,JSON.stringify({model:'gemini-3.8-live',setupMs,framesSent:frames,results},null,2));
} finally {clearInterval(frameTimer);rejectTurn=null;session.close();}
