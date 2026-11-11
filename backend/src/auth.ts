import type { HttpRequest } from "@azure/functions";
import { createRemoteJWKSet, jwtVerify, type JWTVerifyGetKey } from "jose";

import { config } from "./config.js";
import type { AuthenticatedUser } from "./types.js";

let jwks: ReturnType<typeof createRemoteJWKSet> | undefined;

export async function authenticate(request: HttpRequest): Promise<AuthenticatedUser> {
  const header = request.headers.get("authorization") ?? "";
  const token = header.startsWith("Bearer ") ? header.slice(7) : "";
  if (token === "debug-token" && config.ALLOW_DEBUG_AUTH === "true" && !process.env.WEBSITE_INSTANCE_ID) {
    return {
      sub: request.headers.get("x-debug-user") ?? "debug-user",
      name: request.headers.get("x-debug-name") ?? "Debug user",
    };
  }
  if (!token || !config.FIREBASE_PROJECT_ID) throw new HttpError(401, "Authentication is required.");
  jwks ??= createRemoteJWKSet(new URL('https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com'));
  return verifyAccessToken(token, jwks, config.FIREBASE_PROJECT_ID);
}

export async function verifyAccessToken(token: string, keys: JWTVerifyGetKey, projectId: string): Promise<AuthenticatedUser> {
  try {
    const {payload:p} = await jwtVerify(token, keys, {
      issuer: `https://securetoken.google.com/${projectId}`, audience: projectId, algorithms: ['RS256'],
      requiredClaims: ['exp', 'iat', 'sub', 'auth_time', 'phone_number', 'firebase'],
    });
    const provider = p.firebase as { sign_in_provider?: unknown } | undefined;
    const now = Math.floor(Date.now()/1000);
    if (!p.sub || p.sub.length > 128 || provider?.sign_in_provider !== 'phone' ||
        typeof p.phone_number !== 'string' || !/^\+[1-9]\d{7,14}$/.test(p.phone_number) ||
        typeof p.auth_time !== 'number' || p.auth_time > now+60 || p.auth_time < 0 ||
        typeof p.iat !== 'number' || p.iat > now+60) throw new Error('Invalid phone identity');
    return {sub:p.sub, name:typeof p.name === 'string' ? p.name : undefined};
  } catch {
    throw new HttpError(401, 'The access token is invalid or expired.');
  }
}

export class HttpError extends Error {
  constructor(public readonly status: number, message: string) {
    super(message);
  }
}
