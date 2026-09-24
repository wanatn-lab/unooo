// ---------------------------------------------------------------------------
// Reads the room code out of the current URL, if any.
// Shareable links look like  <site>/room/ABC123 . Static hosts need a
// rewrite rule to serve index.html for that path (see _redirects / 404.html
// in this folder, and the "Deploying" section in the root README) — once
// that's in place, this function is all a page needs to find the code.
// A plain ?code=ABC123 query string also works, as a fallback that needs
// no hosting configuration at all.
// ---------------------------------------------------------------------------
export function getRoomCodeFromUrl() {
  const pathMatch = window.location.pathname.match(/\/room\/([A-Z0-9]{6})/i);
  if (pathMatch) return pathMatch[1].toUpperCase();

  const queryCode = new URLSearchParams(window.location.search).get("code");
  if (queryCode) return queryCode.toUpperCase();

  return null;
}
