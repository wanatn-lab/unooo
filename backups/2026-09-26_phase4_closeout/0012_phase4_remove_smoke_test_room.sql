-- ---------------------------------------------------------------------------
-- Phase 4 closeout cleanup, matching the Phase 3 pattern (see
-- 0007_phase3_remove_smoke_test_room.sql / 0009_phase3_production_smoke_test.sql):
-- removes the exact 2-player smoke-test room used for Phase 4's mandatory
-- live browser test (create/join, start game, full play/draw/pass/wild/
-- skip/draw2 chain, bot takeover + reconnect, and a real win). Scoped
-- narrowly by id AND code so it can only ever match this one test room.
--
-- games and game_players cascade from rooms.id / games.id (see
-- 0001_phase1_room_system.sql, 0003_phase2_game_schema.sql), so deleting
-- the room is sufficient to remove the game and both seats.
-- ---------------------------------------------------------------------------

delete from public.rooms
where id = '7e08e662-2879-413b-9b83-ee8a33ec4bfd'
  and code = 'BD6351';
