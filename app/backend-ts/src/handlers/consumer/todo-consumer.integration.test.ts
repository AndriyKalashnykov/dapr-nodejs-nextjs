import { buildTodos } from '@/lib/test/models/todo';
import { getServer } from '@/lib/test/vitest.integration.setup';
import type { Todo, TodoDb } from '@/types';
import { randomUUID } from 'crypto';
import type { Express } from 'express';
import request from 'supertest';
import { beforeAll, beforeEach, describe, expect, it } from 'vitest';

describe('Integration: Todo Consumer', () => {
  let todos: Array<{ todoDb: TodoDb; todo: Todo }>;
  let todo: Todo;
  let app: Express;

  beforeAll(async () => {
    const serverContext = await getServer();
    app = serverContext.server.app;
  });

  beforeEach(async () => {
    todos = buildTodos({ completed: false }, 2);
    todo = todos[0].todo;
  });

  describe('POST /consumer/todo', () => {
    it('returns a valid payload', async () => {
      const res = await request(app).post('/consumer/todo').send({ id: randomUUID(), data: todo });
      expect(res.body).toEqual({
        status: 'SUCCESS',
      });
      expect(res.status).toBe(200);
    });
    it('returns a DROP status from the queue when the message fails', async () => {
      const res = await request(app)
        .post('/consumer/todo')
        .send({ id: randomUUID(), data: { not_title: 'Create a new todo' } });
      expect(res.body).toEqual({
        status: 'DROP',
      });
      expect(res.status).toBe(200);
    });

    // Real Dapr deliveries arrive with a full CloudEvent envelope and
    // `Content-Type: application/cloudevents+json`. The flat `{id, data}` body
    // above tests the route + zod schema; this case exercises the JSON parser
    // branch in `server.ts` that sniffs `cloudevents+json` and re-parses.
    it('accepts a full CloudEvent envelope (application/cloudevents+json)', async () => {
      const cloudEvent = {
        specversion: '1.0',
        type: 'com.dapr.event.sent',
        source: 'integration-test',
        id: randomUUID(),
        datacontenttype: 'application/json',
        time: new Date().toISOString(),
        topic: 'todo-data',
        pubsubname: 'redis-pubsub',
        data: todo,
      };
      const res = await request(app)
        .post('/consumer/todo')
        .set('Content-Type', 'application/cloudevents+json')
        .send(cloudEvent);
      expect(res.status).toBe(200);
      expect(res.body).toEqual({ status: 'SUCCESS' });
    });
  });
});
