# Config snapshot — Phase 1 close (2026-09-25)

- Supabase organization: `reviewsuphanburi` (id `wstrzwldqopiemgqzuqn`)
- Supabase project: `uno-game` (ref `asjxgsaxdngbqjzcxoxn`), region `ap-southeast-1`
- Project URL: `https://asjxgsaxdngbqjzcxoxn.supabase.co`
- Anon/publishable key: stored in `frontend/js/config.js` (safe to expose —
  it's restricted by Row Level Security, not a secret)
- Max players per room at this phase: 8 (see `frontend/js/config.js` →
  `CONFIG.MAX_PLAYERS_PER_ROOM`)
- Vendored library: `@supabase/supabase-js` v2.117.1 (UMD build), copied into
  `frontend/vendor/supabase.js`

No `.env` file or secret credentials exist for this phase — the anon key is
the only credential the frontend uses, and it's meant to be public.
