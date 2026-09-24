-- Turns on Realtime (live updates) for the two Phase 1 tables, so the
-- lobby page can see players join without refreshing.
alter publication supabase_realtime add table players;
alter publication supabase_realtime add table rooms;
