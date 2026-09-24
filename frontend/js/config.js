// ---------------------------------------------------------------------------
// App configuration — the ONLY place hardcoded values should live.
// If you need to change the max player count, the Supabase project, etc,
// change it here, not inside logic files.
// ---------------------------------------------------------------------------

export const CONFIG = {
  // Supabase project connection.
  // The anon/publishable key is safe to expose in frontend code — it is
  // restricted by the Row Level Security policies defined in
  // backend/supabase/migrations/*.sql. Never put a service_role key here.
  SUPABASE_URL: "https://asjxgsaxdngbqjzcxoxn.supabase.co",
  SUPABASE_ANON_KEY:
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFzanhnc2F4ZG5nYnFqemN4b3huIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTAyNjIyNDMsImV4cCI6MjEwNTgzODI0M30.j8rlKFt12Lovw73iZ0S6CBScLZvKsxfS6exhZcTOhc4",

  // Room rules
  MAX_PLAYERS_PER_ROOM: 8,

  // How the shareable room link is built. With no custom domain yet this is
  // just the current site origin + /room/<CODE>.
  roomLink(code) {
    return `${window.location.origin}/room/${code}`;
  },
};
