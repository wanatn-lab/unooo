-- Phase 3: protected game-state discovery for capability-token clients.
--
-- Private Supabase Realtime channels use JWT/RLS authorization. This app
-- intentionally uses its own per-seat capability tokens, so exposing games
-- via public Postgres Changes would leak state. The frontend polls this narrow,
-- token-protected RPC while retaining the same least-privilege boundary.

create or replace function public.get_room_game(
  p_room_id uuid,
  p_player_id uuid,
  p_access_token text
)
returns public.game_state_public
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_game public.games%rowtype;
begin
  perform private.assert_room_player(p_room_id, p_player_id, p_access_token);

  select *
    into v_game
    from public.games
   where room_id = p_room_id
   order by created_at desc
   limit 1;

  if not found then
    return null;
  end if;

  return row(
    v_game.id,
    v_game.room_id,
    v_game.status,
    v_game.discard_pile,
    v_game.direction,
    v_game.current_color,
    v_game.turn_player_id,
    v_game.has_drawn_this_turn,
    v_game.winner_id,
    v_game.config,
    v_game.created_at,
    v_game.updated_at
  )::public.game_state_public;
end;
$$;

revoke all on function public.get_room_game(uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function public.get_room_game(uuid, uuid, text) to anon;
