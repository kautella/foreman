#!/usr/bin/env bash

set -u

repo_root="$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)"
# shellcheck source=src/tasks/validate.sh
. "$repo_root/src/tasks/validate.sh"
# shellcheck source=tests/test-helper.sh
. "$repo_root/tests/test-helper.sh"

test_root=$(mktemp -d '/tmp/foreman-task-contracts.XXXXXX') || exit 1
trap 'rm -rf "$test_root"' EXIT HUP INT TERM
examples="$repo_root/src/contracts/task/examples"

test_examples_satisfy_task_contracts() {
  foreman_task_validate_metadata "$examples/task.json" \
    || test_fail 'task metadata example did not validate'
  foreman_task_validate_configuration_snapshot "$examples/configuration-snapshot.json" \
    || test_fail 'configuration snapshot example did not validate'
  foreman_task_validate_endpoint "$examples/endpoint.json" \
    || test_fail 'runtime endpoint example did not validate'
  foreman_task_validate_event "$examples/event.json" change \
    || test_fail 'task event example did not validate'
  foreman_task_validate_validation_record "$examples/validation-record.json" \
    || test_fail 'validation record example did not validate'
  foreman_task_validate_result "$examples/result.json" \
    || test_fail 'task result example did not validate'
  foreman_task_validate_handoff "$examples/handoff.json" \
    || test_fail 'local handoff example did not validate'
  foreman_task_validate_research_finding "$examples/research-finding.json" \
    || test_fail 'research finding example did not validate'
  foreman_task_validate_teardown_record "$examples/teardown-record.json" \
    || test_fail 'teardown record example did not validate'
  test_pass 'all durable task contract examples validate'
}

test_schema_documents_are_valid_json() {
  local schema
  for schema in "$repo_root"/src/contracts/task/*.schema.json; do
    jq empty "$schema" || test_fail "invalid task schema JSON: $schema"
  done
  test_pass 'task schema documents are valid JSON'
}

test_metadata_rejects_unknown_and_unsafe_environment_fields() {
  local unknown research_branch missing_reservation
  unknown="$test_root/unknown.json"
  research_branch="$test_root/research-branch.json"
  missing_reservation="$test_root/missing-reservation.json"

  jq '.unexpected = true' "$examples/task.json" >"$unknown"
  if foreman_task_validate_metadata "$unknown" >/dev/null 2>&1; then
    test_fail 'task metadata accepted an unknown field'
  fi

  jq '.task.type = "research" | .worktree.branch = "feat/not-allowed"' \
    "$examples/task.json" >"$research_branch"
  if foreman_task_validate_metadata "$research_branch" >/dev/null 2>&1; then
    test_fail 'research task accepted a branch instead of detached worktree identity'
  fi

  jq '.configuration_snapshot = null' "$examples/task.json" >"$missing_reservation"
  if foreman_task_validate_metadata "$missing_reservation" >/dev/null 2>&1; then
    test_fail 'prepared task accepted a missing configuration snapshot'
  fi
  test_pass 'task metadata rejects unknown fields and incomplete prepared environments'
}

test_lifecycle_transitions_and_conditions_fail_closed() {
  local conditioned recovered invalid
  conditioned="$test_root/conditioned-event.json"
  recovered="$test_root/recovered-event.json"
  invalid="$test_root/invalid-event.json"

  foreman_task_validate_lifecycle_transition change planned null approved null \
    || test_fail 'planned change task could not be approved'
  foreman_task_validate_lifecycle_transition research validated null report-ready null \
    || test_fail 'validated research task could not become report-ready'
  foreman_task_validate_lifecycle_transition change delivery-ready null landed null \
    || test_fail 'delivery-ready change task could not record confirmed landing'
  foreman_task_validate_lifecycle_transition change delivery-ready null teardown-ready null \
    || test_fail 'delivery-ready change task could become teardown-ready after explicit discard'
  if foreman_task_validate_lifecycle_transition change approved null running null >/dev/null 2>&1; then
    test_fail 'lifecycle skipped prepared state'
  fi
  if foreman_task_validate_lifecycle_transition research validated null delivery-ready null >/dev/null 2>&1; then
    test_fail 'research task accepted a change handoff state'
  fi

  jq '.kind = "condition-observed" | .from = {status:"running", condition:null} | .to = {status:"running", condition:"unreachable"}' \
    "$examples/event.json" >"$conditioned"
  foreman_task_validate_event "$conditioned" change \
    || test_fail 'unreachable condition event was rejected'

  jq '.kind = "reconciliation" | .from = {status:"running", condition:"unreachable"} | .to = {status:"awaiting-reconciliation", condition:null}' \
    "$examples/event.json" >"$recovered"
  foreman_task_validate_event "$recovered" change \
    || test_fail 'condition reconciliation event was rejected'

  jq '.from = {status:"approved", condition:null} | .to = {status:"running", condition:null}' \
    "$examples/event.json" >"$invalid"
  if foreman_task_validate_event "$invalid" change >/dev/null 2>&1; then
    test_fail 'event accepted an invalid lifecycle skip'
  fi
  test_pass 'legal transitions and condition recovery are explicit and fail closed'
}

test_validation_outcomes_preserve_noncompletion() {
  local candidate passed_without_output outcome
  candidate="$test_root/validation-outcome.json"
  passed_without_output="$test_root/passed-without-output.json"

  for outcome in paused blocked missing unreachable unknown; do
    jq --arg outcome "$outcome" \
      '.outcome = $outcome | .finished_at = null | .exit_status = null | .output = null' \
      "$examples/validation-record.json" >"$candidate"
    foreman_task_validate_validation_record "$candidate" \
      || test_fail "validation outcome was rejected: $outcome"
  done

  jq '.output = null' "$examples/validation-record.json" >"$passed_without_output"
  if foreman_task_validate_validation_record "$passed_without_output" >/dev/null 2>&1; then
    test_fail 'passed validation accepted no durable output record'
  fi
  test_pass 'paused and abnormal validation outcomes remain distinct from success'
}

test_results_and_handoffs_remain_local_and_type_specific() {
  local research_result remote_handoff
  research_result="$test_root/research-result.json"
  remote_handoff="$test_root/remote-handoff.json"

  jq '.task_type = "research" | .lifecycle = {status:"report-ready", condition:null} | .outcome = "report-ready" | .git = null | .artifacts = {handoff:null, report:"/state/tasks/task-0123456789ab/reports/report-sample.html", findings:"/state/tasks/task-0123456789ab/findings.json"}' \
    "$examples/result.json" >"$research_result"
  foreman_task_validate_result "$research_result" \
    || test_fail 'research result with standalone report was rejected'

  jq '.kind = "remote-change-request"' "$examples/handoff.json" >"$remote_handoff"
  if foreman_task_validate_handoff "$remote_handoff" >/dev/null 2>&1; then
    test_fail 'local Phase 2 handoff accepted a remote delivery kind'
  fi
  test_pass 'results are task-type-specific and handoffs remain local'
}

test_examples_satisfy_task_contracts
test_schema_documents_are_valid_json
test_metadata_rejects_unknown_and_unsafe_environment_fields
test_lifecycle_transitions_and_conditions_fail_closed
test_validation_outcomes_preserve_noncompletion
test_results_and_handoffs_remain_local_and_type_specific
