import { DefaultAzureCredential, getBearerTokenProvider } from "@azure/identity";
import { createFcmV1Notification, NotificationHubsClient } from "@azure/notification-hubs";
import { WebPubSubServiceClient } from "@azure/web-pubsub";
import { AzureOpenAI } from "openai";

import { config } from "./config.js";
import type { Alert, Device, Profile } from "./types.js";

let openai: AzureOpenAI | undefined;

export async function analyzeScene(image: Uint8Array, language: string) {
  if (!config.AZURE_OPENAI_ENDPOINT) {
    return { cue: "Vision service is not configured", risk: "unknown", confidence: 0 };
  }
  const tokenProvider = getBearerTokenProvider(
    new DefaultAzureCredential(),
    "https://cognitiveservices.azure.com/.default",
  );
  openai ??= new AzureOpenAI({
    endpoint: config.AZURE_OPENAI_ENDPOINT,
    deployment: config.AZURE_OPENAI_DEPLOYMENT,
    apiVersion: "2025-04-01-preview",
    azureADTokenProvider: tokenProvider,
  });
  const base64 = Buffer.from(image).toString("base64");
  const prompt = `You assist a blind person navigating the space directly ahead. Return only JSON with cue (one natural ${language} instruction, maximum 14 words), risk (clear, caution, danger, or unknown), and confidence (0 to 1). Prioritize immediate obstacles, stairs, doors, people, vehicles, drop-offs and low visibility. Never invent distance. If unclear, report low visibility.`;
  const response = await openai.responses.create({
    model: config.AZURE_OPENAI_DEPLOYMENT,
    store: false,
    max_output_tokens: 80,
    reasoning: { effort: "none" },
    text: { verbosity: "low" },
    input: [{
      role: "user",
      content: [
        { type: "input_text", text: prompt },
        { type: "input_image", image_url: `data:image/jpeg;base64,${base64}`, detail: "low" },
      ],
    }],
  });
  const raw = response.output_text.trim().replace(/^```json\s*|\s*```$/g, "");
  const parsed = JSON.parse(raw) as Record<string, unknown>;
  const risks = new Set(["clear", "caution", "danger", "unknown"]);
  const risk = risks.has(String(parsed.risk)) ? String(parsed.risk) : "unknown";
  const confidence = Math.max(0, Math.min(1, Number(parsed.confidence) || 0));
  const cue = String(parsed.cue ?? "Vision unavailable").replace(/\s+/g, " ").trim().slice(0, 160);
  return { cue: cue || "Vision unavailable", risk, confidence };
}

export async function synthesizeSpeech(text: string, language: string) {
  if (!config.SARVAM_API_KEY) throw new Error("Sarvam speech is not configured.");
  const languageCode = language === "Hindi" ? "hi-IN" : language === "Tamil" ? "ta-IN" : "en-IN";
  const response = await fetch("https://api.sarvam.ai/text-to-speech/stream", {
    method: "POST",
    headers: {
      "api-subscription-key": config.SARVAM_API_KEY,
      "content-type": "application/json",
      accept: "audio/mpeg",
    },
    body: JSON.stringify({
      text,
      language_code: languageCode,
      speaker: config.SARVAM_TTS_SPEAKER,
      model: config.SARVAM_TTS_MODEL,
      output_audio_codec: "mp3",
      output_audio_bitrate: "64k",
      speech_sample_rate: 24000,
      pace: 1.12,
      temperature: 0.65,
    }),
  });
  if (!response.ok || !response.body) {
    throw new Error(`Sarvam speech failed with status ${response.status}.`);
  }
  return response;
}

export async function sendEmergencyPush(devices: Device[], alert: Alert, blindProfile?: Profile) {
  if (!config.NOTIFICATION_HUB_CONNECTION_STRING || !config.NOTIFICATION_HUB_NAME || !devices.length) return;
  const client = new NotificationHubsClient(config.NOTIFICATION_HUB_CONNECTION_STRING, config.NOTIFICATION_HUB_NAME);
  const notification = createFcmV1Notification({
    body: {
      notification: {
        title: "Emergency assistance requested",
        body: `${blindProfile?.displayName ?? "A trusted Blind Way user"} needs your help.`,
      },
      data: { alertId: alert.id, type: "emergency" },
      android: {
        priority: "high",
        notification: { channel_id: "emergency_alerts", sound: "default" },
      },
    },
  });
  await Promise.allSettled(
    devices.map((device) => client.sendNotification(notification, { deviceHandle: device.pushToken })),
  );
}

function realtimeClient() {
  return config.WEB_PUBSUB_CONNECTION_STRING
    ? new WebPubSubServiceClient(config.WEB_PUBSUB_CONNECTION_STRING, config.WEB_PUBSUB_HUB)
    : undefined;
}

export async function publishAlert(blindUserId: string, event: unknown) {
  const client = realtimeClient();
  if (client) await client.group(`alert:${blindUserId}`).sendToAll(event as Record<string, unknown>);
}

export async function realtimeToken(userId: string, groups: string[]) {
  const client = realtimeClient();
  if (!client) return { url: "", expiresInMinutes: 0 };
  return client.getClientAccessToken({ userId, groups, expirationTimeInMinutes: 60 });
}

export async function sendEmergencySms(profiles: Profile[], blindProfile: Profile | undefined, alert: Alert) {
  if (!config.MSG91_AUTH_KEY || !config.MSG91_TEMPLATE_ID) return { skipped: true };
  const recipients = profiles
    .filter((profile) => profile.phoneVerified && profile.phone)
    .map((profile) => ({
      mobiles: profile.phone!.replace(/^\+/, ""),
      NAME: blindProfile?.displayName ?? "Blind Way user",
      ALERT_ID: alert.id,
    }));
  if (!recipients.length) return { skipped: true };
  const response = await fetch("https://control.msg91.com/api/v5/flow", {
    method: "POST",
    headers: { accept: "application/json", authkey: config.MSG91_AUTH_KEY, "content-type": "application/json" },
    body: JSON.stringify({ template_id: config.MSG91_TEMPLATE_ID, short_url: "1", short_url_expiry: "86400", realTimeResponse: "1", recipients }),
  });
  if (!response.ok) throw new Error(`MSG91 rejected the alert with status ${response.status}.`);
  return response.json();
}
