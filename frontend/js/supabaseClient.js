// ---------------------------------------------------------------------------
// Shared Supabase client and per-seat capability tokens.
// Anonymous Auth is disabled on this project, so each tab creates a random
// 256-bit room token. The database stores only its SHA-256 digest.
// ---------------------------------------------------------------------------
import { CONFIG } from "./config.js";

export const supabase = window.supabase.createClient(CONFIG.SUPABASE_URL, CONFIG.SUPABASE_ANON_KEY);

const PENDING_TOKEN_KEY = "uno_pending_access_token";

export function getOrCreateAccessToken() {
  let token = sessionStorage.getItem(PENDING_TOKEN_KEY);
  if (!token) {
    const bytes = crypto.getRandomValues(new Uint8Array(32));
    token = Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("");
    sessionStorage.setItem(PENDING_TOKEN_KEY, token);
  }
  return token;
}

export function getAccessToken() {
  try {
    const session = JSON.parse(sessionStorage.getItem("uno_session"));
    if (session?.accessToken) return session.accessToken;
  } catch {}
  return getOrCreateAccessToken();
}

export function clearPendingAccessToken() {
  sessionStorage.removeItem(PENDING_TOKEN_KEY);
}