import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    include: ["test/**/*.test.ts"],
    environment: "node",
    // Azure SDK imports are expensive with a cold cache alongside Android builds.
    maxWorkers: 1,
    hookTimeout: 30000,
  },
});
