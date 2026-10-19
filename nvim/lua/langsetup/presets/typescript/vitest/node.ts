// Vitest for Node code: tests next to the code or under tests/, coverage with v8
// target: vitest.config.ts
import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    include: ["src/**/*.{test,spec}.ts", "tests/**/*.{test,spec}.ts"],
    environment: "node",
    coverage: { provider: "v8", reporter: ["text", "html"] },
  },
});
