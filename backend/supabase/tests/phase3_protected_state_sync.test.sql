-- Phase 3 protected polling contract.
-- Run after 0005_phase3_capability_security.sql and
-- 0006_phase3_protected_state_sync.sql.

begin;

do $$
begin
  if to_regprocedure('public.get_room_game(uuid,uuid,text)') is null then
    raise exception 'get_room_game RPC is missing';
  end if;

  if not has_function_privilege(
    'anon',
    'public.get_room_game(uuid,uuid,text)',
    'EXECUTE'
  ) then
    raise exception 'anon cannot execute get_room_game';
  end if;

  if has_table_privilege('anon', 'public.games', 'SELECT')
     or has_table_privilege('anon', 'public.game_players', 'SELECT') then
    raise exception 'anon must not read game tables directly';
  end if;

  raise notice 'PHASE 3 PROTECTED STATE SYNC TESTS PASSED';
end;
$$;

rollback;
