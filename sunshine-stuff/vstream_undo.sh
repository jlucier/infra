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
echo "  Target: ${TARGET_OUT:-<not set>} (rot: ${TARGET_ROT:-?}, pos: ${TARGET_POS:-?}, mode: ${TARGET_MODE:-?})"
echo "  Other: ${OTHER_OUT:-<not set>} (rot: ${OTHER_ROT:-?}, pos: ${OTHER_POS:-?}, mode: ${OTHER_MODE:-?})"

# Stop Steam if it still runs.
pkill -TERM -f "steam -gamepadui" 2>/dev/null || true

# Build one kscreen-doctor command that restores everything. The order counts.
# Enable the output first, then configure it.
KS_ARGS=()

# Enable the other output.
[[ -n "${OTHER_OUT:-}" ]] && KS_ARGS+=("output.$OTHER_OUT.enable")

# Restore the settings of the other output.
[[ -n "${OTHER_OUT:-}" && -n "${OTHER_MODE:-}" ]] && KS_ARGS+=("output.$OTHER_OUT.mode.$OTHER_MODE")
[[ -n "${OTHER_OUT:-}" && -n "${OTHER_POS:-}" ]] && KS_ARGS+=("output.$OTHER_OUT.position.$OTHER_POS")
[[ -n "${OTHER_OUT:-}" && -n "${OTHER_ROT:-}" ]] && KS_ARGS+=("output.$OTHER_OUT.rotation.$OTHER_ROT")
[[ -n "${OTHER_OUT:-}" && -n "${OTHER_SCALE:-}" ]] && KS_ARGS+=("output.$OTHER_OUT.scale.$OTHER_SCALE")

# Restore the settings of the target output.
[[ -n "${TARGET_OUT:-}" && -n "${TARGET_MODE:-}" ]] && KS_ARGS+=("output.$TARGET_OUT.mode.$TARGET_MODE")
[[ -n "${TARGET_OUT:-}" && -n "${TARGET_POS:-}" ]] && KS_ARGS+=("output.$TARGET_OUT.position.$TARGET_POS")
[[ -n "${TARGET_OUT:-}" && -n "${TARGET_ROT:-}" ]] && KS_ARGS+=("output.$TARGET_OUT.rotation.$TARGET_ROT")
[[ -n "${TARGET_OUT:-}" && -n "${TARGET_SCALE:-}" ]] && KS_ARGS+=("output.$TARGET_OUT.scale.$TARGET_SCALE")

# Set the primary output last.
[[ -n "${PRIMARY_OUT:-}" ]] && KS_ARGS+=("output.$PRIMARY_OUT.primary")

if [[ ${#KS_ARGS[@]} -gt 0 ]]; then
  echo "Running: kscreen-doctor ${KS_ARGS[*]}"
  kscreen-doctor "${KS_ARGS[@]}"
fi

rm -f "$STATE_FILE"
echo "Restored display configuration."
