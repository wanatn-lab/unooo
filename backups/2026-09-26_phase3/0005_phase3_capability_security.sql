-- Phase 3: Auth-independent capability security.
-- Anonymous Auth is disabled for this Supabase project, so each seat gets a
-- browser-generated 256-bit bearer token. Only its SHA-256 digest is stored.
-- All sensitive reads and writes go through narrow SECURITY DEFINER RPCs;
-- direct table access and Postgres Changes are intentionally unavailable.

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

alter table public.players add column if not exists access_token_hash text;
-- The live project was verified empty before rollout; old unbound seats cannot
-- be safely assigned a capability after the fact.
alter table public.players alter column access_token_hash set not null;
create unique index if not exists players_access_token_hash_uidx
  on public.players(access_token_hash);

create or replace function private.hash_access_token(p_token text)
returns text language sql immutable security invoker set search_path = ''
as $$
  select case
    when p_token ~ '^[0-9a-f]{64}$'
      then pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(p_token, 'UTF8')), 'hex')
    else null
  end;
$$;

create or replace function private.assert_room_player(p_room_id uuid, p_player_id uuid, p_access_token text)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  if private.hash_access_token(p_access_token) is null then raise exception 'invalid_access_token'; end if;
  if not exists (
    select 1 from public.players p
    where p.room_id = p_room_id and p.id = p_player_id
      and p.access_token_hash = private.hash_access_token(p_access_token)
  ) then raise exception 'player_not_in_room'; end if;
end;
$$;

create or replace function private.assert_game_player(p_game_id uuid, p_player_id uuid, p_access_token text)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  if private.hash_access_token(p_access_token) is null then raise exception 'invalid_access_token'; end if;
  if not exists (
    select 1 from public.game_players gp
    join public.players p on p.id = gp.player_id
    where gp.game_id = p_game_id and gp.player_id = p_player_id
      and p.access_token_hash = private.hash_access_token(p_access_token)
  ) then raise exception 'player_not_in_game'; end if;
end;
$$;

create or replace function private.assert_game_member(p_game_id uuid, p_access_token text)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  if private.hash_access_token(p_access_token) is null then raise exception 'invalid_access_token'; end if;
  if not exists (
    select 1 from public.game_players gp
    join public.players p on p.id = gp.player_id
    where gp.game_id = p_game_id
      and p.access_token_hash = private.hash_access_token(p_access_token)
  ) then raise exception 'player_not_in_game'; end if;
end;
$$;

revoke all on all functions in schema private from public, anon, authenticated;

-- Do not expose room/player/game rows or changefeeds directly through the API.
drop policy if exists "rooms are publicly readable" on public.rooms;
drop policy if exists "anyone can create a room" on public.rooms;
drop policy if exists "players are publicly readable" on public.players;
drop policy if exists "no direct player inserts" on public.players;
drop policy if exists rooms_read_for_members on public.rooms;
drop policy if exists players_read_for_room_members on public.players;
drop policy if exists games_read_for_members on public.games;
drop policy if exists game_players_read_for_members on public.game_players;
drop policy if exists "games are publicly readable" on public.games;
drop policy if exists "no direct game writes" on public.games;
drop policy if exists "no direct game updates" on public.games;
drop policy if exists "game_players are publicly readable" on public.game_players;
drop policy if exists "no direct game_player writes" on public.game_players;
drop policy if exists "no direct game_player updates" on public.game_players;
revoke all on public.rooms, public.players, public.games, public.game_players from public, anon, authenticated;

drop function if exists public.create_room(text, integer);
drop function if exists public.join_room(text, text);
drop function if exists public.lookup_room(text);

create or replace function public.create_room(p_host_name text, p_access_token text, p_max_players integer default 8)
returns table (room_id uuid, code text, player_id uuid)
language plpgsql security definer set search_path = ''
as $$
declare
  v_hash text := private.hash_access_token(p_access_token);
  v_code text;
  v_room_id uuid;
  v_player_id uuid;
  v_tries int := 0;
begin
  if v_hash is null then raise exception 'invalid_access_token'; end if;
  if p_host_name is null or length(btrim(p_host_name)) not between 1 and 24 then raise exception 'invalid_player_name'; end if;
  if p_max_players < 2 or p_max_players > 8 then raise exception 'invalid_max_players'; end if;

  -- Idempotent retry if the network dropped the prior create response.
  select p.id, p.room_id, r.code into v_player_id, v_room_id, v_code
  from public.players p join public.rooms r on r.id = p.room_id
  where p.access_token_hash = v_hash;
  if found then return query select v_room_id, v_code, v_player_id; return; end if;

  loop
    v_code := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
    begin
      insert into public.rooms (code, max_players) values (v_code, p_max_players) returning id into v_room_id;
      exit;
    exception when unique_violation then
      v_tries := v_tries + 1;
      if v_tries > 10 then raise exception 'could_not_generate_unique_code'; end if;
    end;
  end loop;
  insert into public.players (room_id, name, is_host, access_token_hash)
  values (v_room_id, btrim(p_host_name), true, v_hash) returning id into v_player_id;
  return query select v_room_id, v_code, v_player_id;
end;
$$;

create or replace function public.join_room(p_code text, p_name text, p_access_token text)
returns table (id uuid, room_id uuid, name text, is_host boolean, joined_at timestamptz)
language plpgsql security definer set search_path = ''
as $$
declare
  v_hash text := private.hash_access_token(p_access_token);
  v_room public.rooms%rowtype;
  v_player public.players%rowtype;
  v_count int;
begin
  if v_hash is null then raise exception 'invalid_access_token'; end if;
  if p_name is null or length(btrim(p_name)) not between 1 and 24 then raise exception 'invalid_player_name'; end if;
  select * into v_player from public.players p where p.access_token_hash = v_hash;
  if found then return query select v_player.id, v_player.room_id, v_player.name, v_player.is_host, v_player.joined_at; return; end if;

  select * into v_room from public.rooms where code = upper(p_code) for update;
  if not found then raise exception 'room_not_found'; end if;
  if v_room.status <> 'lobby' then raise exception 'room_not_in_lobby'; end if;
  select count(*) into v_count from public.players p where p.room_id = v_room.id;
  if v_count >= v_room.max_players then raise exception 'room_full'; end if;
  insert into public.players (room_id, name, is_host, access_token_hash)
  values (v_room.id, btrim(p_name), false, v_hash) returning * into v_player;
  return query select v_player.id, v_player.room_id, v_player.name, v_player.is_host, v_player.joined_at;
end;
$$;

-- Invite-code lookup intentionally returns only non-sensitive room metadata.
create or replace function public.lookup_room(p_code text)
returns table (id uuid, code text, status text, max_players integer, player_count bigint, is_member boolean)
language plpgsql security definer set search_path = ''
as $$
begin
  return query select r.id, r.code, r.status, r.max_players, count(p.id), false
    from public.rooms r left join public.players p on p.room_id = r.id
    where r.code = upper(p_code) group by r.id;
end;
$$;

create or replace function public.get_room_players(p_room_id uuid, p_access_token text)
returns table (id uuid, name text, is_host boolean, joined_at timestamptz)
language plpgsql security definer set search_path = ''
as $$
begin
  if private.hash_access_token(p_access_token) is null or not exists (
    select 1 from public.players p where p.room_id = p_room_id
      and p.access_token_hash = private.hash_access_token(p_access_token)
  ) then raise exception 'player_not_in_room'; end if;
  return query select p.id, p.name, p.is_host, p.joined_at
    from public.players p where p.room_id = p_room_id order by p.joined_at;
end;
$$;

create type public.game_state_public as (
 id uuid, room_id uuid, status text, discard_pile jsonb, direction integer,
 current_color text, turn_player_id uuid, has_drawn_this_turn boolean,
 winner_id uuid, config jsonb, created_at timestamptz, updated_at timestamptz
);
create type public.game_player_public_state as (
 game_id uuid, player_id uuid, seat_order integer, said_uno boolean, is_bot boolean, connected boolean
);
revoke all on type public.game_state_public, public.game_player_public_state from public, anon, authenticated;
grant usage on type public.game_state_public, public.game_player_public_state to anon;

alter function public.start_game(uuid, uuid) rename to _start_game_unchecked;
alter function public.play_card(uuid, uuid, jsonb, text, boolean) rename to _play_card_unchecked;
alter function public.draw_card(uuid, uuid) rename to _draw_card_unchecked;
alter function public.pass_turn(uuid, uuid) rename to _pass_turn_unchecked;
alter function public.call_uno(uuid, uuid) rename to _call_uno_unchecked;
alter function public.catch_uno_failure(uuid, uuid, uuid) rename to _catch_uno_failure_unchecked;
alter function public.heartbeat(uuid, uuid) rename to _heartbeat_unchecked;

revoke all on function public._start_game_unchecked(uuid, uuid) from public, anon, authenticated;
revoke all on function public._play_card_unchecked(uuid, uuid, jsonb, text, boolean) from public, anon, authenticated;
revoke all on function public._draw_card_unchecked(uuid, uuid) from public, anon, authenticated;
revoke all on function public._pass_turn_unchecked(uuid, uuid) from public, anon, authenticated;
revoke all on function public._call_uno_unchecked(uuid, uuid) from public, anon, authenticated;
revoke all on function public._catch_uno_failure_unchecked(uuid, uuid, uuid) from public, anon, authenticated;
revoke all on function public._heartbeat_unchecked(uuid, uuid) from public, anon, authenticated;

create or replace function public.start_game(p_room_id uuid, p_player_id uuid, p_access_token text)
returns public.game_state_public language plpgsql security definer set search_path = '' as $$
declare v public.games%rowtype;
begin
 perform private.assert_room_player(p_room_id,p_player_id,p_access_token);
 v:=public._start_game_unchecked(p_room_id,p_player_id);
 return row(v.id,v.room_id,v.status,v.discard_pile,v.direction,v.current_color,v.turn_player_id,v.has_drawn_this_turn,v.winner_id,v.config,v.created_at,v.updated_at)::public.game_state_public;
end; $$;

create or replace function public.play_card(p_game_id uuid,p_player_id uuid,p_access_token text,p_card jsonb,p_chosen_color text default null,p_declare_uno boolean default false)
returns public.game_state_public language plpgsql security definer set search_path = '' as $$
declare v public.games%rowtype;
begin
 perform private.assert_game_player(p_game_id,p_player_id,p_access_token);
 v:=public._play_card_unchecked(p_game_id,p_player_id,p_card,p_chosen_color,p_declare_uno);
 return row(v.id,v.room_id,v.status,v.discard_pile,v.direction,v.current_color,v.turn_player_id,v.has_drawn_this_turn,v.winner_id,v.config,v.created_at,v.updated_at)::public.game_state_public;
end; $$;

create or replace function public.draw_card(p_game_id uuid,p_player_id uuid,p_access_token text)
returns table(drawn_card jsonb, playable boolean) language plpgsql security definer set search_path = '' as $$
begin
 perform private.assert_game_player(p_game_id,p_player_id,p_access_token);
 return query select * from public._draw_card_unchecked(p_game_id,p_player_id);
end; $$;

create or replace function public.pass_turn(p_game_id uuid,p_player_id uuid,p_access_token text)
returns public.game_state_public language plpgsql security definer set search_path = '' as $$
declare v public.games%rowtype;
begin
 perform private.assert_game_player(p_game_id,p_player_id,p_access_token);
 v:=public._pass_turn_unchecked(p_game_id,p_player_id);
 return row(v.id,v.room_id,v.status,v.discard_pile,v.direction,v.current_color,v.turn_player_id,v.has_drawn_this_turn,v.winner_id,v.config,v.created_at,v.updated_at)::public.game_state_public;
end; $$;

create or replace function public.call_uno(p_game_id uuid,p_player_id uuid,p_access_token text)
returns public.game_player_public_state language plpgsql security definer set search_path = '' as $$
declare v public.game_players%rowtype;
begin
 perform private.assert_game_player(p_game_id,p_player_id,p_access_token);
 v:=public._call_uno_unchecked(p_game_id,p_player_id);
 return row(v.game_id,v.player_id,v.seat_order,v.said_uno,v.is_bot,v.connected)::public.game_player_public_state;
end; $$;

create or replace function public.catch_uno_failure(p_game_id uuid,p_accuser_id uuid,p_target_id uuid,p_access_token text)
returns public.game_player_public_state language plpgsql security definer set search_path = '' as $$
declare v public.game_players%rowtype;
begin
 perform private.assert_game_player(p_game_id,p_accuser_id,p_access_token);
 v:=public._catch_uno_failure_unchecked(p_game_id,p_accuser_id,p_target_id);
 return row(v.game_id,v.player_id,v.seat_order,v.said_uno,v.is_bot,v.connected)::public.game_player_public_state;
end; $$;

create or replace function public.heartbeat(p_game_id uuid,p_player_id uuid,p_access_token text)
returns public.game_player_public_state language plpgsql security definer set search_path = '' as $$
declare v public.game_players%rowtype;
begin
 perform private.assert_game_player(p_game_id,p_player_id,p_access_token);
 v:=public._heartbeat_unchecked(p_game_id,p_player_id);
 return row(v.game_id,v.player_id,v.seat_order,v.said_uno,v.is_bot,v.connected)::public.game_player_public_state;
end; $$;

create or replace function public.get_my_hand(p_game_id uuid,p_player_id uuid,p_access_token text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_hand jsonb;
begin
  perform private.assert_game_player(p_game_id,p_player_id,p_access_token);
  select gp.hand into v_hand from public.game_players gp
  where gp.game_id = p_game_id and gp.player_id = p_player_id;
  return coalesce(v_hand, '[]'::jsonb);
end;
$$;

create or replace function public.get_game_state(p_game_id uuid,p_access_token text)
returns public.game_state_public language plpgsql security definer set search_path = ''
as $$
declare v public.games%rowtype;
begin
  perform private.assert_game_member(p_game_id,p_access_token);
  select * into v from public.games where id = p_game_id;
  return row(v.id,v.room_id,v.status,v.discard_pile,v.direction,v.current_color,v.turn_player_id,v.has_drawn_this_turn,v.winner_id,v.config,v.created_at,v.updated_at)::public.game_state_public;
end;
$$;

create or replace function public.get_game_players(p_game_id uuid,p_access_token text)
returns setof public.game_player_public_state language plpgsql security definer set search_path = ''
as $$
begin
  perform private.assert_game_member(p_game_id,p_access_token);
  return query select gp.game_id,gp.player_id,gp.seat_order,gp.said_uno,gp.is_bot,gp.connected
    from public.game_players gp where gp.game_id = p_game_id order by gp.seat_order;
end;
$$;

revoke all on function public.create_room(text,text,integer) from public, anon, authenticated;
revoke all on function public.join_room(text,text,text) from public, anon, authenticated;
revoke all on function public.lookup_room(text) from public, anon, authenticated;
revoke all on function public.get_room_players(uuid,text) from public, anon, authenticated;
revoke all on function public.start_game(uuid,uuid,text) from public, anon, authenticated;
revoke all on function public.play_card(uuid,uuid,text,jsonb,text,boolean) from public, anon, authenticated;
revoke all on function public.draw_card(uuid,uuid,text) from public, anon, authenticated;
revoke all on function public.pass_turn(uuid,uuid,text) from public, anon, authenticated;
revoke all on function public.call_uno(uuid,uuid,text) from public, anon, authenticated;
revoke all on function public.catch_uno_failure(uuid,uuid,uuid,text) from public, anon, authenticated;
revoke all on function public.heartbeat(uuid,uuid,text) from public, anon, authenticated;
revoke all on function public.get_my_hand(uuid,uuid,text) from public, anon, authenticated;
revoke all on function public.get_game_state(uuid,text) from public, anon, authenticated;
revoke all on function public.get_game_players(uuid,text) from public, anon, authenticated;

grant execute on function public.create_room(text,text,integer) to anon;
grant execute on function public.join_room(text,text,text) to anon;
grant execute on function public.lookup_room(text) to anon;
grant execute on function public.get_room_players(uuid,text) to anon;
grant execute on function public.start_game(uuid,uuid,text) to anon;
grant execute on function public.play_card(uuid,uuid,text,jsonb,text,boolean) to anon;
grant execute on function public.draw_card(uuid,uuid,text) to anon;
grant execute on function public.pass_turn(uuid,uuid,text) to anon;
grant execute on function public.call_uno(uuid,uuid,text) to anon;
grant execute on function public.catch_uno_failure(uuid,uuid,uuid,text) to anon;
grant execute on function public.heartbeat(uuid,uuid,text) to anon;
grant execute on function public.get_my_hand(uuid,uuid,text) to anon;
grant execute on function public.get_game_state(uuid,text) to anon;
grant execute on function public.get_game_players(uuid,text) to anon;