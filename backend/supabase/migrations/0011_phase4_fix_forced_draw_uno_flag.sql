-- ---------------------------------------------------------------------------
-- Phase 4 bug fix, found during the mandatory 2-player live browser test
-- (not a Phase 4 feature change): _apply_play_card() applies a Draw 2 /
-- Wild Draw 4 forced draw to the next player's hand but never reset that
-- player's `said_uno` flag. If that player had said UNO on a previous turn
-- (hand length 1) and was then hit by a forced draw, `said_uno` stayed
-- true even though their hand had grown back past 1 card — observed live
-- as an opponent's "UNO!" badge sticking incorrectly in the Game Table UI
-- with a 6-card hand.
--
-- This does not change any rule, any RPC signature, or any return shape —
-- it only makes the forced-draw hand update also clear said_uno/
-- reached_one_at, matching what already happens on a normal draw
-- (_apply_draw_and_pass, unchanged) and on the acting player's own hand
-- update earlier in this same function (also unchanged). catch_uno_failure
-- already requires hand length = 1 to catch someone, so this was never
-- exploitable to dodge a real catch — it was a cosmetic/data-consistency
-- bug, not a scoring bug. Fixing it here rather than leaving it because a
-- stale said_uno is exactly the kind of case-by-case game-state
-- inconsistency PROJECT.md's phase-close testing is meant to catch.
-- ---------------------------------------------------------------------------

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
  v_forced_new_hand jsonb;
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

    select hand into v_forced_new_hand from game_players
      where game_id = p_game_id and player_id = v_forced_target_id for update;
    v_forced_new_hand := v_forced_new_hand || v_drawn;

    -- Fix (this migration): a forced draw always leaves the target with
    -- more than one card (they had >=1 before it, and just gained 2 or 4),
    -- so said_uno can never still be accurate afterwards — clear it, the
    -- same way a normal draw already does.
    update game_players set
      hand = v_forced_new_hand,
      said_uno = false,
      reached_one_at = null
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
