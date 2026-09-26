// ---------------------------------------------------------------------------
// Lobby view: shows the room code, invite link, and the live player list.
// Only handles DOM/rendering for this view — all Supabase logic lives in
// roomApi.js.
// ---------------------------------------------------------------------------
import { getPlayers, subscribeToPlayers } from "./roomApi.js";
import { CONFIG } from "./config.js";
import { clearSession, getSession } from "./session.js";
import { startGame } from "./gameApi.js";
import { subscribeToRoomGame } from "./gameSync.js";
import { avatarFor } from "./avatars.js";

let unsubscribePlayers = null;
let unsubscribeGameDiscovery = null;
let startInProgress = false;
let gameStarted = false;
let syncedGameId = null;
let onGameStarted = null;

async function renderPlayers(roomId) {
  const players = await getPlayers(roomId);
  const list = document.getElementById("player-list");
  list.innerHTML = "";

  players.forEach((player, index) => {
    const avatar = avatarFor(index);

    const li = document.createElement("li");
    li.className = "player-tile";
    li.style.setProperty("--glow", avatar.glow);

    const img = document.createElement("img");
    img.className = "avatar";
    img.src = `assets/avatars/${avatar.file}`;
    img.alt = "";
    li.appendChild(img);

    const name = document.createElement("b");
    name.textContent = player.name;
    li.appendChild(name);

    if (player.is_host) {
      const tag = document.createElement("span");
      tag.className = "host-tag";
      tag.textContent = "HOST";
      li.appendChild(tag);
    }

    list.appendChild(li);
  });

  document.getElementById("player-count").textContent = players.length;

  const session = getSession();
  const isHost = players.some((player) => player.id === session?.playerId && player.is_host);
  const startButton = document.getElementById("btn-start-game");
  const gameHint = document.getElementById("lobby-game-hint");
  if (startButton) {
    startButton.hidden = !isHost;
    startButton.disabled = players.length < 2 || startInProgress || gameStarted;
    startButton.textContent = gameStarted ? "Game started" : "Start Game";
  }
  if (gameHint && !gameStarted) {
    gameHint.textContent = isHost
      ? (players.length < 2 ? "Invite at least one player before starting." : "You're the host. Start when everyone's ready.")
      : "Waiting for the host to start the game…";
  }

  const status = document.getElementById("lobby-status");
  if (status && !gameStarted) {
    status.textContent =
      players.length >= CONFIG.MAX_PLAYERS_PER_ROOM
        ? "Room is full — ready to start"
        : `${players.length} of ${CONFIG.MAX_PLAYERS_PER_ROOM} echoes online`;
  }
}

// Once a game exists for this room, the Lobby's job is done — it hands off
// to the Game Table view (game.js), which does its own state sync. The
// Lobby does not poll game state itself.
function beginGameSync(game) {
  if (!game?.id || game.id === syncedGameId) return;

  gameStarted = true;
  syncedGameId = game.id;
  if (unsubscribeGameDiscovery) {
    unsubscribeGameDiscovery();
    unsubscribeGameDiscovery = null;
  }

  const startButton = document.getElementById("btn-start-game");
  if (startButton) {
    startButton.disabled = true;
    startButton.textContent = "Game started";
  }

  if (onGameStarted) onGameStarted(game);
}

/**
 * Wires up the Lobby view and starts the real-time player list.
 * `onStarted(game)` is called once a game exists for this room (whether
 * this tab started it or another player did) so main.js can switch to the
 * Game Table view. Call teardownLobbyView() when leaving this view.
 */
export function initLobbyView(roomId, code, onStarted) {
  startInProgress = false;
  gameStarted = false;
  syncedGameId = null;
  onGameStarted = onStarted ?? null;

  const lobby = document.getElementById("view-lobby");
  const leaveButton = document.getElementById("btn-leave-room");
  const oldHint = lobby.querySelector(".hint:not(#copy-feedback)");
  if (oldHint) oldHint.remove();

  const gameHint = document.createElement("p");
  gameHint.id = "lobby-game-hint";
  gameHint.className = "hint";
  gameHint.textContent = "Waiting for the host to start the game…";

  const startButton = document.createElement("button");
  startButton.id = "btn-start-game";
  startButton.className = "btn btn-primary";
  startButton.type = "button";
  startButton.textContent = "Start Game";
  startButton.hidden = true;
  startButton.disabled = true;

  const feedback = document.createElement("p");
  feedback.id = "game-start-feedback";
  feedback.className = "hint";
  feedback.setAttribute("role", "status");
  feedback.hidden = true;

  lobby.insertBefore(gameHint, leaveButton);
  lobby.insertBefore(startButton, leaveButton);
  lobby.insertBefore(feedback, leaveButton);

  startButton.onclick = async () => {
    const session = getSession();
    if (!session?.playerId) {
      feedback.textContent = "Your player session is missing. Leave and rejoin the room.";
      feedback.hidden = false;
      return;
    }

    startInProgress = true;
    startButton.disabled = true;
    feedback.hidden = true;

    try {
      const game = await startGame(roomId, session.playerId);
      beginGameSync(game);
      gameHint.textContent = "Game started — synchronizing every player now.";
      feedback.textContent = "Game started. Every seated player will detect and synchronize it automatically.";
      feedback.hidden = false;
    } catch (error) {
      feedback.textContent = error.message;
      feedback.hidden = false;
    } finally {
      startInProgress = false;
      renderPlayers(roomId);
    }
  };

  document.getElementById("lobby-code").textContent = code;
  document.getElementById("player-max").textContent = CONFIG.MAX_PLAYERS_PER_ROOM;

  renderPlayers(roomId);
  unsubscribePlayers = subscribeToPlayers(roomId, () => renderPlayers(roomId));

  const session = getSession();
  if (session?.playerId) {
    unsubscribeGameDiscovery = subscribeToRoomGame(
      roomId,
      session.playerId,
      (game) => {
        beginGameSync(game);
        const feedback = document.getElementById("game-start-feedback");
        if (feedback) {
          feedback.textContent = "The host started the game. State sync is active.";
          feedback.hidden = false;
        }
        void renderPlayers(roomId);
      },
      () => {
        const status = document.getElementById("lobby-status");
        if (status && !gameStarted) status.textContent = "Reconnecting room state…";
      },
    );
  }

  document.getElementById("btn-copy-link").onclick = async () => {
    const link = CONFIG.roomLink(code);
    try {
      await navigator.clipboard.writeText(link);
    } catch {
      window.prompt("Copy this link:", link);
    }
    const feedback = document.getElementById("copy-feedback");
    feedback.hidden = false;
    setTimeout(() => (feedback.hidden = true), 2000);
  };

  document.getElementById("btn-leave-room").onclick = () => {
    clearSession();
    window.location.href = "/";
  };
}

export function teardownLobbyView() {
  if (unsubscribePlayers) unsubscribePlayers();
  if (unsubscribeGameDiscovery) unsubscribeGameDiscovery();
  document.getElementById("btn-start-game")?.remove();
  document.getElementById("lobby-game-hint")?.remove();
  document.getElementById("game-start-feedback")?.remove();
  unsubscribePlayers = null;
  unsubscribeGameDiscovery = null;
  syncedGameId = null;
  onGameStarted = null;
}
