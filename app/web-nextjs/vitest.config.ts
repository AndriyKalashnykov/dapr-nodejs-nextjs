import { defineConfig } from 'vitest/config';

export default defineConfig({
  resolve: { tsconfigPaths: true },
  test: {
    globals: true,
    environment: 'node',
    include: ['src/**/*.test.{ts,tsx}'],
    exclude: ['**/node_modules', '**/.next'],
    coverage: {
      include: ['src/**/*.{ts,tsx}'],
      exclude: ['**/*.d.ts', '**/layout.tsx', '**/page.tsx'],
    },
  },
});
