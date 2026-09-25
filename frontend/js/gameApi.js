// ---------------------------------------------------------------------------
// All Supabase calls related to actually PLAYING a game (Phase 2 rules
// engine) live here, mirroring how roomApi.js is the single place for
// room/lobby calls. Nothing outside this file should call the game_* RPCs
// directly.
//
// This file is a thin wrapper only — it does not decide whether a move is
// legal, does not track whose turn it is, and does not render anything.
// All of that lives in the database functions in
// backend/supabase/migrations/0004_phase2_game_logic.sql, which is the
// actual rules engine and the thing backend/supabase/tests/ tests. This
// file exists so Phase 3 (Realtime Sync) and later the UI/animation phase
// have one obvious place to call into, matching the layering established
// in Phase 1.
//
// A "card" object everywhere here looks like:
//   { color: "red" | "yellow" | "green" | "blue" | "wild",
//     value: "0".."9" | "skip" | "reverse" | "draw2" | "wild" | "wild4" }
// ---------------------------------------------------------------------------
import { supabase, getAccessToken } from "./supabaseClient.js";

/** Starts the game for a room. Only the host may call this. */
export async function startGame(roomId, playerId) {
  const { data, error } = await supabase
    .rpc("start_game", { p_room_id: roomId, p_player_id: playerId, p_access_token: getAccessToken() })
    .single();

  if (error) {
    if (error.message.includes("only_host_can_start")) {
      throw new Error("Only the host can start the game.");
    }
    if (error.message.includes("not_enough_players")) {
      throw new Error("You need at least 2 players to start.");
    }
    if (error.message.includes("room_not_in_lobby")) {
      throw new Error("This room has already started or finished.");
    }
    throw new Error("Could not start the game. Please try again.");
  }
  return data;
}

/**
 * Plays a card. For a Wild or Wild Draw 4, pass the chosen color as
 * `chosenColor`. Pass `declareUno: true` when the player is calling UNO
 * as part of this exact play (i.e. this card brings them to one left).
 * Throws a specific, catchable error — never fails silently.
 */
export async function playCard(gameId, playerId, card, { chosenColor = null, declareUno = false } = {}) {
  const { data, error } = await supabase
    .rpc("play_card", {
      p_game_id: gameId,
      p_player_id: playerId,
      p_access_token: getAccessToken(),
      p_card: card,
      p_chosen_color: chosenColor,
      p_declare_uno: declareUno,
    })
    .single();

  if (error) throw new Error(mapGameError(error.message));
  return data;
}

/**
 * Draws one card for the current player. Returns whether the drawn card
 * is playable, so the UI can offer "play it" vs. just show it was drawn.
 * The turn does NOT pass automatically — call passTurn() next if the
 * player doesn't play the drawn card.
 */
export async function drawCard(gameId, playerId) {
  const { data, error } = await supabase
    .rpc("draw_card", { p_game_id: gameId, p_player_id: playerId, p_access_token: getAccessToken() })
    .single();

  if (error) throw new Error(mapGameError(error.message));
  return { card: data.drawn_card, playable: data.playable };
}

/** Ends the current player's turn after a draw they didn't/couldn't play. */
export async function passTurn(gameId, playerId) {
  const { data, error } = await supabase
    .rpc("pass_turn", { p_game_id: gameId, p_player_id: playerId, p_access_token: getAccessToken() })
    .single();

  if (error) throw new Error(mapGameError(error.message));
  return data;
}

/** Declares "UNO" for the calling player's own one-card hand. */
export async function callUno(gameId, playerId) {
  const { data, error } = await supabase
    .rpc("call_uno", { p_game_id: gameId, p_player_id: playerId, p_access_token: getAccessToken() })
    .single();

  if (error) throw new Error(mapGameError(error.message));
  return data;
}

/**
 * Catches `targetId` for sitting on one card without having called UNO.
 * Only succeeds within the game's configured call-out window.
 */
export async function catchUnoFailure(gameId, accuserId, targetId) {
  const { data, error } = await supabase
    .rpc("catch_uno_failure", { p_game_id: gameId, p_accuser_id: accuserId, p_target_id: targetId, p_access_token: getAccessToken() })
    .single();

  if (error) throw new Error(mapGameError(error.message));
  return data;
}

/**
 * Tells the server "I'm still here". Call this every few seconds while a
 * game screen is open — it's also how disconnects get detected (a player
 * who stops heartbeating gets handed to a bot after the configured
 * timeout) and how reconnecting hands control back to a human instantly.
 */
export async function heartbeat(gameId, playerId) {
  const { data, error } = await supabase
    .rpc("heartbeat", { p_game_id: gameId, p_player_id: playerId, p_access_token: getAccessToken() })
    .single();

  if (error) throw new Error(mapGameError(error.message));
  return data;
}

/** Reads the current game row (deck/discard counts, turn, direction, etc). */
export async function getGame(gameId) {
  const { data, error } = await supabase
    .rpc("get_game_state", { p_game_id: gameId, p_access_token: getAccessToken() }).maybeSingle();

  if (error) throw new Error("Could not load the game.");
  return data;
}

/** Reads every player's public game state (NOT hands — see getMyHand). */
export async function getGamePlayers(gameId) {
  const { data, error } = await supabase
    .rpc("get_game_players", { p_game_id: gameId, p_access_token: getAccessToken() });

  if (error) throw new Error("Could not load the players.");
  return data;
}

/** Reads only the authenticated player's own hand via the protected RPC. */
export async function getHand(gameId, playerId) {
  const { data, error } = await supabase.rpc("get_my_hand", {
    p_game_id: gameId,
    p_player_id: playerId,
      p_access_token: getAccessToken(),
  });

  if (error) throw new Error("Could not load your hand.");
  return data ?? [];
}

/** Human-readable text for every error code the Phase 2 RPCs can raise. */
function mapGameError(message) {
  const known = {
    not_your_turn: "It's not your turn.",
    card_not_in_hand: "You don't have that card.",
    invalid_move: "That card doesn't match — pick a card that matches the color, number, or symbol, or play a Wild.",
    game_not_in_progress: "This game isn't in progress.",
    game_not_found: "That game doesn't exist.",
    player_is_bot_controlled: "You've been disconnected — a bot is currently playing your hand.",
    chosen_color_required: "Pick a color for that card first.",
    already_drawn_this_turn: "You've already drawn this turn.",
    must_draw_before_passing: "Draw a card before passing your turn.",
    uno_only_valid_with_one_card: "You can only call UNO when you have exactly one card left.",
    no_uno_violation: "That player doesn't have an uncalled UNO right now.",
    uno_call_window_expired: "Too late — the UNO call-out window has passed.",
    cannot_catch_self: "You can't catch yourself.",
    player_not_in_game: "That player isn't in this game.",
  };
  for (const [code, friendly] of Object.entries(known)) {
    if (message.includes(code)) return friendly;
  }
  return "Something went wrong with that action. Please try again.";
}
