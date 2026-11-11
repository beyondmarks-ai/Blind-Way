import http from 'node:http';
import {languages} from './languages.mjs';
import {ConversationMemory} from './memory.mjs';
import {GoogleAuth} from 'google-auth-library';
import {WebSocketServer,WebSocket} from 'ws';
import {verifyUser} from './auth.mjs';
import {decodeMessage} from './protocol.mjs';
import {VertexSession} from './vertex.mjs';
import {createMediaHandler} from './navigation-media.mjs';
const project=process.env.GOOGLE_CLOUD_PROJECT;
const model=process.env.VERTEX_LIVE_MODEL??'gemini-3.8-live';
const location=process.env.VERTEX_LOCATION??'us-central1';
const auth=new GoogleAuth({scopes:['https://www.googleapis.com/auth/cloud-platform']});
const users=new Map(); let vertexReady=false;
const mediaHandler=createMediaHandler({verifyUser,auth,project,apiBase:process.env.AZURE_API_BASE_URL});
const server=http.createServer((req,res)=>{
  if(['/speech','/navigation/translate'].includes(new URL(req.url,'http://localhost').pathname)){void mediaHandler(req,res);return;}
  if(req.url!=='/health') {res.writeHead(404).end();return;}
  res.writeHead(200,{'content-type':'application/json','cache-control':'no-store'}).end(JSON.stringify({status:'ok',model,vertexReady}));
});
const wss=new WebSocketServer({noServer:true,maxPayload:450000,perMessageDeflate:false});
server.on('upgrade',async(req,socket,head)=>{
  try {
    const url=new URL(req.url,'http://localhost');
    const language=url.searchParams.get('language')??'auto';
    if(url.pathname!=='/live'||!Object.hasOwn(languages,language)||wss.clients.size>=20) throw new Error('Unavailable');
    const user=await verifyUser(req.headers.authorization);
    const profile=await fetch(`${process.env.AZURE_API_BASE_URL}/v1/live/access`,{headers:{Authorization:req.headers.authorization},signal:AbortSignal.timeout(6000)});
    if(profile.status!==204)throw new Error('Vision-assistance registration required');
    if((users.get(user.id)??0)>=2) {socket.end('HTTP/1.1 429 Too Many Requests\r\n\r\n');return;}
    wss.handleUpgrade(req,socket,head,ws=>wss.emit('connection',ws,user,req.headers.authorization,language));
  } catch {socket.end('HTTP/1.1 401 Unauthorized\r\nConnection: close\r\n\r\n');}
});
wss.on('connection',(ws,user,authorization,language)=>{
  users.set(user.id,(users.get(user.id)??0)+1);
  let navigationPrompt='none',navigationLanguage='auto'; let upstream; let generation=0; let turn=0; let inputOpen=false; let lastFrame=0; let lastBegin=0; let turnTimer;
  let audioWindow=Date.now(),audioBytes=0; let reconnectAt=0;
  const send=event=>{if(ws.readyState===WebSocket.OPEN) {
    if(ws.bufferedAmount>2*1024*1024) {ws.close(1013,'Playback too slow');return;}
    ws.send(JSON.stringify(event));
  }};
  const memory=new ConversationMemory(authorization,send);
  let memoryLoaded=false;
  const connect=async()=>{
    const epoch=++generation;upstream?.close();upstream=undefined;turn=0;inputOpen=false;lastFrame=0;clearTimeout(turnTimer);
    try {
      const [token]=await Promise.all([auth.getAccessToken(),memoryLoaded?Promise.resolve():memory.load()]);memoryLoaded=true;
      if(epoch!==generation||ws.readyState!==WebSocket.OPEN)return;
      upstream=new VertexSession({project,model,location,token,memory:memory.recent,language,onEvent:event=>{
        if(epoch!==generation||ws.readyState!==WebSocket.OPEN)return;
        memory.event(event);
        if(event.type==='audio') {clearTimeout(turnTimer);turnTimer=setTimeout(()=>{send({type:'error',message:'Live audio stalled. Restart live mode.'});void connect();},30000);}
        if(event.type==='ready')vertexReady=true;
        if(event.type==='end') {turn=0;inputOpen=false;clearTimeout(turnTimer);}
        if(event.type==='sos') {inputOpen=false;clearTimeout(turnTimer);}
        send(event.type==='ready'?{...event,language}:event);
        if(['error','closed','reconnect'].includes(event.type))ws.close(1012,'Reconnect live session');
      }});
    } catch {send({type:'error',message:'Live service is unavailable. Try again.'});ws.close(1011);}
  };
  ws.on('message',raw=>{
    try {
      const m=decodeMessage(raw);
      if(m.type==='ping'){send({type:'pong'});return;}
      if(m.type==='played'){void memory.played(m.turn);return;}
      if(m.type==='language') {
        memory.cancel();language=m.language;void connect();return;
      }
      if(m.type==='cancel') {memory.cancel();if(Date.now()-reconnectAt<1500)return;reconnectAt=Date.now();void connect();return;}
      if(m.type==='navigationPrompt'){navigationPrompt=['destination','start'].includes(m.prompt)?m.prompt:'none';navigationLanguage=m.language??'auto';return;}
      if(!upstream?.ready)return;
      if(m.type==='frame') {if(Date.now()-lastFrame<950)return;lastFrame=Date.now();upstream.frame(m.data);return;}
      if(m.type==='begin'||m.type==='observe') {
        if(turn||Date.now()-lastBegin<1000)return;
        if(Date.now()-lastFrame>2500){send({type:'error',message:'No fresh camera image. Reconnect the camera.'});return;}
        lastBegin=Date.now();turn=m.turn;inputOpen=m.type==='begin';memory.begin(turn,m.type==='observe');
        if(inputOpen){upstream.begin(turn,navigationPrompt,navigationLanguage);navigationPrompt='none';}else upstream.observe(turn,m.language);
        turnTimer=setTimeout(()=>{send({type:'error',message:'Question timed out. Please try again.'});void connect();},60000);
      }
      if(m.type==='audio'&&inputOpen&&m.turn===turn) {
        if(Date.now()-audioWindow>1000){audioWindow=Date.now();audioBytes=0;}
        audioBytes+=m.data.length;
        if(audioBytes>100000)throw new Error('Audio rate exceeded');
        upstream.audio(m.data);
      }
      if(m.type==='end'&&inputOpen&&m.turn===turn){inputOpen=false;upstream.end();}
    } catch {send({type:'error',message:'Invalid live media request.'});ws.close(1008);}
  });
  const expiry=setTimeout(()=>ws.close(1000,'Session expired. Reconnect.'),Math.max(1000,Math.min(9*60*1000,user.expires*1000-Date.now())));
  ws.on('close',()=>{generation++;clearTimeout(expiry);clearTimeout(turnTimer);upstream?.close();users.set(user.id,Math.max(0,(users.get(user.id)??1)-1));if(!users.get(user.id))users.delete(user.id);});
  ws.on('error',()=>ws.close());
  void connect();
});
server.listen(process.env.PORT??8080,()=>console.log('Blind Way live relay listening'));
// One startup connectivity check validates the deployed service identity, never user audio.
(async()=>{
  let probe;const timeout=setTimeout(()=>probe?.close(),15000);
  try {probe=new VertexSession({project,model,location,token:await auth.getAccessToken(),onEvent:event=>{
    if(event.type==='ready'){vertexReady=true;clearTimeout(timeout);probe.close();console.log('Vertex Live identity verified');}
    if(event.type==='error'){clearTimeout(timeout);probe?.close();console.log('Vertex Live startup check failed');}
  }});}catch{clearTimeout(timeout);console.log('Vertex Live credentials unavailable');}
})();
