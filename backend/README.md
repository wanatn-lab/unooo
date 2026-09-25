# Backend (Supabase)

This project has no custom server for Phase 1. "Backend logic" is entirely
Supabase: a Postgres database, two RPC functions, and Realtime.

## Project

- Supabase project: `uno-game` (ref `asjxgsaxdngbqjzcxoxn`), org `reviewsuphanburi`
- URL and anon key are in `frontend/js/config.js` (safe to expose — see the
  comment there on why).

## Schema

See `supabase/migrations/` — run these in order in the Supabase SQL editor
(or `supabase db push`) to rebuild the database from scratch.

- **rooms** — `id, code (unique), status, max_players, created_at`
- **players** — `id, room_id, name, is_host, joined_at`
- **create_room(host_name, max_players)** — generates a unique 6-character
  code and adds the host as the first player, atomically.
- **join_room(code, name)** — checks the room exists and isn't full, then
  adds the player, atomically. This is the *only* way to add a player;
  direct `insert`s into `players` are blocked by Row Level Security so the
  8-player cap can't be bypassed from the client.
- Realtime is enabled on `rooms` and `players` so the frontend can subscribe
  to player join/leave events live.

## Why RPC functions instead of plain inserts?

Two clients could otherwise create a room with the same code at the same
instant, or two players could join the last free seat in a full room at the
same instant. Both checks (unique code, room not full) are done inside a
single atomic database function instead of "check on the client, then
insert" — a much smaller window for anyone to race.

## Phase 2: game logic

Still no custom server. The full UNO rules engine (dealing, move
validation, special cards, win condition, the UNO-call rule, and bot
takeover) lives in `supabase/migrations/0004_phase2_game_logic.sql` as
Postgres functions, on top of the schema in
`supabase/migrations/0003_phase2_game_schema.sql` (`games`,
`game_players`). The frontend calls these the same way it calls
`create_room`/`join_room` — see `frontend/js/gameApi.js`.

Key functions: `start_game`, `play_card`, `draw_card`, `pass_turn`,
`call_uno`, `catch_uno_failure`, `heartbeat`. All of them (a) re-check
game/turn state server-side rather than trusting the client, and (b)
raise a specific error code on anything invalid instead of silently doing
nothing — `frontend/js/gameApi.js` translates each code into a plain-
English message.

There is no background job/cron in this stack. Bot takeover is instead
piggybacked on ordinary traffic: every `heartbeat()` call (which the
frontend should call every few seconds while a game screen is open) also
sweeps for players who've gone quiet past `disconnect_timeout_seconds`
and, if it's currently their turn, plays consecutive bot turns until
control lands back on a human or the game ends. A player reconnecting is
just them calling `heartbeat()` again — this instantly clears their
bot flag and hands their seat back, hand untouched.

### Testing this phase

This sandbox cannot reach `*.supabase.co` (same network restriction noted
in the Phase 1 PROGRESS.md), so the rules engine was tested against a
disposable local Postgres 16 instance instead, running the exact same
migration files. To repeat this:

```
createdb uno_test
psql uno_test -v ON_ERROR_STOP=1 \
  -f supabase/migrations/0001_phase1_room_system.sql \
  -f supabase/migrations/0003_phase2_game_schema.sql \
  -f supabase/migrations/0004_phase2_game_logic.sql \
  -f supabase/tests/phase2_game_logic.test.sql
```

A clean run ends with `ALL PHASE 2 TESTS PASSED` and exit code 0. This
proves the rules engine is correct against real Postgres; it does NOT
prove the live Supabase project has these functions deployed yet, or that
Realtime picks up game state changes the way it already does for the
lobby (that wiring is Phase 3's job) — see PROGRESS.md for exactly what
is and isn't verified.
