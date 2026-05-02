import { defineConfig } from "vitest/config";

export default defineConfig({
  resolve: { tsconfigPaths: true },
  test: {
    globals: true,
    environment: "node",
    include: ["src/**/*.test.{ts,tsx}"],
    // Exclude *.integration.test.* — those run via vitest.integration.config.ts
    // against a running compose stack (see `make web-nextjs-integration`).
    exclude: [
      "**/node_modules",
      "**/.next",
      "src/**/*.integration.test.{ts,tsx}",
    ],
    coverage: {
      include: ["src/**/*.{ts,tsx}"],
      exclude: ["**/*.d.ts", "**/layout.tsx", "**/page.tsx"],
    },
  },
});
