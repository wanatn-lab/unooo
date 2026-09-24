// ---------------------------------------------------------------------------
// Remembers "who am I in this room" in sessionStorage, so refreshing the
// lobby page (or clicking the shared link again on the same tab) doesn't
// make the player join a second time as a duplicate entry.
// sessionStorage is per-tab, which is what we want: opening the link in a
// second tab/browser correctly joins as a separate player.
// ---------------------------------------------------------------------------
const KEY = "uno_session";

export function saveSession({ roomId, code, playerId, name }) {
  sessionStorage.setItem(KEY, JSON.stringify({ roomId, code, playerId, name }));
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
}
