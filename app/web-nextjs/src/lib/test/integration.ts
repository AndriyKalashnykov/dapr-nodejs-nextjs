// Compose-attached integration test helpers. Each helper assumes the full
// docker-compose stack is already running (`make up -d`).
//
// `probeStackOrSkip()` is the gate: returns a function that callers invoke at
// the start of each test/suite to short-circuit when the Next.js SSR
// frontend isn't reachable, so the suite passes (skipped) rather than fails
// when run outside an integration context.

const NEXTJS_URL =
  process.env.NEXTJS_URL ??
  `http://localhost:${process.env.NEXTJS_PORT ?? "3000"}`;
const COOKIE_NAME = process.env.COOKIE_NAME ?? "session";

export const baseUrl = (): string => NEXTJS_URL;

export const isStackReachable = async (timeoutMs = 2_000): Promise<boolean> => {
  try {
    const ac = new AbortController();
    const t = setTimeout(() => ac.abort(), timeoutMs);
    const res = await fetch(NEXTJS_URL, { signal: ac.signal });
    clearTimeout(t);
    return res.status >= 200 && res.status < 600;
  } catch {
    return false;
  }
};

/**
 * Hits the dev `/api/auth` endpoint to mint a session cookie, then returns
 * the raw cookie header string ready to attach to subsequent requests.
 *
 * The dev endpoint creates a session for user `a1b2c3` (see route source).
 * Throws if the env isn't `development` (the route returns a no-op JSON in
 * other envs, with no Set-Cookie header), or if the cookie is missing for
 * any other reason.
 */
export const acquireSessionCookie = async (): Promise<string> => {
  const res = await fetch(`${NEXTJS_URL}/api/auth`, { redirect: "manual" });
  if (res.status !== 200) {
    throw new Error(
      `/api/auth returned ${res.status}; stack is up but dev session endpoint refused`,
    );
  }
  const setCookie = res.headers.get("set-cookie");
  if (!setCookie) {
    throw new Error(
      `/api/auth returned 200 but no Set-Cookie header — Next.js NODE_ENV is not 'development'?`,
    );
  }
  // Take the first cookie matching our name; `set-cookie` may contain multiple
  // comma-separated cookies. The runtime fetch implementation collapses them.
  const re = new RegExp(`${COOKIE_NAME}=[^;]+`);
  const match = setCookie.match(re);
  if (!match) {
    throw new Error(
      `Set-Cookie header missing '${COOKIE_NAME}' cookie: ${setCookie}`,
    );
  }
  return match[0];
};
