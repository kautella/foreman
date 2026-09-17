#!/usr/bin/env bash

set -u

repo_root="$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)"
# shellcheck source=tests/test-helper.sh
. "$repo_root/tests/test-helper.sh"

test_root=$(mktemp -d '/tmp/foreman-live-check.XXXXXX') || exit 1
trap 'rm -rf "$test_root"' EXIT HUP INT TERM
fakebin="$test_root/fakebin"
fake_state="$test_root/fake-tmux"
evidence="$test_root/evidence"
evidence_canonical="$(CDPATH='' cd -P -- "$test_root" && pwd)/evidence"
mkdir -p "$fakebin" "$fake_state"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -u' \
  'state=${FAKE_TMUX_STATE:?}' \
  'if [ "${1:-}" = -L ]; then shift 2; fi' \
  'command=${1:-}' \
  'shift || true' \
  'case "$command" in' \
  '  -V) printf "tmux live fake 1.0\\n" ;;' \
  '  has-session)' \
  '    [ "${1:-}" = -t ] || exit 64' \
  '    [ -f "$state/$2" ]' \
  '    ;;' \
  '  new-session)' \
  '    session=""' \
  '    while [ "$#" -gt 0 ]; do' \
  '      case "$1" in' \
  '        -d) shift ;;' \
  '        -s) session=$2; shift 2 ;;' \
  '        -c) shift 2 ;;' \
  '        *) break ;;' \
  '      esac' \
  '    done' \
  '    [ -n "$session" ] && [ "$#" -eq 2 ] || exit 64' \
  '    printf "owned live endpoint\\n" >"$state/$session"' \
  '    ;;' \
  '  capture-pane) printf "live fake capture\\n" ;;' \
  '  kill-session)' \
  '    [ "${1:-}" = -t ] || exit 64' \
  '    rm -f -- "$state/$2"' \
  '    ;;' \
  '  *) exit 64 ;;' \
  'esac' >"$fakebin/tmux"
chmod +x "$fakebin/tmux"

test_live_tmux_harness_retains_durable_evidence() {
  local output
  output=$(PATH="$fakebin:$PATH" FAKE_TMUX_STATE="$fake_state" "$repo_root/scripts/live-check.sh" \
    --tmux --evidence-dir "$evidence") || test_fail 'live tmux harness did not complete against the portable runtime fake'
  test_assert_contains "$output" "Live tmux evidence: $evidence_canonical" 'live tmux harness did not report its evidence location'
  jq -e '
    .mode == "tmux" and .status == "passed" and .task_id == null and .report == null
  ' "$evidence/live-result.json" >/dev/null || test_fail 'live tmux harness did not retain a valid completion record'
  jq -e '.state == "closed"' "$evidence/tmux-state/endpoint.json" >/dev/null \
    || test_fail 'live tmux harness did not retain proven endpoint closure evidence'
  [ -f "$evidence/tmux-state/capture.txt" ] || test_fail 'live tmux harness did not retain bounded capture evidence'
  test_pass 'opt-in live tmux harness uses adapter-owned operations and retains evidence'
}

test_codex_live_mode_requires_explicit_usage_authority() {
  local output status
  set +e
  output="$($repo_root/scripts/live-check.sh --codex-task --evidence-dir "$test_root/no-authority" 2>&1)"
  status=$?
  set -e
  [ "$status" -ne 0 ] || test_fail 'Codex live mode accepted no explicit usage authority'
  test_assert_contains "$output" 'requires --allow-codex-usage, --model, and --reasoning' \
    'Codex live mode refusal did not explain the required authority and profile'
  [ ! -e "$test_root/no-authority" ] || test_fail 'Codex live mode created evidence before explicit usage authority'
  test_pass 'real Codex live mode requires explicit usage authority and profile selection'
}

test_live_tmux_harness_retains_durable_evidence
test_codex_live_mode_requires_explicit_usage_authority
