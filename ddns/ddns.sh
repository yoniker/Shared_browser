#!/bin/sh
# Keeps <DUCKDNS_SUBDOMAIN>.duckdns.org pointed at this network's public IP.
# Neko tells WebRTC viewers the public IP it looked up once at startup, so we
# restart the neko container (via the Docker socket) when:
#   - the public IP changes, or
#   - the network wasn't up yet when we started (e.g. right after a reboot),
#     because neko started at the same moment and couldn't look its IP up either.
# Runs inside the "ddns" service in docker-compose.yml.
set -u
INTERVAL="${INTERVAL:-300}"
RETRY="${RETRY:-30}"
last_ip=""
network_was_down=0

restart_neko() {
	echo "$1: restarting neko"
	curl -s --unix-socket /var/run/docker.sock -X POST -o /dev/null -w "restart: HTTP %{http_code}\n" \
		"http://localhost/containers/neko/restart?t=10"
}

while true; do
	ip=$(curl -fsS --max-time 10 https://checkip.amazonaws.com | tr -d '[:space:]')
	if [ -z "$ip" ]; then
		echo "$(date -u +%FT%TZ) could not determine public IP, retrying in ${RETRY}s"
		[ -z "$last_ip" ] && network_was_down=1
		sleep "$RETRY"
		continue
	fi

	resp=$(curl -fsS --max-time 15 "https://www.duckdns.org/update?domains=${DUCKDNS_SUBDOMAIN}&token=${DUCKDNS_TOKEN}&ip=${ip}")
	echo "$(date -u +%FT%TZ) ip=${ip} duckdns=${resp:-no-response}"

	if [ -n "$last_ip" ] && [ "$ip" != "$last_ip" ]; then
		restart_neko "public IP changed ${last_ip} -> ${ip}"
	elif [ -z "$last_ip" ] && [ "$network_was_down" = 1 ]; then
		restart_neko "network came up after startup"
	fi
	last_ip="$ip"
	sleep "$INTERVAL"
done
