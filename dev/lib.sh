# Shared helpers for the dev tests (source it; see CLAUDE.md "Testing").
# Needs the stack running (./neko.sh) and the admin password in .env.
set -euo pipefail
export PATH="/usr/local/bin:$PATH"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEV="$ROOT/dev"
OUT="$DEV/out"
mkdir -p "$OUT"
API=http://127.0.0.1:8090/api
IMAGE=ghcr.io/m1k1o/neko/chromium:3
EXT_ID=pmmhkjgheofnpanjpnlcnifhlicfknma # the user's extension inside Neko

env_get() { grep "^$1=" "$ROOT/.env" | cut -d= -f2-; }
MPW=$(env_get NEKO_MEMBER_PASSWORD)
APW=$(env_get NEKO_ADMIN_PASSWORD)

# ---- Neko admin API ----------------------------------------------------------------------
json_login() { /usr/bin/python3 -c 'import json,sys; print(json.dumps({"username": sys.argv[1], "password": sys.argv[2]}))' "$1" "$2"; }
ADM=""
api() { # curl args... (authenticated as an admin API session)
	if [ -z "$ADM" ]; then
		ADM=$(curl -s -X POST "$API/login" -H 'Content-Type: application/json' -d "$(json_login dev-admin "$APW")" |
			/usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["token"])')
	fi
	curl -s -H "Authorization: Bearer $ADM" "$@"
}
api -o /dev/null "$API/room/control" # log in now, so subshells like $(host) reuse the same token
sid() { # session id of the connected member NAME
	api "$API/sessions" | /usr/bin/python3 -c '
import json, sys
print(next((s["id"] for s in json.load(sys.stdin) if s["profile"]["name"] == sys.argv[1] and s["state"]["is_connected"]), ""))' "$1"
}
give() { api -o /dev/null -X POST "$API/room/control/give/$(sid "$1")"; }
host() { api "$API/room/control" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("host_id") or "nobody")'; }
reset_control() { api -o /dev/null -X POST "$API/room/control/reset"; }
set_locks() { # CONTROLS ROOM  (True/False)
	local s
	s=$(api "$API/room/settings" | /usr/bin/python3 -c "import json,sys; d=json.load(sys.stdin); d['locked_controls']=$1; d['locked_logins']=$2; print(json.dumps(d))")
	api -o /dev/null -X POST -H 'Content-Type: application/json' -d "$s" "$API/room/settings"
}

# ---- results -------------------------------------------------------------------------------
FAILS=0
check() { # LABEL ACTUAL EXPECTED-SUBSTRING
	if [[ "$2" == *"$3"* ]]; then echo "  PASS  $1"; else echo "  FAIL  $1 (got: $2)"; FAILS=$((FAILS + 1)); fi
}
check_not() { # LABEL ACTUAL FORBIDDEN-SUBSTRING
	if [[ "$2" != *"$3"* ]]; then echo "  PASS  $1"; else echo "  FAIL  $1 (got: $2)"; FAILS=$((FAILS + 1)); fi
}

# ---- throwaway test browsers -----------------------------------------------------------------
# Headless Chromium containers on the compose network, logged in to Neko as NAME. They run without
# our lockdown policies. Docker may only mount this project and the extension folder, so test
# extensions are copied in with docker cp instead of mounted.
page() { # NAME PASSWORD [EXTENSION_DIR] [URL]
	local name=$1 pw=$2 ext=${3:-} url=${4:-"http://neko:8080/?usr=$1&pwd=$2"}
	local addhost=() h
	if [[ "$url" == https://* ]]; then # reach the real HTTPS site via Caddy inside Docker (secure context)
		h=${url#https://}
		h=${h%%/*}
		addhost=(--add-host "$h:$(docker inspect neko-caddy --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')")
	fi
	docker rm -f "pt-$name" >/dev/null 2>&1 || true
	docker create --name "pt-$name" --network neko_default ${addhost[@]+"${addhost[@]}"} --entrypoint /usr/lib/chromium/chromium "$IMAGE" \
		--headless=new --no-sandbox --disable-gpu --window-size=1280,760 --hide-scrollbars --user-data-dir=/tmp/p \
		--autoplay-policy=no-user-gesture-required ${ext:+--load-extension=/ext} "$url" >/dev/null
	docker cp -q "$DEV/empty-policies.json" "pt-$name":/etc/chromium/policies/managed/policies.json
	if [ -n "$ext" ]; then docker cp -q "$ext/." "pt-$name":/ext; fi
	docker start "pt-$name" >/dev/null
}

templated() { # copy test extension NAME to a temp dir, replacing __KEY__ placeholders: templated NAME KEY=VALUE...
	local tmp
	tmp=$(mktemp -d)
	cp -R "$DEV/test-extensions/$1/." "$tmp/"
	shift
	for kv in "$@"; do sed -i '' "s#__${kv%%=*}__#${kv#*=}#g" "$tmp"/*.js "$tmp"/*.json; done
	echo "$tmp"
}

shot() { # SHOT USER PASSWORD [CLICK_MS]: page logged in as USER that optionally clicks "Take control"
	# after CLICK_MS, then screenshots itself after 24 s (collect it with: fetchshot SHOT)
	local ext
	ext=$(templated shotter CAPTURE_MS=24000 CLICK_MS="${4:-0}")
	page "$1" "$3" "$ext" "http://neko:8080/?usr=$2&pwd=$3"
	rm -rf "$ext"
}
fetchshot() { # SHOT -> dev/out/SHOT.png (the capture sometimes lands a few seconds late)
	local i
	for i in 1 2 3 4 5 6; do
		if docker cp "pt-$1":/root/Downloads/shot.png "$OUT/$1.png" >/dev/null 2>&1; then
			echo "  screenshot: dev/out/$1.png"
			return
		fi
		sleep 2
	done
	echo "  (no screenshot for $1)"
}

probe() { # NAME PASSWORD PROBE_FILE DELAY_MS [URL]: run dev/probes/PROBE_FILE in the page, read its result
	local ext
	ext=$(templated probe DELAY_MS="$4")
	cp "$DEV/probes/$3" "$ext/main.js"
	page "$1" "$2" "$ext" "${5:-}"
	rm -rf "$ext"
}
probe_result() { docker exec "pt-$1" cat /root/Downloads/result.txt 2>/dev/null || echo "(no result)"; }

cleanup() {
	docker ps -a --format '{{.Names}}' | grep '^pt-' | xargs docker rm -f >/dev/null 2>&1 || true
	if [ -n "$ADM" ]; then
		reset_control
		api -o /dev/null -X POST "$API/logout"
	fi
}
