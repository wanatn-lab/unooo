// ---------------------------------------------------------------------------
// Protected game-state synchronization (Phase 3).
//
// This project authorizes players with per-seat capability tokens rather than
// Supabase Auth JWTs. Private Realtime channels cannot safely validate those
// tokens, so this module polls the narrow protected RPCs instead of exposing
// game rows through public Postgres Changes.
// ---------------------------------------------------------------------------
import { getGame, getGamePlayers, getHand, getRoomGame, heartbeat } from "./gameApi.js";

export const GAME_SYNC_INTERVAL_MS = 2000;
export const HEARTBEAT_INTERVAL_MS = 8000;
export const ROOM_GAME_DISCOVERY_INTERVAL_MS = 1500;

function noop() {}

/**
 * Watches for the host to create a game in this room. The callback receives
 * null until a game exists, then the protected public game-state object.
 */
export function subscribeToRoomGame(
  roomId,
  playerId,
  onGame,
  onError = noop,
  { intervalMs = ROOM_GAME_DISCOVERY_INTERVAL_MS } = {},
) {
  let active = true;
  let inFlight = false;
  let lastGameId = null;

  const poll = async () => {
    if (!active || inFlight) return;
    inFlight = true;
    try {
      const game = await getRoomGame(roomId, playerId);
      if (game?.id && game.id !== lastGameId) {
        lastGameId = game.id;
        onGame(game);
      }
    } catch (error) {
      if (active) onError(error);
    } finally {
      inFlight = false;
    }
  };

  void poll();
  const timer = window.setInterval(poll, intervalMs);
  return () => {
    active = false;
    window.clearInterval(timer);
  };
}

/**
 * Polls the minimal protected state a seated player may see. The caller gets
 * public game/player state plus only their own hand; no other hand is queried.
 * heartbeat is intentionally piggybacked here so bot takeover and reconnect
 * work whenever the game view is open.
 */
export function subscribeToGameState(
  gameId,
  playerId,
  onSnapshot,
  onError = noop,
  {
    intervalMs = GAME_SYNC_INTERVAL_MS,
    heartbeatIntervalMs = HEARTBEAT_INTERVAL_MS,
  } = {},
) {
  let active = true;
  let inFlight = false;
  let lastHeartbeatAt = 0;
  let lastFingerprint = null;

  const poll = async () => {
    if (!active || inFlight) return;
    inFlight = true;
    try {
      const now = Date.now();
      if (now - lastHeartbeatAt >= heartbeatIntervalMs) {
        await heartbeat(gameId, playerId);
        lastHeartbeatAt = now;
      }

      const [game, players, hand] = await Promise.all([
        getGame(gameId),
        getGamePlayers(gameId),
        getHand(gameId, playerId),
      ]);
      const snapshot = { game, players, hand };
      const fingerprint = JSON.stringify(snapshot);
      if (fingerprint !== lastFingerprint) {
        lastFingerprint = fingerprint;
        onSnapshot(snapshot);
      }
    } catch (error) {
      if (active) onError(error);
    } finally {
      inFlight = false;
    }
  };

  void poll();
  const timer = window.setInterval(poll, intervalMs);
  return () => {
    active = false;
    window.clearInterval(timer);
  };
}
