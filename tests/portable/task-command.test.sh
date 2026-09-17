#!/usr/bin/env bash

set -u

repo_root="$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)"
foreman="$repo_root/foreman"
FOREMAN_SOURCE_ROOT=$repo_root
export FOREMAN_SOURCE_ROOT
# shellcheck source=src/tasks/validate.sh
. "$repo_root/src/tasks/validate.sh"
# shellcheck source=tests/test-helper.sh
. "$repo_root/tests/test-helper.sh"

test_root=$(mktemp -d '/tmp/foreman-task-command.XXXXXX') || exit 1
trap 'rm -rf "$test_root"' EXIT HUP INT TERM
fakebin="$test_root/fakebin"
fake_tmux_state="$test_root/fake-tmux"
home="$test_root/home"
repository="$test_root/repository"
mkdir -p "$fakebin" "$fake_tmux_state" "$repository"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'case "${1:-}" in' \
  '  --version) printf "codex fake 1.0\\n" ;;' \
  '  login)' \
  '    [ "${2:-}" = status ] || exit 64' \
  '    [ "${FAKE_CODEX_AUTH:-yes}" = yes ] || exit 1' \
  '    ;;' \
  '  *) exit 64 ;;' \
  'esac' >"$fakebin/codex"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -u' \
  'state=${FAKE_TMUX_STATE:?}' \
  'command=${1:-}' \
  'shift || true' \
  'case "$command" in' \
  '  -V) printf "tmux fake 1.0\\n" ;;' \
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
  '    printf "runner=%s\\nspec=%s\\n" "$1" "$2" >"$state/$session"' \
  '    ;;' \
  '  capture-pane) printf "fake terminal capture\\n" ;;' \
  '  kill-session)' \
  '    [ "${1:-}" = -t ] || exit 64' \
  '    rm -f -- "$state/$2"' \
  '    ;;' \
  '  *) exit 64 ;;' \
  'esac' >"$fakebin/tmux"
chmod +x "$fakebin/codex" "$fakebin/tmux"
PATH="$fakebin:$PATH"
FAKE_TMUX_STATE=$fake_tmux_state
export PATH FAKE_TMUX_STATE

git -C "$repository" init -q
printf 'fixture\n' >"$repository/README.md"
git -C "$repository" add README.md
git -C "$repository" -c user.name='Foreman Tests' -c user.email='tests@example.invalid' \
  commit -qm 'Create fixture'
git -C "$repository" config user.name 'Foreman Tests'
git -C "$repository" config user.email 'tests@example.invalid'

FOREMAN_HOME="$home" "$foreman" init \
  --name 'Task Project' --project "$repository" --agent codex --model test-model \
  --reasoning medium --runtime tmux --yes >/dev/null || test_fail 'task fixture initialization failed'
project_root="$home/projects/task-project"

plan_id_from_output() {
  printf '%s\n' "$1" | sed -n 's/^Created proposed plan \(plan-[0-9a-f]*\)$/\1/p'
}

task_id_from_output() {
  printf '%s\n' "$1" | sed -n 's/^Started task \(task-[0-9a-f]*\)$/\1/p'
}

create_plan() {
  local title=$1 input output plan_id
  input="$test_root/$title.json"
  jq --arg title "$title" '.title = $title | .tasks[0].validation = ["test -f RESULT.md"]' "$repo_root/src/contracts/plan/examples/direct-plan.json" >"$input"
  output=$(FOREMAN_HOME="$home" "$foreman" plan create --project task-project --file "$input") || return 1
  plan_id=$(plan_id_from_output "$output")
  [ -n "$plan_id" ] || return 1
  printf '%s\n' "$plan_id"
}

approve_plan() {
  FOREMAN_HOME="$home" "$foreman" plan approve --project task-project --plan "$1" --yes >/dev/null
}

test_start_requires_an_approved_plan_and_explicit_change_branch() {
  local plan_id output status task_count
  plan_id=$(create_plan 'Unapproved task') || test_fail 'could not create unapproved plan'
  task_count=$(find "$project_root/tasks" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')
  set +e
  output=$(FOREMAN_HOME="$home" "$foreman" task start --project task-project --plan "$plan_id" --task health-summary --branch feat/unapproved 2>&1)
  status=$?
  set -e
  [ "$status" -ne 0 ] || test_fail 'unapproved plan started a task'
  test_assert_contains "$output" 'plan is not approved' 'unapproved-plan refusal was unclear'
  test_assert_equal "$(find "$project_root/tasks" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')" "$task_count" \
    'unapproved plan created task state'

  approve_plan "$plan_id" || test_fail 'could not approve branch-requirement plan'
  set +e
  output=$(FOREMAN_HOME="$home" "$foreman" task start --project task-project --plan "$plan_id" --task health-summary 2>&1)
  status=$?
  set -e
  [ "$status" -ne 0 ] || test_fail 'change task started without an explicit branch'
  test_assert_contains "$output" 'requires an explicit --branch' 'missing-branch refusal was unclear'
  test_pass 'task start refuses unapproved plans and unnamed change branches without state'
}

test_start_persists_identity_before_launch_and_status_is_read_only() {
  local plan_id output task_id task_file endpoint worktree session status_output before after
  plan_id=$(create_plan 'Start task') || test_fail 'could not create start plan'
  approve_plan "$plan_id" || test_fail 'could not approve start plan'
  output=$(FOREMAN_HOME="$home" "$foreman" task start --project task-project --plan "$plan_id" --task health-summary --branch feat/task-command) \
    || test_fail 'approved change task did not start through the fake adapters'
  task_id=$(task_id_from_output "$output")
  [ -n "$task_id" ] || test_fail 'task start did not report its durable identity'
  task_file="$project_root/tasks/$task_id/task.json"
  endpoint="$project_root/tasks/$task_id/endpoint.json"
  worktree=$(jq -r '.worktree.path' "$task_file")
  session="foreman-task-${task_id#task-}"
  foreman_task_validate_metadata "$task_file" || test_fail 'started task metadata is invalid'
  jq -e --arg task_id "$task_id" '
    .task_id == $task_id and
    .lifecycle == {status:"running", condition:null, updated_at:.lifecycle.updated_at, sequence:3} and
    .configuration_snapshot.path == (.artifacts.events | sub("/events.jsonl$"; "/configuration.json")) and
    .worktree.branch == "feat/task-command" and
    (.runtime_endpoint.path | endswith("/endpoint.json"))
  ' "$task_file" >/dev/null || test_fail 'task start did not persist complete prepared identity before launch'
  [ -f "$project_root/tasks/$task_id/configuration.json" ] && [ -f "$project_root/tasks/$task_id/worktree.json" ] && \
    [ -f "$project_root/tasks/$task_id/endpoint-owner.json" ] && [ -f "$project_root/tasks/$task_id/codex-launch.json" ] || \
    test_fail 'task start omitted durable launch evidence'
  [ -d "$worktree" ] && [ -f "$fake_tmux_state/$session" ] || \
    test_fail 'task start did not create the exact worktree and owned tmux session'
  test_assert_equal "$(git -C "$worktree" symbolic-ref --quiet --short HEAD)" 'feat/task-command' \
    'task worktree branch is not the exact requested branch'
  [ -z "$(git -C "$repository" status --porcelain=v1 --untracked-files=all)" ] || \
    test_fail 'task start dirtied the managed repository'
  [ "$(wc -l <"$project_root/tasks/$task_id/events.jsonl" | tr -d ' ')" = 3 ] || \
    test_fail 'task start did not append the complete lifecycle event sequence'
  before=$(shasum -a 256 "$task_file" | awk '{print $1}')
  status_output=$(FOREMAN_HOME="$home" "$foreman" task status --project task-project --task "$task_id") \
    || test_fail 'task status failed for a running task'
  after=$(shasum -a 256 "$task_file" | awk '{print $1}')
  test_assert_equal "$after" "$before" 'task status mutated durable task state'
  test_assert_contains "$status_output" 'Lifecycle: running' 'task status did not report lifecycle state'
  test_assert_contains "$status_output" 'Endpoint state: active' 'task status did not report runtime state'
  test_pass 'task start records complete state before launch and status only observes it'
  FOREMAN_TEST_TASK_ID=$task_id
  export FOREMAN_TEST_TASK_ID
}

test_reconcile_preserves_absence_and_recovers_proven_liveness() {
  local task_id session output task_file endpoint
  task_id=${FOREMAN_TEST_TASK_ID:-}
  [ -n "$task_id" ] || test_fail 'prior start fixture did not expose a task identity'
  session="foreman-task-${task_id#task-}"
  task_file="$project_root/tasks/$task_id/task.json"
  endpoint="$project_root/tasks/$task_id/endpoint.json"
  rm -f -- "$fake_tmux_state/$session"
  output=$(FOREMAN_HOME="$home" "$foreman" task reconcile --project task-project --task "$task_id") \
    || test_fail 'reconcile did not preserve an absent endpoint as a missing condition'
  test_assert_contains "$output" 'Condition: missing' 'missing endpoint was not reported as a durable condition'
  test_assert_contains "$output" 'Worker evidence: terminal result is not yet complete' \
    'reconciliation did not distinguish incomplete durable worker evidence'
  jq -e '.lifecycle.status == "running" and .lifecycle.condition == "missing" and .lifecycle.sequence == 4' "$task_file" >/dev/null || \
    test_fail 'missing endpoint did not preserve the stable running lifecycle'
  jq -e '.state == "missing"' "$endpoint" >/dev/null || test_fail 'endpoint absence was not recorded'
  printf 'recovered\n' >"$fake_tmux_state/$session"
  output=$(FOREMAN_HOME="$home" "$foreman" task reconcile --project task-project --task "$task_id") \
    || test_fail 'reconcile did not recover a proven active endpoint'
  test_assert_contains "$output" 'Lifecycle: running' 'reconciliation did not resume running supervision'
  test_assert_contains "$output" 'Condition: none' 'reconciliation did not clear the recovered condition'
  jq -e '.lifecycle.status == "running" and .lifecycle.condition == null and .lifecycle.sequence == 6' "$task_file" >/dev/null || \
    test_fail 'reconciliation did not use explicit recovery transitions'
  [ "$(wc -l <"$project_root/tasks/$task_id/events.jsonl" | tr -d ' ')" = 6 ] || \
    test_fail 'reconciliation did not preserve the append-only event history'
  test_pass 'reconcile preserves missing work and resumes only after proven endpoint liveness'
}

test_validate_prepares_a_local_change_handoff_after_terminal_evidence() {
  local task_id task_file worktree session output handoff result
  task_id=${FOREMAN_TEST_TASK_ID:-}
  [ -n "$task_id" ] || test_fail 'prior task fixture did not expose a task identity'
  task_file="$project_root/tasks/$task_id/task.json"
  worktree=$(jq -r '.worktree.path' "$task_file")
  session="foreman-task-${task_id#task-}"
  printf 'completed change\n' >"$worktree/RESULT.md"
  git -C "$worktree" add RESULT.md
  git -C "$worktree" commit -qm 'Add result'
  rm -f -- "$fake_tmux_state/$session"
  printf '%s\n%s\n' '{"type":"thread.started"}' '{"type":"turn.completed"}' >"$project_root/tasks/$task_id/codex-events.jsonl"
  printf '%s\n' '{"status":"completed","summary":"Implemented the requested local change.","changed_files":["RESULT.md"],"risks":[]}' >"$project_root/tasks/$task_id/codex-final.json"
  output=$(FOREMAN_HOME="$home" "$foreman" task validate --project task-project --task "$task_id") \
    || test_fail 'terminal completed task did not validate'
  handoff=$(jq -r '.artifacts.handoff' "$task_file")
  result=$(jq -r '.artifacts.result' "$task_file")
  test_assert_contains "$output" 'Lifecycle: delivery-ready' 'validated change did not become delivery-ready'
  foreman_task_validate_handoff "$handoff" || test_fail 'local handoff does not match its durable contract'
  foreman_task_validate_result "$result" || test_fail 'change result does not match its durable contract'
  jq -e --arg handoff "$handoff" --arg result "$result" '
    .lifecycle.status == "delivery-ready" and .lifecycle.condition == null and
    .artifacts.handoff == $handoff and .artifacts.result == $result
  ' "$task_file" >/dev/null || test_fail 'task metadata does not reference the prepared local handoff'
  [ "$(wc -l <"$project_root/tasks/$task_id/events.jsonl" | tr -d ' ')" = 9 ] || \
    test_fail 'validation and handoff preparation did not preserve lifecycle history'
  test_pass 'terminal change evidence runs validation and produces a local-only handoff'
}

test_teardown_requires_explicit_authority_and_proves_local_landing() {
  local task_id task_file worktree head output status teardown_record event_count
  task_id=${FOREMAN_TEST_TASK_ID:-}
  [ -n "$task_id" ] || test_fail 'prior task fixture did not expose a task identity'
  task_file="$project_root/tasks/$task_id/task.json"
  worktree=$(jq -r '.worktree.path' "$task_file")

  set +e
  output=$(FOREMAN_HOME="$home" "$foreman" task teardown --project task-project --task "$task_id" 2>&1)
  status=$?
  set -e
  [ "$status" -ne 0 ] || test_fail 'teardown accepted no explicit authority'
  test_assert_contains "$output" 'requires exactly one of --landed-at or --discard' \
    'missing teardown authority was unclear'
  [ -d "$worktree" ] || test_fail 'authority refusal removed a task worktree'

  head=$(git -C "$worktree" rev-parse HEAD)
  set +e
  output=$(FOREMAN_HOME="$home" "$foreman" task teardown --project task-project --task "$task_id" --landed-at "$head" 2>&1)
  status=$?
  set -e
  [ "$status" -ne 0 ] || test_fail 'teardown accepted an unlanded change as landed'
  test_assert_contains "$output" 'managed repository current HEAD' 'unlanded change refusal was unclear'
  [ -d "$worktree" ] || test_fail 'unlanded-change refusal removed a task worktree'

  git -C "$repository" merge --ff-only -q feat/task-command || test_fail 'fixture could not locally land the exact task branch'
  head=$(git -C "$repository" rev-parse HEAD)
  output=$(FOREMAN_HOME="$home" "$foreman" task teardown --project task-project --task "$task_id" --landed-at "$head") \
    || test_fail 'teardown did not remove a proven locally landed worktree'
  test_assert_contains "$output" "Closed task $task_id" 'successful teardown did not report the exact task closure'
  [ ! -e "$worktree" ] && [ ! -L "$worktree" ] || test_fail 'landed task worktree remains after teardown'
  teardown_record=$(jq -r '.artifacts.teardown' "$task_file")
  foreman_task_validate_teardown_record "$teardown_record" || test_fail 'landed teardown record is invalid'
  jq -e --arg head "$head" '
    .lifecycle.status == "closed" and .lifecycle.condition == null and
    .artifacts.teardown != null
  ' "$task_file" >/dev/null || test_fail 'landed teardown did not close durable task state'
  jq -e --arg head "$head" '
    .authority == {kind:"confirmed-local-landing", landing_commit:$head} and
    .worktree.head_commit == $head and .outcome == "closed" and .completed_at != null
  ' "$teardown_record" >/dev/null || test_fail 'landed teardown record lacks exact landing evidence'
  event_count=$(wc -l <"$project_root/tasks/$task_id/events.jsonl" | tr -d ' ')
  test_assert_equal "$event_count" 12 'landed teardown did not append its complete durable lifecycle evidence'
  output=$(FOREMAN_HOME="$home" "$foreman" task reconcile --project task-project --task "$task_id") \
    || test_fail 'closed task reconciliation should remain a read-only acknowledgement'
  test_assert_contains "$output" "Task $task_id is already closed" 'closed task reconciliation was unclear'
  test_pass 'teardown requires explicit authority and removes only a proven locally landed worktree'
}

test_explicit_discard_removes_only_the_exact_task_owned_worktree() {
  local plan_id output task_id task_file worktree session teardown_record repository_head
  plan_id=$(create_plan 'Discard task') || test_fail 'could not create explicit-discard plan'
  approve_plan "$plan_id" || test_fail 'could not approve explicit-discard plan'
  output=$(FOREMAN_HOME="$home" "$foreman" task start --project task-project --plan "$plan_id" --task health-summary --branch feat/discard-task) \
    || test_fail 'could not start explicit-discard task'
  task_id=$(task_id_from_output "$output")
  [ -n "$task_id" ] || test_fail 'explicit-discard task did not have a durable identity'
  task_file="$project_root/tasks/$task_id/task.json"
  worktree=$(jq -r '.worktree.path' "$task_file")
  session="foreman-task-${task_id#task-}"
  printf 'discarded change\n' >"$worktree/RESULT.md"
  git -C "$worktree" add RESULT.md
  git -C "$worktree" commit -qm 'Add discarded result'
  rm -f -- "$fake_tmux_state/$session"
  printf '%s\n%s\n' '{"type":"thread.started"}' '{"type":"turn.completed"}' >"$project_root/tasks/$task_id/codex-events.jsonl"
  printf '%s\n' '{"status":"completed","summary":"Prepared a change that the maintainer explicitly discarded.","changed_files":["RESULT.md"],"risks":[]}' >"$project_root/tasks/$task_id/codex-final.json"
  FOREMAN_HOME="$home" "$foreman" task validate --project task-project --task "$task_id" >/dev/null \
    || test_fail 'explicit-discard task did not reach local handoff state'
  printf 'uncommitted and explicitly discarded\n' >"$worktree/DISCARD.md"
  repository_head=$(git -C "$repository" rev-parse HEAD)
  output=$(FOREMAN_HOME="$home" "$foreman" task teardown --project task-project --task "$task_id" --discard) \
    || test_fail 'explicit discard did not remove the exact task worktree'
  test_assert_contains "$output" "Closed task $task_id" 'explicit discard did not report the exact task closure'
  [ ! -e "$worktree" ] && [ ! -L "$worktree" ] || test_fail 'explicit discard left its task worktree present'
  test_assert_equal "$(git -C "$repository" rev-parse HEAD)" "$repository_head" \
    'explicit discard changed the managed repository current branch'
  teardown_record=$(jq -r '.artifacts.teardown' "$task_file")
  foreman_task_validate_teardown_record "$teardown_record" || test_fail 'explicit discard teardown record is invalid'
  jq -e '
    .lifecycle.status == "closed" and
    .artifacts.teardown != null
  ' "$task_file" >/dev/null || test_fail 'explicit discard did not close durable task state'
  jq -e '
    .authority == {kind:"explicit-discard", landing_commit:null} and .outcome == "closed"
  ' "$teardown_record" >/dev/null || test_fail 'explicit discard record lacks explicit exact-task authority'
  test_pass 'explicit discard removes unlanded task work only after an exact-task authority request'
}

test_validate_prepares_an_always_dark_research_report() {
  local research_home research_repository input output plan_id task_id task_file session report findings result
  research_home="$test_root/research-home"
  research_repository="$test_root/research-repository"
  mkdir -p "$research_repository"
  git -C "$research_repository" init -q
  printf 'research fixture\n' >"$research_repository/README.md"
  git -C "$research_repository" add README.md
  git -C "$research_repository" -c user.name='Foreman Tests' -c user.email='tests@example.invalid' \
    commit -qm 'Create research fixture'
  FOREMAN_HOME="$research_home" "$foreman" init \
    --name 'Research Project' --project "$research_repository" --agent codex --model test-model \
    --reasoning medium --runtime tmux --yes >/dev/null || test_fail 'research fixture initialization failed'
  input="$test_root/research-plan.json"
  jq '.title = "Research task" | .tasks[0].type = "research" | .tasks[0].validation = ["test -f README.md"]' \
    "$repo_root/src/contracts/plan/examples/direct-plan.json" >"$input"
  output=$(FOREMAN_HOME="$research_home" "$foreman" plan create --project research-project --file "$input") \
    || test_fail 'could not create research plan'
  plan_id=$(plan_id_from_output "$output")
  FOREMAN_HOME="$research_home" "$foreman" plan approve --project research-project --plan "$plan_id" --yes >/dev/null \
    || test_fail 'could not approve research plan'
  output=$(FOREMAN_HOME="$research_home" "$foreman" task start --project research-project --plan "$plan_id" --task health-summary) \
    || test_fail 'branchless research task did not start'
  task_id=$(task_id_from_output "$output")
  task_file="$research_home/projects/research-project/tasks/$task_id/task.json"
  session="foreman-task-${task_id#task-}"
  rm -f -- "$fake_tmux_state/$session"
  printf '%s\n%s\n' '{"type":"thread.started"}' '{"type":"turn.completed"}' >"$research_home/projects/research-project/tasks/$task_id/codex-events.jsonl"
  printf '%s\n' '{"status":"completed","summary":"The repository is healthy for the bounded research objective.","changed_files":[],"risks":[]}' >"$research_home/projects/research-project/tasks/$task_id/codex-final.json"
  output=$(FOREMAN_HOME="$research_home" "$foreman" task validate --project research-project --task "$task_id") \
    || test_fail 'terminal research task did not validate'
  test_assert_contains "$output" 'Lifecycle: report-ready' 'validated research did not become report-ready'
  report=$(jq -r '.artifacts.report' "$task_file")
  findings=$(jq -r '.artifacts.findings' "$task_file")
  result=$(jq -r '.artifacts.result' "$task_file")
  [ -f "$report" ] && [ "${report##*/}" = report-health-summary.html ] || \
    test_fail 'research report does not use the required report-slug filename'
  grep -Fq 'color-scheme:dark' "$report" || test_fail 'research report does not force the dark presentation'
  foreman_task_validate_research_finding "$findings" || test_fail 'research finding does not match its durable contract'
  foreman_task_validate_result "$result" || test_fail 'research result does not match its durable contract'
  [ -z "$(git -C "$research_repository" status --porcelain=v1 --untracked-files=all)" ] || \
    test_fail 'research validation mutated the managed repository'
  test_pass 'terminal research evidence produces a standalone always-dark report without repository mutation'
}

test_unavailable_preflight_creates_no_new_task_state() {
  local plan_id output status before after
  plan_id=$(create_plan 'Unavailable adapter') || test_fail 'could not create unavailable-adapter plan'
  approve_plan "$plan_id" || test_fail 'could not approve unavailable-adapter plan'
  before=$(find "$project_root/tasks" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')
  set +e
  output=$(FAKE_CODEX_AUTH=no FOREMAN_HOME="$home" "$foreman" task start --project task-project --plan "$plan_id" --task health-summary --branch feat/unavailable 2>&1)
  status=$?
  set -e
  [ "$status" -ne 0 ] || test_fail 'unavailable Codex authentication started a task'
  test_assert_contains "$output" 'no task state was created' 'unavailable-adapter refusal was unclear'
  after=$(find "$project_root/tasks" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')
  test_assert_equal "$after" "$before" 'unavailable adapter created task state'
  test_pass 'unavailable adapter preflight refuses task start before durable mutation'
}

test_task_metadata_cannot_redirect_runtime_state() {
  local task_id task_file unowned temporary output status
  task_id=${FOREMAN_TEST_TASK_ID:-}
  [ -n "$task_id" ] || test_fail 'prior task fixture did not expose a task identity'
  task_file="$project_root/tasks/$task_id/task.json"
  unowned="$test_root/unowned-endpoint.json"
  temporary="$test_root/tampered-task.json"
  printf '%s\n' '{}' >"$unowned"
  jq --arg unowned "$unowned" '.runtime_endpoint.path = $unowned' "$task_file" >"$temporary" \
    || test_fail 'could not create metadata-tampering fixture'
  mv "$temporary" "$task_file"
  set +e
  output=$(FOREMAN_HOME="$home" "$foreman" task status --project task-project --task "$task_id" 2>&1)
  status=$?
  set -e
  [ "$status" -ne 0 ] || test_fail 'task status accepted redirected runtime state'
  test_assert_contains "$output" 'outside its exact task directory' \
    'redirected runtime state refusal was unclear'
  test_pass 'task state refuses runtime references redirected outside its exact task directory'
}

test_start_requires_an_approved_plan_and_explicit_change_branch
test_start_persists_identity_before_launch_and_status_is_read_only
test_reconcile_preserves_absence_and_recovers_proven_liveness
test_validate_prepares_a_local_change_handoff_after_terminal_evidence
test_teardown_requires_explicit_authority_and_proves_local_landing
test_explicit_discard_removes_only_the_exact_task_owned_worktree
test_validate_prepares_an_always_dark_research_report
test_unavailable_preflight_creates_no_new_task_state
test_task_metadata_cannot_redirect_runtime_state
