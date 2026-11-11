import { beforeAll, describe, expect, it, vi } from 'vitest';
import { HttpRequest, InvocationContext, type HttpHandler } from '@azure/functions';
const handlers = vi.hoisted(() => new Map<string, HttpHandler>());
const images = vi.hoisted(() => new Map<string, Buffer>());
const queues = vi.hoisted(() => new Map<string, Function>());
vi.mock('../src/navigation.js',async original=>({...await original<typeof import('../src/navigation.js')>(),mapsNavigation:{search:vi.fn(async()=>[]),route:vi.fn(async()=>({steps:[]}))}}));
vi.mock('../src/fcm.js',async original=>({...await original<typeof import('../src/fcm.js')>(),fcm:{send:vi.fn(async()=>({name:'accepted'}))}}));
vi.mock('@azure/functions', async (original) => ({
  ...await original<typeof import('@azure/functions')>(),
  app: { setup: vi.fn(), storageQueue: (name:string,options:{handler:Function})=>queues.set(name,options.handler), http: (name: string, options: {handler: HttpHandler}) => handlers.set(name, options.handler) },
}));
vi.mock('../src/services.js', () => ({
  analyzeScene: vi.fn(async () => ({ cue: 'Object ahead', risk: 'caution', confidence: .5 })),
  publishAlert: vi.fn(), realtimeToken: vi.fn(), sendEmergencyPush: vi.fn(),
  sendEmergencySms: vi.fn(), synthesizeSpeech: vi.fn(),
}));
vi.mock('../src/voice.js', async (original) => ({
  ...await original<typeof import('../src/voice.js')>(),
  transcribeQuestion: vi.fn(async () => ({question:'Help!',detectedLanguage:'en-IN'})),
  answerQuestion: vi.fn(),
}));
vi.mock('../src/snapshot.js', () => ({
  storeEmergencySnapshot: async (_user: string, id: string, base64: string) => { images.set(id, Buffer.from(base64, 'base64')); return id; },
  emergencySnapshot: async (id: string) => images.get(id),
  deleteEmergencySnapshot: async (id: string) => images.delete(id),
}));
beforeAll(async () => {
  vi.stubEnv('ALLOW_DEBUG_AUTH', 'true');
  await import('../src/routes.js');
});
async function call(name: string, user: string, method = 'GET', data?: unknown, params = {}, extraHeaders = {}) {
  const request = new HttpRequest({ url: 'http://localhost/api/test?language=English', method,
    headers: { authorization: 'Bearer debug-token', 'x-debug-user': user, 'content-type': 'application/json', ...extraHeaders },
    params, ...(data === undefined ? {} : {body: {string: JSON.stringify(data)}}),
  });
  return await handlers.get(name)!(request, new InvocationContext()) as {status: number; jsonBody?: any; body?: any};
}
describe('Azure mobile API contract', () => {
  it('requires a vision profile and fresh precise GPS for Maps requests',async()=>{
    await call('registerProfile','nav-reader','POST',{role:'blindUser',displayName:'Reader'});
    await call('registerProfile','nav-guardian','POST',{role:'emergencyContact',displayName:'Guardian'});
    const body={query:'Cubbon Park',origin:{latitude:12,longitude:77,accuracy:5,recordedAt:new Date().toISOString()}};
    expect((await call('navigation-search','nav-guardian','POST',body)).status).toBe(403);
    expect((await call('navigation-search','nav-reader','POST',{...body,origin:{...body.origin,accuracy:100}})).status).toBe(400);
    expect((await call('navigation-search','nav-reader','POST',{...body,origin:{...body.origin,recordedAt:new Date(Date.now()-60000).toISOString()}})).status).toBe(400);
    expect((await call('navigation-search','nav-reader','POST',body)).status).toBe(200);
  });
  it('notification self-test only targets authenticated account devices and throttles repeats',async()=>{
    const {fcm}=await import('../src/fcm.js');
    await call('registerProfile','push-owner','POST',{role:'emergencyContact',displayName:'Guardian'});
    expect((await call('testNotification','push-owner','POST',{})).status).toBe(409);
    await call('registerDevice','push-owner','POST',{role:'emergencyContact',displayName:'Guardian',platform:'android',pushToken:'owned-installation-token-12345'});
    vi.mocked(fcm.send).mockClear();
    expect((await call('testNotification','push-owner','POST',{userId:'someone-else'})).status).toBe(200);
    expect(fcm.send).toHaveBeenCalledWith(expect.objectContaining({token:'owned-installation-token-12345',data:{type:'test'}}));
    expect((await call('testNotification','push-owner','POST',{})).status).toBe(429);
    expect((await call('testNotification','unregistered','POST',{})).status).toBe(409);
  });
  it('queued push rechecks current guardians and skips a cancelled alert',async()=>{
    const {repository}=await import('../src/repository.js');
    const {sendEmergencyPush}=await import('../src/services.js');
    const alert={id:'queued-test',type:'alert' as const,blindUserId:'queue-user',status:'active' as const,startedAt:new Date().toISOString(),idempotencyKey:'queue-test'};
    await repository.saveAlert(alert);
    await repository.saveLink({id:'queue-link',type:'link',blindUserId:'queue-user',contactUserId:'push-owner',createdAt:new Date().toISOString()});
    vi.mocked(sendEmergencyPush).mockClear();
    await queues.get('guardianPush')!({alertId:alert.id},new InvocationContext());
    expect(sendEmergencyPush).toHaveBeenCalledWith(expect.arrayContaining([expect.objectContaining({ownerId:'push-owner'})]),alert,undefined);
    await repository.saveAlert({...alert,status:'cancelled'});
    await queues.get('guardianPush')!({alertId:alert.id},new InvocationContext());
    expect(sendEmergencyPush).toHaveBeenCalledTimes(1);
  });
  it('a retired device token does not prevent testing the current installation',async()=>{
    const {fcm}=await import('../src/fcm.js');
    for(const pushToken of ['old-notification-token-12345','new-notification-token-12345'])await call('registerDevice','refreshed-push','POST',{role:'emergencyContact',displayName:'Guardian',platform:'android',pushToken});
    vi.mocked(fcm.send).mockRejectedValueOnce(Object.assign(Error('Retired token'),{fcmCode:'UNREGISTERED'}));
    expect(await call('testNotification','refreshed-push','POST',{})).toMatchObject({status:200,jsonBody:{accepted:1}});
  });
  it('retries a saved SOS if push scheduling previously failed',async()=>{
    const {sendEmergencyPush}=await import('../src/services.js');
    await call('registerProfile','push-retry','POST',{role:'blindUser',displayName:'Reader'});
    vi.mocked(sendEmergencyPush).mockRejectedValueOnce(Error('temporary delivery failure'));
    const headers={'idempotency-key':'push-retry-key'};
    expect((await call('createAlert','push-retry','POST',{}, {},headers)).status).toBe(500);
    expect((await call('createAlert','push-retry','POST',{}, {},headers)).status).toBe(200);
    const {repository}=await import('../src/repository.js');
    expect((await repository.alertByIdempotency('push-retry','push-retry-key'))?.pushScheduledAt).toBeTruthy();
  });
  it('isolates seven-day memory by authenticated user and rejects guardian access', async () => {
    await call('registerProfile','memory-reader','POST',{role:'blindUser',displayName:'Reader'});
    await call('registerProfile','memory-other','POST',{role:'blindUser',displayName:'Other'});
    await call('registerProfile','memory-guardian','POST',{role:'emergencyContact',displayName:'Guardian'});
    const item={id:'4f4c92da-f98e-4fe4-8cfe-58d3414cc309',question:'What is ahead?',answer:'A chair.'};
    expect((await call('conversationMemory','memory-reader','POST',item)).status).toBe(204);
    expect((await call('conversationMemory','memory-reader')).jsonBody).toMatchObject({retentionDays:7,turns:[item]});
    expect((await call('conversationMemory','memory-other')).jsonBody.turns).toEqual([]);
    expect((await call('conversationMemory','memory-guardian')).status).toBe(403);
    expect((await call('conversationMemory','memory-reader','POST',{...item,owner:'memory-other'})).status).toBe(400);
  });
  it('registers without FCM and keeps the account role immutable', async () => {
    expect((await call('registerProfile', 'reader', 'POST', {role:'blindUser',displayName:'Asha'})).status).toBe(204);
    expect((await call('registerProfile', 'reader', 'POST', {role:'emergencyContact',displayName:'Asha'})).status).toBe(409);
  });
  it('accepts the mobile raw JPEG upload', async () => {
    const request = new HttpRequest({url:'http://localhost/api/v1/vision/analyze', method:'POST',
      headers:{authorization:'Bearer debug-token','x-debug-user':'reader','content-type':'image/jpeg'},
      body:{bytes: new Uint8Array([255,216,255,217])},
    });
    const result = await handlers.get('analyzeVision')!(request, new InvocationContext());
    expect(result).toMatchObject({status:200,jsonBody:{cue:'Object ahead'}});
  });
  it('authorizes only registered vision users for the Google live relay',async()=>{
    expect((await call('liveAccess','reader')).status).toBe(204);
    expect((await call('liveAccess','never-registered')).status).toBe(409);
    await call('registerProfile','live-guardian','POST',{role:'emergencyContact',displayName:'Guardian'});
    expect((await call('liveAccess','live-guardian')).status).toBe(403);
  });
  it('rejects invalid audio before recognition and bypasses AI for an SOS command', async () => {
    expect((await call('askAssistant','reader','POST',{audioBase64:Buffer.alloc(60).toString('base64')})).status).toBe(400);
    const wav=Buffer.alloc(46);
    wav.write('RIFF');wav.writeUInt32LE(38,4);wav.write('WAVEfmt ',8);wav.writeUInt32LE(16,16);
    wav.writeUInt16LE(1,20);wav.writeUInt16LE(1,22);wav.writeUInt32LE(16000,24);wav.writeUInt32LE(32000,28);
    wav.writeUInt16LE(2,32);wav.writeUInt16LE(16,34);wav.write('data',36);wav.writeUInt32LE(2,40);
    expect(await call('askAssistant','reader','POST',{audioBase64:wav.toString('base64')}))
      .toMatchObject({status:200,jsonBody:{emergency:true,answer:''}});
    const {answerQuestion}=await import('../src/voice.js');
    expect(answerQuestion).not.toHaveBeenCalled();
    await call('registerProfile','voiceGuardian','POST',{role:'emergencyContact',displayName:'Guardian'});
    expect((await call('askAssistant','voiceGuardian','POST',{audioBase64:wav.toString('base64')})).status).toBe(403);
  });
  it('preserves SOS context and restricts snapshots to linked people', async () => {
    await call('registerProfile','guardian','POST',{role:'emergencyContact',displayName:'Ravi'});
    await call('registerProfile','stranger','POST',{role:'emergencyContact',displayName:'Other'});
    const invite = await call('createInvite','reader','POST');
    expect((await call('redeemInvite','guardian','POST',{code:invite.jsonBody.code})).status).toBe(201);
    const created = await call('createAlert','reader','POST',{
      triggerSource:'voice', lastCue:'Object ahead', lastRisk:'caution', lastConfidence:.5,
      imageBase64:Buffer.from([255,216,255,217]).toString('base64'),
      snapshotCapturedAt:new Date().toISOString(),latitude:null,longitude:null,accuracy:null,
    },{}, {'idempotency-key':'test-emergency'});
    expect(created.status).toBe(201);
    const alert = created.jsonBody;
    expect(alert).toMatchObject({blindUserName:'Asha',triggerSource:'voice',snapshotAvailable:true,lastCue:'Object ahead'});
    expect(alert.snapshotKey).toBeUndefined();
    expect((await call('alertSnapshot','stranger','GET',undefined,{id:alert.id})).status).toBe(403);
    expect((await call('alertSnapshot','guardian','GET',undefined,{id:alert.id})).status).toBe(200);
    expect((await call('alert-cancel','guardian','POST',{}, {id:alert.id})).status).toBe(403);
    expect((await call('alert-resolve','guardian','POST',{}, {id:alert.id})).status).toBe(200);
    expect((await call('alertSnapshot','guardian','GET',undefined,{id:alert.id})).status).toBe(404);
    expect(images.size).toBe(0);
    expect((await call('alert-acknowledge','guardian','POST',{}, {id:alert.id})).status).toBe(409);
  });
});
