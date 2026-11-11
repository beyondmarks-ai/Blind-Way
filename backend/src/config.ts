import { z } from "zod";

const schema = z.object({
  FIREBASE_PROJECT_ID: z.string().min(1).optional(),
  FCM_WIF_PROVIDER: z.string().optional(),
  FCM_SERVICE_ACCOUNT: z.string().optional(),
  GOOGLE_MAPS_SERVER_KEY: z.string().optional(),
  ALLOW_DEBUG_AUTH: z.enum(["true", "false"]).default("false"),
  SARVAM_API_KEY: z.string().optional(),
  SARVAM_STT_MODEL: z.string().default('saaras:v4'),
  SARVAM_TTS_MODEL: z.string().default('bulbul:v3'),
  SARVAM_TTS_SPEAKER: z.string().default('ritu'),
  AZURE_OPENAI_ENDPOINT: z.string().url().optional(),
  AZURE_OPENAI_DEPLOYMENT: z.string().default("guardian-vision"),
  AZURE_SPEECH_KEY: z.string().optional(),
  AZURE_SPEECH_REGION: z.string().regex(/^[a-z0-9]+$/).default('centralindia'),
  COSMOS_ENDPOINT: z.string().url().optional(),
  COSMOS_DATABASE: z.string().default("blindway"),
  NOTIFICATION_HUB_CONNECTION_STRING: z.string().optional(),
  NOTIFICATION_HUB_NAME: z.string().optional(),
  WEB_PUBSUB_CONNECTION_STRING: z.string().optional(),
  WEB_PUBSUB_HUB: z.string().default("alerts"),
  MSG91_AUTH_KEY: z.string().optional(),
  MSG91_TEMPLATE_ID: z.string().optional(),
  MSG91_SENDER_ID: z.string().optional(),
});

export const config = schema.parse(process.env);
