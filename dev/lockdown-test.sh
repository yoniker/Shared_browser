#!/bin/bash
# Lockdown tests on the REAL shared browser: types URLs and shortcuts into it with xdotool, the way a
# friend would, and checks each one is blocked. Screenshots: dev/out/lockdown-*.jpg (look at the ones
# marked LOOK). Run only when nobody is on Neko: it takes over the browser and clears its Google
# cookies. Ends back on GTO Genesis. Takes about 3 minutes.
source "$(dirname "$0")/lib.sh"

X() { docker exec -u neko -e DISPLAY=:99.0 neko xdotool "$@"; }
win() { X search --onlyvisible --class chromium | tail -1; }
focus() { X windowfocus --sync "$(win)"; } # without this, keys go to the window manager
go() { focus; X key --clearmodifiers ctrl+l; sleep 0.4; X type --delay 12 "$1"; sleep 0.4; X key Return; sleep "${2:-2}"; }
keys() { focus; X key --clearmodifiers "$@"; sleep 1.5; X key Escape; sleep 0.3; }
title() { X getwindowname "$(win)"; }
windows() { docker exec -u neko -e DISPLAY=:99.0 neko sh -c 'xdotool search --onlyvisible --name . | wc -l' | tr -d ' '; }
snap() { api "$API/room/screen/shot.jpg?quality=70" -o "$OUT/lockdown-$1.jpg"; echo "  LOOK  dev/out/lockdown-$1.jpg ($2)"; }
google_cookies() {
	docker exec neko sh -c 'cp /home/neko/.config/chromium/Default/Cookies /tmp/c.db; python3 -c "
import sqlite3; c = sqlite3.connect(\"/tmp/c.db\")
print(c.execute(\"select count(*) from cookies where host_key like \x27%google.%\x27 or host_key like \x27%youtube.com\x27\").fetchone()[0])"; rm -f /tmp/c.db'
}
trap 'go "https://app.gtogenesis.com/" 1; cleanup' EXIT
E="chrome-extension://$EXT_ID"

echo "Pages a friend might open"
for u in chrome://settings chrome://extensions chrome://version chrome://flags; do
	go "$u"
	check "$u blocked" "$(title)" "chrome://" # an open settings page would be titled "Settings", etc.
done
go "https://chromewebstore.google.com/" 3
check_not "Chrome Web Store blocked" "$(title)" "Chrome Web Store"
go "view-source:https://app.gtogenesis.com/"
snap view-source "should say: This page is blocked"
go "file:///home/neko/.config/chromium/Default/Cookies"
snap file "should say: This page is blocked"
go "$E/src/tap.js"
snap extension-code "your extension's code: should say This page is blocked"
go "$E/src/trainer.html" 4
check "your extension's trainer page still opens" "$(title)" "Trainer"

echo "javascript: in the address bar"
go "https://app.gtogenesis.com/" 4
go "javascript:document.title='PWNED'"
check_not "javascript: URL doesn't run" "$(title)" "PWNED"

echo "Shortcuts (DevTools, view source, incognito, open file, save, print)"
before=$(windows)
for k in F12 ctrl+shift+i ctrl+shift+j ctrl+shift+c ctrl+shift+n ctrl+o ctrl+s ctrl+p; do keys "$k"; done
check "no new windows or dialogs opened" "$(windows)" "$before"
keys ctrl+u
check_not "Ctrl+U doesn't open page source" "$(title)" "view-source"

echo "Downloads"
go "https://github.com/m1k1o/neko/archive/refs/tags/v3.1.6.zip" 6
check "nothing downloaded" "files=$(docker exec neko sh -c 'ls -A /home/neko/Downloads 2>/dev/null | wc -l' | tr -d ' ')" "files=0"

echo "Guard: Google sign-out after a GTO login (simulated)"
go "https://www.google.com/" 4
go "https://nfddwwnlnauekmmjvvix.supabase.co/auth/v1/callback" 5
sleep 35 # Chromium writes cookies to disk every ~30 s
check "no Google cookies left" "google-cookies=$(google_cookies)" "google-cookies=0"

echo
if [ "$FAILS" = 0 ]; then echo "All checks passed. Also look at the LOOK screenshots above."; else echo "$FAILS check(s) FAILED."; exit 1; fi
