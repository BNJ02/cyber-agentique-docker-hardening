#!/usr/bin/env bash
# =============================================================================
#  BONUS runner: shows the SAME exfil attempt succeeding through an allowlisted
#  domain with the NAIVE proxy, then blocked by the DEFENSIVE MITM proxy.
# =============================================================================
set -uo pipefail
cd "$(dirname "$0")/.."
EV="$(pwd)/evidence"; mkdir -p "$EV"
log() { echo -e "\n\033[1;35m== $* ==\033[0m"; }

run_mode() {   # $1 = off|on
  local mode="$1" label="$2"
  log "BONUS DEFENSE=$mode ($label)"
  DEFENSE="$mode" docker compose -f compose.bonus.yml up -d --build >/dev/null 2>&1
  sleep 4
  docker compose -f compose.bonus.yml exec -T agent bash -s < attacks/bonus_attack.sh \
      | tee "$EV/bonus_${label}_results.txt"
  echo "--- egress proxy decision log ---"
  docker compose -f compose.bonus.yml logs egress 2>&1 | grep -E "\[egress\]" | tail -6 \
      | tee "$EV/bonus_${label}_egress.log"
  echo "--- trusted-api (attacker landing) log ---"
  docker compose -f compose.bonus.yml logs trusted-api 2>&1 | grep -E "ATTACKER UPLOAD|legit model" | tail -6 \
      | tee "$EV/bonus_${label}_trusted.log"
  docker compose -f compose.bonus.yml down -v >/dev/null 2>&1
}

run_mode off naive       # exfil SUCCEEDS through allowlisted domain
run_mode on  defensive   # exfil BLOCKED by content/identity-aware MITM
log "Bonus done. Evidence in $EV/bonus_*"
