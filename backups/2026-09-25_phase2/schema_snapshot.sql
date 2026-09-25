--
-- PostgreSQL database dump
--

\restrict dl6HSwvhhD9ALHzXCKg73X2eJAf0QB5XAaJ2DnHtPmznURrN82XYusfZnAwuNaa

-- Dumped from database version 16.13 (Ubuntu 16.13-0ubuntu0.24.04.1)
-- Dumped by pg_dump version 16.13 (Ubuntu 16.13-0ubuntu0.24.04.1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: _apply_draw_and_pass(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._apply_draw_and_pass(p_game_id uuid, p_player_id uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
declare
  v_game games%rowtype;
  v_gp game_players%rowtype;
  v_player_count int;
  v_deck jsonb;
  v_discard jsonb;
  v_drawn jsonb;
  v_new_hand jsonb;
begin
  select * into v_game from games where id = p_game_id for update;
  select * into v_gp from game_players where game_id = p_game_id and player_id = p_player_id for update;
  select count(*) into v_player_count from game_players where game_id = p_game_id;

  select new_deck, new_discard, drawn
    into v_deck, v_discard, v_drawn
    from _draw_n_cards(v_game.deck, v_game.discard_pile, 1);

  v_new_hand := v_gp.hand || v_drawn;

  update game_players set
    hand = v_new_hand,
    said_uno = case when jsonb_array_length(v_new_hand) = 1 then false else false end,
    reached_one_at = case when jsonb_array_length(v_new_hand) = 1 then now() else null end
  where game_id = p_game_id and player_id = p_player_id;

  update games set
    deck = v_deck,
    discard_pile = v_discard,
    turn_player_id = (select player_id from game_players where game_id = p_game_id
      and seat_order = _step_seat(v_gp.seat_order, v_game.direction, v_player_count, 1)),
    has_drawn_this_turn = false,
    updated_at = now()
  where id = p_game_id;

  return v_drawn -> 0;
end;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: games; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.games (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    room_id uuid NOT NULL,
    status text DEFAULT 'dealing'::text NOT NULL,
    deck jsonb DEFAULT '[]'::jsonb NOT NULL,
    discard_pile jsonb DEFAULT '[]'::jsonb NOT NULL,
    direction integer DEFAULT 1 NOT NULL,
    current_color text,
    turn_player_id uuid,
    has_drawn_this_turn boolean DEFAULT false NOT NULL,
    winner_id uuid,
    config jsonb DEFAULT '{"uno_penalty_cards": 2, "must_challenge_draw4": false, "uno_call_window_seconds": 3}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT games_current_color_check CHECK ((current_color = ANY (ARRAY['red'::text, 'yellow'::text, 'green'::text, 'blue'::text]))),
    CONSTRAINT games_direction_check CHECK ((direction = ANY (ARRAY[1, '-1'::integer]))),
    CONSTRAINT games_status_check CHECK ((status = ANY (ARRAY['dealing'::text, 'in_progress'::text, 'finished'::text])))
);


--
-- Name: _apply_play_card(uuid, uuid, jsonb, text, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._apply_play_card(p_game_id uuid, p_player_id uuid, p_card jsonb, p_chosen_color text, p_declare_uno boolean) RETURNS public.games
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
declare
  v_game games%rowtype;
  v_gp game_players%rowtype;
  v_player_count int;
  v_current_seat int;
  v_new_color text;
  v_advance_steps int := 1;
  v_new_direction int;
  v_forced_draw_count int := 0;
  v_forced_draw_seat int;
  v_forced_target_id uuid;
  v_hand_idx int;
  v_new_hand jsonb;
  v_deck jsonb;
  v_discard jsonb;
  v_drawn jsonb;
begin
  select * into v_game from games where id = p_game_id for update;
  select * into v_gp from game_players where game_id = p_game_id and player_id = p_player_id for update;
  select count(*) into v_player_count from game_players where game_id = p_game_id;
  v_current_seat := v_gp.seat_order;
  v_new_direction := v_game.direction;

  if (p_card ->> 'color') = 'wild' then
    if p_chosen_color is null or p_chosen_color not in ('red', 'yellow', 'green', 'blue') then
      raise exception 'chosen_color_required';
    end if;
    v_new_color := p_chosen_color;
  else
    v_new_color := p_card ->> 'color';
  end if;

  case p_card ->> 'value'
    when 'skip' then
      v_advance_steps := 2;
    when 'reverse' then
      if v_player_count = 2 then
        v_advance_steps := 2; -- acts as Skip with only 2 players
      else
        v_new_direction := -v_game.direction;
        v_advance_steps := 1;
      end if;
    when 'draw2' then
      v_forced_draw_count := 2;
      v_advance_steps := 2;
    when 'wild4' then
      v_forced_draw_count := 4;
      v_advance_steps := 2;
    else
      v_advance_steps := 1;
  end case;

  -- Remove the played card from the player's hand.
  v_hand_idx := _jsonb_array_index_of(v_gp.hand, p_card);
  if v_hand_idx is null then
    raise exception 'card_not_in_hand';
  end if;
  v_new_hand := v_gp.hand - v_hand_idx;

  update game_players set
    hand = v_new_hand,
    said_uno = case when jsonb_array_length(v_new_hand) = 1 then p_declare_uno else false end,
    reached_one_at = case when jsonb_array_length(v_new_hand) = 1 then now() else null end
  where game_id = p_game_id and player_id = p_player_id;

  -- Apply the forced draw (Draw 2 / Wild Draw 4) to the very next seat,
  -- one step away in the (possibly just-reversed) direction, BEFORE
  -- advancing the turn past them.
  if v_forced_draw_count > 0 then
    v_forced_draw_seat := _step_seat(v_current_seat, v_new_direction, v_player_count, 1);
    select player_id into v_forced_target_id from game_players
      where game_id = p_game_id and seat_order = v_forced_draw_seat;

    select new_deck, new_discard, drawn
      into v_deck, v_discard, v_drawn
      from _draw_n_cards(v_game.deck, v_game.discard_pile || jsonb_build_array(p_card), v_forced_draw_count);

    update game_players set hand = hand || v_drawn
      where game_id = p_game_id and player_id = v_forced_target_id;
  else
    v_deck := v_game.deck;
    v_discard := v_game.discard_pile || jsonb_build_array(p_card);
  end if;

  update games set
    deck = v_deck,
    discard_pile = v_discard,
    direction = v_new_direction,
    current_color = v_new_color,
    turn_player_id = (select player_id from game_players where game_id = p_game_id
      and seat_order = _step_seat(v_current_seat, v_new_direction, v_player_count, v_advance_steps)),
    has_drawn_this_turn = false,
    status = case when jsonb_array_length(v_new_hand) = 0 then 'finished' else status end,
    winner_id = case when jsonb_array_length(v_new_hand) = 0 then p_player_id else winner_id end,
    updated_at = now()
  where id = p_game_id;

  if jsonb_array_length(v_new_hand) = 0 then
    update rooms set status = 'finished' where id = v_game.room_id;
  end if;

  return (select g from games g where id = p_game_id);
end;
$$;


--
-- Name: _bot_take_turn(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._bot_take_turn(p_game_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
declare
  v_game games%rowtype;
  v_hand jsonb;
  v_top jsonb;
  v_card jsonb;
  v_color text;
begin
  select * into v_game from games where id = p_game_id for update;
  if not found or v_game.status <> 'in_progress' then
    return;
  end if;

  select hand into v_hand from game_players
    where game_id = p_game_id and player_id = v_game.turn_player_id;
  v_top := v_game.discard_pile -> (jsonb_array_length(v_game.discard_pile) - 1);

  v_card := _first_valid_card(v_hand, v_top, v_game.current_color);

  if v_card is not null then
    if (v_card ->> 'color') = 'wild' then
      select (elem ->> 'color') into v_color
        from jsonb_array_elements(v_hand) as elem
        where (elem ->> 'color') <> 'wild' and elem <> v_card
        group by elem ->> 'color'
        order by count(*) desc
        limit 1;
      v_color := coalesce(v_color, 'red');
    else
      v_color := null;
    end if;
    perform _apply_play_card(p_game_id, v_game.turn_player_id, v_card, v_color, true);
  else
    perform _apply_draw_and_pass(p_game_id, v_game.turn_player_id);
  end if;
end;
$$;


--
-- Name: _card_matches(jsonb, text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._card_matches(p_top jsonb, p_current_color text, p_candidate jsonb) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    AS $$
  select (p_candidate ->> 'color') = 'wild'
      or (p_candidate ->> 'color') = p_current_color
      or (p_candidate ->> 'value') = (p_top ->> 'value');
$$;


--
-- Name: _draw_n_cards(jsonb, jsonb, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._draw_n_cards(p_deck jsonb, p_discard jsonb, p_n integer) RETURNS TABLE(new_deck jsonb, new_discard jsonb, drawn jsonb)
    LANGUAGE plpgsql
    AS $$
declare
  v_deck jsonb := p_deck;
  v_discard jsonb := p_discard;
  v_drawn jsonb := '[]'::jsonb;
  v_top jsonb;
  v_rest jsonb;
begin
  for i in 1..p_n loop
    if jsonb_array_length(v_deck) = 0 then
      if jsonb_array_length(v_discard) <= 1 then
        -- Both piles exhausted (extremely unlikely with 108 cards before
        -- someone wins, but don't corrupt state — just stop drawing).
        exit;
      end if;
      v_top := v_discard -> (jsonb_array_length(v_discard) - 1);
      select jsonb_agg(elem order by random())
        into v_rest
        from jsonb_array_elements(v_discard) with ordinality as t(elem, ord)
        where ord <= jsonb_array_length(v_discard) - 1;
      v_deck := coalesce(v_rest, '[]'::jsonb);
      v_discard := jsonb_build_array(v_top);
    end if;
    v_drawn := v_drawn || jsonb_build_array(v_deck -> 0);
    v_deck := v_deck - 0;
  end loop;
  new_deck := v_deck;
  new_discard := v_discard;
  drawn := v_drawn;
  return next;
end;
$$;


--
-- Name: _first_valid_card(jsonb, jsonb, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._first_valid_card(p_hand jsonb, p_top jsonb, p_current_color text) RETURNS jsonb
    LANGUAGE sql IMMUTABLE
    AS $$
  select elem
  from jsonb_array_elements(p_hand) with ordinality as t(elem, ord)
  where _card_matches(p_top, p_current_color, elem)
  order by ord
  limit 1;
$$;


--
-- Name: _generate_deck(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._generate_deck() RETURNS jsonb
    LANGUAGE plpgsql IMMUTABLE
    AS $$
declare
  v_colors text[] := array['red', 'yellow', 'green', 'blue'];
  v_color text;
  v_deck jsonb := '[]'::jsonb;
begin
  foreach v_color in array v_colors loop
    -- one 0, two each of 1-9
    v_deck := v_deck || jsonb_build_array(jsonb_build_object('color', v_color, 'value', '0'));
    for n in 1..9 loop
      v_deck := v_deck || jsonb_build_array(jsonb_build_object('color', v_color, 'value', n::text));
      v_deck := v_deck || jsonb_build_array(jsonb_build_object('color', v_color, 'value', n::text));
    end loop;
    -- two each of skip, reverse, draw2
    for i in 1..2 loop
      v_deck := v_deck || jsonb_build_array(jsonb_build_object('color', v_color, 'value', 'skip'));
      v_deck := v_deck || jsonb_build_array(jsonb_build_object('color', v_color, 'value', 'reverse'));
      v_deck := v_deck || jsonb_build_array(jsonb_build_object('color', v_color, 'value', 'draw2'));
    end loop;
  end loop;
  -- 4 wild, 4 wild draw 4
  for i in 1..4 loop
    v_deck := v_deck || jsonb_build_array(jsonb_build_object('color', 'wild', 'value', 'wild'));
    v_deck := v_deck || jsonb_build_array(jsonb_build_object('color', 'wild', 'value', 'wild4'));
  end loop;
  return v_deck;
end;
$$;


--
-- Name: _jsonb_array_index_of(jsonb, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._jsonb_array_index_of(p_array jsonb, p_value jsonb) RETURNS integer
    LANGUAGE sql IMMUTABLE
    AS $$
  select (ord - 1)::int
  from jsonb_array_elements(p_array) with ordinality as t(elem, ord)
  where elem = p_value
  order by ord
  limit 1;
$$;


--
-- Name: _shuffle(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._shuffle(p_cards jsonb) RETURNS jsonb
    LANGUAGE sql
    AS $$
  select coalesce(jsonb_agg(elem order by random()), '[]'::jsonb)
  from jsonb_array_elements(p_cards) as elem;
$$;


--
-- Name: _step_seat(integer, integer, integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._step_seat(p_from_seat integer, p_direction integer, p_player_count integer, p_steps integer) RETURNS integer
    LANGUAGE sql IMMUTABLE
    AS $$
  select ((p_from_seat + p_direction * p_steps) % p_player_count + p_player_count) % p_player_count;
$$;


--
-- Name: _sweep_and_run_bots(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._sweep_and_run_bots(p_game_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
declare
  v_game games%rowtype;
  v_timeout_seconds int;
  v_guard int := 0;
  v_current game_players%rowtype;
begin
  select * into v_game from games where id = p_game_id for update;
  if not found or v_game.status <> 'in_progress' then
    return;
  end if;

  v_timeout_seconds := coalesce((v_game.config ->> 'disconnect_timeout_seconds')::int, 20);

  -- Anyone who hasn't heartbeated recently gets handed to a bot.
  update game_players
    set is_bot = true, connected = false
    where game_id = p_game_id
      and connected = true
      and last_seen_at < now() - make_interval(secs => v_timeout_seconds);

  -- Play consecutive bot turns until control lands on a human, or the
  -- game ends, or we hit the safety guard (defends against a bug turning
  -- this into an infinite loop rather than letting it happen).
  loop
    v_guard := v_guard + 1;
    exit when v_guard > 40;

    select * into v_game from games where id = p_game_id;
    exit when v_game.status <> 'in_progress';

    select * into v_current from game_players
      where game_id = p_game_id and player_id = v_game.turn_player_id;
    exit when not found or not v_current.is_bot;

    perform _bot_take_turn(p_game_id);
  end loop;
end;
$$;


--
-- Name: game_players; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.game_players (
    game_id uuid NOT NULL,
    player_id uuid NOT NULL,
    seat_order integer NOT NULL,
    hand jsonb DEFAULT '[]'::jsonb NOT NULL,
    said_uno boolean DEFAULT false NOT NULL,
    reached_one_at timestamp with time zone,
    is_bot boolean DEFAULT false NOT NULL,
    connected boolean DEFAULT true NOT NULL,
    last_seen_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: call_uno(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.call_uno(p_game_id uuid, p_player_id uuid) RETURNS public.game_players
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
declare
  v_gp game_players%rowtype;
begin
  select * into v_gp from game_players where game_id = p_game_id and player_id = p_player_id for update;
  if not found then
    raise exception 'player_not_in_game';
  end if;
  if jsonb_array_length(v_gp.hand) <> 1 then
    raise exception 'uno_only_valid_with_one_card';
  end if;

  update game_players set said_uno = true
    where game_id = p_game_id and player_id = p_player_id
    returning * into v_gp;
  return v_gp;
end;
$$;


--
-- Name: catch_uno_failure(uuid, uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.catch_uno_failure(p_game_id uuid, p_accuser_id uuid, p_target_id uuid) RETURNS public.game_players
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
declare
  v_game games%rowtype;
  v_target game_players%rowtype;
  v_window_seconds int;
  v_penalty int;
  v_deck jsonb;
  v_discard jsonb;
  v_drawn jsonb;
begin
  if p_accuser_id = p_target_id then
    raise exception 'cannot_catch_self';
  end if;

  select * into v_game from games where id = p_game_id for update;
  if not found or v_game.status <> 'in_progress' then
    raise exception 'game_not_in_progress';
  end if;

  select * into v_target from game_players
    where game_id = p_game_id and player_id = p_target_id for update;
  if not found then
    raise exception 'player_not_in_game';
  end if;

  if jsonb_array_length(v_target.hand) <> 1 or v_target.said_uno or v_target.reached_one_at is null then
    raise exception 'no_uno_violation';
  end if;

  v_window_seconds := coalesce((v_game.config ->> 'uno_call_window_seconds')::int, 3);
  if now() > v_target.reached_one_at + make_interval(secs => v_window_seconds) then
    raise exception 'uno_call_window_expired';
  end if;

  v_penalty := coalesce((v_game.config ->> 'uno_penalty_cards')::int, 2);

  select new_deck, new_discard, drawn
    into v_deck, v_discard, v_drawn
    from _draw_n_cards(v_game.deck, v_game.discard_pile, v_penalty);

  update games set deck = v_deck, discard_pile = v_discard, updated_at = now() where id = p_game_id;

  update game_players set
    hand = hand || v_drawn,
    said_uno = false,
    reached_one_at = null
  where game_id = p_game_id and player_id = p_target_id
  returning * into v_target;

  return v_target;
end;
$$;


--
-- Name: create_room(text, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_room(p_host_name text, p_max_players integer DEFAULT 8) RETURNS TABLE(room_id uuid, code text, player_id uuid)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
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


--
-- Name: draw_card(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.draw_card(p_game_id uuid, p_player_id uuid) RETURNS TABLE(drawn_card jsonb, playable boolean)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
declare
  v_game games%rowtype;
  v_gp game_players%rowtype;
  v_deck jsonb;
  v_discard jsonb;
  v_drawn jsonb;
  v_top jsonb;
begin
  perform _sweep_and_run_bots(p_game_id);

  select * into v_game from games where id = p_game_id for update;
  if not found then
    raise exception 'game_not_found';
  end if;
  if v_game.status <> 'in_progress' then
    raise exception 'game_not_in_progress';
  end if;
  if v_game.turn_player_id <> p_player_id then
    raise exception 'not_your_turn';
  end if;
  if v_game.has_drawn_this_turn then
    raise exception 'already_drawn_this_turn';
  end if;

  select * into v_gp from game_players where game_id = p_game_id and player_id = p_player_id for update;

  select new_deck, new_discard, drawn
    into v_deck, v_discard, v_drawn
    from _draw_n_cards(v_game.deck, v_game.discard_pile, 1);

  update game_players set hand = hand || v_drawn
    where game_id = p_game_id and player_id = p_player_id;

  update games set
    deck = v_deck, discard_pile = v_discard, has_drawn_this_turn = true, updated_at = now()
    where id = p_game_id;

  v_top := v_discard -> (jsonb_array_length(v_discard) - 1);
  drawn_card := v_drawn -> 0;
  playable := _card_matches(v_top, v_game.current_color, v_drawn -> 0);
  return next;
end;
$$;


--
-- Name: heartbeat(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.heartbeat(p_game_id uuid, p_player_id uuid) RETURNS public.game_players
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
declare
  v_gp game_players%rowtype;
begin
  -- A heartbeat from a player is also how we detect a RECONNECT: if they
  -- were bot-controlled, control returns to them immediately, with their
  -- hand and seat untouched (bot only ever mutated hand contents via the
  -- normal play/draw paths, never their identity or seat).
  update game_players set
    last_seen_at = now(),
    connected = true,
    is_bot = false
  where game_id = p_game_id and player_id = p_player_id
  returning * into v_gp;

  if not found then
    raise exception 'player_not_in_game';
  end if;

  perform _sweep_and_run_bots(p_game_id);
  return v_gp;
end;
$$;


--
-- Name: players; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.players (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    room_id uuid NOT NULL,
    name text NOT NULL,
    is_host boolean DEFAULT false NOT NULL,
    joined_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: join_room(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.join_room(p_code text, p_name text) RETURNS public.players
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
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


--
-- Name: pass_turn(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.pass_turn(p_game_id uuid, p_player_id uuid) RETURNS public.games
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
declare
  v_game games%rowtype;
  v_gp game_players%rowtype;
  v_player_count int;
begin
  select * into v_game from games where id = p_game_id for update;
  if not found then
    raise exception 'game_not_found';
  end if;
  if v_game.turn_player_id <> p_player_id then
    raise exception 'not_your_turn';
  end if;
  if not v_game.has_drawn_this_turn then
    raise exception 'must_draw_before_passing';
  end if;

  select * into v_gp from game_players where game_id = p_game_id and player_id = p_player_id;
  select count(*) into v_player_count from game_players where game_id = p_game_id;

  update games set
    turn_player_id = (select player_id from game_players where game_id = p_game_id
      and seat_order = _step_seat(v_gp.seat_order, v_game.direction, v_player_count, 1)),
    has_drawn_this_turn = false,
    updated_at = now()
  where id = p_game_id;

  return (select g from games g where id = p_game_id);
end;
$$;


--
-- Name: play_card(uuid, uuid, jsonb, text, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.play_card(p_game_id uuid, p_player_id uuid, p_card jsonb, p_chosen_color text DEFAULT NULL::text, p_declare_uno boolean DEFAULT false) RETURNS public.games
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
declare
  v_game games%rowtype;
  v_gp game_players%rowtype;
  v_top jsonb;
begin
  perform _sweep_and_run_bots(p_game_id);

  select * into v_game from games where id = p_game_id for update;
  if not found then
    raise exception 'game_not_found';
  end if;
  if v_game.status <> 'in_progress' then
    raise exception 'game_not_in_progress';
  end if;
  if v_game.turn_player_id <> p_player_id then
    raise exception 'not_your_turn';
  end if;

  select * into v_gp from game_players where game_id = p_game_id and player_id = p_player_id;
  if v_gp.is_bot then
    raise exception 'player_is_bot_controlled';
  end if;

  if _jsonb_array_index_of(v_gp.hand, p_card) is null then
    raise exception 'card_not_in_hand';
  end if;

  v_top := v_game.discard_pile -> (jsonb_array_length(v_game.discard_pile) - 1);
  if not _card_matches(v_top, v_game.current_color, p_card) then
    raise exception 'invalid_move';
  end if;

  return _apply_play_card(p_game_id, p_player_id, p_card, p_chosen_color, p_declare_uno);
end;
$$;


--
-- Name: start_game(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.start_game(p_room_id uuid, p_player_id uuid) RETURNS public.games
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
declare
  v_room rooms%rowtype;
  v_is_host boolean;
  v_player_count int;
  v_deck jsonb;
  v_hand jsonb;
  v_game_id uuid;
  v_seat int := 0;
  v_first_discard jsonb;
  v_rec record;
begin
  select * into v_room from rooms where id = p_room_id for update;
  if not found then
    raise exception 'room_not_found';
  end if;
  if v_room.status <> 'lobby' then
    raise exception 'room_not_in_lobby';
  end if;

  select is_host into v_is_host from players where id = p_player_id and room_id = p_room_id;
  if not found then
    raise exception 'player_not_in_room';
  end if;
  if not v_is_host then
    raise exception 'only_host_can_start';
  end if;

  select count(*) into v_player_count from players where room_id = p_room_id;
  if v_player_count < 2 then
    raise exception 'not_enough_players';
  end if;

  v_deck := _shuffle(_generate_deck());
  v_game_id := gen_random_uuid();

  insert into games (id, room_id, status, deck, discard_pile, direction, current_color, config)
  values (v_game_id, p_room_id, 'dealing', v_deck, '[]'::jsonb, 1, null,
    '{"uno_call_window_seconds": 3, "uno_penalty_cards": 2, "must_challenge_draw4": false, "disconnect_timeout_seconds": 20}'::jsonb);

  -- Deal 7 cards to each player, in join order, one at a time round the
  -- table the way a real deal works (not "first 7 off the top go to
  -- player 1" — doesn't change fairness, but matches player expectation
  -- and makes it trivial to eyeball in a test).
  v_seat := 0;
  for v_rec in select id from players where room_id = p_room_id order by joined_at asc loop
    insert into game_players (game_id, player_id, seat_order, hand)
    values (v_game_id, v_rec.id, v_seat, '[]'::jsonb);
    v_seat := v_seat + 1;
  end loop;

  for v_rec in select player_id from game_players where game_id = v_game_id order by seat_order asc loop
    for i in 1..7 loop
      select new_deck, drawn into v_deck, v_hand from _draw_n_cards(v_deck, '[]'::jsonb, 1);
      update game_players set hand = hand || v_hand
        where game_id = v_game_id and player_id = v_rec.player_id;
    end loop;
  end loop;

  -- Flip the starting discard card; re-draw if it's a Wild/Wild4 so the
  -- game never starts with an undefined active color.
  loop
    select new_deck, drawn into v_deck, v_first_discard from _draw_n_cards(v_deck, '[]'::jsonb, 1);
    exit when (v_first_discard -> 0 ->> 'color') <> 'wild';
    v_deck := v_deck || v_first_discard; -- put it back...
    v_deck := _shuffle(v_deck);          -- ...and reshuffle before trying again
  end loop;

  update games set
    status = 'in_progress',
    deck = v_deck,
    discard_pile = v_first_discard,
    current_color = v_first_discard -> 0 ->> 'color',
    turn_player_id = (select player_id from game_players where game_id = v_game_id and seat_order = 0),
    updated_at = now()
  where id = v_game_id;

  update rooms set status = 'in_progress' where id = p_room_id;

  return (select g from games g where id = v_game_id);
end;
$$;


--
-- Name: rooms; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.rooms (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    code text NOT NULL,
    status text DEFAULT 'lobby'::text NOT NULL,
    max_players integer DEFAULT 8 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: game_players game_players_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.game_players
    ADD CONSTRAINT game_players_pkey PRIMARY KEY (game_id, player_id);


--
-- Name: games games_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.games
    ADD CONSTRAINT games_pkey PRIMARY KEY (id);


--
-- Name: players players_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.players
    ADD CONSTRAINT players_pkey PRIMARY KEY (id);


--
-- Name: rooms rooms_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rooms
    ADD CONSTRAINT rooms_code_key UNIQUE (code);


--
-- Name: rooms rooms_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rooms
    ADD CONSTRAINT rooms_pkey PRIMARY KEY (id);


--
-- Name: game_players_game_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX game_players_game_id_idx ON public.game_players USING btree (game_id);


--
-- Name: games_room_id_active_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX games_room_id_active_idx ON public.games USING btree (room_id) WHERE (status <> 'finished'::text);


--
-- Name: players_room_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX players_room_id_idx ON public.players USING btree (room_id);


--
-- Name: game_players game_players_game_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.game_players
    ADD CONSTRAINT game_players_game_id_fkey FOREIGN KEY (game_id) REFERENCES public.games(id) ON DELETE CASCADE;


--
-- Name: game_players game_players_player_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.game_players
    ADD CONSTRAINT game_players_player_id_fkey FOREIGN KEY (player_id) REFERENCES public.players(id) ON DELETE CASCADE;


--
-- Name: games games_room_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.games
    ADD CONSTRAINT games_room_id_fkey FOREIGN KEY (room_id) REFERENCES public.rooms(id) ON DELETE CASCADE;


--
-- Name: games games_turn_player_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.games
    ADD CONSTRAINT games_turn_player_id_fkey FOREIGN KEY (turn_player_id) REFERENCES public.players(id);


--
-- Name: games games_winner_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.games
    ADD CONSTRAINT games_winner_id_fkey FOREIGN KEY (winner_id) REFERENCES public.players(id);


--
-- Name: players players_room_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.players
    ADD CONSTRAINT players_room_id_fkey FOREIGN KEY (room_id) REFERENCES public.rooms(id) ON DELETE CASCADE;


--
-- Name: rooms anyone can create a room; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "anyone can create a room" ON public.rooms FOR INSERT WITH CHECK (true);


--
-- Name: game_players; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.game_players ENABLE ROW LEVEL SECURITY;

--
-- Name: game_players game_players are publicly readable; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "game_players are publicly readable" ON public.game_players FOR SELECT USING (true);


--
-- Name: games; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.games ENABLE ROW LEVEL SECURITY;

--
-- Name: games games are publicly readable; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "games are publicly readable" ON public.games FOR SELECT USING (true);


--
-- Name: games no direct game updates; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "no direct game updates" ON public.games FOR UPDATE USING (false);


--
-- Name: games no direct game writes; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "no direct game writes" ON public.games FOR INSERT WITH CHECK (false);


--
-- Name: game_players no direct game_player updates; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "no direct game_player updates" ON public.game_players FOR UPDATE USING (false);


--
-- Name: game_players no direct game_player writes; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "no direct game_player writes" ON public.game_players FOR INSERT WITH CHECK (false);


--
-- Name: players no direct player inserts; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "no direct player inserts" ON public.players FOR INSERT WITH CHECK (false);


--
-- Name: players; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.players ENABLE ROW LEVEL SECURITY;

--
-- Name: players players are publicly readable; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "players are publicly readable" ON public.players FOR SELECT USING (true);


--
-- Name: rooms; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.rooms ENABLE ROW LEVEL SECURITY;

--
-- Name: rooms rooms are publicly readable; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "rooms are publicly readable" ON public.rooms FOR SELECT USING (true);


--
-- PostgreSQL database dump complete
--

\unrestrict dl6HSwvhhD9ALHzXCKg73X2eJAf0QB5XAaJ2DnHtPmznURrN82XYusfZnAwuNaa

