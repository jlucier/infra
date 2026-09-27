# infra

## Dependencies

```
ansible-galaxy install -r requirements.yml
```

## Notes

- A custom dnsmasq.d config file gives wildcard resolution for the fqdn of the
  main server.

## ytdlp

`yt-dlp` in a loop, routed through a WireGuard sidecar. Syncthing supplies the
inputs. Downloads go to `{{ ytdlp_download_dir }}`. The WG peer config lives at
`roles/containers/files/ytdlp/wg0.conf`, which is gitignored. Keep it as a
symlink to your local copy.

To refresh the cookies after YouTube blocks the downloads again:

1. Open a private window in Firefox or Chromium. Sign in to YouTube. A
   throwaway account is fine.
2. Export the cookies with the "Get cookies.txt LOCALLY" extension while a
   YouTube tab is open.
3. Close the private window immediately. Do not browse elsewhere and do not log
   out. Both actions invalidate the cookies.
4. Save the file as `cookies.txt` in the syncthing ytdlp dir. `run.sh` finds it.

If the cookies are not enough, read the
[PO Token Guide](https://github.com/yt-dlp/yt-dlp/wiki/PO-Token-Guide). The
bgutil sidecar was removed. See the git history for the wiring if you must add
it back. To pull a newer yt-dlp, rebuild:
`docker compose -f /fastboi/docker/ytdlp/docker-compose.yml up -d --build`.

## Sunshine

`sunshine-stuff/vstream_do.sh` saves `DP-1` settings and switches to its
available 2560×1440 (16:9) mode for streaming. `sunshine-stuff/vstream_undo.sh`
restores the saved settings when the session ends.

The optional Skyrim wrapper is kept with the mod bundle at
`~/sync/games/skyrim-mods-1.7.104/skyrim-launch.sh`.
Run `~/sync/games/skyrim-mods-1.7.104/install.sh --install-launcher`
to install it in the Skyrim game root. The installer prints the matching Steam
launch option; add `[PATH]` if the library cannot be auto-detected.
