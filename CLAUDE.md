# CLAUDE.md: shared browser (Neko) for Discord friends

Read this first when resuming work here. Then: `README.md` (operations reference), `MANUAL.md`
(local only, not in git: real link, passwords, router details), `./neko.sh` (start/stop/status).

## What this is and the user's hard requirements

A self-hosted shared Chromium ([Neko](https://github.com/m1k1o/neko)) on the user's MacBook so Discord
friends can use it together (mostly GTO Genesis poker study + the user's own extension). One person
drives at a time; the user is the only admin.

- **Friends must never get** the user's passwords, session cookies (GTO Genesis / Google) or the user's
  extension code. Assume friends will poke around. Everything else should be a smooth experience
  (the user explicitly does not want friends blocked from sites or GTO pages).
- Don't touch anything outside this folder except Docker Desktop. Ask before anything destructive.
- **This repo is public** (github.com/yoniker/Shared_browser). Never commit `.env`, `MANUAL.md`,
  `guard/guard-signing-key.pem`, `installers/` (all in `.gitignore`). Scan staged content for the
  passwords/token before every push.
- The extension (`GTO_EXTENSION_DIR` in `.env`) belongs to another repo of the user that cloud agents
  work on: only read it / mount it read-only; if it ever must change, do it on its own branch there.
- How the user likes to work: understand first, short plan, then act; ask clarifying questions one at
  a time; run commands yourself and stop only for things they must do by hand (installer clicks,
  passwords, router); end each stage with an explicit "what you need to do next"; design first (show
  options) for visible UI changes; keep README.md and MANUAL.md current.

## The machine

- MacBook Pro 2015 (i7-4770HQ, 4 cores/8 threads, 16 GB), **macOS 12.7.6: must not be upgraded**.
- **Docker Desktop 4.41.2**, the last release for macOS 12. Never update it (update checks and
  auto-download are off). Limits: 4 CPUs, 6 GB RAM, 1 GB swap, 10 GB disk.
- Docker settings: `~/Library/Group Containers/group.com.docker/settings-store.json` (edit only while
  Docker is stopped: `docker desktop stop` / `docker desktop start`). `FilesharingDirectories` is
  limited to this folder + the extension folder, so containers can't bind-mount anything else
  (test tools copy files in with `docker cp` instead).
- Docker Desktop starts at login; containers are `restart: unless-stopped`. The Mac must stay plugged in
  with the lid open (sleep on AC is already off). Automatic login is needed for unattended restarts
  after a reboot (the user decides; FileVault is off).

## Architecture (docker-compose.yml, project name `neko`)

| Service | What | Notes |
|---|---|---|
| `neko` | `ghcr.io/m1k1o/neko/chromium:3` (v3.1.6, Chromium 154, Debian trixie) | ports `127.0.0.1:8090->8080`, `52000/udp+tcp` (WebRTC UDP/TCP mux). Profile in volume `neko_chromium-profile` (the GTO login lives there). `cap_add: SYS_ADMIN` so Chromium's own sandbox works (`chromium/chromium.conf` drops `--no-sandbox`). |
| `ext-host` | busybox httpd serving `guard/dist/` | internal only; lets policy force-install the guard extension |
| `caddy` | HTTPS reverse proxy, Let's Encrypt (TLS-ALPN on 443) | sets X-Real-IP, strips True-Client-IP, `Cache-Control: no-cache` everywhere (so page patches show up at once) |
| `ddns` | curl loop: DuckDNS update every 5 min | restarts `neko` through the Docker socket when the public IP changes or the network came up late (Neko looks its public IP up only once, at startup; `NEKO_WEBRTC_NAT1TO1` empty = auto) |

All logs are capped (json-file, 10 MB x 3). Neko's web page is the **legacy v2 client** (v3 server in
legacy mode); its JS/CSS live in `/var/www` in the container.

## Lockdown: `chromium/policies/policies.json` (mounted read-only as a directory)

Decisions and gotchas, all verified on this Chromium:
- `ExtensionInstallBlocklist: ["*"]` would also block the user's `--load-extension` unpacked extension,
  so it is **not used**. Installs are blocked another way: Web Store URLs blocked, developer mode off
  (`ExtensionDeveloperModeSettings: 1`; command-line extensions are exempt), `ExtensionAllowedTypes`,
  `chrome://extensions` blocked, no downloads, no file dialogs.
- `--load-extension` still works in Chromium (only branded Chrome 137+ dropped it). The user's extension
  ID inside Neko is `pmmhkjgheofnpanjpnlcnifhlicfknma` (derived from its mount path
  `/opt/extensions/genesis`). New extension version: `./neko.sh reload` (restarts only Chromium via
  supervisorctl; `chrome://extensions` is blocked for everyone, admin included). Check what's loaded:
  `extensions.settings.<id>.service_worker_registration_info.version` in the profile's `Preferences`.
- **Gotcha (Chromium 154):** after an unpacked `--load-extension` extension's files change, a restart
  does NOT re-register its background service worker: Chromium keeps the old registration and cached
  script (popup/content scripts are new, background old). Removing the pref record alone, or the whole
  extension prefs entry, doesn't help; clearing `Default/Service Worker` + every extension's
  `service_worker_registration_info` before start does (verified in a throwaway container across two
  upgrades). `chromium/start-chromium.sh` does that on every Chromium start (chromium.conf runs it).
- `DeveloperToolsAvailability: 2` also kills view-source (menu items show "DevTools not allowed").
- `URLBlocklist`: `chrome://*` (allowlist: History, tab search), `chrome-untrusted://*`,
  `chrome-search://*`, `devtools://*`, `view-source:*`, `file://*`, `javascript://*` (typed URLs and
  bookmarklets), `chrome-extension://*` (allowlist: the extension's popup, trainer and
  `vendor/gg-table/table.html` pages only), Web Store. Note: URL blocking doesn't cover SPA (pushState)
  navigation or subresources.
- `AllowFileSelectionDialogs: false` is critical: otherwise a friend could upload the profile's Cookies
  database or the extension's files to any website.
- Cookies are session-only, except `[*.]gtogenesis.com` and the extension origin (keeps the GTO login).
- User decisions: downloads off (so the extension's export doesn't work inside Neko: accepted), no GTO
  page blocking, friends may browse anywhere.
- **GTO Genesis login is Google-only.** The guard extension (`guard/extension/`) deletes all Google
  cookies (incl. partitioned) 3 s after a request to `*.supabase.co/auth/v1/callback`, so the shared
  browser doesn't stay signed in to the user's Google account. It is force-installed (friends can't
  remove it) via `ExtensionSettings` + `ext-host`; signing key `guard/guard-signing-key.pem` (PKCS#8,
  not in git). Rebuild command in README. Chromium checks for a new guard hourly
  (`--extensions-update-frequency=3600`); to apply at once, remove the guard's `ExtensionSettings`
  entry, wait ~20 s, put it back.
- Residual risks (known, accepted): friends can "Remove from Chromium" the user's unpacked extension or
  use its "Clear stored solutions" (data loss only); friends' browsing comes from the user's home IP.

## Neko page customisation: `client-patch/`

`apply.sh` runs at container start (supervisord program `client-patch.conf`). `patch_js NAME SED`
patches both copies of the minified page code (`/var/www/js/app.*.js`, `app-legacy.*.js`) once,
leaving a `/*NAME*/` marker; `inject` adds tags to `index.html`. Check:
`docker exec neko cat /var/log/neko/client-patch.log`. If a Neko update changes the code, a patch logs
"pattern not found" and that part falls back to stock behaviour. Files in `client-patch/www/` are
mounted live (edit + reload the page, no restart).

| Piece | Why |
|---|---|
| `auto-handover` patch | Stock legacy client only shows the driver "X is requesting the controls". Patched: a non-admin driver's page gives control to the requester automatically; admin pages don't. (Neko's "implicit hosting" is no alternative: in legacy mode `LegacyIsHost()` is true for everyone, i.e. free-for-all input.) |
| `quiet-events` patch | Control changes are chat entries of type `event`; every chat entry played `chat.mp3`. Now only real chat messages do. |
| `www/ui.css` | Big take/ask/release control pill. Button state = classes on `i.fa-keyboard.request`: `faded` = nobody drives, `disabled` = someone else drives, neither = you drive; "Ask for control" via `#neko:has(.members .member.host.admin)`. Green frame + "You're in control" via `:has()`. DRIVING tag on `.member.host`. Admin-only header switches hidden from guests (they get "Controls locked by admin" when locked); labelled for admins. Neko bug: the room-lock icon always has `fa-lock`, only `.locked` reflects the state. |
| `www/cursor.js` | With `NEKO_CAPTURE_VIDEO_SHOW_POINTER: "false"` the video has no pointer (fixes the double, lagging pointer for the driver). Watchers get the driver's pointer drawn from server data-channel messages (header: u8 op, u16 length incl. header, big-endian; op 1 = position x,y; op 2 = image w,h,xhot,yhot + PNG). Neko's legacy move handler never updates that broadcast position, so the driver's page mirrors each legacy move (op 1, little-endian, length 4) as a current-format move (big-endian) on the server-created data channel. Also sets `jitterBufferTarget`/`playoutDelayHint` = 0 on video receivers. If this breaks, watchers see no pointer: set SHOW_POINTER back to `"true"`. |
| `www/fullscreen.js` | Neko calls `navigator.keyboard.lock()` in full screen (Chrome/Edge), making exit "press and hold Esc"; this no-ops it so one Esc works everywhere. (`navigator.keyboard` only exists in secure contexts: https/localhost.) |

## Network facts (details with real values in MANUAL.md)

- Router: consumer ISP router with a real public IPv4 (no CGNAT). Forwarded to the Mac's fixed LAN IP: TCP 80,
  TCP 443, TCP+UDP 52000.
- The router keeps port 443 for itself, so the public link doesn't open from inside the LAN (use
  `http://localhost:8090`). TCP 80/52000 hairpin fine.
- Docker Desktop masks client IPs (every visitor is `192.168.65.1`): never use Neko's IP "Ban".

## Testing (`dev/`)

Run when nobody is using Neko. Both end clean (control reset, test containers removed).
- `dev/lockdown-test.sh` (~3 min): drives the **real** shared browser with `xdotool` (types URLs and
  shortcuts like a friend) + admin-API screenshots in `dev/out/`; asserts chrome:// / Web Store /
  javascript: / shortcuts / downloads / guard. Three checks are screenshot-only (LOOK lines).
- `dev/ui-test.sh` (~4 min): throwaway headless Chromium pages (containers on `neko_default`, no lockdown
  policies, test extensions in `dev/test-extensions/`, probes in `dev/probes/`) logged in as friends
  and an admin; checks handover, admin keeps control, locks, pointer positions, silent control changes,
  keyboard lock; screenshots of each control state in `dev/out/`.
- Helpers in `dev/lib.sh`: admin API (`POST /api/login` -> token; `GET /api/sessions`;
  `/api/room/control/give/{id}|reset|request`; `GET|POST /api/room/settings`;
  `/api/room/screen/shot.jpg`), `page`, `shot`/`fetchshot`, `probe`/`probe_result`, `check`.
- Gotchas: `xdotool` needs `windowfocus` on the Chromium window first; headless
  `--virtual-time-budget` breaks Neko's login (always wait in real time); test pages on
  `http://neko:8080` are not a secure context (keyboard probe uses https via Caddy inside Docker).

## Open ideas / not done

- Latency of page reactions (~0.1-0.2 s): the legacy video pipeline is Neko's default VP8, 25 fps,
  `cpu-used=4`. Options: 30 fps, faster encoder, or H.264 (Safari decodes it in hardware) via
  `NEKO_CAPTURE_VIDEO_PIPELINE` (Neko's legacy hack rewrites a literal `show-pointer=false` to true in
  custom pipelines: write `show-pointer=0`).
- Not yet verified with real friends: sound, friend-to-friend handover in practice; reboot test with
  automatic login.
- The user's extension can't be force-installed (unpacked, changes often), so friends can remove it.
