// ---------------------------------------------------------------------------
// Lobby view: shows the room code, invite link, and the live player list.
// Only handles DOM/rendering for this view — all Supabase logic lives in
// roomApi.js.
// ---------------------------------------------------------------------------
import { getPlayers, subscribeToPlayers } from "./roomApi.js";
import { CONFIG } from "./config.js";
import { clearSession, getSession } from "./session.js";
import { startGame } from "./gameApi.js";

let unsubscribe = null;
let startInProgress = false;
let gameStarted = false;

// Decorative only — Phase 1 has no character-select step yet (that's a
// later phase per the project README), so each player just gets one of
// these avatars assigned by their position in the room, purely for the
// party visual. --glow drives that tile's border/shadow color (set in css).
const AVATARS = [
  { file: "nari.webp", glow: "#ff5abf" },
  { file: "sol.webp", glow: "#51e5ff" },
  { file: "wren.webp", glow: "#d9ff52" },
  { file: "imani.webp", glow: "#ffb55d" },
  { file: "farah.webp", glow: "#a374ff" },
  { file: "aya.webp", glow: "#77b7ff" },
  { file: "bao.webp", glow: "#ff7d8e" },
  { file: "zero.webp", glow: "#f5efff" },
];

async function renderPlayers(roomId) {
  const players = await getPlayers(roomId);
  const list = document.getElementById("player-list");
  list.innerHTML = "";

  players.forEach((player, index) => {
    const avatar = AVATARS[index % AVATARS.length];

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
  if (status) {
    status.textContent =
      players.length >= CONFIG.MAX_PLAYERS_PER_ROOM
        ? "Room is full — ready to start"
        : `${players.length} of ${CONFIG.MAX_PLAYERS_PER_ROOM} echoes online`;
  }
}

/**
 * Wires up the Lobby view and starts the real-time player list.
 * Call the returned cleanup function when leaving this view.
 */
export function initLobbyView(roomId, code) {
  startInProgress = false;
  gameStarted = false;

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
      gameStarted = true;
      gameHint.textContent = "Game started.";
      feedback.textContent = "Game started successfully. The start-game RPC is connected; the card-table UI is not wired yet.";
      feedback.hidden = false;
      startButton.textContent = "Game started";
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
  unsubscribe = subscribeToPlayers(roomId, () => renderPlayers(roomId));

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
  if (unsubscribe) unsubscribe();
  document.getElementById("btn-start-game")?.remove();
  document.getElementById("lobby-game-hint")?.remove();
  document.getElementById("game-start-feedback")?.remove();
  unsubscribe = null;
}
