-- Phase 4: expose opponents' hand SIZE (not contents) so the game table UI
-- can show "3 cards left" next to other players. This is purely additive:
-- no table, RPC, or rule is removed or changed in meaning. Only a new
-- attribute is added to the existing public.game_player_public_state type,
-- and the functions that build that type are updated to fill it in.
--
-- Why this is safe to expose: hand_count is a count, not the cards
-- themselves. Actual hand contents remain readable only via
-- get_my_hand(), which still only returns the caller's own hand.

alter type public.game_player_public_state add attribute hand_count integer;

create or replace function public.get_game_players(p_game_id uuid, p_access_token text)
returns setof public.game_player_public_state
language plpgsql security definer set search_path = ''
as $$
begin
  perform private.assert_game_member(p_game_id, p_access_token);
  return query select gp.game_id, gp.player_id, gp.seat_order, gp.said_uno, gp.is_bot, gp.connected,
      jsonb_array_length(gp.hand)
    from public.game_players gp where gp.game_id = p_game_id order by gp.seat_order;
end;
$$;

create or replace function public.call_uno(p_game_id uuid, p_player_id uuid, p_access_token text)
returns public.game_player_public_state
language plpgsql security definer set search_path = ''
as $$
declare v public.game_players%rowtype;
begin
  perform private.assert_game_player(p_game_id, p_player_id, p_access_token);
  v := public._call_uno_unchecked(p_game_id, p_player_id);
  return row(v.game_id, v.player_id, v.seat_order, v.said_uno, v.is_bot, v.connected,
    jsonb_array_length(v.hand))::public.game_player_public_state;
end;
$$;

create or replace function public.catch_uno_failure(p_game_id uuid, p_accuser_id uuid, p_target_id uuid, p_access_token text)
returns public.game_player_public_state
language plpgsql security definer set search_path = ''
as $$
declare v public.game_players%rowtype;
begin
  perform private.assert_game_player(p_game_id, p_accuser_id, p_access_token);
  v := public._catch_uno_failure_unchecked(p_game_id, p_accuser_id, p_target_id);
  return row(v.game_id, v.player_id, v.seat_order, v.said_uno, v.is_bot, v.connected,
    jsonb_array_length(v.hand))::public.game_player_public_state;
end;
$$;

create or replace function public.heartbeat(p_game_id uuid, p_player_id uuid, p_access_token text)
returns public.game_player_public_state
language plpgsql security definer set search_path = ''
as $$
declare v public.game_players%rowtype;
begin
  perform private.assert_game_player(p_game_id, p_player_id, p_access_token);
  v := public._heartbeat_unchecked(p_game_id, p_player_id);
  return row(v.game_id, v.player_id, v.seat_order, v.said_uno, v.is_bot, v.connected,
    jsonb_array_length(v.hand))::public.game_player_public_state;
end;
$$;
