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
  --user-agent "Mozilla/5.0 (Macintosh; Intel Mac OS X 14.7; rv:128.0) Gecko/20100101 Firefox/128.0"
  --sleep-requests 1.5
  --min-sleep-interval 30
  --max-sleep-interval 90
)

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
    RUN_ARGS=("${EXTRA_ARGS[@]}")
    if [ -s "$COOKIES" ]; then
      RUN_ARGS+=(--cookies "$COOKIES")
    fi
    echo "[ytdlp] $(date -Is) running"
    yt-dlp \
      -a "$INPUT" \
      --download-archive "$ARCHIVE" \
      --embed-thumbnail \
      -o "%(playlist_title)s/%(title)s.%(ext)s" \
      "${RUN_ARGS[@]}" \
      || echo "[ytdlp] yt-dlp exited non-zero"
  else
    echo "[ytdlp] $(date -Is) input missing or empty, skipping"
  fi
  echo "[ytdlp] sleeping ${SLEEP}s"
  sleep "$SLEEP"
done
