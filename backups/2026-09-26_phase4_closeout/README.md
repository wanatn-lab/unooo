# Phase 4 closeout backup — 2026-09-26

This directory is the closeout backup required by PROJECT.md for Phase 4
("Game Table UI"). The phase is now closed after a real, live 2-player
browser test against production (see PROGRESS.md for the full account).

## Database changes backed up

- `0010_phase4_hand_count.sql`: additive migration exposing `hand_count` on
  `game_player_public_state` (and the functions that build it), so the
  table UI can show "N cards left" per opponent without exposing their
  actual hand.
- `0011_phase4_fix_forced_draw_uno_flag.sql`: bug fix found live during
  testing — `_apply_play_card()`'s Draw 2 / Wild Draw 4 forced-draw branch
  added cards to the penalized player's hand but never cleared their
  `said_uno` flag, so an opponent's "UNO!" badge could stick on long after
  their hand had grown back past 1 card. `catch_uno_failure()` already
  requires hand length = 1 to catch someone, so this was a UI/data
  consistency bug, not a scoring bug. Same function signature, no RPC
  contract change.
- `0012_phase4_remove_smoke_test_room.sql`: removes the exact 2-player
  smoke-test room (`BD6351`, id `7e08e662-2879-413b-9b83-ee8a33ec4bfd`)
  created for the live test, narrowly scoped by id AND code. `games` and
  `game_players` cascade from `rooms.id` / `games.id`, so this alone
  removed the game and both seats. Verified zero rows remain for that
  room/game after the delete.

Applied migration records in production: `phase4_hand_count`,
`phase4_fix_forced_draw_uno_flag`, `phase4_remove_smoke_test_room`.

Frontend bug fixes (no schema involved, tracked in git history, not
duplicated here as SQL):
- `frontend/js/roomApi.js`: `getPlayers()` called `getAccessToken()` but
  the module never imported it (only `getOrCreateAccessToken`), so every
  player-list fetch threw and the lobby always showed "0/8 players" with
  no roster — broken since Phase 1/3, only caught now because this is the
  first real live-browser test run against production for this project.
- `frontend/css/style.css`: `.btn` and `.modal-overlay` both set an
  unconditional `display` value with no `[hidden]` override, so browser
  `hidden` attributes on buttons and on the color-picker/UNO-confirm/
  game-over/reconnect-error overlays were ignored — the Game Table view
  was completely unusable (all overlays visible at once, stacked on the
  table) until `.btn[hidden]`/`.modal-overlay[hidden] { display: none; }`
  were added, matching the pre-existing `.view[hidden]` pattern.

## Deployment configuration

`netlify.toml` is the snapshot of the production build setting at
closeout. Publishes the static `frontend` directory. Netlify production
URL: https://unooo-lobby.netlify.app — confirmed serving each fix within
its normal auto-deploy window from `main` throughout this test.

## What the live test actually covered

Two real browser tabs (via Chrome automation), one per player, against
the live production Supabase project and the live Netlify production URL
— not a local mock:

- Create room / join room by code, host-only Start Game gating.
- Both tabs auto-entering the Game Table view when the host starts.
- Own hand, discard pile, current color, whose turn, direction, and
  opponent hand-count badge all rendering correctly and privately (an
  opponent's actual cards are never sent to the other client — verified
  both by the UI and by inspecting `get_game_players`'s return shape).
- play_card for a plain card, a Wild (with the color-picker modal), a
  Skip, and a Draw 2 (forced-draw chain), all applying instantly via the
  RPC's returned row before the next poll reconciles.
- draw_card when no card is playable, including the "doesn't match, pass"
  toast.
- pass_turn, and turn alternating correctly in both directions.
- The client-side "It's not your turn" error guard.
- Bot takeover after client idle time and reconnect-and-reclaim, observed
  naturally multiple times during the test (not synthesized).
- A real win: one seat emptied its hand via a draw2/skip/draw2/card chain,
  the server set `status = 'finished'` and `winner_id` correctly, and both
  clients independently rendered the correct Game Over overlay ("You win!
  🎉" vs. "Nat wins!") and stopped polling.

Not independently exercised live in this pass: the "declare UNO" and
"Catch!" UI flows specifically (the test game ended by a forced-draw win
before either seat lingered at exactly 1 card long enough to trigger
them). These are covered instead by: (a) code review of `game.js`'s
`confirmUnoCall()`/`handleCallUno()`/`handleCatch()`, which use the exact
same "call the RPC, apply its returned row, let the next poll reconcile"
pattern already proven live for play/draw/pass; and (b) Phase 2's
automated test suite (`backend/supabase/tests/phase2_game_logic.test.sql`),
which already exercises the UNO-call/catch/penalty rules against a real
Postgres 16 instance (11/11 passing, including the full forgot-to-say-UNO
→ caught → penalty-draw sequence). This is a real gap between "verified
live end-to-end" and "verified by code + server-side test", and is worth
closing with a dedicated live pass if a bug is ever suspected there.

No secrets are stored in this backup.
