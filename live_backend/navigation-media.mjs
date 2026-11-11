import {languages} from './languages.mjs';

export function mediaRequest(path,body) {
  if(!body || !Object.hasOwn(languages,body.language) || body.language==='auto')throw Error('Invalid language');
  if(path==='/speech') {
    if(typeof body.text!=='string'||!body.text.trim()||Buffer.byteLength(body.text)>4500)throw Error('Invalid speech text');
    return {input:{text:body.text},voice:{languageCode:body.language==='ar-EG'?'ar-XA':body.language},audioConfig:{audioEncoding:'MP3',speakingRate:1.0}};
  }
  if(!Array.isArray(body.texts)||!body.texts.length||body.texts.length>100||body.texts.some(t=>typeof t!=='string'||!t.trim())||body.texts.join('').length>20000)throw Error('Invalid translation text');
  return {contents:body.texts,mimeType:'text/plain',targetLanguageCode:body.language==='od-IN'?'or':body.language.split('-')[0]};
}

export async function navigationMedia(path,body,{token,project,request=fetch}) {
  const input=mediaRequest(path,body);
  const url=path==='/speech'?'https://texttospeech.googleapis.com/v1/text:synthesize':`https://translation.googleapis.com/v3/projects/${project}:translateText`;
  const response=await request(url,{method:'POST',headers:{Authorization:`Bearer ${token}`,'content-type':'application/json','x-goog-user-project':project},body:JSON.stringify(input),signal:AbortSignal.timeout(15000)});
  if(!response.ok)throw Error('Navigation language service unavailable');
  const data=await response.json();
  if(path==='/speech') {
    if(!data.audioContent)throw Error('No speech returned');
    return Buffer.from(data.audioContent,'base64');
  }
  const texts=data.translations?.map(t=>t.translatedText);
  if(!texts||texts.length!==body.texts.length||texts.some(t=>typeof t!=='string'||!t))throw Error('Incomplete translation');
  return {texts};
}

export function createMediaHandler({verifyUser,auth,project,apiBase,request=fetch}) {
  const quotas=new Map();
  return async(req,res)=>{
    const path=new URL(req.url??'/', 'http://localhost').pathname;
    const send=(status,data)=>res.writeHead(status,{'content-type':'application/json','cache-control':'no-store'}).end(JSON.stringify(data));
    if(req.method!=='POST')return send(405,{error:'POST required'});
    let user;
    try{user=await verifyUser(req.headers.authorization);}catch{return send(401,{error:'Sign in required'});}
    try {
      const profile=await request(`${apiBase}/v1/live/access`,{headers:{Authorization:req.headers.authorization},signal:AbortSignal.timeout(6000)});
      if(profile.status!==204)return send(403,{error:'Vision-assistance registration required'});
      const minute=Math.floor(Date.now()/60000),quota=quotas.get(user.id);
      if(quota?.minute===minute&&quota.count>=60)return send(429,{error:'Try again shortly'});
      if(quotas.size>10000)quotas.clear();
      quotas.set(user.id,{minute,count:quota?.minute===minute?quota.count+1:1});
      const parts=[];let bytes=0;
      for await(const part of req){bytes+=part.length;if(bytes>90000)return send(413,{error:'Request too large'});parts.push(part);}
      let body;try{body=JSON.parse(Buffer.concat(parts));mediaRequest(path,body);}catch{return send(400,{error:'Invalid navigation language request'});}
      const result=await navigationMedia(path,body,{token:await auth.getAccessToken(),project,request});
      if(Buffer.isBuffer(result))res.writeHead(200,{'content-type':'audio/mpeg','cache-control':'no-store'}).end(result);
      else send(200,result);
    }catch{send(503,{error:'Navigation language service unavailable'});}
  };
}
