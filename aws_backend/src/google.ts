import { GoogleAuth } from "google-auth-library";

import type { Alert, Device, Profile } from "./types.js";

const auth = new GoogleAuth({
  scopes: [
    "https://www.googleapis.com/auth/cloud-platform",
    "https://www.googleapis.com/auth/firebase.messaging",
  ],
});
const authClient = auth.getClient();

async function accessToken() {
  const client = await authClient;
  const token = await client.getAccessToken();
  if (!token.token) throw new Error("Google Cloud did not issue an access token.");
  return token.token;
}

export async function warmGoogleCredentials() {
  await accessToken();
}

export async function analyzeScene(imageBase64: string, language: string) {
  const project = requiredEnv("GCP_PROJECT_ID");
  const location = process.env.GCP_VERTEX_LOCATION ?? "global";
  const model = process.env.GEMINI_MODEL ?? "gemini-3.5-flash-lite";
  const prompt = `Guide a blind person through the space directly ahead. Return JSON only: cue (one natural ${language} instruction, maximum 8 words), details (one factual ${language} sentence, maximum 24 words, describing visible people, objects, obstacles and environment), risk (clear, caution, danger, or unknown), confidence (0 to 1). Prioritize immediate obstacles, stairs, doors, people, vehicles, drop-offs, and low visibility. Never invent distance. If unclear, say visibility is low.`;
  const endpoint = `https://aiplatform.googleapis.com/v1/projects/${encodeURIComponent(project)}/locations/${encodeURIComponent(location)}/publishers/google/models/${encodeURIComponent(model)}:generateContent`;
  const response = await fetch(endpoint, {
    method: "POST",
    headers: {
      authorization: `Bearer ${await accessToken()}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({
      contents: [{ role: "user", parts: [
        { text: prompt },
        { inlineData: { mimeType: "image/jpeg", data: imageBase64 } },
      ] }],
      generationConfig: {
        maxOutputTokens: 128,
        responseMimeType: "application/json",
        responseSchema: {
          type: "OBJECT",
          required: ["cue", "details", "risk", "confidence"],
          properties: {
            cue: { type: "STRING" },
            details: { type: "STRING" },
            risk: { type: "STRING", enum: ["clear", "caution", "danger", "unknown"] },
            confidence: { type: "NUMBER", minimum: 0, maximum: 1 },
          },
        },
        thinkingConfig: { thinkingLevel: "MINIMAL" },
      },
    }),
    signal: AbortSignal.timeout(12_000),
  });
  if (!response.ok) {
    const detail = (await response.text()).slice(0, 500);
    throw new Error(`Vertex AI rejected frame analysis (${response.status}): ${detail}`);
  }
  const payload = await response.json() as {
    candidates?: Array<{ content?: { parts?: Array<{ text?: string }> } }>;
  };
  const raw = payload.candidates?.[0]?.content?.parts?.map((part) => part.text ?? "").join("").trim();
  if (!raw) throw new Error("Vertex AI returned no scene cue.");
  const parsed = JSON.parse(raw) as Record<string, unknown>;
  const risk = ["clear", "caution", "danger", "unknown"].includes(String(parsed.risk)) ? String(parsed.risk) : "unknown";
  const confidence = Math.max(0, Math.min(1, Number(parsed.confidence) || 0));
  const cue = String(parsed.cue ?? "Vision unavailable").replace(/\s+/g, " ").trim().slice(0, 160);
  const details = String(parsed.details ?? cue).replace(/\s+/g, " ").trim().slice(0, 500);
  return { cue: cue || "Vision unavailable", details: details || cue, risk, confidence };
}

export async function sendEmergencyPush(devices: Device[], alert: Alert, blindProfile?: Profile) {
  const project = process.env.GCP_FIREBASE_PROJECT_ID;
  if (!project || !devices.length) return;
  const token = await accessToken();
  await Promise.allSettled(devices.map(async (device) => {
    const response = await fetch(`https://fcm.googleapis.com/v1/projects/${encodeURIComponent(project)}/messages:send`, {
      method: "POST",
      headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
      body: JSON.stringify({ message: {
        token: device.pushToken,
        notification: {
          title: `${blindProfile?.displayName ?? "A trusted user"} needs emergency help`,
          body: alert.lastCue
            ? `Last seen: ${alert.lastCue}`
            : "Open Blind Way to see their live emergency location.",
        },
        data: {
          alertId: alert.id,
          type: "emergency",
          triggerSource: alert.triggerSource,
          lastCue: alert.lastCue ?? "",
          latitude: alert.latitude?.toString() ?? "",
          longitude: alert.longitude?.toString() ?? "",
        },
        android: { priority: "high", notification: { channel_id: "emergency_alerts", sound: "default" } },
      } }),
      signal: AbortSignal.timeout(8_000),
    });
    if (!response.ok) throw new Error(`FCM rejected notification (${response.status}).`);
  }));
}

function requiredEnv(name: string) {
  const value = process.env[name];
  if (!value) throw new Error(`${name} is not configured.`);
  return value;
}
