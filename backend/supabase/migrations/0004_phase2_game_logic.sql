-- Phase 2: Game rules engine
--
-- Everything in this file is the "rules module" for UNO: dealing, move
-- validation, special-card effects, win condition, the UNO-call rule,
-- and bot takeover. It is kept in its own migration file, separate from
-- 0003 (schema) and from the room/networking layer in 0001/0002, so the
-- rules can be found, read, and reasoned about on their own — this
-- project has no separate application server, so "an isolated module"
-- here means "its own file of pure/near-pure SQL functions", the closest
-- equivalent in a Supabase-only stack.
--
-- Naming convention: functions prefixed "_" (e.g. _draw_n_cards,
-- _card_matches) are internal helpers, not meant to be called from the
-- frontend and NOT granted to anon. Functions without the prefix are the
-- public API, granted to anon at the bottom of this file.

-- ---------------------------------------------------------------------
-- Pure helpers (no table access — take/return values only). These are
-- the easiest part of the engine to unit test in isolation, and are
-- exercised directly by the test script in backend/supabase/tests/.
-- ---------------------------------------------------------------------

create or replace function _generate_deck()
returns jsonb
language plpgsql
immutable
as $$
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

create or replace function _shuffle(p_cards jsonb)
returns jsonb
language sql
as $$
  select coalesce(jsonb_agg(elem order by random()), '[]'::jsonb)
  from jsonb_array_elements(p_cards) as elem;
$$;

-- Draws p_n cards off the top of p_deck (index 0 = top). If the deck runs
-- out mid-draw, reshuffles everything in p_discard except its top card
-- (last element) back into the deck, exactly like a physical UNO deck.
-- Pure function: takes state in, returns new state out, touches no table.
create or replace function _draw_n_cards(p_deck jsonb, p_discard jsonb, p_n int)
returns table(new_deck jsonb, new_discard jsonb, drawn jsonb)
language plpgsql
as $$
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

-- A card is playable on top of p_top (with the currently active color
-- p_current_color, which differs from p_top's own color right after a
-- Wild) if it's a Wild/Wild4, matches the active color, or matches value.
create or replace function _card_matches(p_top jsonb, p_current_color text, p_candidate jsonb)
returns boolean
language sql
immutable
as $$
  select (p_candidate ->> 'color') = 'wild'
      or (p_candidate ->> 'color') = p_current_color
      or (p_candidate ->> 'value') = (p_top ->> 'value');
$$;

-- First playable card in p_hand (in hand order), or null if none.
create or replace function _first_valid_card(p_hand jsonb, p_top jsonb, p_current_color text)
returns jsonb
language sql
immutable
as $$
  select elem
  from jsonb_array_elements(p_hand) with ordinality as t(elem, ord)
  where _card_matches(p_top, p_current_color, elem)
  order by ord
  limit 1;
$$;

-- Index (0-based) of the first element in p_array deep-equal to p_value,
-- or null if not present. jsonb equality is key-order independent.
create or replace function _jsonb_array_index_of(p_array jsonb, p_value jsonb)
returns int
language sql
immutable
as $$
  select (ord - 1)::int
  from jsonb_array_elements(p_array) with ordinality as t(elem, ord)
  where elem = p_value
  order by ord
  limit 1;
$$;

-- ---------------------------------------------------------------------
-- Public API (SECURITY DEFINER, granted to anon at the bottom).
-- Every one of these re-checks the game/room/turn state itself instead
-- of trusting the client, and raises a specific, catchable error
-- (never a silent no-op) whenever the request isn't valid.
-- ---------------------------------------------------------------------

-- Marks stale players as bot-controlled and, in a loop (bounded, so a
-- run of several disconnected players in a row can't hang), makes any
-- number of consecutive bot turns happen immediately so the game never
-- stalls. Called at the top of every other public function below, and
-- also directly by the frontend on a timer. Internal — not granted to
-- anon on its own; it always runs as part of a granted call.
create or replace function _sweep_and_run_bots(p_game_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
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

-- One bot action: play the first valid card in hand, or draw if none is
-- playable (per PROJECT.md 2.6 — deliberately simple, not strategic).
-- Wild colors are auto-picked as the most common color left in the
-- bot's hand (falls back to red if the bot has no colored cards left).
create or replace function _bot_take_turn(p_game_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
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

-- Deals a fresh game into an existing (lobby) room and starts play.
create or replace function start_game(p_room_id uuid, p_player_id uuid)
returns games
language plpgsql
security definer
set search_path = public, pg_temp
as $$
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

-- Computes the seat index p_steps away from p_from_seat, wrapping with
-- p_direction and p_player_count. p_steps is always a positive count of
-- single-player hops in p_direction.
create or replace function _step_seat(p_from_seat int, p_direction int, p_player_count int, p_steps int)
returns int
language sql
immutable
as $$
  select ((p_from_seat + p_direction * p_steps) % p_player_count + p_player_count) % p_player_count;
$$;

-- The actual move-application logic, shared by the human-facing
-- play_card() below and the bot loop. No permission/turn checks here —
-- callers are responsible for having already verified it's legal for
-- this player to act.
create or replace function _apply_play_card(
  p_game_id uuid, p_player_id uuid, p_card jsonb, p_chosen_color text, p_declare_uno boolean
)
returns games
language plpgsql
security definer
set search_path = public, pg_temp
as $$
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

-- Human-facing entry point: validates it's this player's turn, the card
-- is playable, and only THEN calls the shared apply logic. Never fails
-- silently — every rejection is a distinct, catchable error message.
create or replace function play_card(
  p_game_id uuid, p_player_id uuid, p_card jsonb, p_chosen_color text default null, p_declare_uno boolean default false
)
returns games
language plpgsql
security definer
set search_path = public, pg_temp
as $$
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

-- Shared draw+pass logic used by both draw_card (human, 2-step: draw
-- then the player decides whether to play or pass) and the bot (which
-- always just draws-and-passes, per the simple bot spec).
create or replace function _apply_draw_and_pass(p_game_id uuid, p_player_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
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

-- Human draw action (2.3): draws one card. If it's playable, the player
-- may immediately call play_card() with it (turn hasn't passed yet). If
-- not — or if they simply choose not to play it — the frontend calls
-- pass_turn() to end the turn. draw_card() itself never advances the
-- turn on its own, EXCEPT it still returns whether the drawn card is
-- playable so the frontend knows whether to even offer that choice.
create or replace function draw_card(p_game_id uuid, p_player_id uuid)
returns table(drawn_card jsonb, playable boolean)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
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

-- Ends the current player's turn after a draw they chose not to (or
-- can't) play. Only legal once they've drawn this turn.
create or replace function pass_turn(p_game_id uuid, p_player_id uuid)
returns games
language plpgsql
security definer
set search_path = public, pg_temp
as $$
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

-- 2.5: a player declares "UNO" for their own 1-card hand.
create or replace function call_uno(p_game_id uuid, p_player_id uuid)
returns game_players
language plpgsql
security definer
set search_path = public, pg_temp
as $$
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

-- 2.5: another player catches p_target_id sitting on exactly one card
-- without having declared UNO, within the configured call-out window.
-- On success, the target draws the configured penalty and their "one
-- card" state is cleared (they can be caught again if it happens once
-- more with a different card, but not for the same lapse twice).
create or replace function catch_uno_failure(p_game_id uuid, p_accuser_id uuid, p_target_id uuid)
returns game_players
language plpgsql
security definer
set search_path = public, pg_temp
as $$
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

-- 2.6: called periodically (and piggybacked on every action above) by
-- every connected client so disconnections get noticed and handed to a
-- bot promptly even if the disconnected player was mid-turn.
create or replace function heartbeat(p_game_id uuid, p_player_id uuid)
returns game_players
language plpgsql
security definer
set search_path = public, pg_temp
as $$
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

grant execute on function start_game(uuid, uuid) to anon;
grant execute on function play_card(uuid, uuid, jsonb, text, boolean) to anon;
grant execute on function draw_card(uuid, uuid) to anon;
grant execute on function pass_turn(uuid, uuid) to anon;
grant execute on function call_uno(uuid, uuid) to anon;
grant execute on function catch_uno_failure(uuid, uuid, uuid) to anon;
grant execute on function heartbeat(uuid, uuid) to anon;

-- PostgreSQL grants EXECUTE on new functions to PUBLIC by default. Keep
-- the internal implementation helpers private so anonymous API clients
-- cannot bypass the validation in the public entry points above.
revoke execute on function _generate_deck() from public, anon, authenticated;
revoke execute on function _shuffle(jsonb) from public, anon, authenticated;
revoke execute on function _draw_n_cards(jsonb, jsonb, int) from public, anon, authenticated;
revoke execute on function _card_matches(jsonb, text, jsonb) from public, anon, authenticated;
revoke execute on function _first_valid_card(jsonb, jsonb, text) from public, anon, authenticated;
revoke execute on function _jsonb_array_index_of(jsonb, jsonb) from public, anon, authenticated;
revoke execute on function _sweep_and_run_bots(uuid) from public, anon, authenticated;
revoke execute on function _bot_take_turn(uuid) from public, anon, authenticated;
revoke execute on function _step_seat(int, int, int, int) from public, anon, authenticated;
revoke execute on function _apply_play_card(uuid, uuid, jsonb, text, boolean) from public, anon, authenticated;
revoke execute on function _apply_draw_and_pass(uuid, uuid) from public, anon, authenticated;
