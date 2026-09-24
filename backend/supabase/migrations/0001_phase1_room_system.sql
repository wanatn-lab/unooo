-- Phase 1: Room creation & join system
-- Applied to the project's Supabase database. If you ever need to rebuild
-- this project from scratch, run every file in this folder in order
-- (via the Supabase SQL editor, or `supabase db push` with the CLI).

create extension if not exists pgcrypto;

create table if not exists rooms (
  id uuid primary key default gen_random_uuid(),
  code text unique not null,
  status text not null default 'lobby',
  max_players int not null default 8,
  created_at timestamptz not null default now()
);

create table if not exists players (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references rooms(id) on delete cascade,
  name text not null,
  is_host boolean not null default false,
  joined_at timestamptz not null default now()
);

create index if not exists players_room_id_idx on players(room_id);

alter table rooms enable row level security;
alter table players enable row level security;

-- Phase 1 has no auth yet: allow anonymous read/insert.
-- NOTE for later phases: tighten these policies once auth/sessions exist.
create policy "rooms are publicly readable" on rooms
  for select using (true);

create policy "anyone can create a room" on rooms
  for insert with check (true);

create policy "players are publicly readable" on players
  for select using (true);

-- Direct inserts into players are blocked; joining must go through
-- join_room() below so the "max 8 players" rule can never be bypassed
-- by a client inserting straight into the table.
create policy "no direct player inserts" on players
  for insert with check (false);

-- Atomically checks room exists + not full, then adds the player.
-- Returns the new player row. Raises a clear error message the
-- frontend can show to the user (room_full / room_not_found).
create or replace function join_room(p_code text, p_name text)
returns players
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_room rooms%rowtype;
  v_count int;
  v_player players%rowtype;
begin
  select * into v_room from rooms where code = p_code for update;

  if not found then
    raise exception 'room_not_found';
  end if;

  select count(*) into v_count from players where room_id = v_room.id;

  if v_count >= v_room.max_players then
    raise exception 'room_full';
  end if;

  insert into players (room_id, name, is_host)
  values (v_room.id, p_name, false)
  returning * into v_player;

  return v_player;
end;
$$;

-- Creates a room with a fresh unique code and adds the creator as host,
-- in one atomic call (avoids a code-collision race between two clients
-- creating a room in the same instant).
create or replace function create_room(p_host_name text, p_max_players int default 8)
returns table (room_id uuid, code text, player_id uuid)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_code text;
  v_room_id uuid;
  v_player_id uuid;
  v_tries int := 0;
begin
  loop
    v_code := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
    begin
      insert into rooms (code, max_players) values (v_code, p_max_players)
        returning id into v_room_id;
      exit;
    exception when unique_violation then
      v_tries := v_tries + 1;
      if v_tries > 10 then
        raise exception 'could_not_generate_unique_code';
      end if;
    end;
  end loop;

  insert into players (room_id, name, is_host)
  values (v_room_id, p_host_name, true)
  returning id into v_player_id;

  return query select v_room_id, v_code, v_player_id;
end;
$$;

grant execute on function join_room(text, text) to anon;
grant execute on function create_room(text, int) to anon;
