// Manual, real Vertex check. Synthetic conversation only; no camera/user audio.
import {VertexSession} from './vertex.mjs';
for(const language of (process.argv.length>2?process.argv.slice(2):['en-IN','ta-IN','fr-FR'])) {
  const result=await new Promise((resolve,reject)=>{
    let answer='',bytes=0,done=false;
    const finish=(error)=>{if(done)return;done=true;clearTimeout(timer);session.close();error?reject(error):resolve({language,answer,audioBytes:bytes});};
    const timer=setTimeout(()=>finish(Error('Language check timed out')),35000);
    const session=new VertexSession({project:process.env.GOOGLE_CLOUD_PROJECT,token:process.env.VERTEX_TEST_TOKEN,language,
      memory:[{question:'What was on the table?',answer:'मेज पर एक किताब थी।'}],
      onEvent:event=>{
        if(event.type==='ready')session.send({clientContent:{turns:[{role:'user',parts:[{text:'According to our earlier conversation, what was on the table?'}]}],turnComplete:true}});
        if(event.type==='answer')answer+=event.text;
        if(event.type==='audio')bytes+=Buffer.from(event.data,'base64').length;
        if(event.type==='end')finish();
        if(event.type==='error'||event.type==='closed')finish(Error(event.message??event.reason??'Connection closed'));
      }});
  });
  console.log(JSON.stringify(result));
}
