import { expect, test } from "@playwright/test";
import jwt from "jsonwebtoken";

// Smoke test of the Next.js SSR frontend against a running compose stack.
// Assumes `make up -d` or `make e2e` has brought up the stack.

const BACKEND_PORT = process.env.SERVER_PORT ?? "3001";
const BACKEND_BASE = `http://localhost:${BACKEND_PORT}`;
const JWT_SECRET = process.env.JWT_SECRET_KEY ?? "secret";

function backendToken(): string {
  return jwt.sign({ sub: "e2e-browser-user" }, JWT_SECRET);
}

test.describe("Next.js SSR frontend", () => {
  test("landing page loads", async ({ page }) => {
    const resp = await page.goto("/");
    expect(resp?.ok()).toBeTruthy();
    await expect(page).toHaveURL(/\//);
  });

  test("dev-auth session endpoint issues a session", async ({ request }) => {
    const resp = await request.get("/api/auth");
    expect(resp.status()).toBe(200);
    const body = await resp.json();
    expect(body.message).toContain("Session");
  });

  test("todos page renders after auth", async ({ page }) => {
    // Hit the dev-auth endpoint to set a session cookie, then load /todos.
    await page.request.get("/api/auth");
    const resp = await page.goto("/todos");
    expect(resp?.status()).toBeLessThan(500);
  });

  // Full round-trip: seed a uniquely-titled todo via the backend's direct
  // HTTP, then load the SSR /todos page. The page renders by calling
  // `getAll()` which goes Next.js → Dapr invoker → Dapr sidecar →
  // backend-ts → Postgres. If the seeded title appears in the rendered
  // DOM, every link in that chain is working.
  test("SSR /todos renders a backend-seeded todo (Next.js → Dapr → backend → Postgres)", async ({
    page,
    request,
  }) => {
    const uniqueTitle = `e2e-browser-${Date.now()}`;
    const token = backendToken();

    // 1. Seed via direct backend (not via Dapr — we want to verify the
    //    SSR-side Dapr invocation independently).
    const create = await request.post(`${BACKEND_BASE}/api/v1/todos`, {
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      data: { title: uniqueTitle },
    });
    expect(create.status(), "seed POST returned non-2xx").toBe(200);
    const { data: seeded } = await create.json();
    expect(seeded?.id, "seed response missing id").toBeTruthy();

    try {
      // 2. Set a session cookie and SSR-render the page.
      await page.request.get("/api/auth");
      const resp = await page.goto("/todos");
      expect(resp?.ok(), `SSR /todos returned ${resp?.status()}`).toBeTruthy();

      // 3. The seeded title must appear in the rendered DOM.
      await expect(page.getByText(uniqueTitle)).toBeVisible();
    } finally {
      // 4. Clean up — best-effort delete via direct backend.
      await request
        .delete(`${BACKEND_BASE}/api/v1/todos/${seeded.id}`, {
          headers: { Authorization: `Bearer ${token}` },
        })
        .catch(() => undefined);
    }
  });
});
