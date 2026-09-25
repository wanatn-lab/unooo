// ---------------------------------------------------------------------------
// Remembers this tab's seat and its unguessable bearer capability token.
// sessionStorage keeps a new tab/browser as a separate room participant.
// ---------------------------------------------------------------------------
const KEY = "uno_session";

export function saveSession({ roomId, code, playerId, name, accessToken }) {
  sessionStorage.setItem(KEY, JSON.stringify({ roomId, code, playerId, name, accessToken }));
  sessionStorage.removeItem("uno_pending_access_token");
}

export function getSession() {
  try {
    return JSON.parse(sessionStorage.getItem(KEY));
  } catch {
    return null;
  }
}

export function clearSession() {
  sessionStorage.removeItem(KEY);
  sessionStorage.removeItem("uno_pending_access_token");
}