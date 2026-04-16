import { expect, test } from '@playwright/test';

// Smoke test of the Next.js SSR frontend against a running compose stack.
// Assumes `make up -d` or `make e2e` has brought up the stack.
test.describe('Next.js SSR frontend', () => {
  test('landing page loads', async ({ page }) => {
    const resp = await page.goto('/');
    expect(resp?.ok()).toBeTruthy();
    await expect(page).toHaveURL(/\//);
  });

  test('dev-auth session endpoint issues a session', async ({ request }) => {
    const resp = await request.get('/api/auth');
    expect(resp.status()).toBe(200);
    const body = await resp.json();
    expect(body.message).toContain('Session');
  });

  test('todos page renders after auth', async ({ page }) => {
    // Hit the dev-auth endpoint to set a session cookie, then load /todos.
    await page.request.get('/api/auth');
    const resp = await page.goto('/todos');
    expect(resp?.status()).toBeLessThan(500);
  });
});
