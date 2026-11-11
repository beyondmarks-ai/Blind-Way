// Manual real-Vertex check with synthetic speech, never a phone navigation action.
import {readFileSync} from 'node:fs';
import {VertexSession} from './vertex.mjs';
const wave=readFileSync(process.env.CONFIRMATION_WAV);
let pcm;
for(let i=12;i+8<=wave.length;) {
  const size=wave.readUInt32LE(i+4);
  if(wave.toString('ascii',i,i+4)==='data'){pcm=wave.subarray(i+8,i+8+size);break;}
  i+=8+size+(size%2);
}
if(!pcm?.length)throw Error('No synthetic PCM data');
const prompt=process.env.CONFIRMATION_PROMPT??'destination';
const expected=process.env.CONFIRMATION_ACTION??'confirm';
console.log(JSON.stringify(await new Promise((resolve,reject)=>{
  let command=null,done=false;
  const finish=error=>{if(done)return;done=true;clearTimeout(timer);session.close();error?reject(error):resolve({prompt,command,syntheticAudio:true});};
  const timer=setTimeout(()=>finish(Error('Confirmation timed out')),30000);
  const session=new VertexSession({project:process.env.GOOGLE_CLOUD_PROJECT,token:process.env.VERTEX_TEST_TOKEN,language:process.env.CONFIRMATION_LANGUAGE??'en-IN',onEvent:event=>{
    if(event.type==='ready')void (async()=>{
      session.begin(1,prompt,process.env.PROMPT_LANGUAGE??'auto');
      for(let i=0;i<pcm.length;i+=2560){session.audio(pcm.subarray(i,i+2560).toString('base64'));await new Promise(r=>setTimeout(r,80));}
      session.end();
    })().catch(finish);
    if(event.type==='navigation')command=event.command;
    if(process.env.CHECK_DEBUG&&['transcript','answer','navigation'].includes(event.type))console.log(JSON.stringify(event));
    if(event.type==='end')finish(command?.action===expected&&(!process.env.EXPECTED_SPOKEN_LANGUAGE||command.spokenLanguage===process.env.EXPECTED_SPOKEN_LANGUAGE)?null:Error('Expected confirmation action/language was not produced'));
    if(event.type==='error')finish(Error(event.message));
  }});
})));
