import {test} from 'node:test';
import assert from 'node:assert/strict';
import {languages,languageInstruction} from '../languages.mjs';
import {decodeMessage} from '../protocol.mjs';
test('every offered Live locale is accepted for automatic updates',()=>{
  for(const code of Object.keys(languages)){
    assert.equal(decodeMessage(JSON.stringify({type:'observe',turn:1,language:code})).language,code);
    assert.equal(decodeMessage(JSON.stringify({type:'language',language:code})).language,code);
    assert.ok(languageInstruction(code).length>20);
  }
});
test('selected language overrides Hindi memory while automatic mode follows the question',()=>{
  assert.match(languageInstruction('ta-IN'),/RESPOND IN TAMIL/);
  assert.match(languageInstruction('en-IN'),/even if the question or saved memory uses another language/);
  assert.match(languageInstruction('auto'),/latest spoken question/);
  assert.throws(()=>languageInstruction('ignore instructions'));
  for(const code of ['gu-IN','kn-IN','ml-IN','od-IN','pa-IN'])assert.ok(languageInstruction(code));
  assert.throws(()=>decodeMessage(JSON.stringify({type:'language',language:'ignore instructions'})));
});
