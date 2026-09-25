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
import { CONFIG } from "./config.js";

const views = {
  home: document.getElementById("view-home"),
  lobby: document.getElementById("view-lobby"),
  error: document.getElementById("view-error"),
};

function showView(name) {
  for (const [key, el] of Object.entries(views)) {
    el.hidden = key !== name;
  }
}

function showErrorView(message) {
  document.getElementById("error-message").textContent = message;
  showView("error");
}

function enterLobby(roomId, code) {
  teardownLobbyView();
  showView("lobby");
  initLobbyView(roomId, code);
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
      showErrorView("Could not check this room right now. Please try again.");
      return;
    }

    if (!room) {
      showErrorView("This room code doesn't exist. Check the link and try again.");
      return;
    }

    if (room.player_count >= (room.max_players || CONFIG.MAX_PLAYERS_PER_ROOM)) {
      showErrorView(`This room is full (max ${room.max_players} players).`);
      return;
    }
  }

  showView("home");
  initHomeView((roomId, code) => enterLobby(roomId, code), urlCode);
}

boot();
