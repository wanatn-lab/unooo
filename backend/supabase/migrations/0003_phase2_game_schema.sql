-- Phase 2: Game state schema
-- Adds the tables needed to actually play a hand of UNO on top of the
-- Phase 1 room/lobby system. No game rules live here — this file only
-- defines *where the state is stored*. The rules themselves (dealing,
-- move validation, special effects, win condition, bot takeover) are in
-- 0004_phase2_game_logic.sql, kept in its own file on purpose so the
-- "rules engine" stays easy to find and reason about separately from
-- storage/schema concerns.
--
-- Card representation used everywhere in Phase 2:
--   {"color": "red|yellow|green|blue|wild", "value": "0".."9"|"skip"|"reverse"|"draw2"|"wild"|"wild4"}
-- Colored number/action cards always have color in (red,yellow,green,blue).
-- Wild and Wild Draw 4 always have color "wild" until played, at which
-- point the acting player's chosen color is stored separately on the
-- game row (current_color) — the card object in the discard pile keeps
-- its original color "wild" so history stays accurate.

create table if not exists games (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references rooms(id) on delete cascade,
  status text not null default 'dealing'
    check (status in ('dealing', 'in_progress', 'finished')),

  -- Remaining draw pile, as a JSON array of card objects. Index 0 is the
  -- top (next card to be drawn) purely by convention of this codebase.
  deck jsonb not null default '[]'::jsonb,

  -- Discard pile, JSON array of card objects. The LAST element is the
  -- top of the pile (the card everyone must match against).
  discard_pile jsonb not null default '[]'::jsonb,

  -- 1 = clockwise (turn order follows seat_order ascending),
  -- -1 = counter-clockwise.
  direction int not null default 1 check (direction in (1, -1)),

  -- The color a Wild card's owner chose. For colored cards this always
  -- mirrors the top discard card's own color. Never "wild" itself.
  current_color text check (current_color in ('red', 'yellow', 'green', 'blue')),

  turn_player_id uuid references players(id),

  -- True once the current player has drawn a card this turn (so they
  -- can't draw twice before passing). Reset to false whenever the turn
  -- advances to a new player.
  has_drawn_this_turn boolean not null default false,

  winner_id uuid references players(id),

  -- House-rule flags, e.g. {"must_challenge_draw4": false,
  -- "uno_call_window_seconds": 3, "uno_penalty_cards": 2}. Never branch
  -- game logic on a hardcoded literal — always read from here so a
  -- house-rule variant is a config change, not a code change.
  config jsonb not null default
    '{"uno_call_window_seconds": 3, "uno_penalty_cards": 2, "must_challenge_draw4": false}'::jsonb,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists games_room_id_active_idx on games(room_id)
  where status <> 'finished';

-- Per-game, per-player state. One row per player per game.
create table if not exists game_players (
  game_id uuid not null references games(id) on delete cascade,
  player_id uuid not null references players(id) on delete cascade,

  -- Turn order position, assigned at deal time (0-based, in the order
  -- players had joined the room).
  seat_order int not null,

  -- JSON array of card objects currently in this player's hand.
  hand jsonb not null default '[]'::jsonb,

  -- Whether this player has declared "UNO" for their current 1-card hand.
  said_uno boolean not null default false,

  -- Set the instant this player's hand drops to exactly 1 card, cleared
  -- once it's no longer exactly 1 (they drew, or played their last
  -- card and won). Used to compute the UNO call-out window.
  reached_one_at timestamptz,

  -- Bot takeover state.
  is_bot boolean not null default false,
  connected boolean not null default true,
  last_seen_at timestamptz not null default now(),

  primary key (game_id, player_id)
);

create index if not exists game_players_game_id_idx on game_players(game_id);

alter table games enable row level security;
alter table game_players enable row level security;

-- Same trust model as Phase 1 (no auth yet): publicly readable, all
-- writes must go through the RPC functions in 0004, direct
-- insert/update/delete is blocked so the client can't mutate hands,
-- decks or whose turn it is on its own.
create policy "games are publicly readable" on games
  for select using (true);
create policy "no direct game writes" on games
  for insert with check (false);
create policy "no direct game updates" on games
  for update using (false);

create policy "game_players are publicly readable" on game_players
  for select using (true);
create policy "no direct game_player writes" on game_players
  for insert with check (false);
create policy "no direct game_player updates" on game_players
  for update using (false);
