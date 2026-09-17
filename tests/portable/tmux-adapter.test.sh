#!/usr/bin/env bash

set -u

repo_root="$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)"
FOREMAN_SOURCE_ROOT=$repo_root
export FOREMAN_SOURCE_ROOT
# shellcheck source=src/adapters/runtimes/tmux/adapter.sh
. "$repo_root/src/adapters/runtimes/tmux/adapter.sh"
# shellcheck source=tests/test-helper.sh
. "$repo_root/tests/test-helper.sh"

test_root=$(mktemp -d '/tmp/foreman-tmux-adapter.XXXXXX') || exit 1
trap 'rm -rf "$test_root"' EXIT HUP INT TERM
fakebin="$test_root/fakebin"
fake_state="$test_root/fake-tmux"
task_state="$test_root/task-state"
worktree="$test_root/worktree"
mkdir -p "$fakebin" "$fake_state" "$task_state" "$worktree"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -u' \
  'state=${FAKE_TMUX_STATE:?}' \
  'server=${FOREMAN_TMUX_SERVER_NAME:?}' \
  '[ "${1:-}" = -L ] && [ "${2:-}" = "$server" ] || exit 64' \
  'shift 2' \
  'command=${1:-}' \
  'shift || true' \
  'case "$command" in' \
  '  -V)' \
  '    printf "tmux fake 1.0\\n"' \
  '    ;;' \
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
  '    [ ! -e "$state/$session" ] || exit 1' \
  '    printf "runner=%s\\nspec=%s\\n" "$1" "$2" > "$state/$session"' \
  '    ;;' \
  '  capture-pane)' \
  '    printf "fake terminal capture\\n"' \
  '    ;;' \
  '  kill-session)' \
  '    [ "${1:-}" = -t ] || exit 64' \
  '    rm -f -- "$state/$2"' \
  '    ;;' \
  '  *) exit 64 ;;' \
  'esac' >"$fakebin/tmux"
chmod +x "$fakebin/tmux"
PATH="$fakebin:$PATH"
FAKE_TMUX_STATE=$fake_state
FOREMAN_TMUX_SERVER_NAME=foreman-test-01
export PATH FAKE_TMUX_STATE FOREMAN_TMUX_SERVER_NAME
printf 'Complete the bounded task and return the required JSON result.\n' >"$task_state/brief.md"

write_launch_spec() {
  local request="$task_state/request.json" spec="$task_state/launch.json"
  jq -n \
    --arg worktree "$worktree" \
    --arg prompt "$task_state/brief.md" \
    --arg jsonl "$task_state/events.jsonl" \
    --arg stderr_path "$task_state/runtime.stderr.log" \
    --arg final "$task_state/final.json" '
      {
        schema_version: 1,
        request_id: "codex-request-0123456789ab",
        task_id: "task-0123456789ab",
        task_type: "change",
        worktree_path: $worktree,
        profile: {model: "gpt-5.6-terra", reasoning: "medium"},
        prompt_path: $prompt,
        jsonl_path: $jsonl,
        stderr_path: $stderr_path,
        final_output_path: $final
      }
    ' >"$request"
  foreman_codex_build_launch_spec "$request" "$spec" \
    || test_fail 'tmux fixture could not create a Codex launch specification'
  printf '%s\n' "$spec"
}

acquire_task_lock() {
  foreman_lock_acquire task "$task_state/task.lock" sample-project task-0123456789ab owner-tmux-01 \
    || test_fail 'could not acquire task lock'
}

release_task_lock() {
  foreman_lock_release task "$task_state/task.lock" sample-project task-0123456789ab owner-tmux-01 \
    || test_fail 'could not release task lock'
}

test_diagnose_and_reservation_create_exact_owned_endpoint() {
  local diagnosis endpoint owner_marker
  diagnosis="$task_state/diagnosis.json"
  endpoint="$task_state/endpoint.json"
  owner_marker="$task_state/endpoint-owner.json"
  foreman_tmux_diagnose diagnose-tmux "$diagnosis" \
    || test_fail 'tmux diagnosis failed with fake runtime'
  jq -e '.ok == true and .status == "ok" and .data.version == "tmux fake 1.0"' "$diagnosis" >/dev/null \
    || test_fail 'tmux diagnosis did not return normalized version data'

  acquire_task_lock
  foreman_tmux_reserve_endpoint task-0123456789ab "$endpoint" "$owner_marker" sample-project "$task_state/task.lock" owner-tmux-01 \
    || test_fail 'could not reserve task-owned tmux endpoint'
  foreman_task_validate_endpoint "$endpoint" \
    || test_fail 'reserved endpoint did not match task endpoint contract'
  jq -e '.state == "reserved" and .endpoint_id == "endpoint-0123456789ab" and .location.session == "foreman-task-0123456789ab"' "$endpoint" >/dev/null \
    || test_fail 'reserved endpoint identity is not exact'
  foreman_tmux_validate_owner_marker "$owner_marker" \
    || test_fail 'endpoint owner marker did not validate'
  release_task_lock
  test_pass 'tmux diagnosis and reservation create exact task-owned endpoint evidence'
}

test_start_inspect_capture_and_close_require_proven_ownership() {
  local endpoint spec runner capture session
  endpoint="$task_state/endpoint.json"
  spec=$(write_launch_spec)
  runner="$task_state/runner.sh"
  capture="$task_state/capture.txt"
  session='foreman-task-0123456789ab'

  acquire_task_lock
  foreman_tmux_start "$endpoint" "$spec" "$runner" sample-project "$task_state/task.lock" owner-tmux-01 \
    || test_fail 'tmux did not start the adapter-provided launch specification'
  [ -x "$runner" ] && [ -f "$fake_state/$session" ] \
    || test_fail 'tmux start did not create the exact owned runner and session'
  jq -e '.state == "active" and .last_observed_at != null' "$endpoint" >/dev/null \
    || test_fail 'tmux start did not persist active endpoint state'
  foreman_tmux_inspect "$endpoint" sample-project "$task_state/task.lock" owner-tmux-01 \
    || test_fail 'tmux inspect did not confirm active session'
  foreman_tmux_capture "$endpoint" "$capture" sample-project "$task_state/task.lock" owner-tmux-01 \
    || test_fail 'tmux did not capture bounded task output'
  test_assert_contains "$(<"$capture")" 'fake terminal capture' \
    'tmux capture did not preserve bounded output'
  foreman_tmux_close "$endpoint" sample-project "$task_state/task.lock" owner-tmux-01 \
    || test_fail 'tmux did not close the proven task-owned session'
  [ ! -e "$fake_state/$session" ] || test_fail 'tmux close left task-owned session behind'
  jq -e '.state == "closed"' "$endpoint" >/dev/null \
    || test_fail 'tmux close did not persist closed endpoint state'
  release_task_lock
  test_pass 'tmux starts, inspects, captures, and closes only proven owned endpoint'
}

test_unowned_or_existing_sessions_are_not_adopted() {
  local task_id state endpoint owner_marker request spec runner session
  task_id='task-111111111111'
  state="$test_root/second-task"
  mkdir -p "$state"
  printf 'Task brief\n' >"$state/brief.md"
  foreman_lock_acquire task "$state/task.lock" sample-project "$task_id" owner-tmux-02 \
    || test_fail 'could not acquire second task lock'
  endpoint="$state/endpoint.json"
  owner_marker="$state/endpoint-owner.json"
  foreman_tmux_reserve_endpoint "$task_id" "$endpoint" "$owner_marker" sample-project "$state/task.lock" owner-tmux-02 \
    || test_fail 'could not reserve second endpoint'
  request="$state/request.json"
  spec="$state/launch.json"
  jq -n --arg worktree "$worktree" --arg prompt "$state/brief.md" --arg jsonl "$state/events.jsonl" --arg stderr_path "$state/runtime.stderr.log" --arg final "$state/final.json" --arg task_id "$task_id" '
    {schema_version:1, request_id:"codex-request-111111111111", task_id:$task_id, task_type:"change", worktree_path:$worktree, profile:{model:"gpt-5.6-terra", reasoning:"medium"}, prompt_path:$prompt, jsonl_path:$jsonl, stderr_path:$stderr_path, final_output_path:$final}
  ' >"$request"
  foreman_codex_build_launch_spec "$request" "$spec" \
    || test_fail 'could not create second launch spec'
  session='foreman-task-111111111111'
  printf 'unowned\n' >"$fake_state/$session"
  runner="$state/runner.sh"
  if foreman_tmux_start "$endpoint" "$spec" "$runner" sample-project "$state/task.lock" owner-tmux-02 >/dev/null 2>&1; then
    test_fail 'tmux adopted a pre-existing session'
  fi
  [ ! -e "$runner" ] || test_fail 'tmux wrote runner before refusing unowned session'
  foreman_lock_release task "$state/task.lock" sample-project "$task_id" owner-tmux-02 \
    || test_fail 'could not release second task lock'
  test_pass 'tmux refuses to adopt existing endpoint sessions'
}

test_diagnose_and_reservation_create_exact_owned_endpoint
test_start_inspect_capture_and_close_require_proven_ownership
test_unowned_or_existing_sessions_are_not_adopted
