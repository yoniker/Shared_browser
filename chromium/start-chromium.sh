#!/bin/sh
# Starts Chromium for Neko (chromium.conf passes all the flags through). First it forgets old
# extension background-script (service worker) registrations: otherwise Chromium keeps running an
# unpacked extension's previous background code after its files change, even across restarts.
# Every extension then registers its current code. Logins, site data and extension data stay.
PROFILE="$HOME/.config/chromium/Default"
rm -rf "$PROFILE/Service Worker"
python3 - "$PROFILE/Preferences" <<'EOF'
import json, os, sys
p = sys.argv[1]
try:
    d = json.load(open(p))
except (OSError, ValueError):
    sys.exit(0)  # first start: nothing to forget
for s in d.get("extensions", {}).get("settings", {}).values():
    s.pop("service_worker_registration_info", None)
json.dump(d, open(p + ".tmp", "w"), separators=(",", ":"))
os.replace(p + ".tmp", p)
EOF
exec /usr/bin/chromium "$@"
