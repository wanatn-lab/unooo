// ---------------------------------------------------------------------------
// Home view: create a room, or join one by code.
// Only handles DOM wiring for this view — all Supabase logic lives in
// roomApi.js.
// ---------------------------------------------------------------------------
import { createRoom, joinRoom } from "./roomApi.js";
import { saveSession } from "./session.js";

/**
 * Wires up the Home view's buttons.
 * @param {(roomId: string, code: string, playerId: string, name: string) => void} onEnterRoom
 *   called after a successful create/join, so main.js can switch to the Lobby view.
 * @param {string|null} prefillCode room code to pre-fill the Join box with (from a shared link)
 */
export function initHomeView(onEnterRoom, prefillCode) {
  const errorEl = document.getElementById("home-error");
  const joinCodeInput = document.getElementById("join-code");

  if (prefillCode) joinCodeInput.value = prefillCode;

  function showError(message) {
    errorEl.textContent = message;
    errorEl.hidden = false;
  }

  function clearError() {
    errorEl.hidden = true;
  }

  document.getElementById("btn-create-room").addEventListener("click", async () => {
    clearError();
    const name = document.getElementById("create-name").value.trim();
    if (!name) return showError("Please enter your name.");

    try {
      const { roomId, code, playerId, accessToken } = await createRoom(name);
      saveSession({ roomId, code, playerId, name, accessToken });
      onEnterRoom(roomId, code, playerId, name);
    } catch (err) {
      showError(err.message);
    }
  });

  document.getElementById("btn-join-room").addEventListener("click", async () => {
    clearError();
    const name = document.getElementById("join-name").value.trim();
    const code = joinCodeInput.value.trim().toUpperCase();

    if (!name) return showError("Please enter your name.");
    if (!/^[A-Z0-9]{6}$/.test(code)) return showError("Room codes are 6 characters, e.g. ABC123.");

    try {
      const { roomId, playerId, accessToken } = await joinRoom(code, name);
      saveSession({ roomId, code, playerId, name, accessToken });
      onEnterRoom(roomId, code, playerId, name);
    } catch (err) {
      showError(err.message);
    }
  });
}
