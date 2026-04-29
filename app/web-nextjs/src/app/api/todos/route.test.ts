import type { NextRequest } from 'next/server';
import { beforeEach, describe, expect, it, vi } from 'vitest';

const getAll = vi.fn();

vi.mock('@/services/todo', () => ({ getAll }));

const { GET } = await import('./route');

const buildRequest = (): NextRequest => ({}) as NextRequest;

describe('Next.js API route /api/todos', () => {
  beforeEach(() => {
    getAll.mockReset();
  });

  it('GET returns the backend payload as JSON', async () => {
    const payload = { items: [{ id: 'abc', title: 'sample' }] };
    getAll.mockResolvedValue(payload);

    const res = await GET(buildRequest());

    expect(getAll).toHaveBeenCalledOnce();
    expect(res.status).toBe(200);
    await expect(res.json()).resolves.toEqual(payload);
  });

  it('GET sets Cache-Control: no-store so the SSR response is never cached', async () => {
    getAll.mockResolvedValue({ items: [] });

    const res = await GET(buildRequest());

    expect(res.headers.get('Cache-Control')).toBe('no-store');
  });

  it('GET propagates errors from the backend service', async () => {
    const err = new Error('backend down');
    getAll.mockRejectedValue(err);

    await expect(GET(buildRequest())).rejects.toThrow('backend down');
  });
});
