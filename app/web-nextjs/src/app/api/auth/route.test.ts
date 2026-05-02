import type { NextRequest } from "next/server";
import { beforeEach, describe, expect, it, vi } from "vitest";

const createSession = vi.fn().mockResolvedValue(undefined);

vi.mock("@/lib/session", () => ({ createSession }));

const envState = vi.hoisted(() => ({ env: "development" }));
vi.mock("@/config", () => ({
  get env() {
    return envState.env;
  },
}));

const { GET, POST } = await import("./route");

const buildRequest = (body?: unknown): NextRequest =>
  ({
    json: async () => body,
  }) as unknown as NextRequest;

describe("Next.js API route /api/auth", () => {
  beforeEach(() => {
    createSession.mockClear();
    envState.env = "development";
  });

  describe("GET (dev-only convenience)", () => {
    it("creates a session for the canonical dev user when env=development", async () => {
      const res = await GET(buildRequest());
      expect(createSession).toHaveBeenCalledWith("a1b2c3");
      expect(res.status).toBe(200);
      await expect(res.json()).resolves.toEqual({
        message: "Session created for user.",
      });
    });

    it("returns the development-only message without creating a session when env!=development", async () => {
      envState.env = "production";
      const res = await GET(buildRequest());
      expect(createSession).not.toHaveBeenCalled();
      await expect(res.json()).resolves.toEqual({
        message: "This endpoint is only available in development mode.",
      });
    });
  });

  describe("POST (auth callback)", () => {
    it("creates a session for the userId in the request body", async () => {
      const res = await POST(buildRequest({ userId: "caller-supplied-id" }));
      expect(createSession).toHaveBeenCalledWith("caller-supplied-id");
      expect(res.status).toBe(200);
      await expect(res.json()).resolves.toEqual({
        message: "Session created for user.",
      });
    });
  });
});
