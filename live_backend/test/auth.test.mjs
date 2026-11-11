import {test,before} from 'node:test';
import assert from 'node:assert/strict';
import {generateKeyPair,SignJWT,exportJWK,createLocalJWKSet} from 'jose';
import {verifyUser} from '../auth.mjs';
const env={FIREBASE_PROJECT_ID:'phone-test'};
let pair,keys;
before(async()=>{pair=await generateKeyPair('RS256');keys=createLocalJWKSet({keys:[{...await exportJWK(pair.publicKey),kid:'test'}]});});
async function token(overrides={},signer=pair.privateKey) {const now=Math.floor(Date.now()/1000);return new SignJWT({iss:'https://securetoken.google.com/phone-test',aud:'phone-test',sub:'user',phone_number:'+919876543210',firebase:{sign_in_provider:'phone'},auth_time:now,exp:now+300,iat:now,...overrides}).setProtectedHeader({alg:'RS256',kid:'test'}).sign(signer);}
test('accepts a verified Google phone token',async()=>assert.equal((await verifyUser(`Bearer ${await token()}`,env,keys)).id,'user'));
for(const [name,claims] of Object.entries({expired:{exp:1},issuer:{iss:'https://evil.invalid'},audience:{aud:'other'},provider:{firebase:{sign_in_provider:'password'}},missingPhone:{phone_number:undefined},invalidPhone:{phone_number:'123'},missingExpiry:{exp:undefined},futureAuth:{auth_time:Math.floor(Date.now()/1000)+3600},missingAuth:{auth_time:undefined},emptyUid:{sub:''},futureIssue:{iat:Math.floor(Date.now()/1000)+3600}})) {
 test(`rejects ${name}`,async()=>assert.rejects(verifyUser(`Bearer ${await token(claims)}`,env,keys)));
}
test('rejects missing authentication and debug tokens',async()=>{await assert.rejects(verifyUser('',env,keys));await assert.rejects(verifyUser('Bearer debug-token',env,keys));});
test('rejects forged signature',async()=>{const attacker=await generateKeyPair('RS256');await assert.rejects(verifyUser(`Bearer ${await token({},attacker.privateKey)}`,env,keys));});
