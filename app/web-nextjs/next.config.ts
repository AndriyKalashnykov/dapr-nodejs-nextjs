import path from "node:path";
import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  output: "standalone",
  // pnpm monorepo: trace deps from workspace root so hoisted node_modules end
  // up in .next/standalone (otherwise the runtime image's `next` symlink
  // dangles).
  outputFileTracingRoot: path.join(__dirname, "../../"),
};

export default nextConfig;
