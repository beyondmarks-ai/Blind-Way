import { createHash, randomBytes, randomUUID } from "node:crypto";

import { SendMessageCommand, SQSClient } from "@aws-sdk/client-sqs";
import type { APIGatewayProxyEventV2WithJWTAuthorizer, APIGatewayProxyResultV2, ScheduledEvent, SQSEvent } from "aws-lambda";

import { analyzeScene, sendEmergencyPush, warmGoogleCredentials } from "./google.js";
import { repository } from "./repository.js";
import { deleteEmergencySnapshot, emergencySnapshot, storeEmergencySnapshot } from "./snapshot.js";
import { sendEmergencySms, synthesizeSpeech } from "./speech.js";
import type { Alert, AlertLocation, Device, Invite, Role, TrustedLink } from "./types.js";

const sqs = new SQSClient({});
type ApiEvent = APIGatewayProxyEventV2WithJWTAuthorizer;

class HttpError extends Error {
  constructor(readonly status: number, message: string) { super(message); }
}

const json = (statusCode: number, body?: unknown): APIGatewayProxyResultV2 => ({
  statusCode,
  ...(body === undefined ? {} : { headers: { "content-type": "application/json" }, body: JSON.stringify(body) }),
});

function alertResponse(alert: Alert) {
  const { snapshotKey: _privateStorageKey, ...safe } = alert;
  return { ...safe, snapshotAvailable: Boolean(alert.snapshotKey) };
}

function parsedBody(event: ApiEvent) {
  if (!event.body) throw new HttpError(400, "A JSON body is required.");
  try {
    const raw = event.isBase64Encoded ? Buffer.from(event.body, "base64").toString("utf8") : event.body;
    return JSON.parse(raw) as Record<string, unknown>;
  } catch { throw new HttpError(400, "A valid JSON body is required."); }
}

function header(event: ApiEvent, name: string) {
  const target = name.toLowerCase();
  const entry = Object.entries(event.headers).find(([key]) => key.toLowerCase() === target);
  return entry?.[1] ?? "";
}

function visionInput(event: ApiEvent) {
  if (header(event, "content-type").toLowerCase().startsWith("image/jpeg")) {
    if (!event.body) throw new HttpError(400, "A JPEG image is required.");
    const image = event.isBase64Encoded
      ? Buffer.from(event.body, "base64")
      : Buffer.from(event.body, "binary");
    if (image.length > 1_500_000) throw new HttpError(413, "The camera image exceeds 1.5 MB.");
    if (image.length < 4 || image[0] !== 0xff || image[1] !== 0xd8 || image.at(-2) !== 0xff || image.at(-1) !== 0xd9) {
      throw new HttpError(400, "A valid JPEG image is required.");
    }
    return {
      imageBase64: image.toString("base64"),
      language: (event.queryStringParameters?.language ?? "English").slice(0, 30),
    };
  }
  const body = parsedBody(event);
  const imageBase64 = required(body.imageBase64, "imageBase64");
  if (imageBase64.length > 2_100_000) throw new HttpError(413, "The camera image exceeds 1.5 MB.");
  if (!imageBase64.startsWith("/9j/")) throw new HttpError(400, "A valid JPEG image is required.");
  return {
    imageBase64,
    language: typeof body.language === "string" ? body.language.slice(0, 30) : "English",
  };
}

function required(value: unknown, name: string) {
  if (typeof value !== "string" || !value.trim()) throw new HttpError(400, `${name} is required.`);
  return value.trim();
}

function user(event: ApiEvent) {
  const claims = event.requestContext.authorizer?.jwt?.claims;
  const sub = typeof claims?.sub === "string" ? claims.sub : "";
  if (!sub) throw new HttpError(401, "Authentication is required.");
  const phone = typeof claims.phone_number === "string" ? claims.phone_number : undefined;
  return {
    sub,
    name: typeof claims.name === "string" ? claims.name : undefined,
    phone,
    phoneVerified: Boolean(phone),
  };
}

async function requireProfile(event: ApiEvent) {
  const current = user(event);
  const profile = await repository.profile(current.sub);
  if (!profile) throw new HttpError(409, "Register this device before using the API.");
  return { user: current, profile };
}

async function authorizeAlert(event: ApiEvent, alertId: string) {
  const current = await requireProfile(event);
  const alert = await repository.alert(alertId);
  if (!alert) throw new HttpError(404, "Alert not found.");
  if (alert.blindUserId !== current.user.sub && !(await repository.activeLink(alert.blindUserId, current.user.sub))) {
    throw new HttpError(403, "You are not authorized to access this alert.");
  }
  return { ...current, alert };
}

async function api(event: ApiEvent): Promise<APIGatewayProxyResultV2> {
  const route = event.routeKey;
  if (route === "GET /health") return json(200, { status: "ok", platform: "aws", vision: "google-vertex-ai" });

  if (route === "POST /v1/devices/register") {
    const current = user(event);
    const body = parsedBody(event);
    const role = required(body.role, "role") as Role;
    if (!["blindUser", "emergencyContact"].includes(role)) throw new HttpError(400, "role is invalid.");
    const displayName = required(body.displayName, "displayName").slice(0, 100);
    const pushToken = required(body.pushToken, "pushToken");
    if (pushToken.length < 20 || pushToken.length > 4096) throw new HttpError(400, "pushToken is invalid.");
    const profile = await repository.ensureProfile(current.sub, role, displayName, {
      phone: current.phone,
      phoneVerified: current.phoneVerified,
    });
    if (profile.role !== role) throw new HttpError(409, "The account role cannot be changed after registration.");
    const device: Device = {
      id: createHash("sha256").update(`${current.sub}:${pushToken}`).digest("hex"),
      type: "device", ownerId: current.sub, platform: "android", pushToken, updatedAt: new Date().toISOString(),
    };
    await repository.saveDevice(device);
    return json(204);
  }

  if (route === "POST /v1/vision/analyze") {
    const { profile } = await requireProfile(event);
    if (profile.role !== "blindUser") throw new HttpError(403, "Only vision-assistance users can analyze frames.");
    const { imageBase64, language } = visionInput(event);
    return json(200, await analyzeScene(imageBase64, language));
  }

  if (route === "GET /v1/speech") {
    await requireProfile(event);
    const text = required(event.queryStringParameters?.text, "text").slice(0, 200);
    const language = (event.queryStringParameters?.language ?? "English").slice(0, 30);
    const audio = await synthesizeSpeech(text, language);
    return {
      statusCode: 200,
      headers: { "content-type": "audio/mpeg", "cache-control": "no-store" },
      body: Buffer.from(audio).toString("base64"),
      isBase64Encoded: true,
    };
  }

  if (route === "POST /v1/contacts/invites") {
    const { user: current, profile } = await requireProfile(event);
    if (profile.role !== "blindUser") throw new HttpError(403, "Only blind users can create invitations.");
    if ((await repository.linksForBlindUser(current.sub)).length >= 5) throw new HttpError(409, "A maximum of five trusted contacts is supported.");
    const code = randomBytes(5).toString("hex").toUpperCase();
    const invite: Invite = {
      id: randomUUID(), type: "invite", blindUserId: current.sub,
      codeHash: createHash("sha256").update(code).digest("hex"),
      expiresAt: new Date(Date.now() + 10 * 60_000).toISOString(),
    };
    await repository.saveInvite(invite);
    return json(201, { code, expiresAt: invite.expiresAt });
  }

  if (route === "POST /v1/contacts/invites/redeem") {
    const { user: current, profile } = await requireProfile(event);
    if (profile.role !== "emergencyContact") throw new HttpError(403, "Only emergency contacts can redeem invitations.");
    const code = required(parsedBody(event).code, "code").toUpperCase();
    const invite = await repository.inviteByHash(createHash("sha256").update(code).digest("hex"));
    if (!invite || invite.redeemedAt || Date.parse(invite.expiresAt) < Date.now()) throw new HttpError(410, "This invitation is invalid or expired.");
    if ((await repository.linksForBlindUser(invite.blindUserId)).length >= 5) throw new HttpError(409, "This user already has five trusted contacts.");
    const link: TrustedLink = { id: randomUUID(), type: "link", blindUserId: invite.blindUserId, contactUserId: current.sub, createdAt: new Date().toISOString() };
    invite.redeemedAt = new Date().toISOString(); invite.redeemedBy = current.sub;
    await repository.saveInvite(invite); await repository.saveLink(link);
    return json(201, { linked: true });
  }

  if (route === "GET /v1/contacts") {
    const { user: current, profile } = await requireProfile(event);
    const links = profile.role === "blindUser" ? await repository.linksForBlindUser(current.sub) : await repository.linksForContact(current.sub);
    const ids = links.map((link) => profile.role === "blindUser" ? link.contactUserId : link.blindUserId);
    const profiles = await repository.profiles(ids);
    return json(200, profiles.map((person) => ({ id: person.id, name: person.displayName, phone: person.phone ? `******${person.phone.slice(-4)}` : "", verified: person.phoneVerified })));
  }

  if (route === "POST /v1/alerts") {
    const { user: current, profile } = await requireProfile(event);
    if (profile.role !== "blindUser") throw new HttpError(403, "Only blind users can create alerts.");
    const key = required(event.headers["idempotency-key"], "Idempotency-Key").slice(0, 200);
    const existing = await repository.alertByIdempotency(current.sub, key);
    if (existing) return json(200, alertResponse(existing));
    const body = parsedBody(event);
    const nullableNumber = (value: unknown, name: string) => {
      if (value === null || value === undefined) return undefined;
      if (typeof value !== "number" || !Number.isFinite(value)) throw new HttpError(400, `${name} is invalid.`);
      return value;
    };
    const triggerSource = body.triggerSource === "voice" ? "voice" : "button";
    const lastRisk = ["clear", "caution", "danger", "unknown"].includes(String(body.lastRisk))
      ? body.lastRisk as Alert["lastRisk"]
      : undefined;
    const lastConfidence = typeof body.lastConfidence === "number"
      ? Math.max(0, Math.min(1, body.lastConfidence))
      : undefined;
    const alert: Alert = {
      id: randomUUID(), type: "alert", blindUserId: current.sub, status: "active",
      startedAt: new Date().toISOString(), idempotencyKey: key,
      blindUserName: profile.displayName,
      triggerSource,
      lastCue: typeof body.lastCue === "string" ? body.lastCue.replace(/\s+/g, " ").trim().slice(0, 200) : undefined,
      lastDetails: typeof body.lastDetails === "string" ? body.lastDetails.replace(/\s+/g, " ").trim().slice(0, 500) : undefined,
      lastRisk,
      lastConfidence,
      snapshotCapturedAt: typeof body.snapshotCapturedAt === "string" ? body.snapshotCapturedAt : undefined,
      latitude: nullableNumber(body.latitude, "latitude"), longitude: nullableNumber(body.longitude, "longitude"), accuracy: nullableNumber(body.accuracy, "accuracy"),
    };
    if (typeof body.imageBase64 === "string" && body.imageBase64) {
      try {
        alert.snapshotKey = await storeEmergencySnapshot(current.sub, alert.id, body.imageBase64);
      } catch (error) {
        console.error("Emergency snapshot could not be stored.", error);
      }
    }
    await repository.saveAlert(alert);
    await repository.saveIdempotency(current.sub, key, alert.id);
    const links = await repository.linksForBlindUser(current.sub);
    const deviceGroups = await Promise.all(links.map((link) => repository.devices(link.contactUserId)));
    await sendEmergencyPush(deviceGroups.flat(), alert, profile);
    if (process.env.SMS_QUEUE_URL) {
      await sqs.send(new SendMessageCommand({ QueueUrl: process.env.SMS_QUEUE_URL, DelaySeconds: 30, MessageBody: JSON.stringify({ alertId: alert.id }) }));
    }
    return json(201, alertResponse(alert));
  }

  if (route === "GET /v1/alerts/active") {
    const { user: current, profile } = await requireProfile(event);
    const alerts = profile.role === "emergencyContact" ? await repository.activeAlertsForContact(current.sub) : await repository.activeAlertsForBlindUser(current.sub);
    return json(200, alerts.map(alertResponse));
  }

  if (route === "GET /v1/alerts/{id}/snapshot") {
    const { alert } = await authorizeAlert(event, required(event.pathParameters?.id, "Alert ID"));
    if (!alert.snapshotKey) throw new HttpError(404, "No emergency snapshot is available.");
    const image = await emergencySnapshot(alert.snapshotKey);
    return {
      statusCode: 200,
      headers: { "content-type": "image/jpeg", "cache-control": "no-store, private" },
      body: Buffer.from(image).toString("base64"),
      isBase64Encoded: true,
    };
  }

  if (route === "PUT /v1/alerts/{id}/location") {
    const id = required(event.pathParameters?.id, "Alert ID");
    const { user: current, alert } = await authorizeAlert(event, id);
    if (alert.blindUserId !== current.sub) throw new HttpError(403, "Only the blind user can update their location.");
    if (!["active", "acknowledged"].includes(alert.status)) throw new HttpError(409, "This alert is no longer active.");
    const body = parsedBody(event);
    const number = (name: string) => {
      const value = body[name];
      if (typeof value !== "number" || !Number.isFinite(value)) throw new HttpError(400, `${name} is invalid.`);
      return value;
    };
    const recordedAt = typeof body.recordedAt === "string" ? body.recordedAt : new Date().toISOString();
    const location: AlertLocation = {
      id: randomUUID(), type: "location", alertId: id, blindUserId: current.sub,
      latitude: number("latitude"), longitude: number("longitude"), accuracy: number("accuracy"), recordedAt,
      expiresAt: Math.floor(Date.now() / 1000) + 30 * 24 * 60 * 60,
    };
    await repository.saveLocation(location);
    Object.assign(alert, {
      latitude: location.latitude,
      longitude: location.longitude,
      accuracy: location.accuracy,
      locationUpdatedAt: location.recordedAt,
    });
    await repository.saveAlert(alert);
    return json(204);
  }

  const actionMatch = route.match(/^POST \/v1\/alerts\/\{id\}\/(acknowledge|resolve|cancel)$/);
  if (actionMatch) {
    const action = actionMatch[1] as "acknowledge" | "resolve" | "cancel";
    const { user: current, profile, alert } = await authorizeAlert(event, required(event.pathParameters?.id, "Alert ID"));
    if (action === "cancel" && alert.blindUserId !== current.sub) throw new HttpError(403, "Only the blind user can cancel an alert.");
    if (action !== "cancel" && profile.role !== "emergencyContact") throw new HttpError(403, "Only a trusted contact can perform this action.");
    if (action === "acknowledge") {
      alert.status = "acknowledged"; alert.acknowledgedBy = current.sub; alert.acknowledgedAt = new Date().toISOString();
    } else {
      alert.status = action === "resolve" ? "resolved" : "cancelled"; alert.resolvedBy = current.sub; alert.resolvedAt = new Date().toISOString();
    }
    if (action !== "acknowledge") {
      await deleteEmergencySnapshot(alert.snapshotKey);
      delete alert.snapshotKey;
    }
    await repository.saveAlert(alert);
    return json(200, alertResponse(alert));
  }

  throw new HttpError(404, "Route not found.");
}

async function processSms(event: SQSEvent) {
  for (const record of event.Records) {
    const { alertId } = JSON.parse(record.body) as { alertId?: string };
    const alert = alertId ? await repository.alert(alertId) : undefined;
    if (!alert || alert.status !== "active" || alert.smsEscalatedAt) continue;
    const links = await repository.linksForBlindUser(alert.blindUserId);
    const profiles = await repository.profiles(links.map((link) => link.contactUserId));
    const owner = await repository.profile(alert.blindUserId);
    await sendEmergencySms(profiles.filter((p) => p.phoneVerified && p.phone).map((p) => p.phone!), owner?.displayName ?? "Blind Way user", alert.id);
    alert.smsEscalatedAt = new Date().toISOString();
    await repository.saveAlert(alert);
  }
}

export async function handler(event: ApiEvent | SQSEvent | ScheduledEvent): Promise<APIGatewayProxyResultV2 | void> {
  if ("source" in event) return warmGoogleCredentials();
  if ("Records" in event) return processSms(event);
  try {
    return await api(event);
  } catch (error) {
    const status = error instanceof HttpError ? error.status : 500;
    const message = error instanceof Error ? error.message : "Unexpected error";
    if (status >= 500) console.error(JSON.stringify({ message, stack: error instanceof Error ? error.stack : undefined }));
    return json(status, { error: status >= 500 ? "The service is temporarily unavailable." : message });
  }
}
