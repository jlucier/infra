#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/sunshine-stream"
STATE_FILE="$STATE_DIR/wayland_state.env"
mkdir -p "$STATE_DIR"

# Strip ANSI color codes from kscreen-doctor output
KS_OUTPUT="$(kscreen-doctor -o 2>&1 | sed 's/\x1b\[[0-9;]*m//g')"

# Map numeric rotation values to kscreen-doctor command names
rotation_num_to_name() {
  case "$1" in
    1) echo "none" ;;
    2) echo "left" ;;
    4) echo "inverted" ;;
    8) echo "right" ;;
    *) echo "none" ;;
  esac
}

# Parse all settings for a given output
# Sets: ${prefix}_ROT, ${prefix}_POS, ${prefix}_MODE, ${prefix}_SCALE
parse_output_settings() {
  local output_name="$1"
  local prefix="$2"
  local in_output=0
  local rot_num="" pos="" mode="" scale=""

  while IFS= read -r line; do
    if [[ "$line" =~ ^Output:.*\ $output_name\  ]]; then
      in_output=1
    elif [[ "$line" =~ ^Output: ]]; then
      in_output=0
    elif [[ $in_output -eq 1 ]]; then
      if [[ "$line" =~ Rotation:\ *([0-9]+) ]]; then
        rot_num="${BASH_REMATCH[1]}"
      elif [[ "$line" =~ Geometry:\ *([0-9]+,[0-9]+) ]]; then
        pos="${BASH_REMATCH[1]}"
      elif [[ "$line" =~ Scale:\ *([0-9.]+) ]]; then
        scale="${BASH_REMATCH[1]}"
      elif [[ "$line" =~ Modes:.*\ ([0-9]+):[0-9]+x[0-9]+@[0-9.]+\*! ]]; then
        # Capture mode index number (e.g., "1" from "1:3440x1440@59.97*!")
        mode="${BASH_REMATCH[1]}"
      fi
    fi
  done <<< "$KS_OUTPUT"

  printf -v "${prefix}_ROT" '%s' "$(rotation_num_to_name "${rot_num:-1}")"
  printf -v "${prefix}_POS" '%s' "$pos"
  printf -v "${prefix}_MODE" '%s' "$mode"
  printf -v "${prefix}_SCALE" '%s' "$scale"
}

# Find the current primary output (priority 1)
PRIMARY_OUT=""
current_output=""
while IFS= read -r line; do
  if [[ "$line" =~ ^Output:\ +[0-9]+\ +([^ ]+) ]]; then
    current_output="${BASH_REMATCH[1]}"
  elif [[ "$line" =~ priority\ 1 ]] && [[ -n "$current_output" ]]; then
    PRIMARY_OUT="$current_output"
    break
  fi
done <<< "$KS_OUTPUT"

if [[ -z "$PRIMARY_OUT" ]]; then
  PRIMARY_OUT="$(echo "$KS_OUTPUT" | awk '/^Output:/{print $3; exit}')"
fi

# Target is DP-2 (the 16:9 monitor you want to use for streaming)
TARGET_OUT="DP-2"
# Other output to disable during streaming
OTHER_OUT="DP-1"

# Capture full settings for both monitors
parse_output_settings "$TARGET_OUT" "TARGET"
parse_output_settings "$OTHER_OUT" "OTHER"

echo "Current state:"
echo "  Primary: $PRIMARY_OUT"
echo "  Target: $TARGET_OUT (rot: $TARGET_ROT, pos: $TARGET_POS, mode: $TARGET_MODE, scale: $TARGET_SCALE)"
echo "  Other: $OTHER_OUT (rot: $OTHER_ROT, pos: $OTHER_POS, mode: $OTHER_MODE, scale: $OTHER_SCALE)"
echo "  Will disable: $OTHER_OUT"

# Save state for undo
cat > "$STATE_FILE" <<EOF
PRIMARY_OUT=$PRIMARY_OUT
TARGET_OUT=$TARGET_OUT
TARGET_ROT=$TARGET_ROT
TARGET_POS=$TARGET_POS
TARGET_MODE=$TARGET_MODE
TARGET_SCALE=$TARGET_SCALE
OTHER_OUT=$OTHER_OUT
OTHER_ROT=$OTHER_ROT
OTHER_POS=$OTHER_POS
OTHER_MODE=$OTHER_MODE
OTHER_SCALE=$OTHER_SCALE
EOF

# Rotate target monitor to landscape, make it primary, and disable other output
echo "Setting $TARGET_OUT to landscape and primary, disabling $OTHER_OUT..."
kscreen-doctor "output.$TARGET_OUT.rotation.none" "output.$TARGET_OUT.primary" "output.$OTHER_OUT.disable"

echo "Done. State saved to $STATE_FILE"
