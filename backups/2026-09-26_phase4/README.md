# Phase 4 in-progress backup — 2026-09-26

**This is not the Phase 4 closeout backup.** PROJECT.md requires a real
functional test and a push to the Git remote before a phase can be marked
closed, and neither has happened yet for Phase 4 (see PROGRESS.md for why).
This directory only backs up the one database change made so far, so it
isn't lost regardless of what happens with the frontend/push work.

## Database changes backed up

- `0010_phase4_hand_count.sql`: additive migration exposing `hand_count` on
  `game_player_public_state` (and the functions that build it). No table,
  RPC, or rule is removed or changed in meaning — this only adds a field so
  the table UI can show "N cards left" per opponent. Applied directly to
  the live Supabase project (`uno-game` / `asjxgsaxdngbqjzcxoxn`) and
  verified via `pg_type`/`pg_attribute` inspection and the security
  advisor (no new findings introduced).

Applied migration record in production: `phase4_hand_count`.

## Deployment configuration

`netlify.toml` is the same snapshot as Phase 3's — no changes.

## Outstanding before this phase can close

- Frontend code (Game Table UI) is written, committed locally on `main`
  (commits `1b8acf1`, `cd04978`), and reviewed, but **not pushed** — this
  session's GitHub connection doesn't have write access to
  `wanatn-lab/unooo`. An org admin needs to install the Claude GitHub App
  (https://github.com/apps/claude/installations/select_target) or
  reconnect GitHub in Claude.ai settings before the push (and Netlify's
  connected auto-deploy) can happen.
- No real 2-player browser test has been run yet, because the code isn't
  live anywhere: this sandbox cannot reach `*.supabase.co` directly (same
  restriction noted in Phase 3), and a direct-to-Netlify preview deploy
  from this sandbox was also refused by its network policy. The test needs
  to happen against a real deployment, which needs the push above first.

No secrets are stored in this backup.
