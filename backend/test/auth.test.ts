import { beforeAll, describe, expect, it } from 'vitest';
import { createLocalJWKSet, exportJWK, generateKeyPair, SignJWT, type JWTPayload } from 'jose';
import { verifyAccessToken } from '../src/auth.js';

const project = 'phone-test';
const uid = 'firebase-user';
let pair: Awaited<ReturnType<typeof generateKeyPair>>;
let keys: ReturnType<typeof createLocalJWKSet>;
beforeAll(async () => {
  pair = await generateKeyPair('RS256');
  keys = createLocalJWKSet({ keys: [{ ...await exportJWK(pair.publicKey), kid: 'test', alg: 'RS256' }] });
});
async function token(overrides: JWTPayload = {}, signer = pair.privateKey) {
  return new SignJWT({
    sub:uid, name:'Asha', phone_number:'+919876543210', firebase:{sign_in_provider:'phone'},
    iss:`https://securetoken.google.com/${project}`, aud:project,
    auth_time:Math.floor(Date.now()/1000),
    iat:Math.floor(Date.now()/1000), exp:Math.floor(Date.now()/1000)+3600,
    ...overrides,
  }).setProtectedHeader({ alg: 'RS256', kid: 'test' }).sign(signer);
}
describe('Google phone authentication', () => {
  it('accepts verified phone ID tokens with a stable Firebase UID', async () => {
    expect(await verifyAccessToken(await token(), keys, project)).toMatchObject({sub:uid,name:'Asha'});
  });
  for(const [name,override] of Object.entries({
    issuer:{iss:'https://evil.example'}, project:{aud:'other'}, expired:{exp:1}, missingExpiry:{exp:undefined},
    emptyUid:{sub:''}, missingUid:{sub:undefined}, longUid:{sub:'a'.repeat(129)},
    missingPhone:{phone_number:undefined}, invalidPhone:{phone_number:'9876543210'},
    emailProvider:{firebase:{sign_in_provider:'password'}}, anonymous:{firebase:{sign_in_provider:'anonymous'}},
    customToken:{firebase:{sign_in_provider:'custom'}}, missingProvider:{firebase:undefined},
    futureAuth:{auth_time:Math.floor(Date.now()/1000)+3600}, missingAuthTime:{auth_time:undefined},
    futureIssue:{iat:Math.floor(Date.now()/1000)+3600},
  })) it(`rejects ${name}`,async()=>{
    await expect(verifyAccessToken(await token(override),keys,project)).rejects.toMatchObject({status:401});
  });
  it('rejects forged signatures',async()=>{
    const attacker=await generateKeyPair('RS256');
    await expect(verifyAccessToken(await token({},attacker.privateKey),keys,project)).rejects.toMatchObject({status:401});
  });
});
