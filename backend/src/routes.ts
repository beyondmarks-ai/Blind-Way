import { app, type HttpRequest, type InvocationContext } from "@azure/functions";
import { QueueServiceClient } from "@azure/storage-queue";
import { createHash, randomBytes, randomUUID } from "node:crypto";
import { z } from "zod";

import { authenticate, HttpError } from "./auth.js";
import { json, required, route } from "./http.js";
import { repository } from "./repository.js";
import { analyzeScene, publishAlert, realtimeToken, sendEmergencyPush, sendEmergencySms, synthesizeSpeech } from "./services.js";
import type { Alert, AlertLocation, Device, Invite, Role, TrustedLink } from "./types.js";

app.setup({ enableHttpStream: true });

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

app.http("analyzeVision", {
  methods: ["POST"], authLevel: "anonymous", route: "v1/vision/analyze",
  handler: route(async (request) => {
    const { profile } = await requireProfile(request);
    if (profile.role !== "blindUser") throw new HttpError(403, "Only vision-assistance users can analyze frames.");
    const form = await request.formData();
    const image = form.get("image");
    if (!(image instanceof File) || image.type !== "image/jpeg") throw new HttpError(400, "A JPEG image field is required.");
    if (image.size > 1_500_000) throw new HttpError(413, "The camera image exceeds 1.5 MB.");
    const language = String(form.get("language") ?? "English").slice(0, 30);
    return json(200, await analyzeScene(new Uint8Array(await image.arrayBuffer()), language));
  }),
});

app.http("speech", {
  methods: ["GET"], authLevel: "anonymous", route: "v1/speech",
  handler: route(async (request) => {
    await requireProfile(request);
    const text = required(request.query.get("text"), "text").slice(0, 200);
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

app.http("createAlert", {
  methods: ["POST"], authLevel: "anonymous", route: "v1/alerts",
  handler: route(async (request, context) => {
    const { user, profile } = await requireProfile(request);
    if (profile.role !== "blindUser") throw new HttpError(403, "Only blind users can create alerts.");
    const key = required(request.headers.get("idempotency-key"), "Idempotency-Key");
    const existing = await repository.alertByIdempotency(user.sub, key);
    if (existing) return json(200, existing);
    const body = z.object({ latitude: z.number().nullable().optional(), longitude: z.number().nullable().optional(), accuracy: z.number().nullable().optional() }).parse(await parsedJson(request));
    const alert: Alert = { id: randomUUID(), type: "alert", blindUserId: user.sub, status: "active", startedAt: new Date().toISOString(), latitude: body.latitude ?? undefined, longitude: body.longitude ?? undefined, accuracy: body.accuracy ?? undefined, idempotencyKey: key };
    await repository.saveAlert(alert);
    const links = await repository.linksForBlindUser(user.sub);
    const devices = await repository.devices(links.map((link) => link.contactUserId));
    await sendEmergencyPush(devices, alert, profile);
    await publishAlert(user.sub, { type: "alert.created", alert });
    if (process.env.AzureWebJobsStorage) {
      const queue = QueueServiceClient.fromConnectionString(process.env.AzureWebJobsStorage).getQueueClient("sms-escalation");
      await queue.createIfNotExists();
      await queue.sendMessage(Buffer.from(JSON.stringify({ alertId: alert.id })).toString("base64"), { visibilityTimeout: 30 });
    } else context.warn("SMS escalation was not scheduled because AzureWebJobsStorage is absent.");
    return json(201, alert);
  }),
});

app.http("activeAlerts", {
  methods: ["GET"], authLevel: "anonymous", route: "v1/alerts/active",
  handler: route(async (request) => {
    const { user, profile } = await requireProfile(request);
    const alerts = profile.role === "emergencyContact"
      ? await repository.activeAlertsForContact(user.sub)
      : await repository.activeAlertsForBlindUser(user.sub);
    return json(200, alerts);
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
    Object.assign(alert, { latitude: body.latitude, longitude: body.longitude, accuracy: body.accuracy });
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
      if (action === "acknowledge") { alert.status = "acknowledged"; alert.acknowledgedBy = user.sub; alert.acknowledgedAt = new Date().toISOString(); }
      else { alert.status = action === "resolve" ? "resolved" : "cancelled"; alert.resolvedBy = user.sub; alert.resolvedAt = new Date().toISOString(); }
      await repository.saveAlert(alert); await publishAlert(alert.blindUserId, { type: `alert.${action}`, alert });
      return json(200, alert);
    }),
  });
}

app.http("realtimeNegotiate", {
  methods: ["GET"], authLevel: "anonymous", route: "v1/realtime/negotiate",
  handler: route(async (request) => {
    const { user, profile } = await requireProfile(request);
    const groups = profile.role === "blindUser" ? [`alert:${user.sub}`] : (await repository.linksForContact(user.sub)).map((link) => `alert:${link.blindUserId}`);
    return json(200, await realtimeToken(user.sub, groups));
  }),
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
