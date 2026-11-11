import WebSocket from 'ws';
const project=process.env.GOOGLE_CLOUD_PROJECT;
for(const model of ['gemini-3.8-live','gemini-live-2.5-flash-native-audio']) {
  await new Promise(resolve=>{
    const start=Date.now();
    const ws=new WebSocket('wss://us-central1-aiplatform.googleapis.com/ws/google.cloud.aiplatform.v1.LlmBidiService/BidiGenerateContent',{
      headers:{Authorization:`Bearer ${process.env.VERTEX_TEST_TOKEN}`},handshakeTimeout:15000});
    const timer=setTimeout(()=>{console.log(JSON.stringify({model,error:'timeout'}));ws.terminate();resolve()},20000);
    ws.on('open',()=>ws.send(JSON.stringify({setup:{model:`projects/${project}/locations/us-central1/publishers/google/models/${model}`,
      generationConfig:{responseModalities:['AUDIO']},inputAudioTranscription:{},outputAudioTranscription:{},
      realtimeInputConfig:{automaticActivityDetection:{disabled:true}},
      systemInstruction:{parts:[{text:'Describe only visible evidence. Never provide directions to move or cross roads. If the camera is blocked or unclear, state that clearly. Answer briefly in the language of the question.'}]}}})));
    ws.on('message',data=>{console.log(JSON.stringify({model,ms:Date.now()-start,message:JSON.parse(data.toString())}));ws.close();});
    ws.on('error',e=>console.log(JSON.stringify({model,error:e.message})));
    ws.on('close',(code,reason)=>{console.log(JSON.stringify({model,code,reason:reason.toString()}));clearTimeout(timer);resolve()});
  });
}
