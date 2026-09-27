// ---------------------------------------------------------------------------
// Entry point: decides which of the 3 views to show, then hands off to that
// view's own module. Views are plain <section>s in index.html, toggled by
// the [hidden] attribute — no framework/router library needed for 3 screens.
// ---------------------------------------------------------------------------
import { getRoomCodeFromUrl } from "./router.js";
import { getSession } from "./session.js";
import { getRoomByCode } from "./roomApi.js";
import { initHomeView } from "./home.js";
import { initLobbyView, teardownLobbyView } from "./lobby.js";
import { initGameView, teardownGameView } from "./game.js";
import { CONFIG } from "./config.js";

const views = {
  home: document.getElementById("view-home"),
  lobby: document.getElementById("view-lobby"),
  game: document.getElementById("view-game"),
  error: document.getElementById("view-error"),
};

function showView(name) {
  for (const [key, el] of Object.entries(views)) {
    el.hidden = key !== name;
  }
  // The game table needs more width than the narrow lobby/home cards do —
  // scoped to a body class so it only affects .app while this view is shown.
  document.body.classList.toggle("in-game", name === "game");
}

function showErrorView(message) {
  document.getElementById("error-message").textContent = message;
  showView("error");
}

function enterLobby(roomId, code) {
  teardownGameView();
  teardownLobbyView();
  showView("lobby");
  initLobbyView(roomId, code, (game) => enterGame(roomId, code, game));
}

function enterGame(roomId, code, game) {
  teardownLobbyView();
  showView("game");
  void initGameView(roomId, code, game);
}

async function boot() {
  const session = getSession();
  const urlCode = getRoomCodeFromUrl();

  // Already in this room this tab (e.g. page refresh in the lobby) — go
  // straight back in without joining again.
  if (session && (!urlCode || urlCode === session.code)) {
    enterLobby(session.roomId, session.code);
    return;
  }

  // Arrived via a shared invite link: verify the room before asking for a
  // name, so a dead/expired link fails clearly instead of after typing.
  if (urlCode) {
    let room;
    try {
      room = await getRoomByCode(urlCode);
    } catch {
      showErrorView("ตรวจสอบห้องนี้ไม่สำเร็จตอนนี้ กรุณาลองใหม่อีกครั้ง");
      return;
    }

    if (!room) {
      showErrorView("ไม่พบรหัสห้องนี้ กรุณาตรวจสอบลิงก์แล้วลองใหม่");
      return;
    }

    if (room.player_count >= (room.max_players || CONFIG.MAX_PLAYERS_PER_ROOM)) {
      showErrorView(`ห้องนี้เต็มแล้ว (สูงสุด ${room.max_players} คน)`);
      return;
    }
  }

  showView("home");
  initHomeView((roomId, code) => enterLobby(roomId, code), urlCode);
}

boot();
