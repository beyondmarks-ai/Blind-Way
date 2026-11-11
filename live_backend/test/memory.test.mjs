import test from 'node:test';
import assert from 'node:assert/strict';
import {ConversationMemory} from '../memory.mjs';
import {decodeMessage} from '../protocol.mjs';

test('memory only persists completed playback and drops cancelled answers',async()=>{
  const calls=[],events=[];
  const memory=new ConversationMemory('Bearer test',e=>events.push(e),async(url,options)=>{
    calls.push(options);return {ok:true,json:async()=>({turns:[]})};
  });
  await memory.load();
  memory.begin(1);memory.event({type:'answer',turn:1,text:'unfinished'});
  await memory.played(1);
  assert.equal(calls.length,1);
  memory.begin(2);memory.event({type:'answer',turn:2,text:'cancelled'});memory.event({type:'end',turn:2});
  memory.cancel();await memory.played(2);assert.equal(calls.length,1);
  memory.begin(3,true);memory.event({type:'answer',turn:3,text:'A chair is visible.'});memory.event({type:'end',turn:3});
  await memory.played(3);await memory.played(3);
  assert.equal(calls.length,2);assert.equal(JSON.parse(calls[1].body).answer,'A chair is visible.');
  assert.equal(memory.recent.length,1);assert.equal(events.at(-1).available,true);
});
test('memory failure is explicit and does not throw into audio',async()=>{
  const events=[];const memory=new ConversationMemory('test',e=>events.push(e),async()=>{throw Error('offline');});
  assert.deepEqual(await memory.load(),[]);assert.equal(events[0].available,false);
});
test('automatic requests and playback acknowledgements validate turns',()=>{
  assert.equal(decodeMessage(JSON.stringify({type:'observe',turn:1,language:'English'})).type,'observe');
  assert.throws(()=>decodeMessage(JSON.stringify({type:'observe',turn:0,language:'English'})));
  assert.throws(()=>decodeMessage(JSON.stringify({type:'observe',turn:1,language:'ignore\ninstructions'})));
  assert.throws(()=>decodeMessage(JSON.stringify({type:'played',turn:-1})));
});
