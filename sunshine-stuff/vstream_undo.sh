#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/sunshine-stream"
STATE_FILE="$STATE_DIR/wayland_state.env"

if [[ ! -f "$STATE_FILE" ]]; then
  echo "No state file; nothing to undo."
  exit 0
fi

# shellcheck disable=SC1090
source "$STATE_FILE"

echo "Restoring state:"
echo "  Primary: ${PRIMARY_OUT:-<not set>}"
echo "  Target: ${TARGET_OUT:-<not set>} -> rotation: ${TARGET_ROT:-<not set>}"

# Kill Steam if still around (optional)
pkill -TERM -f "steam -gamepadui" 2>/dev/null || true

# Restore rotation and primary in one atomic call
if [[ -n "${TARGET_OUT:-}" && -n "${TARGET_ROT:-}" && -n "${PRIMARY_OUT:-}" ]]; then
  kscreen-doctor "output.$TARGET_OUT.rotation.$TARGET_ROT" "output.$PRIMARY_OUT.primary"
elif [[ -n "${TARGET_OUT:-}" && -n "${TARGET_ROT:-}" ]]; then
  kscreen-doctor "output.$TARGET_OUT.rotation.$TARGET_ROT"
elif [[ -n "${PRIMARY_OUT:-}" ]]; then
  kscreen-doctor "output.$PRIMARY_OUT.primary"
fi

rm -f "$STATE_FILE"
echo "Restored display configuration."
