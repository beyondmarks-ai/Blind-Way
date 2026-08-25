import type { APIGatewayProxyEventV2 } from "aws-lambda";
import { createRemoteJWKSet, jwtVerify } from "jose";
import type { Writable } from "node:stream";
import { finished } from "node:stream/promises";
import WebSocket from "ws";

import { repository } from "./repository.js";
import { getSarvamApiKey } from "./speech.js";

interface LambdaResponseStream {
  write(chunk: Uint8Array | string): boolean;
  end(chunk?: Uint8Array | string): void;
  setContentType(contentType: string): void;
}

declare const awslambda: {
  streamifyResponse<T>(handler: (event: T, stream: LambdaResponseStream) => Promise<void>): unknown;
};

const firebaseProjectId = requiredEnv("GCP_FIREBASE_PROJECT_ID");
const issuer = `https://securetoken.google.com/${firebaseProjectId}`;
const audience = firebaseProjectId;
const jwks = createRemoteJWKSet(new URL(
  "https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com",
));

function requiredEnv(name: string) {
  const value = process.env[name];
  if (!value) throw new Error(`${name} is not configured.`);
  return value;
}

async function respond(stream: LambdaResponseStream, statusCode: number, body: string) {
  stream.setContentType("application/json");
  stream.end(JSON.stringify({ statusCode, error: body }));
  await finished(stream as unknown as Writable);
}

function languageCode(language: string) {
  return language === "Hindi" ? "hi-IN" : language === "Tamil" ? "ta-IN" : "en-IN";
}

async function authenticatedUser(event: APIGatewayProxyEventV2) {
  const authorization = event.headers.authorization ?? event.headers.Authorization;
  const token = authorization?.match(/^Bearer\s+(.+)$/i)?.[1];
  if (!token) return undefined;
  const verified = await jwtVerify(token, jwks, { issuer, audience });
  return typeof verified.payload.sub === "string" ? verified.payload.sub : undefined;
}

async function streamSpeech(
  event: APIGatewayProxyEventV2,
  rawStream: LambdaResponseStream,
  state: { started: boolean },
) {
  let userId: string | undefined;
  try {
    userId = await authenticatedUser(event);
  } catch {
    await respond(rawStream, 401, "Authentication is required.");
    return;
  }
  if (!userId) {
    await respond(rawStream, 401, "Authentication is required.");
    return;
  }
  if (!(await repository.profile(userId))) {
    await respond(rawStream, 409, "Register this device before using speech.");
    return;
  }

  const text = event.queryStringParameters?.text?.trim().slice(0, 200);
  if (!text) {
    await respond(rawStream, 400, "text is required.");
    return;
  }
  const language = (event.queryStringParameters?.language ?? "English").slice(0, 30);
  const apiKey = await getSarvamApiKey();
  const model = process.env.SARVAM_TTS_MODEL ?? "bulbul:v3";
  const socket = new WebSocket(
    `wss://api.sarvam.ai/text-to-speech/ws?model=${encodeURIComponent(model)}&send_completion_event=true`,
    { headers: { "Api-Subscription-Key": apiKey }, handshakeTimeout: 5_000 },
  );

  await new Promise<void>((resolve, reject) => {
    socket.once("open", resolve);
    socket.once("error", reject);
  }).catch((error: unknown) => {
    socket.terminate();
    throw error;
  });

  rawStream.setContentType("audio/mpeg");
  const response = rawStream;
  state.started = true;

  await new Promise<void>((resolve) => {
    let finished = false;
    const finish = () => {
      if (finished) return;
      finished = true;
      clearTimeout(timeout);
      if (socket.readyState === WebSocket.OPEN) socket.close(1000);
      response.end();
      resolve();
    };
    const timeout = setTimeout(() => {
      console.error("Sarvam speech stream timed out.");
      socket.terminate();
      finish();
    }, 12_000);

    socket.on("message", (raw) => {
      try {
        const message = JSON.parse(raw.toString()) as {
          type?: string;
          data?: { audio?: string; content?: string; event_type?: string; message?: string };
        };
        if (message.type === "audio") {
          const audio = message.data?.audio ?? message.data?.content;
          if (audio) response.write(Buffer.from(audio, "base64"));
        } else if (message.type === "event" && message.data?.event_type === "final") {
          finish();
        } else if (message.type === "error") {
          console.error(`Sarvam speech stream error: ${message.data?.message ?? "unknown"}`);
          finish();
        }
      } catch (error) {
        console.error("Invalid Sarvam speech stream message.", error);
        finish();
      }
    });
    socket.once("error", (error) => {
      console.error("Sarvam speech WebSocket error.", error);
      finish();
    });
    socket.once("close", finish);

    socket.send(JSON.stringify({
      type: "config",
      data: {
        model,
        language_code: languageCode(language),
        speaker: process.env.SARVAM_TTS_SPEAKER ?? "ritu",
        pace: 1.2,
        temperature: 0.6,
        speech_sample_rate: 24000,
        enable_preprocessing: true,
        output_audio_codec: "mp3",
        output_audio_bitrate: "64k",
        min_buffer_size: 30,
        max_chunk_length: 50,
      },
    }));
    socket.send(JSON.stringify({ type: "text", data: { text } }));
    socket.send(JSON.stringify({ type: "flush" }));
  });
  await finished(response as unknown as Writable);
}

export const handler = awslambda.streamifyResponse(async (
  event: APIGatewayProxyEventV2,
  responseStream: LambdaResponseStream,
) => {
  const state = { started: false };
  try {
    await streamSpeech(event, responseStream, state);
  } catch (error) {
    console.error("Speech streaming failed.", error);
    if (state.started) {
      responseStream.end();
    } else {
      await respond(responseStream, 503, "Speech is temporarily unavailable.");
    }
  }
});
