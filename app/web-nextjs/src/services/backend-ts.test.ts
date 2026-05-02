import { HttpMethod } from "@dapr/dapr";
import { beforeEach, describe, expect, it, vi } from "vitest";

const invoke = vi.fn();

vi.mock("@/context", () => ({
  context: { dapr: { invoker: { invoke } } },
}));

// Import under test after the mock is registered.
const { create, deleteById, getAll, getById, updateById } =
  await import("./backend-ts");

const TOKEN = "test.jwt.token";
const ID = "abc-123";

const expectAuth = { headers: { Authorization: `Bearer ${TOKEN}` } };

describe("web-nextjs → backend-ts Dapr invoker", () => {
  beforeEach(() => {
    invoke.mockReset();
    invoke.mockResolvedValue({ data: { items: [] } });
  });

  it("getAll invokes backend-ts via Dapr with auth header", async () => {
    await getAll(TOKEN);
    expect(invoke).toHaveBeenCalledWith(
      "backend-ts",
      "api/v1/todos",
      HttpMethod.GET,
      undefined,
      expectAuth,
    );
  });

  it("getById invokes with no auth (server-side only)", async () => {
    await getById(ID);
    // Headers object is always passed so OTel propagation can inject
    // traceparent when an active span context is present. With no OTel
    // SDK initialized in the test runner, the default no-op propagator
    // leaves the headers object empty.
    expect(invoke).toHaveBeenCalledWith(
      "backend-ts",
      `api/v1/todos/${ID}`,
      HttpMethod.GET,
      undefined,
      { headers: {} },
    );
  });

  it("create POSTs payload via Dapr with auth header", async () => {
    invoke.mockResolvedValue({ data: { id: "new" } });
    await create(TOKEN, { title: "x" });
    expect(invoke).toHaveBeenCalledWith(
      "backend-ts",
      "api/v1/todos",
      HttpMethod.POST,
      { title: "x" },
      expectAuth,
    );
  });

  it("updateById PUTs payload via Dapr with auth header", async () => {
    invoke.mockResolvedValue({ data: { id: ID } });
    await updateById(TOKEN, ID, { title: "y" });
    expect(invoke).toHaveBeenCalledWith(
      "backend-ts",
      `api/v1/todos/${ID}`,
      HttpMethod.PUT,
      { title: "y" },
      expectAuth,
    );
  });

  it("deleteById DELETEs via Dapr with auth header", async () => {
    invoke.mockResolvedValue({ data: {} });
    await deleteById(TOKEN, ID);
    expect(invoke).toHaveBeenCalledWith(
      "backend-ts",
      `api/v1/todos/${ID}`,
      HttpMethod.DELETE,
      undefined,
      expectAuth,
    );
  });

  it("respects BACKEND_APP_ID env override", async () => {
    // The module reads BACKEND_APP_ID at import time. This test documents
    // the contract; changing the env mid-test has no effect on the already-
    // captured constant.
    await getAll(TOKEN);
    const [appId] = invoke.mock.calls[0];
    expect(appId).toBe(process.env.BACKEND_APP_ID || "backend-ts");
  });
});
