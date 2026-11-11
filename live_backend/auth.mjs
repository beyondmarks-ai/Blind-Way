import {createRemoteJWKSet,jwtVerify} from 'jose';
let remoteKeys;
export async function verifyUser(header,env=process.env,keys) {
  if(!header?.startsWith('Bearer ') || !env.FIREBASE_PROJECT_ID) throw new Error('Authentication required');
  keys ??= remoteKeys ??= createRemoteJWKSet(new URL('https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com'));
  const {payload:p}=await jwtVerify(header.slice(7),keys,{
    issuer:`https://securetoken.google.com/${env.FIREBASE_PROJECT_ID}`,audience:env.FIREBASE_PROJECT_ID,algorithms:['RS256'],
    requiredClaims:['exp','iat','sub','auth_time','phone_number','firebase'],
  });
  const now=Math.floor(Date.now()/1000);
  if(!p.sub || p.sub.length>128 || p.firebase?.sign_in_provider!=='phone' ||
    typeof p.phone_number!=='string' || !/^\+[1-9]\d{7,14}$/.test(p.phone_number) ||
    typeof p.auth_time!=='number' || p.auth_time>now+60 || p.auth_time<0 ||
    typeof p.iat!=='number' || p.iat>now+60) throw new Error('Invalid phone identity');
  return {id:p.sub,expires:p.exp};
}
