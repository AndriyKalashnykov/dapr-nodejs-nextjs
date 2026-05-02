import { createTodos } from '@/lib/test/models/todo';
import { getAuthHeader } from '@/lib/test/utils';
import { getServer } from '@/lib/test/vitest.integration.setup';
import type { ContextKind, Todo, TodoDb } from '@/types';
import type { Context } from '@sos/sdk';
import { randomUUID } from 'crypto';
import type { Express } from 'express';
import request from 'supertest';
import { beforeAll, beforeEach, describe, expect, it } from 'vitest';

describe('Integration: Todo API', () => {
  const token = getAuthHeader('test-user').Authorization;
  let todos: Array<{ todoDb: TodoDb; todo: Todo }>;
  let todo: Todo;
  let context: Context<ContextKind>;
  let app: Express;

  beforeAll(async () => {
    const serverContext = await getServer();
    app = serverContext.server.app;
    context = serverContext.context;
  });

  beforeEach(async () => {
    todos = await createTodos(context, { completed: false }, 2);
    todo = todos[0].todo;
  });

  describe('GET /api/v1/todos', () => {
    it('returns a valid payload', async () => {
      const res = await request(app).get('/api/v1/todos').set('Authorization', token);
      expect(res.body).toEqual({
        apiVersion: '1.0',
        id: expect.any(String),
        data: {
          currentItemCount: 2,
          items: expect.arrayContaining([
            expect.objectContaining({
              id: todo.id,
            }),
          ]),
          itemsPerPage: 50,
          orderBy: 'created_at',
          orderDirection: 'desc',
          pageIndex: 1,
          totalItems: 2,
          totalPages: 1,
        },
      });
      expect(res.status).toBe(200);
    });
    it('returns a paginated payload', async () => {
      const res = await request(app)
        .get('/api/v1/todos?pageSize=1&orderBy=title&orderDirection=asc')
        .set('Authorization', token);
      expect(res.body).toEqual({
        apiVersion: '1.0',
        id: expect.any(String),
        data: {
          currentItemCount: 1,
          items: expect.arrayContaining([
            expect.objectContaining({
              id: todo.id,
            }),
          ]),
          itemsPerPage: 1,
          orderBy: 'title',
          orderDirection: 'asc',
          pageIndex: 1,
          totalItems: 2,
          totalPages: 2,
        },
      });
      expect(res.status).toBe(200);
    });
  });

  describe('POST /api/v1/todos', () => {
    it('returns a valid payload', async () => {
      const res = await request(app)
        .post('/api/v1/todos')
        .send({ title: 'Create a new todo' })
        .set('Authorization', token);
      expect(res.body).toEqual({
        apiVersion: '1.0',
        id: expect.any(String),
        data: {
          id: expect.any(String),
          title: 'Create a new todo',
          completed: false,
          createdAt: expect.any(String),
          kind: 'todo',
        },
      });
      expect(res.status).toBe(200);
    });
    it('returns a validation error', async () => {
      const res = await request(app)
        .post('/api/v1/todos')
        .send({ not_title: 'Create a new todo' })
        .set('Authorization', token);
      expect(res.body).toEqual({
        apiVersion: '1.0',
        id: expect.any(String),
        error: {
          code: 400,
          message: expect.stringContaining('title:'),
        },
      });
      expect(res.body.error.message).toEqual(expect.stringContaining('not_title'));
      expect(res.status).toBe(400);
    });
  });

  describe('PUT /api/v1/todos/{id}', () => {
    it('returns a valid payload', async () => {
      const res = await request(app)
        .put(`/api/v1/todos/${todo.id}`)
        .send({ title: 'Updated todo' })
        .set('Authorization', token);
      expect(res.body).toEqual({
        apiVersion: '1.0',
        id: expect.any(String),
        data: {
          id: todo.id,
          title: 'Updated todo',
          completed: false,
          createdAt: expect.any(String),
          updatedAt: expect.any(String),
          kind: 'todo',
        },
      });
      expect(res.status).toBe(200);
    });
    it('returns a not found error', async () => {
      const invalidId = randomUUID();
      const res = await request(app)
        .put(`/api/v1/todos/${invalidId}`)
        .send({ title: 'Updated todo' })
        .set('Authorization', token);
      expect(res.body).toEqual({
        apiVersion: '1.0',
        id: expect.any(String),
        error: {
          code: 404,
          message: `Todo ${invalidId} not found.`,
        },
      });
      expect(res.status).toBe(404);
    });
    it('returns a validation error', async () => {
      const res = await request(app)
        .put(`/api/v1/todos/${todo.id}`)
        .send({ not_title: 'Updated todo' })
        .set('Authorization', token);
      expect(res.body).toEqual({
        apiVersion: '1.0',
        id: expect.any(String),
        error: {
          code: 400,
          message: expect.stringContaining('title:'),
        },
      });
      expect(res.body.error.message).toEqual(expect.stringContaining('not_title'));
      expect(res.status).toBe(400);
    });
  });

  // PATCH is registered alongside PUT for updateTodoById (`methods: ['put','patch']`).
  // A regression that drops PATCH from the method array would otherwise be silent
  // because the unit suite only mocks the route, not the registered methods.
  describe('PATCH /api/v1/todos/{id}', () => {
    it('returns a valid payload (alias of PUT)', async () => {
      const res = await request(app)
        .patch(`/api/v1/todos/${todo.id}`)
        .send({ title: 'Patched todo' })
        .set('Authorization', token);
      expect(res.status).toBe(200);
      expect(res.body).toEqual({
        apiVersion: '1.0',
        id: expect.any(String),
        data: {
          id: todo.id,
          title: 'Patched todo',
          completed: false,
          createdAt: expect.any(String),
          updatedAt: expect.any(String),
          kind: 'todo',
        },
      });
    });
  });

  describe('DELETE /api/v1/todos/{id}', () => {
    it('returns a valid payload', async () => {
      const res = await request(app).delete(`/api/v1/todos/${todo.id}`).set('Authorization', token);
      expect(res.body).toEqual({
        apiVersion: '1.0',
        id: expect.any(String),
        data: {
          id: todo.id,
          title: 'Test Todo',
          completed: false,
          createdAt: expect.any(String),
          deletedAt: expect.any(String),
          kind: 'todo',
        },
      });
      expect(res.status).toBe(200);
    });
    it('returns a not found error', async () => {
      const invalidId = randomUUID();
      const res = await request(app)
        .delete(`/api/v1/todos/${invalidId}`)
        .set('Authorization', token);
      expect(res.body).toEqual({
        apiVersion: '1.0',
        id: expect.any(String),
        error: {
          code: 404,
          message: `Todo ${invalidId} not found.`,
        },
      });
      expect(res.status).toBe(404);
    });
  });

  describe('GET /api/v1/todos/{id}', () => {
    it('returns a valid payload', async () => {
      const res = await request(app).get(`/api/v1/todos/${todo.id}`).set('Authorization', token);
      expect(res.body).toEqual({
        apiVersion: '1.0',
        id: expect.any(String),
        data: {
          id: todo.id,
          title: 'Test Todo',
          completed: false,
          createdAt: expect.any(String),
          kind: 'todo',
        },
      });
      expect(res.status).toBe(200);
    });
    it('returns a not found error', async () => {
      const invalidId = randomUUID();
      const res = await request(app).get(`/api/v1/todos/${invalidId}`).set('Authorization', token);
      expect(res.body).toEqual({
        apiVersion: '1.0',
        id: expect.any(String),
        error: {
          code: 404,
          message: `Todo ${invalidId} not found.`,
        },
      });
      expect(res.status).toBe(404);
    });
  });

  // Pagination edge cases — the happy path is covered above; these check
  // boundary inputs that have historically been silent regression risks.
  describe('GET /api/v1/todos pagination edges', () => {
    it('returns 400 on pageSize=0 (validation rejects non-positive)', async () => {
      const res = await request(app).get('/api/v1/todos?pageSize=0').set('Authorization', token);
      expect(res.status).toBe(400);
    });
    it('returns 400 on negative pageSize', async () => {
      const res = await request(app).get('/api/v1/todos?pageSize=-1').set('Authorization', token);
      expect(res.status).toBe(400);
    });
    it('returns empty items array when pageIndex past end', async () => {
      const res = await request(app)
        .get('/api/v1/todos?pageSize=10&pageIndex=99')
        .set('Authorization', token);
      expect(res.status).toBe(200);
      expect(res.body.data.items).toEqual([]);
      expect(res.body.data.currentItemCount).toBe(0);
    });
  });

  // Soft-delete leaves the row in Postgres with `deleted_at IS NOT NULL`.
  // The 404-on-second-GET test above proves the SQL filter works; this
  // queries the row directly to confirm it's still present (audit trail).
  describe('soft-delete row remains in Postgres', () => {
    it('row exists with deleted_at set after DELETE', async () => {
      await request(app).delete(`/api/v1/todos/${todo.id}`).set('Authorization', token);
      const row = await context
        .db('todos')
        .where({ id: todo.id })
        .first<{ id: string; deleted_at: Date | null }>();
      expect(row).toBeTruthy();
      expect(row?.id).toBe(todo.id);
      expect(row?.deleted_at).toBeTruthy();
    });
  });

  // Concurrency: integration suite is `maxConcurrency: 1`, so this just
  // exercises two POSTs in flight from one fork to confirm IDs are distinct
  // and both rows land. Catches regressions in the transaction boundary or
  // primary-key generation.
  describe('concurrent create', () => {
    it('two POSTs in parallel produce distinct ids and both rows persist', async () => {
      const [a, b] = await Promise.all([
        request(app)
          .post('/api/v1/todos')
          .send({ title: 'concurrent-A' })
          .set('Authorization', token),
        request(app)
          .post('/api/v1/todos')
          .send({ title: 'concurrent-B' })
          .set('Authorization', token),
      ]);
      expect(a.status).toBe(200);
      expect(b.status).toBe(200);
      expect(a.body.data.id).not.toBe(b.body.data.id);
      const rows = await context
        .db('todos')
        .whereIn('title', ['concurrent-A', 'concurrent-B'])
        .select<Array<{ id: string; title: string }>>('id', 'title');
      expect(rows).toHaveLength(2);
    });
  });
});
