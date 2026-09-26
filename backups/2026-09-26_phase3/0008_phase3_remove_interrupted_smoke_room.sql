-- One-time cleanup for the interrupted Phase 3 REST smoke-test room.
-- The name and SHA-256 capability predicate identify only this test host.

delete from public.rooms r
using public.players p
where p.room_id = r.id
  and p.name = 'Phase 3 final smoke host'
  and p.access_token_hash = private.hash_access_token(repeat('c', 64));
