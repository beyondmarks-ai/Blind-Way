import { app, type HttpRequest, type InvocationContext } from "@azure/functions";
import { QueueServiceClient } from "@azure/storage-queue";
import { createHash, randomBytes, randomUUID } from "node:crypto";
import { z } from "zod";

import { authenticate, HttpError } from "./auth.js";
import { json, required, route } from "./http.js";
import { repository } from "./repository.js";
import {fcm,pushMessage} from './fcm.js';
import {mapsNavigation} from './navigation.js';
import {classifyNavigation} from './navigation-intent.js';
import { recentConversations, saveConversation } from './conversation-memory.js';
import { transcribeQuestion, answerQuestion, emergencyCommand, speechLanguage, speechLanguages } from './voice.js';
import { storeEmergencySnapshot, emergencySnapshot, deleteEmergencySnapshot } from './snapshot.js';
import { analyzeScene, publishAlert, realtimeToken, sendEmergencyPush, sendEmergencySms, synthesizeSpeech } from "./services.js";
import type { Alert, AlertLocation, Device, Invite, Role, TrustedLink } from "./types.js";

app.setup({ enableHttpStream: true });

function alertResponse(alert: Alert) {
  const { snapshotKey, ...safe } = alert;
  return { ...safe, snapshotAvailable: Boolean(snapshotKey) };
}

const deviceSchema = z.object({
  platform: z.literal("android"),
  pushToken: z.string().min(20).max(4096),
  role: z.enum(["blindUser", "emergencyContact"]),
  displayName: z.string().min(1).max(100),
});
const locationSchema = z.object({
  latitude: z.number().min(-90).max(90),
  longitude: z.number().min(-180).max(180),
  accuracy: z.number().min(0).max(100000),
  recordedAt: z.string().datetime().optional(),
});

async function parsedJson(request: HttpRequest) {
  try { return await request.json(); } catch { throw new HttpError(400, "A valid JSON body is required."); }
}

async function requireProfile(request: HttpRequest) {
  const user = await authenticate(request);
  const profile = await repository.profile(user.sub);
  if (!profile) throw new HttpError(409, "Register this device before using the API.");
  return { user, profile };
}

async function authorizeAlert(request: HttpRequest, alertId: string) {
  const { user, profile } = await requireProfile(request);
  const alert = await repository.alert(alertId);
  if (!alert) throw new HttpError(404, "Alert not found.");
  if (alert.blindUserId !== user.sub && !(await repository.activeLink(alert.blindUserId, user.sub))) {
    throw new HttpError(403, "You are not authorized to access this alert.");
  }
  return { user, profile, alert };
}

app.http("health", { methods: ["GET"], authLevel: "anonymous", route: "health", handler: route(async () => json(200, { status: "ok" })) });
app.http('navigationReadiness',{methods:['POST'],authLevel:'function',route:'ops/navigation/validate',handler:route(async()=>{
  const origin={latitude:12.9767,longitude:77.5993};
  const places=await mapsNavigation.search('Cubbon Park Bengaluru',origin,'en-IN');
  if(!places.length)throw new HttpError(502,'Place lookup did not return a result.');
  const walking=await mapsNavigation.route(origin,places[0].id,'en-IN');
  return json(200,{configured:true,places:places.length,steps:walking.steps.length,distanceMeters:walking.distanceMeters,walking:true});
})});
// Administrative validation does not deliver a notification or disclose credentials.
app.http('pushReadiness',{methods:['POST'],authLevel:'function',route:'ops/push/validate',handler:route(async()=>{
  await fcm.send({topic:'blindway-configuration-check',notification:{title:'Configuration validation',body:'Not delivered.'}},true);
  return json(200,{configured:true,validated:true,delivered:false});
})});
const notificationTests=new Map<string,number>();
const navigationRequests=new Map<string,{started:number;count:number}>();
for(const operation of ['search','route'] as const)app.http(`navigation-${operation}`,{
  methods:['POST'],authLevel:'anonymous',route:`v1/navigation/${operation}`,handler:route(async request=>{
    const {user,profile}=await requireProfile(request);
    if(profile.role!=='blindUser')throw new HttpError(403,'Walking navigation is for vision-assistance users.');
    const parsed=z.object({origin:z.object({latitude:z.number().min(-90).max(90),longitude:z.number().min(-180).max(180),accuracy:z.number().min(0).max(30),recordedAt:z.string().datetime()}),language:z.string().regex(/^(auto|[a-z]{2}-[A-Z]{2})$/).default('en-IN'),query:z.string().trim().min(2).max(200).optional(),placeId:z.string().min(5).max(250).optional()}).safeParse(await parsedJson(request));
    if(!parsed.success)throw new HttpError(400,'A destination and a precise current GPS location are required.');
    const body=parsed.data,age=Date.now()-Date.parse(body.origin.recordedAt);
    if(age>30000||age< -5000)throw new HttpError(400,'GPS location is stale. Wait for a new location fix.');
    if(navigationRequests.size>10000)navigationRequests.clear();
    const old=navigationRequests.get(user.sub),budget=old&&Date.now()-old.started<60000?old:{started:Date.now(),count:0};
    if(++budget.count>15)throw new HttpError(429,'Please wait before requesting more routes.');
    navigationRequests.set(user.sub,budget);
    const origin={latitude:body.origin.latitude,longitude:body.origin.longitude};
    if(operation==='search') {
      if(!body.query)throw new HttpError(400,'Say or enter a destination.');
      return json(200,{places:await mapsNavigation.search(body.query,origin,body.language)});
    }
    if(!body.placeId)throw new HttpError(400,'Choose a destination first.');
    return json(200,await mapsNavigation.route(origin,body.placeId,body.language));
  }),
});
app.http('testNotification',{methods:['POST'],authLevel:'anonymous',route:'v1/notifications/test',handler:route(async request=>{
  const {user}=await requireProfile(request);
  if(Date.now()-(notificationTests.get(user.sub)??0)<60000)throw new HttpError(429,'Wait one minute before another test.');
  const devices=await repository.devices([user.sub]);
  if(!devices.length)throw new HttpError(409,'Allow notifications and reopen the app to register this phone.');
  notificationTests.set(user.sub,Date.now());
  const results=await Promise.allSettled([...new Set(devices.map(device=>device.pushToken))].map(token=>fcm.send(pushMessage(token,'Blind Way test notification','Notifications are enabled for this account. This is not an emergency.',{type:'test'}))));
  const accepted=results.filter(result=>result.status==='fulfilled').length;
  const failure=results.find(result=>result.status==='rejected'&&(result.reason as {fcmCode?:string}).fcmCode!=='UNREGISTERED');
  if(!accepted) {
    if(failure?.status==='rejected')throw failure.reason;
    throw new HttpError(409,'Reopen the app to renew this phone notification registration.');
  }
  return json(200,{accepted});
})});
app.http('liveAccess', {
  methods:['GET'],authLevel:'anonymous',route:'v1/live/access',
  handler:route(async(request)=>{
    const {profile}=await requireProfile(request);
    if(profile.role!=='blindUser')throw new HttpError(403,'Live camera questions are for registered vision-assistance users.');
    return json(204);
  }),
});

app.http('conversationMemory', {
  methods: ['GET', 'POST'], authLevel: 'anonymous', route: 'v1/live/memory',
  handler: route(async request => {
    const { user, profile } = await requireProfile(request);
    if (profile.role !== 'blindUser') throw new HttpError(403, 'Conversation memory belongs to the vision-assistance user.');
    if (request.method === 'GET') return json(200, { turns: await recentConversations(user.sub), retentionDays: 7 });
    const parsed = z.object({ id: z.string().uuid(), question: z.string().max(1500), answer: z.string().min(1).max(3000) }).strict().safeParse(await parsedJson(request));
    if (!parsed.success) throw new HttpError(400, 'A bounded text conversation is required.');
    await saveConversation(user.sub, parsed.data);
    return json(204);
  }),
});

app.http("registerDevice", {
  methods: ["POST"], authLevel: "anonymous", route: "v1/devices/register",
  handler: route(async (request) => {
    const user = await authenticate(request);
    const body = deviceSchema.parse(await parsedJson(request));
    const profile = await repository.ensureProfile(user.sub, body.role, body.displayName);
    if (profile.role !== body.role) throw new HttpError(409, "The account role cannot be changed after registration.");
    const id = createHash("sha256").update(`${user.sub}:${body.pushToken}`).digest("hex");
    const device: Device = { id, type: "device", ownerId: user.sub, platform: body.platform, pushToken: body.pushToken, updatedAt: new Date().toISOString() };
    await repository.saveDevice(device);
    return json(204);
  }),
});

// Accounts exist independently of notification permission / FCM availability.
app.http('registerProfile', {
  methods: ['POST'], authLevel: 'anonymous', route: 'v1/profile',
  handler: route(async (request) => {
    const user = await authenticate(request);
    const body = deviceSchema.pick({ role: true, displayName: true }).parse(await parsedJson(request));
    const profile = await repository.ensureProfile(user.sub, body.role, body.displayName);
    if (profile.role !== body.role) throw new HttpError(409, 'The account role cannot be changed after registration.');
    return json(204);
  }),
});

app.http("analyzeVision", {
  methods: ["POST"], authLevel: "anonymous", route: "v1/vision/analyze",
  handler: route(async (request) => {
    const { profile } = await requireProfile(request);
    if (profile.role !== "blindUser") throw new HttpError(403, "Only vision-assistance users can analyze frames.");
    if (request.headers.get('content-type')?.split(';')[0] !== 'image/jpeg') throw new HttpError(400, 'A JPEG image is required.');
    const image = new Uint8Array(await request.arrayBuffer());
    if (image.length > 1_500_000) throw new HttpError(413, 'The camera image exceeds 1.5 MB.');
    if (image.length < 4 || image[0] !== 255 || image[1] !== 216 || image.at(-2) !== 255 || image.at(-1) !== 217) throw new HttpError(400, 'Invalid JPEG image.');
    const language = String(request.query.get('language') ?? 'English').slice(0, 30);
    return json(200, await analyzeScene(image, language));
  }),
});

app.http("speech", {
  methods: ["GET"], authLevel: "anonymous", route: "v1/speech",
  handler: route(async (request) => {
    await requireProfile(request);
    const text = required(request.query.get("text"), "text").slice(0, 1500);
    const language = String(request.query.get("language") ?? "English").slice(0, 30);
    const response = await synthesizeSpeech(text, language);
    return {
      status: 200,
      body: response.body,
      headers: {
        "content-type": response.headers.get("content-type") ?? "audio/mpeg",
        "cache-control": "no-store",
      },
    };
  }),
});

app.http('askAssistant', {
  methods:['POST'],authLevel:'anonymous',route:'v1/assistant/ask',
  handler:route(async(request) => {
    const {profile} = await requireProfile(request);
    if(profile.role !== 'blindUser') throw new HttpError(403,'Only vision-assistance users can ask camera questions.');
    const body = z.object({navigationPrompt:z.enum(['none','destination','start']).default('none'),language:z.enum(['auto','en-IN','hi-IN','bn-IN','gu-IN','kn-IN','ml-IN','mr-IN','od-IN','pa-IN','ta-IN','te-IN']).default('auto'),audioBase64:z.string().min(60).max(700000),imageBase64:z.string().max(2000000).optional()}).parse(await parsedJson(request));
    const audio=Buffer.from(body.audioBase64,'base64');
    if(audio.length<46 || audio.length>384044 || audio.subarray(0,4).toString()!=='RIFF' || audio.subarray(8,16).toString()!=='WAVEfmt '
      || audio.readUInt32LE(16)!==16 || audio.readUInt16LE(20)!==1 || audio.readUInt16LE(22)!==1 || audio.readUInt32LE(24)!==16000
      || audio.readUInt32LE(28)!==32000 || audio.readUInt16LE(32)!==2 || audio.readUInt16LE(34)!==16
      || audio.subarray(36,40).toString()!=='data' || audio.readUInt32LE(40)!==audio.length-44 || audio.readUInt32LE(4)!==audio.length-8
      || audio.length%2!==0) throw new HttpError(400,'A short 16 kHz mono PCM WAV recording is required.');
    const image=body.imageBase64 ? Buffer.from(body.imageBase64,'base64') : undefined;
    if(image && (image.length<4 || image[0]!==255 || image[1]!==216 || image.at(-2)!==255 || image.at(-1)!==217)) throw new HttpError(400,'Invalid camera image.');
    const started=Date.now();
    const {question,detectedLanguage}=await transcribeQuestion(audio);
    const language=body.language==='auto'?speechLanguage(detectedLanguage):body.language;
    const emergency=emergencyCommand(question);
    const navigation=emergency?undefined:await classifyNavigation(question,body.navigationPrompt);
    const answer=emergency||navigation ? '' : await answerQuestion(question,image,language);
    return json(200,{question,answer,language,detectedLanguage,emergency,navigation,
      languageFallback:body.language==='auto'&&!speechLanguages[detectedLanguage],processingMs:Date.now()-started});
  }),
});

app.http("createInvite", {
  methods: ["POST"], authLevel: "anonymous", route: "v1/contacts/invites",
  handler: route(async (request) => {
    const { user, profile } = await requireProfile(request);
    if (profile.role !== "blindUser") throw new HttpError(403, "Only blind users can create invitations.");
    if ((await repository.linksForBlindUser(user.sub)).length >= 5) throw new HttpError(409, "A maximum of five trusted contacts is supported.");
    const code = randomBytes(5).toString("hex").toUpperCase();
    const invite: Invite = {
      id: randomUUID(), type: "invite", blindUserId: user.sub,
      codeHash: createHash("sha256").update(code).digest("hex"),
      expiresAt: new Date(Date.now() + 10 * 60_000).toISOString(),
    };
    await repository.saveInvite(invite);
    return json(201, { code, expiresAt: invite.expiresAt });
  }),
});

app.http("redeemInvite", {
  methods: ["POST"], authLevel: "anonymous", route: "v1/contacts/invites/redeem",
  handler: route(async (request) => {
    const { user, profile } = await requireProfile(request);
    if (profile.role !== "emergencyContact") throw new HttpError(403, "Only emergency contacts can redeem invitations.");
    const body = z.object({ code: z.string().min(8).max(32) }).parse(await parsedJson(request));
    const invite = await repository.inviteByHash(createHash("sha256").update(body.code.toUpperCase()).digest("hex"));
    if (!invite || invite.redeemedAt || Date.parse(invite.expiresAt) < Date.now()) throw new HttpError(410, "This invitation is invalid or expired.");
    if ((await repository.linksForBlindUser(invite.blindUserId)).length >= 5) throw new HttpError(409, "This user already has five trusted contacts.");
    const link: TrustedLink = { id: randomUUID(), type: "link", blindUserId: invite.blindUserId, contactUserId: user.sub, createdAt: new Date().toISOString() };
    invite.redeemedAt = new Date().toISOString(); invite.redeemedBy = user.sub;
    await repository.saveInvite(invite); await repository.saveLink(link);
    return json(201, { linked: true });
  }),
});

app.http("contacts", {
  methods: ["GET"], authLevel: "anonymous", route: "v1/contacts",
  handler: route(async (request) => {
    const { user, profile } = await requireProfile(request);
    const links = profile.role === "blindUser" ? await repository.linksForBlindUser(user.sub) : await repository.linksForContact(user.sub);
    const otherIds = links.map((link) => profile.role === "blindUser" ? link.contactUserId : link.blindUserId);
    const profiles = await Promise.all(otherIds.map((id) => repository.profile(id)));
    return json(200, profiles.filter(Boolean).map((person) => ({ id: person!.id, name: person!.displayName, phone: person!.phone ? `******${person!.phone.slice(-4)}` : "", verified: person!.phoneVerified })));
  }),
});

async function scheduleGuardianPush(alert:Alert) {
  if(alert.pushScheduledAt||alert.status!=='active')return;
  if(process.env.AzureWebJobsStorage) {
    const queue=QueueServiceClient.fromConnectionString(process.env.AzureWebJobsStorage).getQueueClient('guardian-push');
    await queue.createIfNotExists();
    await queue.sendMessage(Buffer.from(JSON.stringify({alertId:alert.id})).toString('base64'));
  } else {
    const links=await repository.linksForBlindUser(alert.blindUserId);
    await sendEmergencyPush(await repository.devices(links.map(link=>link.contactUserId)),alert,await repository.profile(alert.blindUserId));
  }
  // Mark only after enqueue succeeds. Retrying the same SOS repairs an enqueue failure.
  alert.pushScheduledAt=new Date().toISOString();
  await repository.saveAlert(alert);
}

app.http("createAlert", {
  methods: ["POST"], authLevel: "anonymous", route: "v1/alerts",
  handler: route(async (request, context) => {
    const { user, profile } = await requireProfile(request);
    if (profile.role !== "blindUser") throw new HttpError(403, "Only blind users can create alerts.");
    const key = required(request.headers.get("idempotency-key"), "Idempotency-Key");
    const existing = await repository.alertByIdempotency(user.sub, key);
    if (existing) {
      await scheduleGuardianPush(existing);
      return json(200, alertResponse(existing));
    }
    const body = z.object({
      latitude: z.number().min(-90).max(90).nullable().optional(),
      longitude: z.number().min(-180).max(180).nullable().optional(),
      accuracy: z.number().min(0).max(100000).nullable().optional(),
      triggerSource: z.enum(['button', 'voice']).default('button'),
      lastCue: z.string().max(200).optional(), lastDetails: z.string().max(500).optional(),
      lastRisk: z.enum(['clear', 'caution', 'danger', 'unknown']).optional(),
      lastConfidence: z.number().min(0).max(1).optional(),
      snapshotCapturedAt: z.string().datetime().optional(), imageBase64: z.string().max(2_100_000).optional(),
    }).parse(await parsedJson(request));
    const { imageBase64, latitude, longitude, accuracy, ...contextFields } = body;
    const alert: Alert = { id: randomUUID(), type: 'alert', blindUserId: user.sub,
      status: 'active', startedAt: new Date().toISOString(), idempotencyKey: key,
      blindUserName: profile.displayName, ...contextFields,
      latitude: latitude ?? undefined, longitude: longitude ?? undefined, accuracy: accuracy ?? undefined };
    if (imageBase64) {
      try { alert.snapshotKey = await storeEmergencySnapshot(user.sub, alert.id, imageBase64); }
      catch { context.warn('Emergency snapshot could not be stored; continuing with the alert.'); }
    }
    await repository.saveAlert(alert);
    await scheduleGuardianPush(alert);
    await publishAlert(user.sub, { type: "alert.created", alert: alertResponse(alert) });
    if (process.env.AzureWebJobsStorage) {
      const queue = QueueServiceClient.fromConnectionString(process.env.AzureWebJobsStorage).getQueueClient("sms-escalation");
      await queue.createIfNotExists();
      await queue.sendMessage(Buffer.from(JSON.stringify({ alertId: alert.id })).toString("base64"), { visibilityTimeout: 30 });
    } else context.warn("SMS escalation was not scheduled because AzureWebJobsStorage is absent.");
    return json(201, alertResponse(alert));
  }),
});

app.http("activeAlerts", {
  methods: ["GET"], authLevel: "anonymous", route: "v1/alerts/active",
  handler: route(async (request) => {
    const { user, profile } = await requireProfile(request);
    const alerts = profile.role === "emergencyContact"
      ? await repository.activeAlertsForContact(user.sub)
      : await repository.activeAlertsForBlindUser(user.sub);
    return json(200, alerts.map(alertResponse));
  }),
});

app.http("updateLocation", {
  methods: ["PUT"], authLevel: "anonymous", route: "v1/alerts/{id}/location",
  handler: route(async (request) => {
    const id = required(request.params.id, "Alert ID");
    const { user, alert } = await authorizeAlert(request, id);
    if (alert.blindUserId !== user.sub) throw new HttpError(403, "Only the blind user can update their location.");
    if (!["active", "acknowledged"].includes(alert.status)) throw new HttpError(409, "This alert is no longer active.");
    const body = locationSchema.parse(await parsedJson(request));
    const location: AlertLocation = { id: randomUUID(), type: "location", alertId: id, blindUserId: user.sub, ...body, recordedAt: body.recordedAt ?? new Date().toISOString(), ttl: 30 * 24 * 60 * 60 };
    await repository.saveLocation(location);
    Object.assign(alert, { latitude: body.latitude, longitude: body.longitude, accuracy: body.accuracy, locationUpdatedAt: location.recordedAt });
    await repository.saveAlert(alert); await publishAlert(alert.blindUserId, { type: "location.updated", alertId: id, location });
    return json(204);
  }),
});

for (const action of ["acknowledge", "resolve", "cancel"] as const) {
  app.http(`alert-${action}`, {
    methods: ["POST"], authLevel: "anonymous", route: `v1/alerts/{id}/${action}`,
    handler: route(async (request) => {
      const { user, profile, alert } = await authorizeAlert(request, required(request.params.id, "Alert ID"));
      if (action === "cancel" && alert.blindUserId !== user.sub) throw new HttpError(403, "Only the blind user can cancel an alert.");
      if (action !== "cancel" && profile.role !== "emergencyContact") throw new HttpError(403, "Only a trusted contact can perform this action.");
      if (!['active', 'acknowledged'].includes(alert.status)) throw new HttpError(409, 'This alert is no longer active.');
      if (action === "acknowledge") { alert.status = "acknowledged"; alert.acknowledgedBy = user.sub; alert.acknowledgedAt = new Date().toISOString(); }
      else { alert.status = action === "resolve" ? "resolved" : "cancelled"; alert.resolvedBy = user.sub; alert.resolvedAt = new Date().toISOString(); }
      if (action !== 'acknowledge') {
        await deleteEmergencySnapshot(alert.snapshotKey);
        delete alert.snapshotKey;
      }
      await repository.saveAlert(alert); await publishAlert(alert.blindUserId, { type: `alert.${action}`, alert: alertResponse(alert) });
      return json(200, alertResponse(alert));
    }),
  });
}

app.http('alertSnapshot', {
  methods: ['GET'], authLevel: 'anonymous', route: 'v1/alerts/{id}/snapshot',
  handler: route(async (request) => {
    const { alert } = await authorizeAlert(request, required(request.params.id, 'Alert ID'));
    if (!alert.snapshotKey) throw new HttpError(404, 'No emergency snapshot is available.');
    return { status: 200, body: await emergencySnapshot(alert.snapshotKey),
      headers: { 'content-type': 'image/jpeg', 'cache-control': 'no-store, private' } };
  }),
});

app.http("realtimeNegotiate", {
  methods: ["GET"], authLevel: "anonymous", route: "v1/realtime/negotiate",
  handler: route(async (request) => {
    const { user, profile } = await requireProfile(request);
    const groups = profile.role === "blindUser" ? [`alert:${user.sub}`] : (await repository.linksForContact(user.sub)).map((link) => `alert:${link.blindUserId}`);
    return json(200, await realtimeToken(user.sub, groups));
  }),
});

app.storageQueue('guardianPush', {
  queueName:'guardian-push',connection:'AzureWebJobsStorage',
  handler:async(message:unknown,context:InvocationContext)=>{
    const payload=typeof message==='string'?JSON.parse(message):message as {alertId?:string};
    const alert=payload.alertId?await repository.alert(payload.alertId):undefined;
    if(!alert||alert.status!=='active')return;
    const links=await repository.linksForBlindUser(alert.blindUserId);
    const devices=await repository.devices(links.map(link=>link.contactUserId));
    await sendEmergencyPush(devices,alert,await repository.profile(alert.blindUserId));
    context.log('Guardian push processed',{alertId:alert.id,devices:devices.length});
  },
});

app.storageQueue("smsEscalation", {
  queueName: "sms-escalation", connection: "AzureWebJobsStorage",
  handler: async (message: unknown, context: InvocationContext) => {
    const payload = typeof message === "string" ? JSON.parse(message) : message as { alertId?: string };
    const alert = payload.alertId ? await repository.alert(payload.alertId) : undefined;
    if (!alert || alert.status !== "active" || alert.smsEscalatedAt) return;
    const links = await repository.linksForBlindUser(alert.blindUserId);
    const profiles = (await Promise.all(links.map((link) => repository.profile(link.contactUserId))))
      .filter((profile): profile is NonNullable<typeof profile> => profile !== undefined);
    await sendEmergencySms(profiles, await repository.profile(alert.blindUserId), alert);
    alert.smsEscalatedAt = new Date().toISOString(); await repository.saveAlert(alert);
    context.log("SMS escalation processed", { alertId: alert.id, recipients: profiles.length });
  },
});
