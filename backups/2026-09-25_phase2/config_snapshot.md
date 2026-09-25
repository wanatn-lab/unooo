# Phase 2 config snapshot — 2026-09-25

No Supabase project settings changed in Phase 2 (same project as Phase 1:
`uno-game`, ref `asjxgsaxdngbqjzcxoxn`). What changed is the database
schema and functions, captured in `schema_snapshot.sql` next to this file
(taken from a local Postgres 16 instance with the Phase 1 + Phase 2
migrations applied — the closest available stand-in for the real project,
since this sandbox cannot reach `*.supabase.co` — see PROGRESS.md).

New default `games.config` values introduced this phase (per-game, so a
future admin UI could vary these per room without a code change):

```json
{
  "uno_call_window_seconds": 3,
  "uno_penalty_cards": 2,
  "must_challenge_draw4": false,
  "disconnect_timeout_seconds": 20
}
```

- `must_challenge_draw4` is present but not yet wired to any behavior —
  see PROGRESS.md "known issues" for what that means in practice.
- `disconnect_timeout_seconds` (20s) controls how long a silent player is
  given before their seat is handed to a bot. This is a reasonable
  starting default, not a tested-in-production value — worth revisiting
  once real players are on real networks.

## To restore

Run, in order, against a Supabase SQL editor (or `supabase db push`):

1. `backend/supabase/migrations/0001_phase1_room_system.sql`
2. `backend/supabase/migrations/0002_phase1_enable_realtime.sql`
3. `backend/supabase/migrations/0003_phase2_game_schema.sql`
4. `backend/supabase/migrations/0004_phase2_game_logic.sql`

(Same "run every migration file in order" instruction as the Phase 1
backup — nothing about that process changed.)
