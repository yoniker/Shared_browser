# Shared browser (Neko) for Discord friends

A shared, locked-down Chromium running in Docker on this MacBook. Friends open a link,
enter the friend password, and watch/hear/control the same browser. One person drives at
a time; you are the only admin.

| Who | Address | Password |
|---|---|---|
| Friends | `https://<DUCKDNS_SUBDOMAIN>.duckdns.org` | `NEKO_MEMBER_PASSWORD` in `.env` |
| You (admin), away from home | same link | `NEKO_ADMIN_PASSWORD` in `.env` |
| You (admin), on this Mac | http://localhost:8090 | `NEKO_ADMIN_PASSWORD` |

Any display name works; the password decides whether you're a friend or admin.
**Never share the admin password.** See your passwords with: `grep PASSWORD ~/neko/.env`

**Your actual link, passwords and router details are in `LOCAL.md`** (on this Mac only; it's kept out
of git together with `.env`, because this repository is public).

## Start / stop / status

All commands run from `~/neko`:

```bash
cd ~/neko
docker compose up -d                 # start everything (also how changes to .env take effect)
docker compose ps                    # status
docker compose stop                  # stop everything (stays stopped until you start it)
docker compose restart neko          # restart the browser container (kicks everyone briefly)
docker compose logs -f --tail 50 neko   # live logs (Ctrl+C to quit); also: caddy, ddns
docker exec neko supervisorctl -c /etc/neko/supervisord.conf restart chromium   # restart only Chromium
```

Containers restart automatically (`restart: unless-stopped`) whenever Docker Desktop starts,
and Docker Desktop starts when you log in to the Mac.

## Admin controls (in the Neko page)

- **Switching control:** the big button in the bottom bar.
  - Green **Take control**: one click and you drive, instantly. Clicking the video itself never
    takes control, so nobody grabs it by mistake.
  - Amber **Ask for control** (friends see this while an admin drives): sends the admin a request;
    admins are never taken over without agreeing.
  - Red **Release control**: you're driving; the video also gets a green frame and a
    "You're in control" label. The driver's avatar shows a green **DRIVING** tag for everyone.
  - Your override: click Take control (instant when a friend is driving). If someone's page is
    frozen: members list > their name > **Take controls**.
- **Mouse pointer:** the video doesn't contain the pointer. Whoever drives sees just their own pointer
  (instant, and it takes the remote pointer's shape: arrow, text cursor, hand). Everyone else sees the
  driver's pointer with a green name tag, drawn by their page (`client-patch/www/cursor.js`). If a Neko
  update ever breaks this (friends see no pointer), set `NEKO_CAPTURE_VIDEO_SHOW_POINTER: "true"` in
  `docker-compose.yml` and run `docker compose up -d neko` to put the pointer back into the video.
- **Full screen** (expand icon on the video): press **Esc** to exit, in every browser (on a Mac,
  Cmd+Ctrl+F also works). If the shared browser itself went full screen (a video, or F11), take control
  and press Esc or F11 outside Neko's full screen.
- **Kick someone:** open the members list, click their name, choose **Kick**. To keep someone out
  for good, change the friend password (below). **Never use Ban**: Docker Desktop shows every
  visitor to Neko as the same address (`192.168.65.1`), so banning one person bans everyone,
  including you. If it happens anyway: `docker compose restart neko`.
- **Lock controls / Lock room:** the two buttons at the top right (you only; they turn red while
  on). Lock controls = only admins can drive; Lock room = nobody new can log in. Friends don't see
  these buttons; while controls are locked they see "Controls locked by admin" instead.
- **How the custom page works:** `client-patch/apply.sh` runs when the container starts. It patches
  Neko's page for the instant handover and silent control changes (no chat sound when someone takes or
  releases control; real chat messages still play it, switchable per person in Settings > Play Chat
  Sound), and loads `client-patch/www/ui.css` (the look) and
  `client-patch/www/cursor.js` (the shared pointer; it also tells browsers to show video frames as soon
  as they arrive) and `client-patch/www/fullscreen.js` (plain Esc exits full screen everywhere). Edit
  them and reload the page, no restart needed. Check it with `docker exec neko cat /var/log/neko/client-patch.log`.
  If a Neko update changes the page code, the log says "pattern not found" and that part falls back to
  Neko's stock behaviour (nothing breaks).
- **Control protection:** friends can only take control while an admin is connected. Toggle it in
  the room settings, or make it permanent with `NEKO_SESSION_CONTROL_PROTECTION: "true"` in
  `docker-compose.yml`.

## Change passwords

1. Edit `~/neko/.env` and change `NEKO_MEMBER_PASSWORD` and/or `NEKO_ADMIN_PASSWORD`.
   New random one: `openssl rand -base64 18`
2. `docker compose up -d neko` (everyone is disconnected and must log in with the new password).

## Logging in to GTO Genesis (do this yourself, once)

GTO Genesis only offers "Continue with Google", so logging in signs the shared browser in to
Google for a moment. The **Shared Browser Guard** extension (in `guard/`) automatically deletes
all Google cookies about 3 seconds after the GTO login completes. Your GTO session stays;
your Google account does not stay open to friends.

1. Lock the room (or log in before inviting anyone).
2. Click **Continue with Google** and **type** your Google password. Don't paste it: Neko's
   clipboard sync would leave it in the shared clipboard, where the next driver could paste it.
3. After you land in GTO Genesis, open `https://myaccount.google.com` in a new tab. It must show
   a Google **sign-in** page. If it shows your account, click your avatar and choose **Sign out**
   (the guard should have done this; restart Chromium before your next login).
4. Unlock the room.

**Don't sign in to Google (YouTube, Gmail...) or any other personal account anywhere else in the
shared browser.** The guard only cleans up right after the GTO login; any other login stays open to
whoever has control until Chromium restarts.

Chromium never saves the password (password manager off) and can't sign in to Chrome/sync.
GTO cookies are kept across restarts; every other site's cookies are cleared when Chromium
restarts.

## What friends can and can't do

They can browse anywhere, use GTO Genesis and your extension (popup, trainer), copy/paste text,
bookmark, and see History.

Blocked, because each one could expose your session cookies, Google account or extension code:

| Blocked | How |
|---|---|
| DevTools, Inspect, View page source | `DeveloperToolsAvailability: 2` (Chrome ties view-source to DevTools) |
| `chrome://` pages (settings, extensions, flags, version...) except History and tab search | `URLBlocklist` / `URLAllowlist` |
| `file://`, `view-source:`, `devtools://`, `javascript:` typed in the address bar | `URLBlocklist` |
| Your extension's files (`chrome-extension://...`), except its popup, trainer and table pages | `URLBlocklist` + `URLAllowlist` |
| Chrome Web Store, installing extensions, developer mode | `URLBlocklist`, `ExtensionDeveloperModeSettings`, `ExtensionAllowedTypes`, no file dialogs/downloads |
| Password manager, Chrome sign-in/sync, incognito, guest/new profiles | `PasswordManagerEnabled`, `BrowserSignin`, `IncognitoModeAvailability`, ... |
| Downloads, file pickers (upload dialogs), printing | `DownloadRestrictions: 3`, `AllowFileSelectionDialogs`, `PrintingEnabled` |
| Neko file transfer, drag-and-drop upload, webcam/mic sharing | `docker-compose.yml` (`NEKO_FILETRANSFER_ENABLED`, `NEKO_DESKTOP_UPLOAD_DROP`, user profile) |

Known limits (by design or unavoidable):
- A friend could click your extension's toolbar icon > **Remove from Chromium**, or use its
  "Clear stored solutions". That deletes its saved library (not your code or logins). Restarting
  Chromium brings the extension back, but not the deleted data.
- Anything friends do online comes from your home IP address.
- Your extension's export is a download, so it doesn't work inside Neko (downloads are off).

## Add or remove blocked URLs

Edit `~/neko/chromium/policies/policies.json` (keep it valid JSON):

- Block something: add to `"URLBlocklist"`, e.g. `"app.gtogenesis.com/settings"` (path prefix) or
  `"example.com"` (whole site incl. subdomains).
- Make an exception: add to `"URLAllowlist"`. The more specific rule wins.

Chromium picks up changes within seconds. To be sure, restart Chromium (command above).
Check the file is valid: `python3 -m json.tool ~/neko/chromium/policies/policies.json >/dev/null && echo ok`

Note: GTO Genesis is a single-page app. Blocking one of its paths stops loading that page directly,
but clicking an in-app link to it can still get there.

## Your extension

`GTO_EXTENSION_DIR` in `.env` is mounted **read-only** at `/opt/extensions/genesis` and loaded with
`--load-extension` (see `chromium/chromium.conf`). Its ID inside Neko is
`pmmhkjgheofnpanjpnlcnifhlicfknma` (derived from that path).

- After changing the extension's code: restart Chromium (command above).
- If the extension gains a new page that opens in a tab or iframe, add it to `"URLAllowlist"` as
  `chrome-extension://pmmhkjgheofnpanjpnlcnifhlicfknma/<path>.html`.

## The guard extension

`guard/extension/` is force-installed by policy (friends can't remove or disable it). Chromium
downloads it from the internal-only `ext-host` container (`guard/dist/`). To change it: edit the
code, bump `version` in `guard/extension/manifest.json` and `guard/dist/updates.xml`, then rebuild:

```bash
cd ~/neko/guard && docker run --rm -v "$PWD:/guard" --entrypoint /usr/lib/chromium/chromium \
  ghcr.io/m1k1o/neko/chromium:3 --no-sandbox --headless=new --pack-extension=/guard/extension \
  --pack-extension-key=/guard/guard-signing-key.pem && mv extension.crx dist/guard.crx && chmod 644 dist/guard.crx
```

Chromium checks for a new version hourly (`--extensions-update-frequency=3600` in `chromium/chromium.conf`).
To apply it right away: delete the guard's entry (`mnjpallfhiobadobcdaiofikffmcebmg`) from `"ExtensionSettings"`
in `policies.json`, wait ~20 seconds (Chromium uninstalls it), then put the entry back (it reinstalls the new version).
Keep `guard/guard-signing-key.pem` private and don't delete it (it defines the guard's ID).

## Network

- **Friends' link:** `https://<DUCKDNS_SUBDOMAIN>.duckdns.org`. Caddy gets and renews the Let's Encrypt certificate
  by itself.
- **At home, use http://localhost:8090 on this Mac.** The public link doesn't open from inside your
  home network: the router keeps port 443 for its own admin page. Friends outside are not
  affected. To test like a friend, use a phone on mobile data (Wi-Fi off).
- **Router** (its admin page, e.g. http://192.168.0.1; exact values in `LOCAL.md`):
  - DHCP reservation: this Mac's Wi-Fi MAC address → a fixed local IP. It's the **Wi-Fi** MAC; redo it if
    you switch the Mac to Ethernet.
  - Port forwarding to that fixed IP: TCP 80, TCP 443, TCP/UDP 52000.
- **DuckDNS:** subdomain and token in `.env`. The `ddns` container updates it every 5 minutes
  (`docker compose logs ddns` should show `duckdns=OK`). It also restarts `neko` when your public IP
  changes, or when the network came up late after a reboot, because Neko tells viewers the public IP
  it looked up once at startup.
- **Video/audio (WebRTC):** one port, 52000 UDP, with TCP 52000 as a fallback for friends whose network
  blocks UDP. Keep `NEKO_WEBRTC_NAT1TO1=` empty in `.env` (auto-detect). For a local-only test set it to
  `127.0.0.1` and run `docker compose up -d neko`; empty it again afterwards.
- Port forwarding only works because the ISP gives your router a real public IP (no CGNAT). If that
  ever changes, friends won't be able to connect.

## Docker Desktop

- Version **4.41.2**, the last release that supports macOS 12. **Don't update it** (4.42+ needs
  macOS 13.3). Update checks and auto-downloads are off. Installer: `installers/Docker-4.41.2.dmg`.
- Limits: 4 CPUs, 6 GB RAM, 1 GB swap, 10 GB disk. Starts at login without opening its window.
- Only `~/neko` and your extension folder can be mounted into containers. To use Docker for other
  projects, add their folders under Settings > Resources > File sharing.
- These settings live in `~/Library/Group Containers/group.com.docker/settings-store.json`
  (original copy: `installers/docker-settings-store.original.json`).
- Outside `~/neko`, setup changed only Docker itself: `/Applications/Docker.app` plus what its installer
  adds (privileged helper, `docker` command links in `/usr/local/bin`), its settings file above, and its login item.

## Updating Neko

```bash
cd ~/neko && docker compose pull && docker compose up -d
```

Then re-run the test checklist: a new Chromium version can change how policies behave.

## Staying up: sleep, lid, reboots

- On the power adapter the Mac never sleeps (`pmset` sleep 0 on AC, already set). Keep it plugged in
  and **keep the lid open**: closing it puts the Mac to sleep.
- After a reboot, Docker Desktop starts when you log in, and all containers start with it. For that to
  happen without you, turn on **automatic login**: System Preferences > Users & Groups > Login
  Options > Automatic login: your account. (Works because FileVault is off. Trade-off: anyone who can
  touch the Mac gets your desktop without a password.)
- Allow ~2-3 minutes after login for Docker and Neko to come up.
- If the battery is old (System Information > Power says "Service Recommended"), running plugged in
  24/7 is fine, but check now and then that it isn't swelling.

## Test checklist

Test with a friend, or your phone on mobile data (Wi-Fi off), at your link.
"Verified" marks what was already checked during setup on 2026-10-10.

**Basics**

| Test | Expected | Verified |
|---|---|---|
| Friend logs in with the friend password | sees the shared browser | ✓ phone, mobile data |
| Play a YouTube video | friend hears it (they may need to click the video once to unmute) | |
| Friend clicks **Take control** while another friend drives | takes control instantly | ✓ automated test |
| Friend clicks **Ask for control** while you drive | you keep control, you see a request | ✓ automated test |
| Lock controls | friends' button disappears, they see "Controls locked by admin" | ✓ automated test |
| While a friend drives, you click Take control | you get control immediately | |
| Kick the friend from the members list | they're disconnected | ✓ |
| Your extension: toolbar icon > popup, "Open trainer" | popup and trainer tab open | ✓ |
| Your extension records on app.gtogenesis.com | works as on your own Chrome | after GTO login |
| After your GTO login, open `https://myaccount.google.com` | Google **sign-in** page (guard signed Google out) | ✓ real login |
| Reboot the Mac (with automatic login on) | link works again ~3 min after boot, no action needed | |

**Lockdown: as a friend with control, each of these must fail**

| Friend tries | Expected | Verified |
|---|---|---|
| F12, Ctrl+Shift+I, Ctrl+Shift+J, right-click > Inspect | "DevTools not allowed on this page" | ✓ |
| Ctrl+U, right-click > View page source, typing `view-source:...` | not allowed / "This page is blocked" | ✓ |
| `chrome://settings`, `chrome://extensions`, `chrome://version` (any `chrome://` page) | "This page is blocked" | ✓ |
| `file:///home/neko/.config/chromium/Default/Cookies` (any `file://` path) | blocked | ✓ |
| `javascript:...` typed in the address bar, e.g. `javascript:alert(document.cookie)` | nothing happens | ✓ |
| `chrome-extension://pmmhkjgheofnpanjpnlcnifhlicfknma/src/tap.js` (your code) | blocked | ✓ |
| `chromewebstore.google.com` (install an extension) | blocked | ✓ |
| Ctrl+Shift+N (incognito) | nothing | ✓ |
| Ctrl+O (open file), Ctrl+S (save page), Ctrl+P (print) | nothing | ✓ |
| Download any file | blocked, nothing saved | ✓ |
| Log in to some other site | no "save password?" prompt | |
| Profile menu (avatar, top right) | no Guest / Add profile | |

Re-run the lockdown table after any `docker compose pull` (new Chromium) or policy edit.

## Files

| Path | What |
|---|---|
| `docker-compose.yml` | all services: neko, ext-host, caddy, ddns (logs capped at 30 MB each) |
| `.env` | passwords, extension path, DuckDNS token (private, chmod 600, **not in git**) |
| `.env.example` | template for `.env` on a fresh copy |
| `LOCAL.md` | concise manual with your real link, passwords and router details (**not in git**) |
| `chromium/policies/policies.json` | Chromium lockdown policies |
| `chromium/chromium.conf` | Chromium launch flags (sandbox on, loads your extension) |
| `guard/` | guard extension source and packaged CRX (the signing key is **not in git**: back it up privately) |
| `caddy/Caddyfile` | HTTPS reverse proxy |
| `client-patch/` | Neko page customisation: instant handover (`apply.sh`), look (`www/ui.css`), shared pointer (`www/cursor.js`) |
| `ddns/ddns.sh` | DuckDNS updater; restarts neko when your public IP changes or the network came up late |
| `installers/` | Docker installer and original Docker settings |

**Fresh copy of this repository:** copy `.env.example` to `.env` (`chmod 600 .env`) and fill it in, then
`docker compose up -d`. Secrets (`.env`, `LOCAL.md`, `guard/guard-signing-key.pem`) and `installers/` are
listed in `.gitignore` and never pushed.
