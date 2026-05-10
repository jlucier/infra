# infra

## Dependencies

```
ansible-galaxy install -r requirements.yml
```

## Notes

- For resolution of the fqdn of the main server, we use a custom dnsmasq.d config file to get wildcard resolution

## ytdlp

`yt-dlp` in a loop, routed through a WireGuard sidecar. Inputs come from syncthing, downloads go to `{{ ytdlp_download_dir }}`. WG peer config lives at `roles/containers/files/ytdlp/wg0.conf` (gitignored — keep it as a symlink to your local copy).

**When YouTube blocks again — refresh cookies:**

1. Firefox/Chromium **private window** → sign in to YouTube (throwaway account is fine).
2. Export with the **"Get cookies.txt LOCALLY"** extension while on a YouTube tab.
3. **Close the private window immediately** — don't browse elsewhere or log out, both invalidate the cookies.
4. Save as `cookies.txt` in the syncthing ytdlp dir. `run.sh` picks it up automatically.

If cookies aren't enough, the [PO Token Guide](https://github.com/yt-dlp/yt-dlp/wiki/PO-Token-Guide) is the next stop — the bgutil sidecar was removed (see git history for the wiring if you need to add it back). Rebuild to pull a newer yt-dlp: `docker compose -f /fastboi/docker/ytdlp/docker-compose.yml up -d --build`.
