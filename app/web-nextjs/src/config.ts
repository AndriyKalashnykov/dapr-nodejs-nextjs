const getEnv = () => {
  switch (process.env.NODE_ENV) {
    case "development":
      return "development";
    case "test":
      return "test";
    case "production":
      return "production";

    default:
      return "development";
  }
};
const dapr = {
  host: process.env.DAPR_HOST || "127.0.0.1",
  port: process.env.DAPR_PORT || "3500",
};
const env = getEnv();

// Lazy so `next build`'s static page-data collection doesn't need the value
// (the import chain pulls config.ts into the build graph). Validates on first
// sign/verify call instead — see app/web-nextjs/src/lib/session.ts.
const getJwtSecretKey = () => {
  const key = process.env.JWT_SECRET_KEY || "";
  if (!key) {
    throw new Error("Server configuration error, missing JWT signing key.");
  }
  return key;
};

const cookie = {
  name: process.env.COOKIE_NAME || "session",
  maxAge: process.env.COOKIE_MAX_AGE
    ? Number.parseInt(process.env.COOKIE_MAX_AGE)
    : 60 * 60 * 24 * 7, // 7 days
  httpOnly: process.env.COOKIE_HTTP_ONLY === "true",
  secure: process.env.COOKIE_SECURE === "true",
  sameSite: process.env.COOKIE_SAME_SITE || "lax",
};

export { dapr, env, cookie, getJwtSecretKey };
