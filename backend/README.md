# Backend (Supabase)

This project has no custom server for Phase 1. "Backend logic" is entirely
Supabase: a Postgres database, two RPC functions, and Realtime.

## Project

- Supabase project: `uno-game` (ref `asjxgsaxdngbqjzcxoxn`), org `reviewsuphanburi`
- URL and anon key are in `frontend/js/config.js` (safe to expose — see the
  comment there on why).

## Schema

See schema history in supabase/migrations/. Migrations 0001–0009 are deployed; migration 0005 uses per-seat capability tokens instead of Supabase Auth, migration 0006 adds protected game discovery, and migration 0009 records the transactional production smoke test.

- **rooms** — `id, code (unique), status, max_players, created_at`
- **players** — `id, room_id, name, is_host, joined_at`
- **create_room(host_name, max_players)** — generates a unique 6-character
  code and adds the host as the first player, atomically.
- **join_room(code, name)** — checks the room exists and isn't full, then
  adds the player, atomically. This is the *only* way to add a player;
  direct `insert`s into `players` are blocked by Row Level Security so the
  8-player cap can't be bypassed from the client.
- Realtime publication remains enabled, but the frontend polls a token-protected
  roster RPC so player rows are not exposed through changefeeds.

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

The Phase 2 rules suite was tested against a disposable local Postgres 16
instance using the same migration files. To repeat the offline suite:

```
createdb uno_test
psql uno_test -v ON_ERROR_STOP=1 \
  -f supabase/migrations/0001_phase1_room_system.sql \
  -f supabase/migrations/0003_phase2_game_schema.sql \
  -f supabase/migrations/0004_phase2_game_logic.sql \
  -f supabase/tests/phase2_game_logic.test.sql
```

A clean run ends with `ALL PHASE 2 TESTS PASSED` and exit code 0. This tests
the rules against real Postgres. Phase 2 migrations are also deployed on the live
Supabase project (Postgres 17.6). Phase 3 then verified protected two-seat game-state synchronization in production; the card-table UI remains a later phase.

## Phase 3: protected state sync

Migration supabase/migrations/0005_phase3_capability_security.sql does not
depend on Supabase Auth. Each browser tab creates a cryptographically random
256-bit seat token; the database stores only its SHA-256 digest. Room roster,
game state, player hand, and game-action RPCs verify that capability. Direct
table access is revoked, and the lobby polls its protected roster RPC rather
than listening to public Postgres Changes payloads. Invite-code lookup returns
only room metadata and player count.

The token is a bearer secret: anyone who steals it can act as that seat. It is
kept in tab-scoped sessionStorage; do not log or share it. XSS prevention and
a production rate limit for room creation remain important follow-ups.

Migration `supabase/migrations/0006_phase3_protected_state_sync.sql` adds
`get_room_game(room_id, player_id, access_token)`, which lets an already
seated player discover a game without opening up `games` or
`game_players`. `frontend/js/gameSync.js` polls this RPC while waiting in
the lobby, then polls the public game state, player state, and only that
player's own hand every two seconds. It also sends a heartbeat every eight
seconds so reconnect and bot-takeover logic remains live.

This is deliberately protected polling rather than public Postgres Changes:
private Realtime authorization is JWT/RLS-based, while this application uses
non-JWT capability tokens. A public changefeed would reveal card state to
non-members. The Phase 3 metadata/permission check is in
`supabase/tests/phase3_protected_state_sync.test.sql`.
