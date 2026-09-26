// ---------------------------------------------------------------------------
// Shared decorative avatar list. A player keeps the same avatar in the
// Lobby view and the Game Table view because both index into this same
// array by the player's position (Lobby: index in join order; Game Table:
// seat_order, which is assigned in join order at deal time — see the
// comment in backend/supabase/migrations/0004_phase2_game_logic.sql).
// Purely cosmetic — carries no game state.
// ---------------------------------------------------------------------------
export const AVATARS = [
  { file: "nari.webp", glow: "#ff5abf" },
  { file: "sol.webp", glow: "#51e5ff" },
  { file: "wren.webp", glow: "#d9ff52" },
  { file: "imani.webp", glow: "#ffb55d" },
  { file: "farah.webp", glow: "#a374ff" },
  { file: "aya.webp", glow: "#77b7ff" },
  { file: "bao.webp", glow: "#ff7d8e" },
  { file: "zero.webp", glow: "#f5efff" },
];

export function avatarFor(index) {
  return AVATARS[index % AVATARS.length];
}
