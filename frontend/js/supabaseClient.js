// ---------------------------------------------------------------------------
// One shared Supabase client for the whole app.
// The library itself is vendored at vendor/supabase.js (loaded via a plain
// <script> tag in index.html, before this module runs) instead of pulled
// from a CDN — no build step / npm install needed, and no runtime
// dependency on a third-party CDN being reachable.
// ---------------------------------------------------------------------------
import { CONFIG } from "./config.js";

export const supabase = window.supabase.createClient(CONFIG.SUPABASE_URL, CONFIG.SUPABASE_ANON_KEY);
