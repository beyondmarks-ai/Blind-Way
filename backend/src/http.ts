import type { HttpHandler, HttpResponseInit, InvocationContext } from "@azure/functions";

import { HttpError } from "./auth.js";

export function route(handler: HttpHandler): HttpHandler {
  return async (request, context): Promise<HttpResponseInit> => {
    try {
      return await handler(request, context);
    } catch (error) {
      const status = error instanceof HttpError ? error.status : 500;
      const message = error instanceof Error ? error.message : "Unexpected error";
      if (status >= 500) context.error("Request failed", { message });
      return { status, jsonBody: { error: message } };
    }
  };
}

export function json(status: number, body?: unknown): HttpResponseInit {
  return body === undefined ? { status } : { status, jsonBody: body };
}

export function required(value: string | null | undefined, name: string): string {
  if (!value?.trim()) throw new HttpError(400, `${name} is required.`);
  return value.trim();
}
