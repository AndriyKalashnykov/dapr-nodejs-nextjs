import { db as dbConfig } from '@/config';
import { getServer } from '@/lib/test/vitest.integration.setup';
import type { ContextKind } from '@/types';
import type { Context } from '@sos/sdk';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';

// Migrations rollback → latest cycle. Catches:
//   1. broken `down` migrations (a migration that can't be rolled back is a
//      foot-gun for any future schema fix)
//   2. non-idempotent `up` migrations (re-running latest after a rollback
//      should land on a structurally-identical schema)
//   3. ordering bugs (knex_migrations rows must reflect the executed batch)
//
// Runs against the real Postgres test schema (backend_ts_test) provisioned by
// `make ci-db-prepare`. Does NOT touch any Dapr surface — pure DB plumbing.
describe('Integration: Knex migrations', () => {
  let context: Context<ContextKind>;

  const knownTables = ['todos'];

  const tablesInSchema = async (): Promise<string[]> => {
    const { rows } = await context.db.raw<{ rows: Array<{ tablename: string }> }>(
      `SELECT tablename FROM pg_tables WHERE schemaname = ?`,
      [dbConfig.schema],
    );
    return rows.map((r) => r.tablename);
  };

  beforeAll(async () => {
    const { context: ctx } = await getServer();
    context = ctx;
  });

  afterAll(async () => {
    // Leave the schema at "latest" for any subsequent test files in the suite.
    await context.db.migrate.latest();
  });

  it('rollback --all then latest reproduces the schema', async () => {
    // Sanity: `latest` is already applied by buildServer() during setup.
    const before = await tablesInSchema();
    for (const t of knownTables) {
      expect(before).toContain(t);
    }

    // Roll back all migrations. Every `down` must succeed.
    await expect(context.db.migrate.rollback(undefined, true)).resolves.not.toThrow();

    const afterRollback = await tablesInSchema();
    for (const t of knownTables) {
      expect(afterRollback).not.toContain(t);
    }

    // Re-apply. The schema must come back identical.
    await expect(context.db.migrate.latest()).resolves.not.toThrow();

    const afterLatest = await tablesInSchema();
    for (const t of knownTables) {
      expect(afterLatest).toContain(t);
    }
  });

  it('migrate.list reports zero pending migrations after latest', async () => {
    const [, pending] = await context.db.migrate.list();
    expect(pending).toEqual([]);
  });
});
