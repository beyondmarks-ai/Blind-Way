import type { HttpRequest } from "@azure/functions";
import { createRemoteJWKSet, jwtVerify } from "jose";

import { config } from "./config.js";
import type { AuthenticatedUser } from "./types.js";

let jwks: ReturnType<typeof createRemoteJWKSet> | undefined;

export async function authenticate(request: HttpRequest): Promise<AuthenticatedUser> {
  const header = request.headers.get("authorization") ?? "";
  const token = header.startsWith("Bearer ") ? header.slice(7) : "";
  if (token === "debug-token" && config.ALLOW_DEBUG_AUTH === "true") {
    return {
      sub: request.headers.get("x-debug-user") ?? "debug-user",
      name: request.headers.get("x-debug-name") ?? "Debug user",
    };
  }
  if (!token || !config.FIREBASE_PROJECT_ID) {
    throw new HttpError(401, "Authentication is required.");
  }
  const issuer = `https://securetoken.google.com/${config.FIREBASE_PROJECT_ID}`;
  jwks ??= createRemoteJWKSet(
    new URL(
      "https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com",
    ),
  );
  try {
    const verified = await jwtVerify(token, jwks, {
      issuer,
      audience: config.FIREBASE_PROJECT_ID,
      algorithms: ["RS256"],
    });
    if (!verified.payload.sub) throw new Error("Missing subject");
    return {
      sub: verified.payload.sub,
      name: typeof verified.payload.name === "string" ? verified.payload.name : undefined,
      email: typeof verified.payload.email === "string" ? verified.payload.email : undefined,
    };
  } catch {
    throw new HttpError(401, "The access token is invalid or expired.");
  }
}

export class HttpError extends Error {
  constructor(public readonly status: number, message: string) {
    super(message);
  }
}
