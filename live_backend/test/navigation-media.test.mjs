import {test} from 'node:test';
import assert from 'node:assert/strict';
import {Readable} from 'node:stream';
import {mediaRequest,navigationMedia,createMediaHandler} from '../navigation-media.mjs';
test('cloud speech maps Arabic locale and never falls back to English',()=>{
  assert.equal(mediaRequest('/speech',{language:'ar-EG',text:'test'}).voice.languageCode,'ar-XA');
  assert.equal(mediaRequest('/speech',{language:'fr-FR',text:'test'}).voice.languageCode,'fr-FR');
  for(const body of [{language:'auto',text:'x'},{language:'invalid',text:'x'},{language:'fr-FR',text:'x'.repeat(4501)}])assert.throws(()=>mediaRequest('/speech',body));
});
test('route translation preserves order, rejects partial results, and maps Odia',async()=>{
  const body={language:'od-IN',texts:['Turn left','Use caution']};
  assert.equal(mediaRequest('/navigation/translate',body).targetLanguageCode,'or');
  assert.deepEqual(await navigationMedia('/navigation/translate',body,{token:'test',project:'test',request:async()=>Response.json({translations:[{translatedText:'A'},{translatedText:'B'}]})}),{texts:['A','B']});
  await assert.rejects(navigationMedia('/navigation/translate',body,{token:'test',project:'test',request:async()=>Response.json({translations:[{translatedText:'A'}]})}));
});
test('unauthenticated media requests never reach Google APIs',async()=>{
  let calls=0,status;
  const handler=createMediaHandler({verifyUser:async()=>{throw Error('invalid')},request:async()=>{calls++}});
  await handler({method:'POST',headers:{}},{writeHead(code){status=code;return this},end(){}});
  assert.equal(status,401);assert.equal(calls,0);
});
test('authenticated translation accepts a URL with an empty query suffix',async()=>{
  let status,output,calls=0;
  const handler=createMediaHandler({verifyUser:async()=>({id:'test-user'}),auth:{getAccessToken:async()=>'test'},project:'test',apiBase:'https://api.example',request:async()=>++calls===1?new Response(null,{status:204}):Response.json({translations:[{translatedText:'Translated direction'}]})});
  const req=Readable.from([Buffer.from(JSON.stringify({language:'kn-IN',texts:['Head north']}))]);
  Object.assign(req,{method:'POST',url:'/navigation/translate?',headers:{authorization:'Bearer test'}});
  await handler(req,{writeHead(code){status=code;return this},end(body){output=JSON.parse(body)}});
  assert.equal(status,200);assert.deepEqual(output,{texts:['Translated direction']});assert.equal(calls,2);
});
