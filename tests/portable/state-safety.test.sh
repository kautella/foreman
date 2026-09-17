#!/usr/bin/env bash

set -u

repo_root="$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)"
FOREMAN_SOURCE_ROOT=$repo_root
export FOREMAN_SOURCE_ROOT
# shellcheck source=src/state/atomic.sh
. "$repo_root/src/state/atomic.sh"
# shellcheck source=src/state/events.sh
. "$repo_root/src/state/events.sh"
# shellcheck source=tests/test-helper.sh
. "$repo_root/tests/test-helper.sh"

test_root=$(mktemp -d '/tmp/foreman-state-safety.XXXXXX') || exit 1
trap 'rm -rf "$test_root"' EXIT HUP INT TERM
project_state="$test_root/project/state"
task_state="$test_root/project/tasks/task-0123456789ab"
mkdir -p "$project_state" "$task_state"

test_atomic_write_refuses_symbolic_sources() {
  local source link destination
  source="$test_root/source.json"
  link="$test_root/source-link.json"
  destination="$project_state/config.json"
  printf '{"safe":true}\n' >"$source"
  ln -s "$source" "$link"
  if foreman_atomic_write "$link" "$destination" >/dev/null 2>&1; then
    test_fail 'atomic write accepted a symbolic-link source'
  fi
  [ ! -e "$destination" ] || test_fail 'atomic write created state from symbolic-link source'
  test_pass 'atomic writes refuse symbolic-link sources'
}

test_project_locks_require_exact_owner_and_preserve_existing_state() {
  local lock owner output status
  lock="$project_state/project.lock"
  owner='owner-project-01'

  foreman_lock_acquire project "$lock" sample-project null "$owner" \
    || test_fail 'project lock acquisition failed'
  test_assert_equal "$(foreman_lock_inspect "$lock")" active \
    'fresh project lock was not reported active'
  jq -e --arg owner "$owner" '
    .scope == "project" and .project_slug == "sample-project" and
    .task_id == null and .lock_id == $owner
  ' "$lock/owner.json" >/dev/null || test_fail 'project lock owner record is incomplete'

  set +e
  output=$(foreman_lock_acquire project "$lock" sample-project null owner-project-02 2>&1)
  status=$?
  set -e
  [ "$status" -ne 0 ] || test_fail 'second project operation acquired an existing lock'
  test_assert_contains "$output" 'refusing automatic stale-lock recovery' \
    'existing project lock did not explain its preservation'

  if foreman_lock_release project "$lock" sample-project null wrong-owner-99 >/dev/null 2>&1; then
    test_fail 'unrelated owner released the project lock'
  fi
  [ -d "$lock" ] || test_fail 'failed release removed the project lock'
  foreman_lock_release project "$lock" sample-project null "$owner" \
    || test_fail 'exact owner could not release project lock'
  [ ! -e "$lock" ] || test_fail 'exact release left project lock behind'
  test_pass 'project locks preserve existing state and require exact ownership'
}

test_stale_locks_are_refused_without_reclamation() {
  local lock owner stale_owner output status
  lock="$test_root/stale/project.lock"
  owner='owner-stale-01'
  mkdir -p "${lock%/*}"
  foreman_lock_acquire project "$lock" sample-project null "$owner" \
    || test_fail 'stale-lock fixture acquisition failed'
  stale_owner="$test_root/stale-owner.json"
  jq '.pid = 2147483647' "$lock/owner.json" >"$stale_owner"
  foreman_atomic_write "$stale_owner" "$lock/owner.json" \
    || test_fail 'could not create stale-lock fixture'

  set +e
  output=$(foreman_lock_acquire project "$lock" sample-project null owner-stale-02 2>&1)
  status=$?
  set -e
  [ "$status" -ne 0 ] || test_fail 'stale lock was reclaimed automatically'
  test_assert_contains "$output" 'refusing automatic stale-lock recovery' \
    'stale lock refusal was not actionable'
  [ -f "$lock/owner.json" ] || test_fail 'stale owner record was removed'
  test_pass 'stale locks are refused and preserved for explicit recovery'
}

test_task_locked_event_log_is_append_only_and_contiguous() {
  local lock events event_one event_two duplicate duplicate_identity wrong_owner count
  lock="$task_state/task.lock"
  events="$task_state/events.jsonl"
  event_one="$test_root/event-one.json"
  event_two="$test_root/event-two.json"
  duplicate="$test_root/event-duplicate.json"
  duplicate_identity="$test_root/event-duplicate-identity.json"
  wrong_owner='owner-task-wrong'

  foreman_lock_acquire task "$lock" sample-project task-0123456789ab owner-task-01 \
    || test_fail 'task lock acquisition failed'
  jq '.sequence = 1 | .from = {status:"planned", condition:null} | .to = {status:"approved", condition:null}' \
    "$repo_root/src/contracts/task/examples/event.json" >"$event_one"
  jq '.event_id = "event-0123456789ac" | .sequence = 2' \
    "$repo_root/src/contracts/task/examples/event.json" >"$event_two"

  foreman_events_append "$events" "$event_one" change task "$lock" sample-project task-0123456789ab owner-task-01 \
    || test_fail 'first task event was not appended'
  foreman_events_append "$events" "$event_two" change task "$lock" sample-project task-0123456789ab owner-task-01 \
    || test_fail 'second contiguous task event was not appended'
  count=$(wc -l <"$events" | tr -d ' ')
  test_assert_equal "$count" 2 'event log does not contain the two appended events'
  jq -s -e '.[0].sequence == 1 and .[1].sequence == 2' "$events" >/dev/null \
    || test_fail 'event log did not preserve its ordered JSONL records'

  jq '.sequence = 4' "$event_two" >"$duplicate"
  if foreman_events_append "$events" "$duplicate" change task "$lock" sample-project task-0123456789ab owner-task-01 >/dev/null 2>&1; then
    test_fail 'event log accepted a sequence gap'
  fi
  jq '.sequence = 3' "$event_two" >"$duplicate_identity"
  if foreman_events_append "$events" "$duplicate_identity" change task "$lock" sample-project task-0123456789ab owner-task-01 >/dev/null 2>&1; then
    test_fail 'event log accepted a duplicate event identity'
  fi
  if foreman_events_append "$events" "$event_two" change task "$lock" sample-project task-0123456789ab "$wrong_owner" >/dev/null 2>&1; then
    test_fail 'event append accepted an unrelated lock owner'
  fi
  test_assert_equal "$(wc -l <"$events" | tr -d ' ')" 2 \
    'refused event appends altered the durable log'
  foreman_lock_release task "$lock" sample-project task-0123456789ab owner-task-01 \
    || test_fail 'exact owner could not release task lock'
  test_pass 'task-locked events append atomically with contiguous sequences'
}

test_atomic_write_refuses_symbolic_sources
test_project_locks_require_exact_owner_and_preserve_existing_state
test_stale_locks_are_refused_without_reclamation
test_task_locked_event_log_is_append_only_and_contiguous
