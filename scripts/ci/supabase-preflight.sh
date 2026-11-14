#!/usr/bin/env bash
set -Eeuo pipefail

log() { printf '[supabase-preflight] %s\n' "$*"; }
fail() { log "ERROR: $*"; exit 1; }

command -v docker >/dev/null 2>&1 || fail "Docker CLI is not installed."
command -v supabase >/dev/null 2>&1 || fail "Supabase CLI is not installed."
docker info >/dev/null 2>&1 || fail "Docker daemon is unavailable; refusing to continue."

# Remove only this repository's stale Supabase stack. Do not kill arbitrary
# processes or prune global Docker resources on a shared/hosted runner.
log "Stopping any stale Supabase stack for this project."
supabase stop --no-backup >/dev/null 2>&1 || true

# Supabase's default local API/database/studio ports. Report the owning process
# rather than killing it: a port may belong to an unrelated runner service.
ports=(54321 54322 54323 54324 54325 54327 54328 54329)
if command -v ss >/dev/null 2>&1; then
  for port in "${ports[@]}"; do
    if ss -ltnH "sport = :$port" | grep -q .; then
      log "Port $port is already in use:"
      ss -ltnp "sport = :$port" || true
      fail "Port conflict detected. No unrelated process was terminated."
    fi
  done
fi

log "Docker daemon healthy; no default Supabase port conflicts detected."
