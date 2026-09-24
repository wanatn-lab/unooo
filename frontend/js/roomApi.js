// ---------------------------------------------------------------------------
// All Supabase calls related to rooms/players live here, in one place.
// Nothing outside this file should talk to `supabase` directly for rooms —
// that keeps every DB touchpoint (and the Supabase-specific error handling)
// in a single, easy-to-find spot for whoever maintains this next.
// ---------------------------------------------------------------------------
import { supabase } from "./supabaseClient.js";
import { CONFIG } from "./config.js";

/**
 * Creates a new room and makes `hostName` its first player (host).
 * The unique room code is generated and collision-checked on the database
 * side (see create_room() in backend/supabase/migrations), so this never
 * has to retry on the client.
 *
 * @returns {Promise<{roomId: string, code: string, playerId: string}>}
 */
export async function createRoom(hostName) {
  const { data, error } = await supabase
    .rpc("create_room", {
      p_host_name: hostName,
      p_max_players: CONFIG.MAX_PLAYERS_PER_ROOM,
    })
    .single();

  if (error) throw new Error("Could not create the room. Please try again.");

  return { roomId: data.room_id, code: data.code, playerId: data.player_id };
}

/**
 * Joins an existing room by its code.
 * Throws a friendly, specific error for the two expected failure cases
 * (room does not exist / room is full) so the UI can show a clear message
 * instead of a blank or stuck screen.
 *
 * @returns {Promise<{playerId: string, roomId: string}>}
 */
export async function joinRoom(code, playerName) {
  const { data, error } = await supabase
    .rpc("join_room", { p_code: code, p_name: playerName })
    .single();

  if (error) {
    if (error.message.includes("room_not_found")) {
      throw new Error("This room code doesn't exist. Check the link or code and try again.");
    }
    if (error.message.includes("room_full")) {
      throw new Error(`This room is full (max ${CONFIG.MAX_PLAYERS_PER_ROOM} players).`);
    }
    throw new Error("Could not join the room. Please try again.");
  }

  return { playerId: data.id, roomId: data.room_id };
}

/** Looks up a room by its shareable code. Returns null if it doesn't exist. */
export async function getRoomByCode(code) {
  const { data, error } = await supabase
    .from("rooms")
    .select("id, code, status, max_players, created_at")
    .eq("code", code)
    .maybeSingle();

  if (error) throw new Error("Could not look up the room.");
  return data;
}

/** Returns every player currently in a room, oldest-joined first. */
export async function getPlayers(roomId) {
  const { data, error } = await supabase
    .from("players")
    .select("id, name, is_host, joined_at")
    .eq("room_id", roomId)
    .order("joined_at", { ascending: true });

  if (error) throw new Error("Could not load the player list.");
  return data;
}

/**
 * Subscribes to real-time player join/leave events for a room, so every
 * device in the lobby sees new players appear without refreshing.
 * Call the returned function to unsubscribe (e.g. when leaving the page).
 */
export function subscribeToPlayers(roomId, onChange) {
  const channel = supabase
    .channel(`players-room-${roomId}`)
    .on(
      "postgres_changes",
      { event: "*", schema: "public", table: "players", filter: `room_id=eq.${roomId}` },
      onChange
    )
    .subscribe();

  return () => supabase.removeChannel(channel);
}
