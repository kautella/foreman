#!/usr/bin/env bash

set -u

repo_root="$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)"
foreman="$repo_root/foreman"
# shellcheck source=tests/test-helper.sh
. "$repo_root/tests/test-helper.sh"

test_root=$(mktemp -d '/tmp/foreman-plan-review.XXXXXX') || exit 1
trap 'rm -rf "$test_root"' EXIT HUP INT TERM
fakebin="$test_root/fakebin"
home="$test_root/home"
repository="$test_root/repository"
mkdir -p "$fakebin" "$repository"
for executable in codex herdr; do
  printf '#!/usr/bin/env bash\nexit 0\n' >"$fakebin/$executable"
  chmod +x "$fakebin/$executable"
done
PATH="$fakebin:$PATH"
export PATH
git -C "$repository" init -q
printf 'fixture\n' >"$repository/README.md"
git -C "$repository" add README.md
git -C "$repository" -c user.name='Foreman Tests' -c user.email='tests@example.invalid' \
  commit -qm 'Create fixture'
FOREMAN_HOME="$home" "$foreman" init \
  --name 'Plan Project' --project "$repository" --agent codex --model test-model \
  --reasoning high --runtime herdr --yes >/dev/null || test_fail 'plan fixture initialization failed'

project_root="$home/projects/plan-project"

plan_id_from_output() {
  printf '%s\n' "$1" | sed -n 's/^Created proposed plan \(plan-[0-9a-f]*\)$/\1/p'
}

test_direct_plan_creates_canonical_json_and_standalone_review() {
  local input output plan_id plan_dir review status
  input="$test_root/direct.json"
  jq '.title = "<script>alert(1)</script>" | .objective = "Review <safe> content"' \
    "$repo_root/src/contracts/plan/examples/direct-plan.json" >"$input"
  output=$(FOREMAN_HOME="$home" "$foreman" plan create --project plan-project --file "$input") \
    || test_fail 'direct plan creation failed'
  plan_id=$(plan_id_from_output "$output")
  [ -n "$plan_id" ] || test_fail 'direct plan did not return its deterministic ID'
  plan_dir="$project_root/plans/$plan_id"
  review="$plan_dir/plan-script-alert-1-script.html"
  [ -f "$plan_dir/plan.json" ] || test_fail 'canonical plan JSON is missing'
  [ -f "$review" ] || test_fail 'standalone plan review is missing'
  jq -e --arg id "$plan_id" '
    .plan_id == $id and .project_slug == "plan-project" and
    .source == {kind:"direct", system:null, reference:null} and
    .status == "proposed" and .approval == null
  ' "$plan_dir/plan.json" >/dev/null || test_fail 'canonical plan metadata is incorrect'
  test_assert_contains "$(sed -n '1,260p' "$review")" '<style>' \
    'review does not embed its styling'
  test_assert_contains "$(sed -n '1,260p' "$review")" 'color-scheme: dark' \
    'review does not force the Foreman dark presentation'
  test_assert_contains "$(sed -n '1,260p' "$review")" '&lt;script&gt;alert(1)&lt;/script&gt;' \
    'review did not escape plan content'
  if grep -Eq '<script|rel="stylesheet"' "$review"; then
    test_fail 'review contains an executable script or external stylesheet'
  fi
  if find "$project_root/tasks" -mindepth 1 -print -quit | grep -q .; then
    test_fail 'plan review initialized a task'
  fi

  set +e
  FOREMAN_HOME="$home" "$foreman" plan create --project plan-project --file "$input" \
    >"$test_root/duplicate.out" 2>&1
  status=$?
  set -e
  [ "$status" -ne 0 ] || test_fail 'deterministic plan creation overwrote an existing plan'
  test_assert_contains "$(cat "$test_root/duplicate.out")" 'will not be overwritten' \
    'duplicate refusal did not explain the collision'
  test_pass 'direct plan creates canonical JSON and a safe standalone review'
}

test_invalid_structure_dependencies_and_policy_are_rejected() {
  local input output status before after
  input="$test_root/invalid.json"
  before=$(find "$project_root/plans" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')

  jq '.unexpected = true' "$repo_root/src/contracts/plan/examples/direct-plan.json" >"$input"
  set +e
  output=$(FOREMAN_HOME="$home" "$foreman" plan create --project plan-project --file "$input" 2>&1)
  status=$?
  set -e
  [ "$status" -ne 0 ] || test_fail 'unknown plan field was accepted'
  test_assert_contains "$output" 'does not match' 'invalid structure was not diagnosed'

  jq '.tasks[0].depends_on = ["missing-task"]' \
    "$repo_root/src/contracts/plan/examples/direct-plan.json" >"$input"
  set +e
  output=$(FOREMAN_HOME="$home" "$foreman" plan create --project plan-project --file "$input" 2>&1)
  status=$?
  set -e
  [ "$status" -ne 0 ] || test_fail 'unknown task dependency was accepted'
  test_assert_contains "$output" 'unknown task' 'unknown dependency was not diagnosed'

  jq '.tasks[0].depends_on = ["health-summary"]' \
    "$repo_root/src/contracts/plan/examples/direct-plan.json" >"$input"
  set +e
  output=$(FOREMAN_HOME="$home" "$foreman" plan create --project plan-project --file "$input" 2>&1)
  status=$?
  set -e
  [ "$status" -ne 0 ] || test_fail 'cyclic task dependency was accepted'
  test_assert_contains "$output" 'contain a cycle' 'dependency cycle was not diagnosed'

  jq '.tasks[0].delivery_expectation = "automated-change-request"' \
    "$repo_root/src/contracts/plan/examples/direct-plan.json" >"$input"
  set +e
  output=$(FOREMAN_HOME="$home" "$foreman" plan create --project plan-project --file "$input" 2>&1)
  status=$?
  set -e
  [ "$status" -ne 0 ] || test_fail 'plan input elevated the registered delivery policy'
  test_assert_contains "$output" 'project policy does not allow it' \
    'policy elevation refusal was not actionable'

  after=$(find "$project_root/plans" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
  test_assert_equal "$after" "$before" 'rejected plans created durable state'
  test_pass 'invalid plans and attempted policy elevation are rejected without state'
}

test_external_handover_records_provenance_without_authority() {
  local handover output plan_id plan
  handover="$test_root/handover.json"
  cp "$repo_root/src/contracts/plan/examples/external-handover.json" "$handover"
  output=$(FOREMAN_HOME="$home" "$foreman" plan handover --project plan-project --file "$handover") \
    || test_fail 'valid external handover failed'
  plan_id=$(plan_id_from_output "$output")
  plan="$project_root/plans/$plan_id/plan.json"
  jq -e '
    .source == {kind:"external-handover", system:"planning-agent", reference:"conversation-123"} and
    all(.tasks[]; .delivery_expectation == "project-default")
  ' "$plan" >/dev/null || test_fail 'handover provenance was not normalized correctly'
  test_pass 'external handover records provenance without changing project authority'
}

test_guided_drafting_creates_a_reviewable_proposal() {
  local output plan_id plan
  output=$(printf '%s\n' \
    'Guided plan' \
    'Create a bounded guided proposal' \
    'One portable behavior' \
    'Remote delivery' \
    'No repository mutation' \
    'Implement one behavior' \
    '' \
    'Implement and test one behavior' \
    'The behavior is tested' \
    './scripts/check.sh' \
    '' \
    '' | FOREMAN_HOME="$home" "$foreman" plan guided --project plan-project) \
    || test_fail 'guided drafting failed'
  plan_id=$(plan_id_from_output "$output")
  plan="$project_root/plans/$plan_id/plan.json"
  jq -e '
    .source.kind == "guided-draft" and .tasks[0].type == "change" and
    .tasks[0].delivery_expectation == "project-default" and .status == "proposed"
  ' "$plan" >/dev/null || test_fail 'guided answers were not normalized correctly'
  test_pass 'guided drafting creates a validated reviewable proposal'
}

test_approval_blocks_incomplete_plans_and_updates_complete_plans() {
  local blocked decision clean output blocked_id decision_id clean_id status clean_plan review
  blocked="$test_root/blocked.json"
  decision="$test_root/decision.json"
  clean="$test_root/clean.json"
  jq '.title = "Blocked plan" | .missing_information = ["Required API behavior"]' \
    "$repo_root/src/contracts/plan/examples/direct-plan.json" >"$blocked"
  output=$(FOREMAN_HOME="$home" "$foreman" plan create --project plan-project --file "$blocked") \
    || test_fail 'blocked proposal creation failed'
  blocked_id=$(plan_id_from_output "$output")
  set +e
  output=$(FOREMAN_HOME="$home" "$foreman" plan approve --project plan-project --plan "$blocked_id" --yes 2>&1)
  status=$?
  set -e
  [ "$status" -ne 0 ] || test_fail 'plan with missing information was approved'
  test_assert_contains "$output" 'information is missing' 'approval refusal was not actionable'

  jq '.title = "Decision plan" | .unresolved_decisions = [{id:"delivery-choice", question:"Which delivery policy applies?", blocking:true}]' \
    "$repo_root/src/contracts/plan/examples/direct-plan.json" >"$decision"
  output=$(FOREMAN_HOME="$home" "$foreman" plan create --project plan-project --file "$decision") \
    || test_fail 'blocking-decision proposal creation failed'
  decision_id=$(plan_id_from_output "$output")
  set +e
  output=$(FOREMAN_HOME="$home" "$foreman" plan approve --project plan-project --plan "$decision_id" --yes 2>&1)
  status=$?
  set -e
  [ "$status" -ne 0 ] || test_fail 'plan with a blocking unresolved decision was approved'
  test_assert_contains "$output" 'blocking decision is unresolved' \
    'blocking-decision refusal was not actionable'

  jq '.title = "Clean approval plan"' "$repo_root/src/contracts/plan/examples/direct-plan.json" >"$clean"
  output=$(FOREMAN_HOME="$home" "$foreman" plan create --project plan-project --file "$clean") \
    || test_fail 'clean proposal creation failed'
  clean_id=$(plan_id_from_output "$output")
  FOREMAN_HOME="$home" "$foreman" plan approve --project plan-project --plan "$clean_id" \
    --approved-by maintainer --yes >/dev/null || test_fail 'complete proposal approval failed'
  clean_plan="$project_root/plans/$clean_id/plan.json"
  review="$project_root/plans/$clean_id/plan-clean-approval-plan.html"
  jq -e '.status == "approved" and .approval.approved_by == "maintainer" and (.approval.approved_at | length > 0)' \
    "$clean_plan" >/dev/null || test_fail 'approval state was not persisted'
  test_assert_contains "$(sed -n '1,220p' "$review")" 'Approved' \
    'approved HTML review was not refreshed'
  if find "$project_root/tasks" -mindepth 1 -print -quit | grep -q .; then
    test_fail 'plan approval initialized Phase 2 task state'
  fi
  test_pass 'approval blocks incomplete plans and records explicit complete-plan approval'
}

test_plan_contract_documents_are_valid_json() {
  local file
  for file in "$repo_root"/src/contracts/plan/*.json "$repo_root"/src/contracts/plan/examples/*.json; do
    jq empty "$file" >/dev/null || test_fail "invalid plan contract JSON: $file"
  done
  test_pass 'plan contract documents are valid JSON'
}

test_direct_plan_creates_canonical_json_and_standalone_review
test_invalid_structure_dependencies_and_policy_are_rejected
test_external_handover_records_provenance_without_authority
test_guided_drafting_creates_a_reviewable_proposal
test_approval_blocks_incomplete_plans_and_updates_complete_plans
test_plan_contract_documents_are_valid_json
