import {test} from 'node:test';
import assert from 'node:assert/strict';
import {decodeMessage} from '../protocol.mjs';
const decode=m=>decodeMessage(JSON.stringify(m));
test('accepts bounded JPEG and 16-bit PCM messages',()=>{
 assert.equal(decode({type:'frame',data:Buffer.from([255,216,255,217]).toString('base64')}).type,'frame');
 assert.equal(decode({type:'audio',turn:1,data:Buffer.alloc(2560).toString('base64')}).turn,1);
});
test('rejects invalid and oversized media',()=>{
 for(const message of [{type:'frame',data:'aaaa'},{type:'audio',turn:0,data:'AAA='},{type:'audio',turn:1,data:'AA=='},{type:'audio',turn:1,data:'A'.repeat(20000)},{type:'frame',data:'bad!'}])assert.throws(()=>decode(message));
});
test('rejects arbitrary upstream messages and model overrides',()=>{
 assert.throws(()=>decode({type:'setup',model:'unapproved'}));
 assert.throws(()=>decode({type:'begin',turn:'1'}));
});
