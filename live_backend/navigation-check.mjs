// Manual cloud check using synthetic destinations; does not start phone tracking.
import {VertexSession} from './vertex.mjs';
for(const [language,text] of [['en-IN','Take me to Cubbon Park in Bengaluru.'],['kn-IN','ನನ್ನನ್ನು ಬೆಂಗಳೂರಿನ ಕಬ್ಬನ್ ಪಾರ್ಕಿಗೆ ಕರೆದುಕೊಂಡು ಹೋಗು.']]) {
  console.log(JSON.stringify(await new Promise((resolve,reject)=>{
    let command=null,done=false;
    const finish=error=>{if(done)return;done=true;clearTimeout(timer);session.close();error?reject(error):resolve({language,command});};
    const timer=setTimeout(()=>finish(Error('Navigation command timed out')),30000);
    const session=new VertexSession({project:process.env.GOOGLE_CLOUD_PROJECT,token:process.env.VERTEX_TEST_TOKEN,language,onEvent:event=>{
      if(event.type==='ready'){session.turn=1;session.send({clientContent:{turns:[{role:'user',parts:[{text}]}],turnComplete:true}});}
      if(event.type==='navigation')command=event.command;
      if(event.type==='end')finish(command?null:Error('No navigation command produced'));
      if(event.type==='error')finish(Error(event.message));
    }});
  })));
}
