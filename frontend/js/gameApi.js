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
      throw new Error("มีแค่โฮสต์เท่านั้นที่เริ่มเกมได้");
    }
    if (error.message.includes("not_enough_players")) {
      throw new Error("ต้องมีผู้เล่นอย่างน้อย 2 คนถึงจะเริ่มเกมได้");
    }
    if (error.message.includes("room_not_in_lobby")) {
      throw new Error("ห้องนี้เริ่มเกมไปแล้วหรือจบไปแล้ว");
    }
    throw new Error("เริ่มเกมไม่สำเร็จ กรุณาลองใหม่อีกครั้ง");
  }
  return data;
}


/** Finds the current game for a room without exposing any unprotected rows. */
export async function getRoomGame(roomId, playerId) {
  const { data, error } = await supabase
    .rpc("get_room_game", {
      p_room_id: roomId,
      p_player_id: playerId,
    p_access_token: getAccessToken(),
    })
    .maybeSingle();

  if (error) throw new Error("ตรวจสอบสถานะห้องไม่สำเร็จ");
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

  if (error) throw new Error("โหลดข้อมูลเกมไม่สำเร็จ");
  return data;
}

/** Reads every player's public game state (NOT hands — see getMyHand). */
export async function getGamePlayers(gameId) {
  const { data, error } = await supabase
    .rpc("get_game_players", { p_game_id: gameId, p_access_token: getAccessToken() });

  if (error) throw new Error("โหลดข้อมูลผู้เล่นไม่สำเร็จ");
  return data;
}

/** Reads only the token holder's own hand via the protected RPC. */
export async function getHand(gameId, playerId) {
  const { data, error } = await supabase.rpc("get_my_hand", {
    p_game_id: gameId,
    p_player_id: playerId,
      p_access_token: getAccessToken(),
  });

  if (error) throw new Error("โหลดไพ่ในมือไม่สำเร็จ");
  return data ?? [];
}

/** Human-readable text for every error code the Phase 2 RPCs can raise. */
function mapGameError(message) {
  const known = {
    not_your_turn: "ยังไม่ถึงตาคุณ",
    card_not_in_hand: "คุณไม่มีไพ่ใบนี้",
    invalid_move: "ไพ่ใบนี้ลงไม่ได้ — เลือกไพ่ที่มีสี ตัวเลข หรือสัญลักษณ์ตรงกัน หรือใช้ไพ่ไวลด์",
    game_not_in_progress: "เกมนี้ยังไม่ได้เริ่มหรือจบไปแล้ว",
    game_not_found: "ไม่พบเกมนี้",
    player_is_bot_controlled: "คุณหลุดการเชื่อมต่อ — ตอนนี้บอทกำลังเล่นแทนคุณอยู่",
    chosen_color_required: "กรุณาเลือกสีให้ไพ่ใบนี้ก่อน",
    already_drawn_this_turn: "คุณจั่วไพ่ไปแล้วในตานี้",
    must_draw_before_passing: "จั่วไพ่ก่อนถึงจะกดข้ามตาได้",
    uno_only_valid_with_one_card: "ประกาศ UNO ได้ตอนเหลือไพ่ใบเดียวเท่านั้น",
    no_uno_violation: "ผู้เล่นคนนี้ไม่ได้ค้างประกาศ UNO อยู่",
    uno_call_window_expired: "ช้าไปแล้ว — หมดเวลาจับผิดการไม่ประกาศ UNO",
    cannot_catch_self: "จับผิดตัวเองไม่ได้",
    player_not_in_game: "ผู้เล่นคนนี้ไม่ได้อยู่ในเกมนี้",
  };
  for (const [code, friendly] of Object.entries(known)) {
    if (message.includes(code)) return friendly;
  }
  return "เกิดข้อผิดพลาด กรุณาลองใหม่อีกครั้ง";
}
