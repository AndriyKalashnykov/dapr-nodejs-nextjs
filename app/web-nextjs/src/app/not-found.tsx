// Next.js App Router `not-found` UI. Without a user-defined `not-found.tsx`,
// Next.js synthesizes an internal `/_not-found` route whose static prerender
// crashes with the same null-context bug that hits `/_global-error`
// (vercel/next.js#87719 family). Defining our own file bypasses the synthesis.

export default function NotFound() {
  return (
    <div>
      <h1>404 — Not Found</h1>
      <p>The page you requested does not exist.</p>
    </div>
  );
}
