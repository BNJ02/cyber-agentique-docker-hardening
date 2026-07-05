#!/usr/bin/env bash
# =============================================================================
#  Before/after harness. Runs the compromised-agent attack script against the
#  baseline (nu) and hardened (durci) deployments, captures proof, and emits a
#  results table. Idempotent: it snapshots the pristine config and restores it.
#
#  Usage:  demo/run-attacks.sh            # both, + table
#          demo/run-attacks.sh baseline   # only baseline
#          demo/run-attacks.sh hardened   # only hardened
# =============================================================================
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
EV="$ROOT/evidence"
mkdir -p "$EV"
SNAP="$(mktemp -d)"

log() { echo -e "\n\033[1;36m== $* ==\033[0m"; }

snapshot_config() { rm -rf "$SNAP/config"; cp -a "$ROOT/config" "$SNAP/config"; }
restore_config()  { rm -rf "$ROOT/config"; cp -a "$SNAP/config" "$ROOT/config"; }

run_attacks_in() {   # $1 = compose file, $2 = label
  local file="$1" label="$2"
  docker compose -f "$file" exec -T agent bash -s < attacks/attack.sh \
      | tee "$EV/${label}_results.txt"
}

do_baseline() {
  log "BASELINE (agent nu) — bring up"
  docker compose -f compose.baseline.yml up -d --build
  sleep 3
  log "BASELINE — run attacks"
  run_attacks_in compose.baseline.yml baseline
  log "BASELINE — capture evidence"
  docker compose -f compose.baseline.yml logs exfil > "$EV/baseline_exfil.log" 2>&1 || true
  diff -ru "$SNAP/config" "$ROOT/config" > "$EV/baseline_config_diff.txt" 2>&1 \
      && echo "(config unchanged)" > "$EV/baseline_config_diff.txt" \
      || echo "^ host config was MODIFIED by the compromised agent (see diff above)"
  docker compose -f compose.baseline.yml down -v
  restore_config   # undo the damage the baseline attack did to ./config
}

do_hardened() {
  restore_config   # ensure pristine config before hardened run
  log "HARDENED (agent durci) — bring up"
  docker compose -f compose.hardened.yml up -d --build
  sleep 3
  log "HARDENED — sanity: user / caps / seccomp"
  {
    echo "## identity"; docker compose -f compose.hardened.yml exec -T agent id
    echo "## no-new-privileges + caps"; docker compose -f compose.hardened.yml exec -T agent sh -c 'grep -E "CapEff|NoNewPrivs" /proc/self/status'
    echo "## rootfs read-only test"; docker compose -f compose.hardened.yml exec -T agent sh -c 'touch /rootfs_write_test 2>&1 || echo "rootfs write refused (expected)"'
  } > "$EV/hardened_sanity.txt" 2>&1
  log "HARDENED — run attacks"
  run_attacks_in compose.hardened.yml hardened
  log "HARDENED — capture evidence"
  docker diff agent_hardened > "$EV/hardened_docker_diff.txt" 2>&1 || true
  if diff -ru "$SNAP/config" "$ROOT/config" > /dev/null 2>&1; then
    echo "host config UNCHANGED after hardened attack (read-only mount held)" \
        | tee "$EV/hardened_config_diff.txt"
  else
    diff -ru "$SNAP/config" "$ROOT/config" | tee "$EV/hardened_config_diff.txt"
  fi
  docker compose -f compose.hardened.yml down -v
}

build_table() {
  [ -f "$EV/baseline_results.txt" ] && [ -f "$EV/hardened_results.txt" ] || return 0
  log "Building results table"
  {
    echo "| # | Attaque tentée | Agent nu | Agent durci |"
    echo "|---|----------------|----------|-------------|"
    for id in 1 2 3 4 5 6; do
      b=$(grep "^RESULT|$id|" "$EV/baseline_results.txt" | head -1)
      h=$(grep "^RESULT|$id|" "$EV/hardened_results.txt" | head -1)
      name=$(echo "$b" | cut -d'|' -f3)
      bstat=$(echo "$b" | cut -d'|' -f4); bdet=$(echo "$b" | cut -d'|' -f5)
      hstat=$(echo "$h" | cut -d'|' -f4); hdet=$(echo "$h" | cut -d'|' -f5)
      echo "| $id | $name | ${bstat} | ${hstat} (${hdet}) |"
    done
  } | tee "$EV/results_table.md"
}

snapshot_config
case "${1:-both}" in
  baseline) do_baseline ;;
  hardened) do_hardened ;;
  both)     do_baseline; do_hardened; build_table ;;
  *) echo "usage: $0 [baseline|hardened|both]"; exit 1 ;;
esac
restore_config
rm -rf "$SNAP"
log "Done. Evidence in $EV/"
