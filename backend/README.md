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
