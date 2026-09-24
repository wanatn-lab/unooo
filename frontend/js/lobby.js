// ---------------------------------------------------------------------------
// Lobby view: shows the room code, invite link, and the live player list.
// Only handles DOM/rendering for this view — all Supabase logic lives in
// roomApi.js.
// ---------------------------------------------------------------------------
import { getPlayers, subscribeToPlayers } from "./roomApi.js";
import { CONFIG } from "./config.js";
import { clearSession } from "./session.js";

let unsubscribe = null;

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
  unsubscribe = null;
}
