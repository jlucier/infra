#! /bin/bash
set -u

INPUT="${INPUT:-/data/input.txt}"
ARCHIVE="${ARCHIVE:-/data/archive.txt}"
OUTPUT_DIR="${OUTPUT_DIR:-/downloads}"
SLEEP="${SLEEP:-3600}"
POT_BASE_URL="${POT_BASE_URL:-http://[::1]:4416}"
COOKIES="${COOKIES:-/sync/cookies.txt}"

EXTRA_ARGS=(
  --extractor-args "youtubepot-bgutilhttp:base_url=$POT_BASE_URL"
  --remote-components ejs:github
)

if [ -s "$COOKIES" ]; then
  EXTRA_ARGS+=(--cookies "$COOKIES")
  echo "[ytdlp] using cookies from $COOKIES"
fi

cd "$OUTPUT_DIR"

check_vpn() {
  local ip
  ip="$(curl -fsS --max-time 10 https://ipecho.net/plain 2>/dev/null)"
  if [ -z "$ip" ]; then
    echo "[ytdlp] connectivity check FAILED (no response)"
    return 1
  fi
  echo "[ytdlp] external IP: $ip"
  return 0
}

while true; do
  if ! check_vpn; then
    echo "[ytdlp] skipping run, sleeping ${SLEEP}s"
    sleep "$SLEEP"
    continue
  fi

  if [ -s "$INPUT" ]; then
    echo "[ytdlp] $(date -Is) running"
    yt-dlp \
      -a "$INPUT" \
      --download-archive "$ARCHIVE" \
      --embed-thumbnail \
      -o "%(playlist_title)s/%(title)s.%(ext)s" \
      "${EXTRA_ARGS[@]}" \
      || echo "[ytdlp] yt-dlp exited non-zero"
  else
    echo "[ytdlp] $(date -Is) input missing or empty, skipping"
  fi
  echo "[ytdlp] sleeping ${SLEEP}s"
  sleep "$SLEEP"
done
