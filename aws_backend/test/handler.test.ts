import { describe, expect, it } from "vitest";

import { handler } from "../src/handler.js";

const event = (routeKey: string) => ({
  version: "2.0",
  routeKey,
  rawPath: routeKey.split(" ")[1],
  rawQueryString: "",
  headers: {},
  requestContext: {
    accountId: "test",
    apiId: "test",
    domainName: "test",
    domainPrefix: "test",
    http: { method: routeKey.split(" ")[0], path: routeKey.split(" ")[1], protocol: "HTTP/1.1", sourceIp: "127.0.0.1", userAgent: "test" },
    requestId: "test",
    routeKey,
    stage: "$default",
    time: "",
    timeEpoch: 0,
    authorizer: { jwt: { claims: {}, scopes: [] } },
  },
  isBase64Encoded: false,
});

describe("AWS API handler", () => {
  it("reports the multicloud health configuration", async () => {
    const response = await handler(event("GET /health") as never) as { statusCode: number; body: string };
    expect(response.statusCode).toBe(200);
    expect(JSON.parse(response.body)).toMatchObject({ status: "ok", platform: "aws", vision: "google-vertex-ai" });
  });

  it("rejects protected operations without a Firebase subject", async () => {
    const response = await handler(event("GET /v1/contacts") as never) as { statusCode: number; body: string };
    expect(response.statusCode).toBe(401);
  });
});
