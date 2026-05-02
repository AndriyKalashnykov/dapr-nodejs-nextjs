import { defineConfig } from "vitest/config";

// Compose-attached integration tests for web-nextjs. Tests fetch against the
// running Next.js dev server at NEXTJS_URL (defaults to http://localhost:3000)
// — assumes the full compose stack is already up via `make up -d`.
//
// Pattern: option B from the test-coverage gap analysis. Each test acquires
// a dev session via GET /api/auth, then exercises the protected JSON routes
// end-to-end through Next.js → Dapr invoker → backend-ts → Postgres. If the
// stack isn't reachable the suite skips cleanly so `make ci-style` invocations
// don't false-fail.
//
// Run via `make web-nextjs-integration` (which runs `make up -d` first if the
// stack isn't up, or just runs the tests if it is).
export default defineConfig({
  resolve: { tsconfigPaths: true },
  test: {
    globals: true,
    environment: "node",
    include: ["src/**/*.integration.test.{ts,tsx}"],
    exclude: ["**/node_modules", "**/.next"],
    // HTTP round-trips through the compose stack are slower than unit tests
    // — give them generous budgets, especially for the first probe which may
    // wait for Next.js dev-server JIT compilation.
    testTimeout: 30_000,
    hookTimeout: 60_000,
    // Tests share session cookies via a top-level fetch; serialize to keep
    // the cookie jar deterministic.
    sequence: { concurrent: false },
  },
});
