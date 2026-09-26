-- One-time cleanup for the Phase 3 REST smoke-test room.
-- The exact host-name + SHA-256 capability predicate limits this to the room
-- created by the failed test setup on 2026-09-26. Deleting the room cascades
-- to its only player; no game was started for this room.

delete from public.rooms r
using public.players p
where p.room_id = r.id
  and p.name = 'Phase 3 smoke host'
  and p.access_token_hash = private.hash_access_token(repeat('a', 64));
