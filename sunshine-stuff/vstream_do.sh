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

# Find the current primary output (priority 1)
# Output format: "Output: <num> <name> <uuid>" followed by "priority N" on next lines
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

# Fallback to first enabled output if no priority 1 found
if [[ -z "$PRIMARY_OUT" ]]; then
  PRIMARY_OUT="$(echo "$KS_OUTPUT" | awk '/^Output:/{print $3; exit}')"
fi

# Target is DP-2 (the 16:9 monitor you want to use for streaming)
TARGET_OUT="DP-2"

# Get current rotation for TARGET_OUT
TARGET_ROT_NUM=""
in_target=0
while IFS= read -r line; do
  if [[ "$line" =~ ^Output:.*\ $TARGET_OUT\  ]]; then
    in_target=1
  elif [[ "$line" =~ ^Output: ]]; then
    in_target=0
  elif [[ $in_target -eq 1 ]] && [[ "$line" =~ Rotation:\ *([0-9]+) ]]; then
    TARGET_ROT_NUM="${BASH_REMATCH[1]}"
    break
  fi
done <<< "$KS_OUTPUT"

TARGET_ROT="$(rotation_num_to_name "${TARGET_ROT_NUM:-1}")"

echo "Current state:"
echo "  Primary: $PRIMARY_OUT"
echo "  Target: $TARGET_OUT (rotation: $TARGET_ROT)"

# Save state for undo
cat > "$STATE_FILE" <<EOF
PRIMARY_OUT=$PRIMARY_OUT
TARGET_OUT=$TARGET_OUT
TARGET_ROT=$TARGET_ROT
EOF

# Rotate target monitor to landscape and make it primary
echo "Setting $TARGET_OUT to landscape and primary..."
kscreen-doctor "output.$TARGET_OUT.rotation.none" "output.$TARGET_OUT.primary"

echo "Done. State saved to $STATE_FILE"
