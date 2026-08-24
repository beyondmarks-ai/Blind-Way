import { GetSecretValueCommand, SecretsManagerClient } from "@aws-sdk/client-secrets-manager";

const secrets = new SecretsManagerClient({});
let sarvamApiKey: string | undefined;

export async function getSarvamApiKey() {
  if (sarvamApiKey) return sarvamApiKey;
  const secretId = process.env.SARVAM_SECRET_ARN;
  if (!secretId) throw new Error("Sarvam speech is not configured.");
  const response = await secrets.send(new GetSecretValueCommand({ SecretId: secretId }));
  const parsed = JSON.parse(response.SecretString ?? "{}") as { apiKey?: string };
  if (!parsed.apiKey) throw new Error("The Sarvam secret has no API key.");
  sarvamApiKey = parsed.apiKey;
  return sarvamApiKey;
}

export async function synthesizeSpeech(text: string, language: string) {
  const apiKey = await getSarvamApiKey();
  const languageCode = language === "Hindi" ? "hi-IN" : language === "Tamil" ? "ta-IN" : "en-IN";
  const response = await fetch("https://api.sarvam.ai/text-to-speech/stream", {
    method: "POST",
    headers: { "api-subscription-key": apiKey, "content-type": "application/json", accept: "audio/mpeg" },
    body: JSON.stringify({
      text,
      language_code: languageCode,
      speaker: process.env.SARVAM_TTS_SPEAKER ?? "ritu",
      model: process.env.SARVAM_TTS_MODEL ?? "bulbul:v3",
      output_audio_codec: "mp3",
      output_audio_bitrate: "64k",
      speech_sample_rate: 24000,
      pace: 1.12,
      temperature: 0.65,
    }),
    signal: AbortSignal.timeout(10_000),
  });
  if (!response.ok) throw new Error(`Sarvam speech failed with status ${response.status}.`);
  return new Uint8Array(await response.arrayBuffer());
}

export async function sendEmergencySms(phoneNumbers: string[], displayName: string, alertId: string) {
  const authKey = process.env.MSG91_AUTH_KEY;
  const templateId = process.env.MSG91_TEMPLATE_ID;
  if (!authKey || !templateId || !phoneNumbers.length) return;
  const response = await fetch("https://control.msg91.com/api/v5/flow", {
    method: "POST",
    headers: { accept: "application/json", authkey: authKey, "content-type": "application/json" },
    body: JSON.stringify({
      template_id: templateId,
      short_url: "1",
      short_url_expiry: "86400",
      realTimeResponse: "1",
      recipients: phoneNumbers.map((phone) => ({ mobiles: phone.replace(/^\+/, ""), NAME: displayName, ALERT_ID: alertId })),
    }),
    signal: AbortSignal.timeout(10_000),
  });
  if (!response.ok) throw new Error(`MSG91 rejected the alert with status ${response.status}.`);
}
