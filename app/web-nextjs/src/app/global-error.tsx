"use client";

// Next.js App Router global error boundary. Without a user-defined
// `global-error.tsx`, Next.js synthesizes an internal `/_global-error` route
// whose static prerender crashes on `useContext` null in the 16.x line —
// see upstream issue vercel/next.js#87719 (recurring regression across
// 16.0.3, 16.0.8, 16.1.1, 16.2.x). Providing our own file bypasses the
// synthesis and is best practice for production error UX anyway.

export default function GlobalError({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  return (
    <html lang="en">
      <body>
        <h1>Something went wrong</h1>
        {error.digest && <p>Error digest: {error.digest}</p>}
        <button type="button" onClick={() => reset()}>
          Try again
        </button>
      </body>
    </html>
  );
}
