import {
  acquireSessionCookie,
  baseUrl,
  isStackReachable,
} from "@/lib/test/integration";
import { beforeAll, describe, expect, it } from "vitest";

// Compose-attached integration test for the Next.js JSON API route at
// `/api/todos`. Exercises the full chain that unit tests can't cover with
// mocks:
//
//   browser → Next.js route handler → verifySession() (real cookie)
//          → BackendTs.getAll()       (real DaprClient)
//          → Dapr sidecar             (web-nextjs sidecar)
//          → backend-ts Dapr sidecar  (real service invocation)
//          → backend-ts Express       (real Express + auth middleware)
//          → Postgres                 (real DB)
//
// SKIP guard: if the running stack isn't reachable, the suite skips so a
// developer running `make ci`-style targets without `make up -d` doesn't get
// a false failure. Run `make web-nextjs-integration` to exercise it for real.

describe("Integration: GET /api/todos (Next.js → Dapr → backend → Postgres)", () => {
  let stackUp = false;
  let cookie = "";

  beforeAll(async () => {
    stackUp = await isStackReachable();
    if (!stackUp) {
      console.warn(
        `[web-nextjs integration] skipping — stack not reachable at ${baseUrl()}; run \`make up -d\``,
      );
      return;
    }
    cookie = await acquireSessionCookie();
  });

  it("returns the backend payload as JSON with Cache-Control no-store", async () => {
    if (!stackUp) return;
    const res = await fetch(`${baseUrl()}/api/todos`, {
      headers: { Cookie: cookie },
      redirect: "manual",
    });
    expect(res.status).toBe(200);
    expect(res.headers.get("cache-control")).toBe("no-store");
    const body = (await res.json()) as {
      data?: { items?: unknown[] };
      payload?: unknown;
    };
    // The backend wraps the list in `{ data: { items: [...], ... } }` per the
    // SDK's Api.PaginatedQueryResults shape. The Next.js route forwards that
    // envelope unchanged.
    expect(body).toBeTypeOf("object");
    expect(Array.isArray(body.data?.items)).toBe(true);
  });

  it("redirects unauthenticated requests away from the protected route", async () => {
    if (!stackUp) return;
    const res = await fetch(`${baseUrl()}/api/todos`, { redirect: "manual" });
    // verifySession() calls redirect('/') when no session cookie is present.
    // Next.js converts that to a 307 (or 302 on older versions) with Location
    // header. Don't assert exact status — just that we didn't get the
    // protected payload.
    expect(res.status).not.toBe(200);
  });
});
