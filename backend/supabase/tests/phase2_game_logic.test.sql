-- Phase 2 automated tests.
--
-- These are REAL automated tests against a REAL Postgres database (not a
-- "did it compile" check) — run in a transaction, asserting exact
-- before/after state, and raising a loud, specific error the moment
-- anything doesn't match what the rules in PROJECT.md phase-2 spec out.
--
-- How to run (locally, or against a disposable Supabase branch/project —
-- never against a live game in production, since it inserts test rows):
--   psql "<connection string>" -v ON_ERROR_STOP=1 \
--     -f backend/supabase/migrations/0001_phase1_room_system.sql \
--     -f backend/supabase/migrations/0003_phase2_game_schema.sql \
--     -f backend/supabase/migrations/0004_phase2_game_logic.sql \
--     -f backend/supabase/tests/phase2_game_logic.test.sql
--
-- Every block below either prints "PASS: <name>" or aborts the whole
-- script with a non-zero exit code (ON_ERROR_STOP) and a message
-- starting with "TEST FAILED:" naming exactly what didn't hold.

\set ON_ERROR_STOP 1
begin;

-- ======================================================================
-- 2.1 — deck has exactly 108 cards, correct color/type distribution
-- ======================================================================
do $$
declare
  v_deck jsonb := _generate_deck();
  v_total int;
  v_reds int;
  v_wilds int;
  v_wild4s int;
  v_zeros int;
  v_fives int; -- should be 2 (color-specific check below covers per-color count)
begin
  select jsonb_array_length(v_deck) into v_total;
  if v_total <> 108 then
    raise exception 'TEST FAILED: deck size — expected 108, got %', v_total;
  end if;

  select count(*) into v_reds from jsonb_array_elements(v_deck) e where e ->> 'color' = 'red';
  if v_reds <> 25 then
    raise exception 'TEST FAILED: red card count — expected 25, got %', v_reds;
  end if;

  select count(*) into v_wilds from jsonb_array_elements(v_deck) e where e ->> 'value' = 'wild';
  select count(*) into v_wild4s from jsonb_array_elements(v_deck) e where e ->> 'value' = 'wild4';
  if v_wilds <> 4 or v_wild4s <> 4 then
    raise exception 'TEST FAILED: wild counts — expected 4/4, got %/%', v_wilds, v_wild4s;
  end if;

  select count(*) into v_zeros from jsonb_array_elements(v_deck) e where e ->> 'value' = '0';
  if v_zeros <> 4 then -- one per color
    raise exception 'TEST FAILED: zero count — expected 4, got %', v_zeros;
  end if;

  select count(*) into v_fives from jsonb_array_elements(v_deck) e
    where e ->> 'value' = '5' and e ->> 'color' = 'red';
  if v_fives <> 2 then
    raise exception 'TEST FAILED: red-5 count — expected 2, got %', v_fives;
  end if;

  raise notice 'PASS: 2.1 deck has 108 cards with correct distribution';
end $$;

-- ======================================================================
-- 2.2 — start_game deals 7 cards each and leaves a correct remaining
-- deck, for a range of player counts (2..8)
-- ======================================================================
do $$
declare
  v_n int;
  v_room_id uuid;
  v_host_id uuid;
  v_code text;
  v_pid uuid;
  v_game games;
  v_hand_len int;
  v_total_in_hands int;
  v_discard_len int;
  v_deck_len int;
  v_r record;
begin
  foreach v_n in array array[2,3,4,8] loop
    select room_id, player_id into v_room_id, v_host_id from create_room('host', 8);
    for i in 2..v_n loop
      perform join_room((select code from rooms where id = v_room_id), 'p' || i);
    end loop;

    select * into v_game from start_game(v_room_id, v_host_id);

    if v_game.status <> 'in_progress' then
      raise exception 'TEST FAILED: start_game (n=%) — status expected in_progress, got %', v_n, v_game.status;
    end if;

    select sum(jsonb_array_length(hand)) into v_total_in_hands
      from game_players where game_id = v_game.id;
    if v_total_in_hands <> v_n * 7 then
      raise exception 'TEST FAILED: start_game (n=%) — total dealt cards expected %, got %',
        v_n, v_n * 7, v_total_in_hands;
    end if;

    for v_r in select hand from game_players where game_id = v_game.id loop
      if jsonb_array_length(v_r.hand) <> 7 then
        raise exception 'TEST FAILED: start_game (n=%) — a player has % cards, expected 7',
          v_n, jsonb_array_length(v_r.hand);
      end if;
    end loop;

    select jsonb_array_length(discard_pile) into v_discard_len from games where id = v_game.id;
    select jsonb_array_length(deck) into v_deck_len from games where id = v_game.id;

    if v_discard_len <> 1 then
      raise exception 'TEST FAILED: start_game (n=%) — discard pile should have exactly 1 card, got %', v_n, v_discard_len;
    end if;
    if (v_total_in_hands + v_discard_len + v_deck_len) <> 108 then
      raise exception 'TEST FAILED: start_game (n=%) — card total should be 108, got % (hands) + % (discard) + % (deck) = %',
        v_n, v_total_in_hands, v_discard_len, v_deck_len, v_total_in_hands + v_discard_len + v_deck_len;
    end if;
    if v_game.current_color not in ('red','yellow','green','blue') then
      raise exception 'TEST FAILED: start_game (n=%) — starting discard must not be Wild, current_color=%', v_n, v_game.current_color;
    end if;
    if v_game.turn_player_id is null then
      raise exception 'TEST FAILED: start_game (n=%) — turn_player_id not set', v_n;
    end if;
  end loop;

  raise notice 'PASS: 2.2 dealing is correct for 2/3/4/8 players';
end $$;

-- ======================================================================
-- 2.3 — invalid moves are rejected with clear errors and never corrupt
-- state
-- ======================================================================
do $$
declare
  v_room_id uuid; v_host_id uuid; v_p2_id uuid; v_code text;
  v_game games; v_before games; v_after games;
  v_host_hand jsonb;
  v_bad_card jsonb;
  v_caught boolean;
begin
  select room_id, player_id into v_room_id, v_host_id from create_room('host', 8);
  select code into v_code from rooms where id = v_room_id;
  select id into v_p2_id from join_room(v_code, 'guest');
  select * into v_game from start_game(v_room_id, v_host_id);
  select * into v_before from games where id = v_game.id;

  -- (a) playing out of turn
  v_caught := false;
  begin
    perform play_card(v_game.id, v_p2_id, jsonb_build_object('color','red','value','0'));
  exception when others then
    if sqlerrm = 'not_your_turn' then v_caught := true; else raise; end if;
  end;
  if not v_caught then
    raise exception 'TEST FAILED: 2.3a — out-of-turn play was not rejected';
  end if;

  -- (b) playing a card not in hand
  v_caught := false;
  begin
    perform play_card(v_game.id, v_game.turn_player_id, jsonb_build_object('color','not_a_color','value','99'));
  exception when others then
    if sqlerrm = 'card_not_in_hand' then v_caught := true; else raise; end if;
  end;
  if not v_caught then
    raise exception 'TEST FAILED: 2.3b — playing a card not in hand was not rejected';
  end if;

  -- (c) playing a real card from hand that doesn't match color/value/wild
  select hand into v_host_hand from game_players where game_id = v_game.id and player_id = v_game.turn_player_id;
  -- force a hand + discard pile combo guaranteed to mismatch, then try it
  update game_players set hand = jsonb_build_array(jsonb_build_object('color','red','value','9'))
    where game_id = v_game.id and player_id = v_game.turn_player_id;
  update games set discard_pile = jsonb_build_array(jsonb_build_object('color','blue','value','3')),
    current_color = 'blue' where id = v_game.id;

  v_caught := false;
  begin
    perform play_card(v_game.id, v_game.turn_player_id, jsonb_build_object('color','red','value','9'));
  exception when others then
    if sqlerrm = 'invalid_move' then v_caught := true; else raise; end if;
  end;
  if not v_caught then
    raise exception 'TEST FAILED: 2.3c — mismatched card was not rejected as invalid_move';
  end if;

  -- state must be untouched by all three rejected attempts
  select * into v_after from games where id = v_game.id;
  if v_after.turn_player_id <> v_before.turn_player_id
     or v_after.discard_pile <> jsonb_build_array(jsonb_build_object('color','blue','value','3')) then
    raise exception 'TEST FAILED: 2.3 — game state was mutated by a rejected move';
  end if;

  raise notice 'PASS: 2.3 invalid moves are rejected without corrupting state';
end $$;

-- ======================================================================
-- 2.4 — special effects, each isolated with a hand-crafted state
-- ======================================================================

-- Skip (3 players: seats 0,1,2 — seat 0 plays Skip, seat 2 should be next)
do $$
declare
  v_room_id uuid; v_host_id uuid; v_p2 uuid; v_p3 uuid; v_code text; v_game games;
  v_seat2_player uuid;
begin
  select room_id, player_id into v_room_id, v_host_id from create_room('host', 8);
  select code into v_code from rooms where id = v_room_id;
  select id into v_p2 from join_room(v_code, 'p2');
  select id into v_p3 from join_room(v_code, 'p3');
  select * into v_game from start_game(v_room_id, v_host_id);

  update games set discard_pile = jsonb_build_array(jsonb_build_object('color','red','value','5')),
    current_color = 'red', direction = 1 where id = v_game.id;
  update game_players set hand = jsonb_build_array(jsonb_build_object('color','red','value','skip'))
    where game_id = v_game.id and player_id = v_game.turn_player_id;

  select player_id into v_seat2_player from game_players where game_id = v_game.id and seat_order = 2;

  perform play_card(v_game.id, v_game.turn_player_id, jsonb_build_object('color','red','value','skip'));

  if (select turn_player_id from games where id = v_game.id) <> v_seat2_player then
    raise exception 'TEST FAILED: 2.4 Skip — seat 1 was not skipped';
  end if;
  raise notice 'PASS: 2.4 Skip advances two seats';
end $$;

-- Reverse with >2 players: direction flips, turn goes to the PREVIOUS
-- seat instead of the next one
do $$
declare
  v_room_id uuid; v_host_id uuid; v_p2 uuid; v_p3 uuid; v_code text; v_game games;
  v_last_seat_player uuid;
begin
  select room_id, player_id into v_room_id, v_host_id from create_room('host', 8);
  select code into v_code from rooms where id = v_room_id;
  select id into v_p2 from join_room(v_code, 'p2');
  select id into v_p3 from join_room(v_code, 'p3');
  select * into v_game from start_game(v_room_id, v_host_id);

  update games set discard_pile = jsonb_build_array(jsonb_build_object('color','red','value','5')),
    current_color = 'red', direction = 1 where id = v_game.id;
  update game_players set hand = jsonb_build_array(jsonb_build_object('color','red','value','reverse'))
    where game_id = v_game.id and player_id = v_game.turn_player_id;

  -- current player is seat 0; with 3 players, reversing direction to -1
  -- then advancing 1 step lands on seat 2 (the "previous" player).
  select player_id into v_last_seat_player from game_players where game_id = v_game.id and seat_order = 2;

  perform play_card(v_game.id, v_game.turn_player_id, jsonb_build_object('color','red','value','reverse'));

  if (select direction from games where id = v_game.id) <> -1 then
    raise exception 'TEST FAILED: 2.4 Reverse (3p) — direction did not flip';
  end if;
  if (select turn_player_id from games where id = v_game.id) <> v_last_seat_player then
    raise exception 'TEST FAILED: 2.4 Reverse (3p) — turn did not go to seat 2';
  end if;
  raise notice 'PASS: 2.4 Reverse (3+ players) flips direction correctly';
end $$;

-- Reverse with exactly 2 players acts as Skip (turn stays with the same
-- player who played it, i.e. the opponent is skipped)
do $$
declare
  v_room_id uuid; v_host_id uuid; v_p2 uuid; v_code text; v_game games;
begin
  select room_id, player_id into v_room_id, v_host_id from create_room('host', 8);
  select code into v_code from rooms where id = v_room_id;
  select id into v_p2 from join_room(v_code, 'p2');
  select * into v_game from start_game(v_room_id, v_host_id);

  update games set discard_pile = jsonb_build_array(jsonb_build_object('color','red','value','5')),
    current_color = 'red', direction = 1 where id = v_game.id;
  update game_players set hand = jsonb_build_array(jsonb_build_object('color','red','value','reverse'))
    where game_id = v_game.id and player_id = v_game.turn_player_id;

  perform play_card(v_game.id, v_game.turn_player_id, jsonb_build_object('color','red','value','reverse'));

  if (select turn_player_id from games where id = v_game.id) <> v_host_id then
    raise exception 'TEST FAILED: 2.4 Reverse (2p) — should act as Skip and return turn to host';
  end if;
  raise notice 'PASS: 2.4 Reverse acts as Skip in a 2-player game';
end $$;

-- Draw 2: next player draws 2 and is skipped
do $$
declare
  v_room_id uuid; v_host_id uuid; v_p2 uuid; v_p3 uuid; v_code text; v_game games;
  v_p2_hand_before int; v_p2_hand_after int; v_seat2_player uuid;
begin
  select room_id, player_id into v_room_id, v_host_id from create_room('host', 8);
  select code into v_code from rooms where id = v_room_id;
  select id into v_p2 from join_room(v_code, 'p2');
  select id into v_p3 from join_room(v_code, 'p3');
  select * into v_game from start_game(v_room_id, v_host_id);

  update games set discard_pile = jsonb_build_array(jsonb_build_object('color','red','value','5')),
    current_color = 'red', direction = 1 where id = v_game.id;
  update game_players set hand = jsonb_build_array(jsonb_build_object('color','red','value','draw2'))
    where game_id = v_game.id and player_id = v_game.turn_player_id;

  select jsonb_array_length(hand) into v_p2_hand_before from game_players where game_id = v_game.id and player_id = v_p2;
  select player_id into v_seat2_player from game_players where game_id = v_game.id and seat_order = 2;

  perform play_card(v_game.id, v_game.turn_player_id, jsonb_build_object('color','red','value','draw2'));

  select jsonb_array_length(hand) into v_p2_hand_after from game_players where game_id = v_game.id and player_id = v_p2;

  if v_p2_hand_after <> v_p2_hand_before + 2 then
    raise exception 'TEST FAILED: 2.4 Draw2 — p2 should have drawn 2 (before %, after %)', v_p2_hand_before, v_p2_hand_after;
  end if;
  if (select turn_player_id from games where id = v_game.id) <> v_seat2_player then
    raise exception 'TEST FAILED: 2.4 Draw2 — turn should skip past the player who drew';
  end if;
  raise notice 'PASS: 2.4 Draw2 forces a draw of 2 and skips that player';
end $$;

-- Wild Draw 4 + color choice
do $$
declare
  v_room_id uuid; v_host_id uuid; v_p2 uuid; v_code text; v_game games;
  v_p2_hand_before int; v_p2_hand_after int;
begin
  select room_id, player_id into v_room_id, v_host_id from create_room('host', 8);
  select code into v_code from rooms where id = v_room_id;
  select id into v_p2 from join_room(v_code, 'p2');
  select * into v_game from start_game(v_room_id, v_host_id);

  update games set discard_pile = jsonb_build_array(jsonb_build_object('color','red','value','5')),
    current_color = 'red' where id = v_game.id;
  update game_players set hand = jsonb_build_array(jsonb_build_object('color','wild','value','wild4'))
    where game_id = v_game.id and player_id = v_game.turn_player_id;

  select jsonb_array_length(hand) into v_p2_hand_before from game_players where game_id = v_game.id and player_id = v_p2;

  -- must require a chosen color
  begin
    perform play_card(v_game.id, v_game.turn_player_id, jsonb_build_object('color','wild','value','wild4'));
    raise exception 'TEST FAILED: 2.4 Wild4 — should require chosen_color';
  exception when others then
    if sqlerrm <> 'chosen_color_required' then raise; end if;
  end;

  perform play_card(v_game.id, v_game.turn_player_id, jsonb_build_object('color','wild','value','wild4'), 'green');

  select jsonb_array_length(hand) into v_p2_hand_after from game_players where game_id = v_game.id and player_id = v_p2;
  if v_p2_hand_after <> v_p2_hand_before + 4 then
    raise exception 'TEST FAILED: 2.4 Wild4 — p2 should have drawn 4 (before %, after %)', v_p2_hand_before, v_p2_hand_after;
  end if;
  if (select current_color from games where id = v_game.id) <> 'green' then
    raise exception 'TEST FAILED: 2.4 Wild4 — current_color should be the chosen color';
  end if;
  -- 2 players: draw4 also acts as a skip, so turn returns to the player who played it
  if (select turn_player_id from games where id = v_game.id) <> v_host_id then
    raise exception 'TEST FAILED: 2.4 Wild4 (2p) — turn should return to the player who played it';
  end if;
  raise notice 'PASS: 2.4 Wild Draw 4 forces a draw of 4, sets chosen color, and skips';
end $$;

-- ======================================================================
-- 2.5 — win condition + UNO call rule
-- ======================================================================
do $$
declare
  v_room_id uuid; v_host_id uuid; v_p2 uuid; v_code text; v_game games; v_result games;
begin
  select room_id, player_id into v_room_id, v_host_id from create_room('host', 8);
  select code into v_code from rooms where id = v_room_id;
  select id into v_p2 from join_room(v_code, 'p2');
  select * into v_game from start_game(v_room_id, v_host_id);

  update games set discard_pile = jsonb_build_array(jsonb_build_object('color','red','value','5')),
    current_color = 'red' where id = v_game.id;
  update game_players set hand = jsonb_build_array(jsonb_build_object('color','red','value','9'))
    where game_id = v_game.id and player_id = v_game.turn_player_id;

  select * into v_result from play_card(v_game.id, v_game.turn_player_id, jsonb_build_object('color','red','value','9'), null, false);

  if v_result.status <> 'finished' or v_result.winner_id <> v_game.turn_player_id then
    raise exception 'TEST FAILED: 2.5 win — game should be finished with the correct winner';
  end if;
  if (select status from rooms where id = v_room_id) <> 'finished' then
    raise exception 'TEST FAILED: 2.5 win — room status should also flip to finished';
  end if;
  raise notice 'PASS: 2.5 playing the last card wins immediately';
end $$;

-- UNO: forgetting to call it lets another player catch you within the
-- window and force a penalty draw; catching outside the window, or when
-- UNO was correctly called, must fail.
do $$
declare
  v_room_id uuid; v_host_id uuid; v_p2 uuid; v_code text; v_game games;
  v_hand_before int; v_hand_after int; v_caught boolean;
begin
  select room_id, player_id into v_room_id, v_host_id from create_room('host', 8);
  select code into v_code from rooms where id = v_room_id;
  select id into v_p2 from join_room(v_code, 'p2');
  select * into v_game from start_game(v_room_id, v_host_id);

  update games set discard_pile = jsonb_build_array(jsonb_build_object('color','red','value','5')),
    current_color = 'red' where id = v_game.id;
  -- host plays down to exactly 1 card (a 9) WITHOUT declaring uno
  update game_players set hand = jsonb_build_array(
      jsonb_build_object('color','red','value','9'),
      jsonb_build_object('color','red','value','8')
    ) where game_id = v_game.id and player_id = v_game.turn_player_id;

  perform play_card(v_game.id, v_game.turn_player_id, jsonb_build_object('color','red','value','9'), null, false);
  -- it's now p2's turn; simulate p2 catching the host out immediately (within window)
  select jsonb_array_length(hand) into v_hand_before from game_players where game_id = v_game.id and player_id = v_host_id;
  perform catch_uno_failure(v_game.id, v_p2, v_host_id);
  select jsonb_array_length(hand) into v_hand_after from game_players where game_id = v_game.id and player_id = v_host_id;

  if v_hand_after <> v_hand_before + 2 then
    raise exception 'TEST FAILED: 2.5 UNO — forgetting to call uno should cost a 2-card penalty (before %, after %)', v_hand_before, v_hand_after;
  end if;

  -- catching again immediately must now fail: the violation was cleared
  v_caught := false;
  begin
    perform catch_uno_failure(v_game.id, v_p2, v_host_id);
  exception when others then
    if sqlerrm = 'no_uno_violation' then v_caught := true; else raise; end if;
  end;
  if not v_caught then
    raise exception 'TEST FAILED: 2.5 UNO — catching the same lapse twice should fail';
  end if;

  -- now: play down to 1 card again, but DO declare uno this time
  update game_players set hand = jsonb_build_array(
      jsonb_build_object('color','red','value','7'),
      jsonb_build_object('color','red','value','6')
    ) where game_id = v_game.id and player_id = v_p2;
  update games set discard_pile = jsonb_build_array(jsonb_build_object('color','red','value','1')),
    current_color = 'red', turn_player_id = v_p2 where id = v_game.id;

  perform play_card(v_game.id, v_p2, jsonb_build_object('color','red','value','7'), null, true);

  v_caught := false;
  begin
    perform catch_uno_failure(v_game.id, v_host_id, v_p2);
  exception when others then
    if sqlerrm = 'no_uno_violation' then v_caught := true; else raise; end if;
  end;
  if not v_caught then
    raise exception 'TEST FAILED: 2.5 UNO — a correctly declared uno must not be catchable';
  end if;

  -- window expiry: force reached_one_at into the past beyond the window
  update game_players set said_uno = false, reached_one_at = now() - interval '10 seconds'
    where game_id = v_game.id and player_id = v_p2;
  v_caught := false;
  begin
    perform catch_uno_failure(v_game.id, v_host_id, v_p2);
  exception when others then
    if sqlerrm = 'uno_call_window_expired' then v_caught := true; else raise; end if;
  end;
  if not v_caught then
    raise exception 'TEST FAILED: 2.5 UNO — catching after the call window expired should fail';
  end if;

  raise notice 'PASS: 2.5 UNO call/catch/penalty/window all behave correctly';
end $$;

-- ======================================================================
-- 2.6 — bot takeover on disconnect, and seamless reconnect
-- ======================================================================
do $$
declare
  v_room_id uuid; v_host_id uuid; v_p2 uuid; v_code text; v_game games;
  v_gp_before game_players;
  v_gp_after game_players;
  v_turn_before uuid;
begin
  select room_id, player_id into v_room_id, v_host_id from create_room('host', 8);
  select code into v_code from rooms where id = v_room_id;
  select id into v_p2 from join_room(v_code, 'p2');
  select * into v_game from start_game(v_room_id, v_host_id);

  -- give the current turn player one guaranteed-playable card and make
  -- them look disconnected for a long time.
  update games set discard_pile = jsonb_build_array(jsonb_build_object('color','red','value','5')),
    current_color = 'red', config = config || '{"disconnect_timeout_seconds": 5}'::jsonb
    where id = v_game.id;
  update game_players set
    hand = jsonb_build_array(jsonb_build_object('color','red','value','2')) || hand,
    last_seen_at = now() - interval '1 hour'
    where game_id = v_game.id and player_id = v_game.turn_player_id;

  select * into v_gp_before from game_players where game_id = v_game.id and player_id = v_game.turn_player_id;
  v_turn_before := v_game.turn_player_id;

  -- Any other player's heartbeat is what a normal client does every few
  -- seconds; it must notice the timeout, take the seat over with a bot,
  -- and keep the game moving (never stall).
  perform heartbeat(v_game.id, v_p2);

  select * into v_gp_after from game_players where game_id = v_game.id and player_id = v_turn_before;
  if not v_gp_after.is_bot then
    raise exception 'TEST FAILED: 2.6 — disconnected player should have been marked is_bot';
  end if;
  if (select turn_player_id from games where id = v_game.id) = v_turn_before then
    raise exception 'TEST FAILED: 2.6 — bot should have taken its turn and passed play on';
  end if;
  if (select status from games where id = v_game.id) <> 'in_progress' then
    raise exception 'TEST FAILED: 2.6 — game should not stall/crash when a player is bot-controlled';
  end if;

  -- Reconnect: the original player heartbeats again — control must
  -- return to them, with their hand/seat exactly preserved.
  perform heartbeat(v_game.id, v_turn_before);
  select * into v_gp_after from game_players where game_id = v_game.id and player_id = v_turn_before;

  if v_gp_after.is_bot or not v_gp_after.connected then
    raise exception 'TEST FAILED: 2.6 — reconnecting should immediately return control to the human';
  end if;
  if v_gp_after.seat_order <> v_gp_before.seat_order then
    raise exception 'TEST FAILED: 2.6 — reconnect must preserve seat/position';
  end if;

  raise notice 'PASS: 2.6 bot takeover on disconnect, and clean reconnect';
end $$;

rollback;

\echo 'ALL PHASE 2 TESTS PASSED'
