import {test} from 'node:test';
import assert from 'node:assert/strict';
import {navigationCommand} from '../navigation.mjs';
import {decodeMessage} from '../protocol.mjs';
test('confirmation commands require a current phone prompt, and protocol validates it',()=>{
  for(const action of ['confirm','reject','next']) {
    assert.equal(navigationCommand({action}),null);
    assert.deepEqual(navigationCommand({action},'destination'),{action});
    assert.deepEqual(navigationCommand({action},'start'),{action});
  }
  assert.equal(decodeMessage(JSON.stringify({type:'navigationPrompt',prompt:'start'})).prompt,'start');
  assert.throws(()=>decodeMessage(JSON.stringify({type:'navigationPrompt',prompt:'invent a route'})));
});
test('only valid navigation intents and explicit place selections reach the phone',()=>{
  assert.deepEqual(navigationCommand({action:'search',destination:'Park',spokenLanguage:'kn-IN'}),{action:'search',destination:'Park',spokenLanguage:'kn-IN'});
  assert.deepEqual(navigationCommand({action:'confirm',spokenLanguage:'invalid'},'start'),{action:'confirm'});
  assert.deepEqual(navigationCommand({action:'search',destination:'Cubbon Park'}),{action:'search',destination:'Cubbon Park'});
  assert.deepEqual(navigationCommand({action:'select',index:2}),{action:'select',index:2});
  for(const input of [{action:'cross_road'},{action:'select',index:9},{action:'search',destination:''},{action:'search',destination:'x'.repeat(201)}])assert.equal(navigationCommand(input),null);
});
