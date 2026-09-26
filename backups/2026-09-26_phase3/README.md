# Phase 3 closeout backup — 2026-09-26

This directory is the closeout backup required by PROJECT.md for Phase 3.

## Database changes backed up

- `0005_phase3_capability_security.sql`: capability-token security boundary.
- `0006_phase3_protected_state_sync.sql`: protected game discovery RPC.
- `0007_phase3_remove_smoke_test_room.sql` and
  `0008_phase3_remove_interrupted_smoke_room.sql`: narrowly scoped cleanup
  of two interrupted smoke-test setups, matching both name and token hash.
- `0009_phase3_production_smoke_test.sql`: two-seat production smoke test;
  it deletes its own room before commit.

Applied migration records in production include:
`phase3_capability_security`, `phase3_protected_state_sync`,
`phase3_remove_smoke_test_room`, `phase3_remove_interrupted_smoke_room`,
and `phase3_production_smoke_test`.

## Deployment configuration

`netlify.toml` is the snapshot of the production build setting. It publishes
the static `frontend` directory. Netlify production URL:
https://unooo-lobby.netlify.app

No secrets are stored in this backup.
