#!/bin/bash
# UI tests with throwaway headless browser pages (see dev/lib.sh): control button states, instant
# handover, shared pointer, silent control changes, Esc-only full screen. Screenshots go to dev/out/
# (look at them). It changes who has control while it runs, so use it when nobody is on Neko.
# Takes about 4 minutes.
source "$(dirname "$0")/lib.sh"
trap cleanup EXIT

echo "1. A friend (alice) drives; a guest and an admin watch"
page alice "$MPW"
sleep 12
give alice
shot friend-drives guest1 "$MPW"
shot admin-view boss "$APW"
sleep 30
fetchshot friend-drives # expect: green "Take control", DRIVING tag on alice, no admin buttons
fetchshot admin-view    # expect: "Lock controls" / "Lock room" buttons at the top right

echo "2. A guest clicks Take control while alice drives"
shot you-drive guest2 "$MPW" 9000
sleep 30
fetchshot you-drive # expect: red "Release control", green frame, "You're in control"
check "instant handover from a friend" "$(host)" "guest2-"

echo "3. The admin drives; a guest clicks"
give boss
sleep 1
shot admin-drives guest3 "$MPW" 9000
sleep 30
fetchshot admin-drives # expect: amber "Ask for control"
check "admin keeps control" "$(host)" "boss-"

echo "4. Controls locked"
set_locks True False
reset_control
shot locked guest4 "$MPW" 9000
sleep 30
fetchshot locked # expect: no control button, "Controls locked by admin"
check "locked: a guest can't take control" "$(host)" "nobody"
set_locks False False

echo "5. Shared pointer: alice drives and moves the mouse"
page alice "$MPW" "$DEV/test-extensions/mover"
sleep 12
give alice
probe watcher1 "$MPW" data-channel.js 25000
shot watcher2 watcher2 "$MPW"
sleep 30
fetchshot watcher2 # expect: pointer with an "alice" tag, 45% down the video
positions=$(probe_result watcher1 | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("1", 0))' 2>/dev/null || echo 0)
check "watchers receive pointer positions ($positions)" "$([ "${positions:-0}" -gt 5 ] && echo yes || echo no)" "yes"

echo "6. No chat sound for control changes"
probe sound "$MPW" chat-sound.js 12000
sleep 18
check "control change silent, chat message still plays" "$(probe_result sound)" "event=0 text=1"

echo "7. One Esc exits full screen (keyboard lock skipped; tested over https)"
probe kb "$MPW" keyboard-lock.js 12000 "https://$(env_get DUCKDNS_SUBDOMAIN).duckdns.org/"
sleep 18
check "full-screen keyboard lock skipped" "$(probe_result kb)" "keyboard-api=true lock-replaced=true"

echo
if [ "$FAILS" = 0 ]; then echo "All checks passed. Review the screenshots in dev/out/."; else echo "$FAILS check(s) FAILED."; exit 1; fi
