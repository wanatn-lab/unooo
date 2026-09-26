// ---------------------------------------------------------------------------
// Game Table view (Phase 4): renders the table and wires play/draw/pass/
// UNO actions to the protected RPCs. This file ONLY does DOM/rendering and
// calls into gameApi.js / gameSync.js — it never talks to Supabase
// directly, never decides whether a move is legal, and never touches
// Postgres Changes/Realtime (see backend/README.md, Phase 3, for why: this
// app uses non-JWT capability tokens, so state sync is protected polling).
//
// Every action (play/draw/pass/call UNO/catch UNO) is sent to the server
// and the server's response is authoritative. Where an RPC hands back the
// new state directly (play_card, pass_turn, call_uno, catch_uno_failure all
// return the row they just changed), this file applies that immediately so
// the UI feels instant instead of waiting for the next ~2s poll. The next
// poll (subscribeToGameState) always reconciles with the real server state
// afterwards, so a stale local guess can't drift for long.
// ---------------------------------------------------------------------------
import { getPlayers } from "./roomApi.js";
import { getSession } from "./session.js";
import {
  playCard,
  drawCard,
  passTurn,
  callUno,
  catchUnoFailure,
} from "./gameApi.js";
import { subscribeToGameState } from "./gameSync.js";
import { avatarFor } from "./avatars.js";

const COLOR_LABEL = { red: "Red", yellow: "Yellow", green: "Green", blue: "Blue" };
const VALUE_LABEL = { skip: "⦸", reverse: "⇄", draw2: "+2", wild: "★", wild4: "+4" };

let unsubscribeGameState = null;
let roomId = null;
let gameId = null;
let myPlayerId = null;
let roster = new Map(); // player_id -> { name, is_host }
let snapshot = null; // { game, players, hand } — latest known state
let toastTimer = null;
let errorTimer = null;

function cardValueLabel(card) {
  return VALUE_LABEL[card.value] ?? card.value;
}

function cardColorClass(card) {
  return `card-${card.color}`;
}

function cardAriaLabel(card) {
  const value = card.value in VALUE_LABEL
    ? { skip: "Skip", reverse: "Reverse", draw2: "Draw 2", wild: "Wild", wild4: "Wild Draw 4" }[card.value]
    : card.value;
  return card.color === "wild" ? value : `${COLOR_LABEL[card.color] ?? card.color} ${value}`;
}

function buildCardEl(card, { small = false } = {}) {
  const el = document.createElement(small ? "li" : "div");
  el.className = `card ${cardColorClass(card)}${small ? " hand-card" : ""}`;
  el.setAttribute("aria-label", cardAriaLabel(card));
  const value = document.createElement("span");
  value.className = "card-value";
  value.textContent = cardValueLabel(card);
  el.appendChild(value);
  return el;
}

function topDiscard() {
  const pile = snapshot?.game?.discard_pile ?? [];
  return pile.length ? pile[pile.length - 1] : null;
}

function isPlayableClientSide(card) {
  const top = topDiscard();
  if (!top || !snapshot?.game) return false;
  return card.color === "wild" || card.color === snapshot.game.current_color || card.value === top.value;
}

function myGamePlayer() {
  return snapshot?.players?.find((p) => p.player_id === myPlayerId) ?? null;
}

function canAct() {
  if (!snapshot?.game) return false;
  const me = myGamePlayer();
  return (
    snapshot.game.status === "in_progress" &&
    snapshot.game.turn_player_id === myPlayerId &&
    !(me?.is_bot)
  );
}

function playerName(playerId) {
  return roster.get(playerId)?.name ?? "Player";
}

function showToast(message) {
  const el = document.getElementById("game-toast");
  if (!el) return;
  window.clearTimeout(toastTimer);
  el.textContent = message;
  el.hidden = false;
  toastTimer = window.setTimeout(() => { el.hidden = true; }, 4000);
}

function showActionError(message) {
  const el = document.getElementById("game-action-error");
  if (!el) return;
  window.clearTimeout(errorTimer);
  el.textContent = message;
  el.hidden = false;
  errorTimer = window.setTimeout(() => { el.hidden = true; }, 5000);
}

function showReconnectBanner(show) {
  const el = document.getElementById("game-reconnect-banner");
  if (el) el.hidden = !show;
}

// ---- Wild color picker + UNO confirm: small promise-based modals ----

function pickColor() {
  return new Promise((resolve) => {
    const modal = document.getElementById("color-picker");
    modal.hidden = false;
    const cleanup = (result) => {
      modal.hidden = true;
      modal.querySelectorAll(".color-option").forEach((btn) => (btn.onclick = null));
      document.getElementById("color-picker-cancel").onclick = null;
      resolve(result);
    };
    modal.querySelectorAll(".color-option").forEach((btn) => {
      btn.onclick = () => cleanup(btn.dataset.color);
    });
    document.getElementById("color-picker-cancel").onclick = () => cleanup(null);
  });
}

function confirmUnoCall() {
  return new Promise((resolve) => {
    const modal = document.getElementById("uno-confirm");
    modal.hidden = false;
    const cleanup = (result) => {
      modal.hidden = true;
      document.getElementById("uno-confirm-yes").onclick = null;
      document.getElementById("uno-confirm-no").onclick = null;
      resolve(result);
    };
    document.getElementById("uno-confirm-yes").onclick = () => cleanup(true);
    document.getElementById("uno-confirm-no").onclick = () => cleanup(false);
  });
}

// ---- Actions ----

async function handleHandCardClick(card) {
  if (!canAct()) {
    showActionError("It's not your turn.");
    return;
  }

  let chosenColor = null;
  if (card.color === "wild") {
    chosenColor = await pickColor();
    if (!chosenColor) return; // cancelled
  }

  let declareUno = false;
  if ((snapshot.hand?.length ?? 0) === 2) {
    declareUno = await confirmUnoCall();
  }

  try {
    const updatedGame = await playCard(gameId, myPlayerId, card, { chosenColor, declareUno });
    // Optimistic local update — the next poll reconciles the rest (e.g. an
    // opponent forced to draw by this Draw 2 / Wild Draw 4).
    snapshot.game = updatedGame;
    snapshot.hand = snapshot.hand.filter((c) => !(c.color === card.color && c.value === card.value));
    const me = myGamePlayer();
    if (me) {
      me.hand_count = snapshot.hand.length;
      me.said_uno = snapshot.hand.length === 1 ? declareUno : false;
    }
    render();
  } catch (error) {
    showActionError(error.message);
  }
}

async function handleDrawPile() {
  if (!canAct() || snapshot.game.has_drawn_this_turn) return;
  try {
    const { card, playable } = await drawCard(gameId, myPlayerId);
    snapshot.hand = [...snapshot.hand, card];
    snapshot.game = { ...snapshot.game, has_drawn_this_turn: true };
    const me = myGamePlayer();
    if (me) me.hand_count = snapshot.hand.length;
    showToast(playable
      ? `You drew ${cardAriaLabel(card)} — you can play it or pass.`
      : `You drew ${cardAriaLabel(card)} — it doesn't match, so you'll need to pass.`);
    render();
  } catch (error) {
    showActionError(error.message);
  }
}

async function handlePassTurn() {
  if (!canAct() || !snapshot.game.has_drawn_this_turn) return;
  try {
    snapshot.game = await passTurn(gameId, myPlayerId);
    render();
  } catch (error) {
    showActionError(error.message);
  }
}

async function handleCallUno() {
  try {
    const updated = await callUno(gameId, myPlayerId);
    const me = myGamePlayer();
    if (me) Object.assign(me, updated);
    showToast("UNO called!");
    render();
  } catch (error) {
    showActionError(error.message);
  }
}

async function handleCatch(targetId) {
  try {
    const updated = await catchUnoFailure(gameId, myPlayerId, targetId);
    const target = snapshot.players.find((p) => p.player_id === targetId);
    if (target) Object.assign(target, updated);
    showToast(`Caught ${playerName(targetId)} — they draw penalty cards.`);
    render();
  } catch (error) {
    showActionError(error.message);
  }
}

// ---- Rendering ----

function orderedOpponents() {
  const players = snapshot?.players ?? [];
  const me = myGamePlayer();
  if (!me || players.length < 2) return [];
  const n = players.length;
  return players
    .filter((p) => p.player_id !== myPlayerId)
    .map((p) => ({ p, rel: (p.seat_order - me.seat_order + n) % n }))
    .sort((a, b) => a.rel - b.rel)
    .map((entry) => entry.p);
}

function renderOpponents() {
  const list = document.getElementById("opponent-ring");
  list.innerHTML = "";

  orderedOpponents().forEach((player) => {
    const avatar = avatarFor(player.seat_order);
    const li = document.createElement("li");
    li.className = "player-tile opponent-tile";
    li.style.setProperty("--glow", avatar.glow);
    if (player.player_id === snapshot.game.turn_player_id) li.classList.add("is-turn");

    const img = document.createElement("img");
    img.className = "avatar";
    img.src = `assets/avatars/${avatar.file}`;
    img.alt = "";
    li.appendChild(img);

    const name = document.createElement("b");
    name.textContent = playerName(player.player_id);
    li.appendChild(name);

    const badges = document.createElement("div");
    badges.className = "opponent-badges";
    const handBadge = document.createElement("span");
    handBadge.className = "badge";
    handBadge.textContent = player.hand_count === 1 ? "1 card" : `${player.hand_count} cards`;
    badges.appendChild(handBadge);
    if (player.is_bot) {
      const botBadge = document.createElement("span");
      botBadge.className = "badge badge-warn";
      botBadge.textContent = "Bot";
      badges.appendChild(botBadge);
    } else if (!player.connected) {
      const offBadge = document.createElement("span");
      offBadge.className = "badge badge-warn";
      offBadge.textContent = "Away";
      badges.appendChild(offBadge);
    }
    if (player.said_uno) {
      const unoBadge = document.createElement("span");
      unoBadge.className = "badge badge-uno";
      unoBadge.textContent = "UNO!";
      badges.appendChild(unoBadge);
    }
    li.appendChild(badges);

    if (player.hand_count === 1 && !player.said_uno && snapshot.game.status === "in_progress") {
      const catchBtn = document.createElement("button");
      catchBtn.type = "button";
      catchBtn.className = "btn btn-secondary catch-btn";
      catchBtn.textContent = "Catch!";
      catchBtn.onclick = () => handleCatch(player.player_id);
      li.appendChild(catchBtn);
    }

    list.appendChild(li);
  });
}

function renderHand() {
  const list = document.getElementById("my-hand");
  list.innerHTML = "";
  const active = canAct();

  (snapshot.hand ?? []).forEach((card) => {
    const el = buildCardEl(card, { small: true });
    const playable = active && isPlayableClientSide(card);
    el.classList.toggle("is-playable", playable);
    el.classList.toggle("is-dim", active && !playable);
    el.setAttribute("role", "button");
    el.tabIndex = 0;
    el.onclick = () => handleHandCardClick(card);
    el.onkeydown = (event) => {
      if (event.key === "Enter" || event.key === " ") {
        event.preventDefault();
        handleHandCardClick(card);
      }
    };
    list.appendChild(el);
  });
}

function renderCenter() {
  const top = topDiscard();
  const discardEl = document.getElementById("discard-pile");
  discardEl.innerHTML = "";
  discardEl.className = "card";
  if (top) {
    discardEl.classList.add(cardColorClass(top));
    const value = document.createElement("span");
    value.className = "card-value";
    value.textContent = cardValueLabel(top);
    discardEl.appendChild(value);
  }

  const chip = document.getElementById("current-color-chip");
  const color = snapshot.game.current_color;
  chip.className = "color-chip";
  if (color) chip.classList.add(`swatch-${color}`);
  document.getElementById("current-color-label").textContent = color ? COLOR_LABEL[color] : "Color";

  const drawBtn = document.getElementById("draw-pile");
  drawBtn.disabled = !canAct() || snapshot.game.has_drawn_this_turn;
}

function renderTurnBar() {
  const turnEl = document.getElementById("turn-indicator");
  const dirEl = document.getElementById("direction-indicator");
  const { game } = snapshot;

  if (game.status === "finished") {
    turnEl.textContent = "Game over";
  } else if (game.turn_player_id === myPlayerId) {
    turnEl.textContent = game.has_drawn_this_turn ? "Your turn — play or pass" : "Your turn!";
  } else {
    turnEl.textContent = `${playerName(game.turn_player_id)}'s turn`;
  }

  dirEl.textContent = game.direction === 1 ? "↻" : "↺";
  dirEl.setAttribute("aria-label", game.direction === 1 ? "Turn order: clockwise" : "Turn order: counter-clockwise");
}

function renderActionBar() {
  const me = myGamePlayer();
  const passBtn = document.getElementById("btn-pass-turn");
  passBtn.hidden = !(canAct() && snapshot.game.has_drawn_this_turn);

  const unoBtn = document.getElementById("btn-call-uno");
  unoBtn.hidden = !(snapshot.game.status === "in_progress" && (snapshot.hand?.length ?? 0) === 1 && !me?.said_uno);
}

function renderGameOver() {
  const overlay = document.getElementById("game-over");
  if (snapshot.game.status !== "finished") {
    overlay.hidden = true;
    return;
  }
  overlay.hidden = false;
  const title = document.getElementById("game-over-title");
  title.textContent = snapshot.game.winner_id === myPlayerId
    ? "You win! 🎉"
    : `${playerName(snapshot.game.winner_id)} wins!`;

  // Nothing left to do once the game is over — stop polling.
  if (unsubscribeGameState) {
    unsubscribeGameState();
    unsubscribeGameState = null;
  }
}

function render() {
  if (!snapshot) return;
  document.getElementById("game-loading").hidden = true;
  document.getElementById("game-content").hidden = false;

  const botBanner = document.getElementById("game-bot-banner");
  botBanner.hidden = !myGamePlayer()?.is_bot;

  renderTurnBar();
  renderOpponents();
  renderCenter();
  renderHand();
  renderActionBar();
  renderGameOver();
}

/**
 * Wires up the Game Table view and starts protected state polling.
 * `initialGameId` only needs to carry the game's id — this view fetches
 * its own full state via gameSync.js rather than trusting the caller's copy.
 */
export async function initGameView(roomIdArg, code, initialGame) {
  teardownGameView();

  roomId = roomIdArg;
  gameId = initialGame.id;
  const session = getSession();
  myPlayerId = session?.playerId ?? null;

  document.getElementById("game-loading").hidden = false;
  document.getElementById("game-content").hidden = true;
  document.getElementById("game-reconnect-banner").hidden = true;
  document.getElementById("game-bot-banner").hidden = true;
  document.getElementById("game-action-error").hidden = true;
  document.getElementById("game-toast").hidden = true;

  document.getElementById("draw-pile").onclick = handleDrawPile;
  document.getElementById("btn-pass-turn").onclick = handlePassTurn;
  document.getElementById("btn-call-uno").onclick = handleCallUno;
  document.getElementById("btn-leave-game").onclick = () => {
    window.location.href = "/";
  };

  try {
    const players = await getPlayers(roomId);
    roster = new Map(players.map((p) => [p.id, { name: p.name, is_host: p.is_host }]));
  } catch {
    roster = new Map();
  }

  if (!myPlayerId) {
    showActionError("Your player session is missing. Leave and rejoin the room.");
    return;
  }

  unsubscribeGameState = subscribeToGameState(
    gameId,
    myPlayerId,
    (freshSnapshot) => {
      snapshot = freshSnapshot;
      showReconnectBanner(false);
      render();
    },
    () => showReconnectBanner(true),
  );
}

export function teardownGameView() {
  if (unsubscribeGameState) unsubscribeGameState();
  unsubscribeGameState = null;
  window.clearTimeout(toastTimer);
  window.clearTimeout(errorTimer);
  snapshot = null;
  roster = new Map();
  gameId = null;
  myPlayerId = null;
  document.getElementById("color-picker")?.setAttribute("hidden", "");
  document.getElementById("uno-confirm")?.setAttribute("hidden", "");
  document.getElementById("game-over")?.setAttribute("hidden", "");
}
