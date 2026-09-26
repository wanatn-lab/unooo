// ---------------------------------------------------------------------------
// All Supabase calls related to rooms/players live here. Room/player rows
// are never read directly; RPCs verify the caller's per-seat capability.
// ---------------------------------------------------------------------------
import { supabase, getOrCreateAccessToken, getAccessToken } from "./supabaseClient.js";
import { CONFIG } from "./config.js";

export async function createRoom(hostName) {
  const accessToken = getOrCreateAccessToken();
  const { data, error } = await supabase
    .rpc("create_room", {
      p_host_name: hostName,
      p_access_token: accessToken,
      p_max_players: CONFIG.MAX_PLAYERS_PER_ROOM,
    })
    .single();

  if (error) throw new Error("Could not create the room. Please try again.");
  return { roomId: data.room_id, code: data.code, playerId: data.player_id, accessToken };
}

export async function joinRoom(code, playerName) {
  const accessToken = getOrCreateAccessToken();
  const { data, error } = await supabase
    .rpc("join_room", { p_code: code, p_name: playerName, p_access_token: accessToken })
    .single();

  if (error) {
    if (error.message.includes("room_not_found")) {
      throw new Error("This room code doesn't exist. Check the link or code and try again.");
    }
    if (error.message.includes("room_full")) {
      throw new Error("This room is full.");
    }
    throw new Error("Could not join the room. Please try again.");
  }
  return { playerId: data.id, roomId: data.room_id, accessToken };
}

export async function getRoomByCode(code) {
  const { data, error } = await supabase.rpc("lookup_room", { p_code: code }).maybeSingle();
  if (error) throw new Error("Could not look up the room.");
  return data;
}

export async function getPlayers(roomId) {
  const { data, error } = await supabase.rpc("get_room_players", {
    p_room_id: roomId,
    p_access_token: getAccessToken(),
  });
  if (error) throw new Error("Could not load the player list.");
  return data ?? [];
}

// Capability tokens cannot be attached to Postgres Changes row filters. Poll
// the protected roster RPC instead of subscribing to public row payloads.
export function subscribeToPlayers(roomId, onChange) {
  const timer = setInterval(onChange, 2500);
  return () => clearInterval(timer);
}