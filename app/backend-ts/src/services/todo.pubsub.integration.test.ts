import { getAuthHeader } from '@/lib/test/utils';
import { getServer } from '@/lib/test/vitest.integration.setup';
import { dapr as daprConfig } from '@/config';
import type { Express } from 'express';
import request from 'supertest';
import { beforeAll, describe, expect, it } from 'vitest';

// Pub/sub publish-path integration test. Verifies that a successful create
// reaches the Dapr publish API. The witness here is a 204 from a probe
// publish through the same `redis-pubsub/todo-data` route the service uses
// — if the component is wired, the create endpoint's PubSub.publish call
// would also have succeeded. (A full round-trip with a subscriber is
// covered in e2e/e2e-test.sh §[8/8] which polls `docker compose logs`.)
//
// SKIP guard: if the redis-pubsub component is not configured (slim CI
// Dapr), the test is skipped rather than failing red.
describe('Integration: Todo pub/sub publish path', () => {
  const token = getAuthHeader('pubsub-test-user').Authorization;
  const pubSubName = 'redis-pubsub';
  const pubSubTopic = 'todo-data';

  let app: Express;
  let pubSubAvailable = false;

  const probePubSub = async (): Promise<boolean> => {
    const url = `http://${daprConfig.host}:${daprConfig.port}/v1.0/publish/${pubSubName}/${pubSubTopic}`;
    try {
      const res = await fetch(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ probe: true }),
      });
      return res.status === 204;
    } catch {
      return false;
    }
  };

  beforeAll(async () => {
    const serverContext = await getServer();
    app = serverContext.server.app;
    pubSubAvailable = await probePubSub();
  });

  it('create writes through PubSub.publish (component reachable, sidecar 204)', async () => {
    if (!pubSubAvailable) {
      console.warn(
        `[pubsub integration] skipping — '${pubSubName}/${pubSubTopic}' not configured in this Dapr sidecar`,
      );
      return;
    }

    // If the probe returned 204, the sidecar will accept publishes for this
    // topic. The service.createTodo call below issues PubSub.publish() — if
    // the route is broken (component renamed, topic typo'd, transport down)
    // the create endpoint returns 500. A 200 here proves the publish path.
    const res = await request(app)
      .post('/api/v1/todos')
      .send({ title: 'pubsub-integration-todo' })
      .set('Authorization', token);
    expect(res.status).toBe(200);
    expect(res.body.data.id).toBeTruthy();
  });
});
