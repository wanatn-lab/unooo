-- Phase 3 production smoke test.
-- This migration creates a two-seat game, validates protected discovery and
-- the seat capability boundary, then deletes the room before commit. If any
-- assertion fails the migration transaction rolls back, leaving no test data.

do $$
declare
  v_host record;
  v_guest record;
  v_game public.game_state_public;
  v_host_game public.game_state_public;
  v_guest_game public.game_state_public;
  v_hand jsonb;
  v_host_token text := repeat('e', 64);
  v_guest_token text := repeat('f', 64);
begin
  select *
    into v_host
    from public.create_room('P3 smoke host', v_host_token, 2);

  select *
    into v_guest
    from public.join_room(v_host.code, 'P3 smoke guest', v_guest_token);

  select *
    into v_game
    from public.start_game(v_host.room_id, v_host.player_id, v_host_token);
  select *
    into v_host_game
    from public.get_room_game(v_host.room_id, v_host.player_id, v_host_token);
  select *
    into v_guest_game
    from public.get_room_game(v_host.room_id, v_guest.id, v_guest_token);
  select public.get_my_hand(v_game.id, v_host.player_id, v_host_token)
    into v_hand;

  if v_game.status <> 'in_progress'
     or v_host_game.id is distinct from v_game.id
     or v_guest_game.id is distinct from v_game.id
     or jsonb_array_length(v_hand) <> 7 then
    raise exception 'phase3_protected_state_sync_smoke_failed';
  end if;

  begin
    perform public.get_room_game(v_host.room_id, v_host.player_id, v_guest_token);
    raise exception 'phase3_wrong_capability_was_accepted';
  exception
    when others then
      if sqlerrm = 'phase3_wrong_capability_was_accepted' then
        raise;
      end if;
      if position('player_not_in_room' in sqlerrm) = 0 then
        raise exception 'phase3_unexpected_capability_error: %', sqlerrm;
      end if;
  end;

  delete from public.rooms where id = v_host.room_id;
end;
$$;
