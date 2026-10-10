#!/bin/bash
# neko.sh - run the shared browser (Neko) on this Mac.
#
#   ./neko.sh              start everything (starts Docker Desktop first if needed)
#   ./neko.sh stop         stop everything
#   ./neko.sh restart      restart the shared browser (everyone reconnects)
#   ./neko.sh status       containers, link, who is connected
#   ./neko.sh passwords    show the admin and friend passwords
#   ./neko.sh manual       show the quick manual (MANUAL.md)
#   ./neko.sh logs [svc]   follow logs (neko, caddy, ddns, ext-host; default neko)
#   ./neko.sh update       pull newer Neko/Caddy images and restart (then re-run the tests)
set -euo pipefail
cd "$(dirname "$0")"
export PATH="/usr/local/bin:$PATH"

env_get() { grep "^$1=" .env | cut -d= -f2-; }
link() { echo "https://$(env_get DUCKDNS_SUBDOMAIN).duckdns.org"; }

ensure_docker() {
	docker info >/dev/null 2>&1 && return
	echo "Starting Docker Desktop..."
	docker desktop start --timeout 300 >/dev/null 2>&1 || open -a Docker
	until docker info >/dev/null 2>&1; do sleep 3; done
}

# names of people connected right now (uses the admin API on localhost)
connected() {
	local body token
	body=$(/usr/bin/python3 -c 'import json,sys; print(json.dumps({"username": "neko-sh", "password": sys.argv[1]}))' "$(env_get NEKO_ADMIN_PASSWORD)")
	token=$(curl -s -m 5 -X POST http://127.0.0.1:8090/api/login -H 'Content-Type: application/json' -d "$body" |
		/usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["token"])' 2>/dev/null) || { echo "  (Neko not answering yet)"; return; }
	curl -s -m 5 -H "Authorization: Bearer $token" http://127.0.0.1:8090/api/sessions | /usr/bin/python3 -c '
import json, sys
people = [s["profile"]["name"] for s in json.load(sys.stdin) if s["state"]["is_connected"] and s["profile"]["name"] != "neko-sh"]
print("  connected:", ", ".join(people) if people else "nobody")'
	curl -s -m 5 -o /dev/null -X POST -H "Authorization: Bearer $token" http://127.0.0.1:8090/api/logout
}

case "${1:-start}" in
start)
	ensure_docker
	docker compose up -d
	echo
	echo "Friends: $(link)   password: $(env_get NEKO_MEMBER_PASSWORD)"
	echo "You:     http://localhost:8090 at home ($(link) when away), admin password: ./neko.sh passwords"
	;;
stop)
	docker compose stop
	;;
restart)
	docker compose restart neko
	;;
status)
	docker compose ps --format 'table {{.Name}}\t{{.Status}}'
	echo "  link: $(link)"
	connected
	;;
passwords)
	echo "Admin (only you): $(env_get NEKO_ADMIN_PASSWORD)"
	echo "Friends:          $(env_get NEKO_MEMBER_PASSWORD)"
	;;
manual)
	cat MANUAL.md
	;;
logs)
	docker compose logs -f --tail 50 "${2:-neko}"
	;;
update)
	docker compose pull
	docker compose up -d
	echo "Updated. Re-run the checks: dev/lockdown-test.sh and dev/ui-test.sh (see CLAUDE.md)."
	;;
*)
	sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
	exit 1
	;;
esac
