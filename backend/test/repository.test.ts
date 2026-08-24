import { describe, expect, it } from "vitest";

import { MemoryRepository } from "../src/repository.js";

describe("emergency data boundaries", () => {
  it("keeps account role immutable after registration", async () => {
    const repository = new MemoryRepository();
    const initial = await repository.ensureProfile("user-1", "blindUser", "Asha");
    const repeated = await repository.ensureProfile("user-1", "emergencyContact", "Changed");
    expect(initial.role).toBe("blindUser");
    expect(repeated.role).toBe("blindUser");
  });

  it("returns an idempotent alert for the same user and key", async () => {
    const repository = new MemoryRepository();
    await repository.saveAlert({
      id: "alert-1",
      type: "alert",
      blindUserId: "blind-1",
      status: "active",
      startedAt: new Date().toISOString(),
      idempotencyKey: "request-1",
    });
    const alert = await repository.alertByIdempotency("blind-1", "request-1");
    expect(alert?.id).toBe("alert-1");
    expect(await repository.alertByIdempotency("blind-2", "request-1")).toBeUndefined();
  });

  it("shows active alerts only to linked contacts", async () => {
    const repository = new MemoryRepository();
    await repository.saveLink({
      id: "link-1",
      type: "link",
      blindUserId: "blind-1",
      contactUserId: "contact-1",
      createdAt: new Date().toISOString(),
    });
    await repository.saveAlert({
      id: "alert-1",
      type: "alert",
      blindUserId: "blind-1",
      status: "active",
      startedAt: new Date().toISOString(),
      idempotencyKey: "request-1",
    });
    expect(await repository.activeAlertsForContact("contact-1")).toHaveLength(1);
    expect(await repository.activeAlertsForContact("stranger")).toHaveLength(0);
  });
});
