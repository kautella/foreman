#!/usr/bin/env bash

# This file is loaded after src/tasks/command.sh defines the shared task helpers.
# shellcheck source=src/artifacts/research-report.sh
. "$FOREMAN_SOURCE_ROOT/src/artifacts/research-report.sh"

foreman_task_transition_with_event() {
  local task_file=$1 task_type=$2 project_slug=$3 task_id=$4 lock_id=$5 to_status=$6 actor=$7 message=$8 evidence_json=$9
  local from_status from_condition sequence

  from_status=$(jq -r '.lifecycle.status' "$task_file")
  from_condition=$(jq -r '.lifecycle.condition // "null"' "$task_file")
  [ "$from_condition" = null ] || return 1
  sequence=$(jq '.lifecycle.sequence + 1' "$task_file")
  foreman_task_transition "$task_file" "$task_type" "$to_status" null && \
    foreman_task_append_event "${task_file%/*}" "$task_type" "$project_slug" "$task_id" "$lock_id" "$sequence" lifecycle-transition "$actor" "$from_status" null "$to_status" null "$message" "$evidence_json"
}

foreman_task_clear_condition() {
  local task_file=$1 task_type=$2 project_slug=$3 task_id=$4 lock_id=$5 message=$6 evidence_json=$7
  local from_status from_condition sequence

  from_status=$(jq -r '.lifecycle.status' "$task_file")
  from_condition=$(jq -r '.lifecycle.condition // "null"' "$task_file")
  [ "$from_condition" != null ] || return 1
  sequence=$(jq '.lifecycle.sequence + 1' "$task_file")
  foreman_task_transition "$task_file" "$task_type" awaiting-reconciliation null && \
    foreman_task_append_event "${task_file%/*}" "$task_type" "$project_slug" "$task_id" "$lock_id" "$sequence" reconciliation recovery "$from_status" "$from_condition" awaiting-reconciliation null "$message" "$evidence_json"
}

foreman_task_validation_records_json() {
  local directory=$1 task_id=$2 record paths
  local -a paths_array
  paths_array=()
  while IFS= read -r record; do
    [ -n "$record" ] || continue
    foreman_task_validate_validation_record "$record" || return 1
    [ "$(jq -r '.task_id' "$record")" = "$task_id" ] || return 1
    paths_array+=("$record")
  done <<EOF
$(find "$directory" -maxdepth 1 -type f -name 'validation-*.json' -print | LC_ALL=C sort)
EOF
  jq -cn '$ARGS.positional' --args "${paths_array[@]}"
}

foreman_task_write_validation_record() {
  local destination=$1 task_id=$2 sequence=$3 command=$4 working_directory=$5 exit_status=$6 output=$7 directory temporary outcome output_sha output_bytes

  case "$exit_status" in
    0) outcome=passed ;;
    *) outcome=failed ;;
  esac
  output_sha=$(foreman_task_sha256 "$output") || return 1
  output_bytes=$(wc -c <"$output" | tr -d ' ')
  directory=${destination%/*}
  temporary=$(mktemp "$directory/.foreman-validation-record.XXXXXX") || return 1
  if ! jq -n \
    --arg validation_id "validation-$(foreman_task_hash_prefix "$task_id:validation:$sequence:$command")" \
    --arg task_id "$task_id" --argjson sequence "$sequence" --arg command "$command" \
    --arg working_directory "$working_directory" --arg started_at "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    --arg finished_at "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" --arg outcome "$outcome" \
    --argjson exit_status "$exit_status" --arg output "$output" --arg output_sha "$output_sha" --argjson output_bytes "$output_bytes" '
      {schema_version:1, validation_id:$validation_id, task_id:$task_id, sequence:$sequence, command:$command, working_directory:$working_directory, started_at:$started_at, finished_at:$finished_at, exit_status:$exit_status, outcome:$outcome, output:{path:$output,sha256:$output_sha,bytes:$output_bytes}, evidence:[$output]}
    ' >"$temporary" || ! foreman_atomic_write "$temporary" "$destination"; then
    rm -f -- "$temporary"
    return 1
  fi
  rm -f -- "$temporary"
  foreman_task_validate_validation_record "$destination"
}

foreman_task_run_validations() {
  local task_file=$1 snapshot=$2 task_id=$3 worktree=$4 commands count index command output record temporary exit_status

  commands=$(jq -cs '([.[0].validation.commands[], .[1].task.validation_commands[]] | unique)' "$snapshot" "$task_file") || return 1
  count=$(printf '%s' "$commands" | jq 'length')
  index=0
  while [ "$index" -lt "$count" ]; do
    command=$(printf '%s' "$commands" | jq -r --argjson index "$index" '.[$index]')
    output="${task_file%/*}/validation/validation-$((index + 1)).log"
    record="${task_file%/*}/validation/validation-$((index + 1)).json"
    [ ! -e "$output" ] && [ ! -e "$record" ] || {
      foreman_task_command_error "validation evidence already exists and will not be replaced: $record"
      return 1
    }
    temporary=$(mktemp "${output%/*}/.foreman-validation-output.XXXXXX") || return 1
    set +e
    (cd "$worktree" && bash -c "$command") >"$temporary" 2>&1
    exit_status=$?
    set -e
    if ! foreman_atomic_write "$temporary" "$output" || ! foreman_task_write_validation_record "$record" "$task_id" "$((index + 1))" "$command" "$worktree" "$exit_status" "$output"; then
      rm -f -- "$temporary"
      return 1
    fi
    rm -f -- "$temporary"
    [ "$exit_status" -eq 0 ] || return "$exit_status"
    index=$((index + 1))
  done
}

foreman_task_update_artifacts() {
  local task_file=$1 result=$2 handoff=$3 report=$4 findings=$5 directory temporary

  directory=${task_file%/*}
  temporary=$(mktemp "$directory/.foreman-task-artifacts.XXXXXX") || return 1
  if ! jq -S --arg result "$result" --arg handoff "$handoff" --arg report "$report" --arg findings "$findings" '
      .artifacts.result = $result |
      .artifacts.handoff = (if $handoff == "null" then null else $handoff end) |
      .artifacts.report = (if $report == "null" then null else $report end) |
      .artifacts.findings = (if $findings == "null" then null else $findings end)
    ' "$task_file" >"$temporary" || ! foreman_atomic_write "$temporary" "$task_file"; then
    rm -f -- "$temporary"
    return 1
  fi
  rm -f -- "$temporary"
  foreman_task_validate_metadata "$task_file"
}

foreman_task_write_change_artifacts() {
  local task_file=$1 inspection=$2 records_json=$3 result=$4 handoff=$5 task_id base branch head directory temporary

  task_id=$(jq -r '.task_id' "$task_file")
  base=$(jq -r '.identity.base_commit' "$task_file")
  branch=$(jq -r '.worktree.branch' "$task_file")
  head=$(git -C "$(jq -r '.worktree.path' "$task_file")" rev-parse HEAD) || return 1
  directory=${result%/*}
  temporary=$(mktemp "$directory/.foreman-change-handoff.XXXXXX") || return 1
  if ! jq -n --arg handoff_id "handoff-$(foreman_task_hash_prefix "$task_id:handoff:$head")" --arg task_id "$task_id" --arg base "$base" --arg branch "$branch" --arg head "$head" --arg created_at "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" --argjson records "$records_json" --slurpfile inspection "$inspection" '
      {schema_version:1,handoff_id:$handoff_id,task_id:$task_id,kind:"local-change",base_commit:$base,branch:$branch,head_commit:$head,created_at:$created_at,validation_records:$records,risks:$inspection[0].data.final.risks,instructions:["Review and integrate the exact local branch only after maintainer approval.","No remote change, merge, landing, or teardown was performed."]}
    ' >"$temporary" || ! foreman_atomic_write "$temporary" "$handoff"; then rm -f -- "$temporary"; return 1; fi
  rm -f -- "$temporary"
  foreman_task_validate_handoff "$handoff" || return 1
  temporary=$(mktemp "$directory/.foreman-change-result.XXXXXX") || return 1
  if ! jq -n --arg result_id "result-$(foreman_task_hash_prefix "$task_id:result:$head")" --arg task_id "$task_id" --arg created_at "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" --arg base "$base" --arg branch "$branch" --arg head "$head" --arg handoff "$handoff" --argjson records "$records_json" --slurpfile inspection "$inspection" '
      {schema_version:1,result_id:$result_id,task_id:$task_id,task_type:"change",created_at:$created_at,lifecycle:{status:"delivery-ready",condition:null},outcome:"handoff-ready",summary:$inspection[0].data.final.summary,git:{base_commit:$base,branch:$branch,head_commit:$head},validation_records:$records,artifacts:{handoff:$handoff,report:null,findings:null}}
    ' >"$temporary" || ! foreman_atomic_write "$temporary" "$result"; then rm -f -- "$temporary"; return 1; fi
  rm -f -- "$temporary"
  foreman_task_validate_result "$result"
}

foreman_task_write_research_artifacts() {
  local task_file=$1 inspection=$2 records_json=$3 result=$4 report=$5 findings=$6 task_id directory temporary

  task_id=$(jq -r '.task_id' "$task_file")
  foreman_render_research_report "$task_file" "$inspection" "$records_json" "$report" || return 1
  directory=${result%/*}
  temporary=$(mktemp "$directory/.foreman-research-finding.XXXXXX") || return 1
  if ! jq -n --arg finding_id "finding-$(foreman_task_hash_prefix "$task_id:finding")" --arg task_id "$task_id" --arg report "$report" --arg inspection "$inspection" --arg created_at "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" --slurpfile inspection_data "$inspection" '
      {schema_version:1,finding_id:$finding_id,task_id:$task_id,title:"Worker research summary",summary:$inspection_data[0].data.final.summary,confidence:"medium",evidence:[{kind:"file",reference:$inspection,description:"Structured worker final output."}],report_path:$report,created_at:$created_at}
    ' >"$temporary" || ! foreman_atomic_write "$temporary" "$findings"; then rm -f -- "$temporary"; return 1; fi
  rm -f -- "$temporary"
  foreman_task_validate_research_finding "$findings" || return 1
  temporary=$(mktemp "$directory/.foreman-research-result.XXXXXX") || return 1
  if ! jq -n --arg result_id "result-$(foreman_task_hash_prefix "$task_id:result")" --arg task_id "$task_id" --arg created_at "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" --arg report "$report" --arg findings "$findings" --argjson records "$records_json" --slurpfile inspection "$inspection" '
      {schema_version:1,result_id:$result_id,task_id:$task_id,task_type:"research",created_at:$created_at,lifecycle:{status:"report-ready",condition:null},outcome:"report-ready",summary:$inspection[0].data.final.summary,git:null,validation_records:$records,artifacts:{handoff:null,report:$report,findings:$findings}}
    ' >"$temporary" || ! foreman_atomic_write "$temporary" "$result"; then rm -f -- "$temporary"; return 1; fi
  rm -f -- "$temporary"
  foreman_task_validate_result "$result"
}

foreman_task_validate_command() {
  local project_slug='' task_id='' task_type endpoint lock_id task_lock state status inspection final_status worktree records result handoff report findings

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --project) [ "$#" -ge 2 ] || return 64; project_slug=$2; shift 2 ;;
      --task) [ "$#" -ge 2 ] || return 64; task_id=$2; shift 2 ;;
      -h|--help) foreman_task_usage; return 0 ;;
      *) foreman_task_command_error "unknown validate option: $1"; return 64 ;;
    esac
  done
  [ -n "$project_slug" ] && [ -n "$task_id" ] || { foreman_task_command_error 'validate requires --project and --task'; return 64; }
  foreman_task_load_metadata "$project_slug" "$task_id" || return 1
  task_type=$(jq -r '.task.type' "$FOREMAN_TASK_FILE")
  endpoint=$(jq -r '.runtime_endpoint.path' "$FOREMAN_TASK_FILE")
  task_lock="$FOREMAN_TASK_DIRECTORY/task.lock"
  lock_id="validate-task-${task_id#task-}-$$"
  foreman_lock_acquire task "$task_lock" "$project_slug" "$task_id" "$lock_id" || return 1
  FOREMAN_TASK_LOCK_ID=$lock_id
  export FOREMAN_TASK_LOCK_ID
  if foreman_tmux_inspect "$endpoint" "$project_slug" "$task_lock" "$lock_id" && foreman_task_refresh_endpoint_reference "$FOREMAN_TASK_FILE" "$endpoint"; then status=0; else status=$?; fi
  state=$(jq -r '.state' "$endpoint")
  if [ "$status" -ne 0 ] || [ "$state" = active ]; then
    if [ "$status" -ne 0 ]; then foreman_task_record_condition "$FOREMAN_TASK_FILE" "$task_type" unreachable || true; fi
    foreman_lock_release task "$task_lock" "$project_slug" "$task_id" "$lock_id" || return 1
    foreman_task_command_error 'worker completion cannot yet be proven; task state was preserved'
    return 1
  fi
  inspection="$FOREMAN_TASK_DIRECTORY/codex-inspection.json"
  if foreman_codex_collect_result "$FOREMAN_TASK_DIRECTORY/codex-launch.json" "$inspection"; then status=0; else status=$?; fi
  if [ "$status" -ne 0 ]; then
    foreman_task_record_condition "$FOREMAN_TASK_FILE" "$task_type" unknown || true
    foreman_lock_release task "$task_lock" "$project_slug" "$task_id" "$lock_id" || return 1
    foreman_task_command_error 'worker output is incomplete or ambiguous; task state was preserved'
    return 1
  fi
  final_status=$(jq -r '.data.final.status' "$inspection")
  if [ "$(jq -r '.lifecycle.condition // "null"' "$FOREMAN_TASK_FILE")" != null ]; then
    foreman_task_clear_condition "$FOREMAN_TASK_FILE" "$task_type" "$project_slug" "$task_id" "$lock_id" 'Structured worker evidence resolved the prior runtime condition.' "$(foreman_task_evidence "$inspection")" || status=$?
  elif [ "$(jq -r '.lifecycle.status' "$FOREMAN_TASK_FILE")" = running ]; then
    foreman_task_transition_with_event "$FOREMAN_TASK_FILE" "$task_type" "$project_slug" "$task_id" "$lock_id" awaiting-reconciliation recovery 'Collected structured worker completion evidence.' "$(foreman_task_evidence "$inspection")" || status=$?
  fi
  if [ "${status:-0}" -eq 0 ] && [ "$final_status" != completed ]; then
    foreman_task_record_condition "$FOREMAN_TASK_FILE" "$task_type" "$final_status" || status=$?
  fi
  if [ "${status:-0}" -eq 0 ] && [ "$final_status" = completed ]; then
    worktree=$(jq -r '.worktree.path' "$FOREMAN_TASK_FILE")
    if foreman_task_run_validations "$FOREMAN_TASK_FILE" "$FOREMAN_TASK_DIRECTORY/configuration.json" "$task_id" "$worktree"; then status=0; else status=$?; fi
    if [ "$status" -ne 0 ]; then foreman_task_record_condition "$FOREMAN_TASK_FILE" "$task_type" failed || true; fi
  fi
  if [ "${status:-0}" -eq 0 ] && [ "$final_status" = completed ]; then
    foreman_task_transition_with_event "$FOREMAN_TASK_FILE" "$task_type" "$project_slug" "$task_id" "$lock_id" validated validation 'Declared validation completed successfully.' "$(foreman_task_evidence "$FOREMAN_TASK_DIRECTORY/validation")" || status=$?
  fi
  if [ "${status:-0}" -eq 0 ] && [ "$final_status" = completed ]; then
    records=$(foreman_task_validation_records_json "$FOREMAN_TASK_DIRECTORY/validation" "$task_id") || status=$?
    result="$FOREMAN_TASK_DIRECTORY/result.json"
    if [ "$task_type" = change ]; then
      worktree=$(jq -r '.worktree.path' "$FOREMAN_TASK_FILE")
      [ -z "$(git -C "$worktree" status --porcelain=v1 --untracked-files=all)" ] && [ "$(git -C "$worktree" rev-parse HEAD)" != "$(jq -r '.identity.base_commit' "$FOREMAN_TASK_FILE")" ] || status=1
      handoff="$FOREMAN_TASK_DIRECTORY/delivery/local-handoff.json"
      if [ "${status:-0}" -eq 0 ] && foreman_task_write_change_artifacts "$FOREMAN_TASK_FILE" "$inspection" "$records" "$result" "$handoff" && foreman_task_transition_with_event "$FOREMAN_TASK_FILE" "$task_type" "$project_slug" "$task_id" "$lock_id" delivery-ready foreman 'Prepared a local change handoff.' "$(foreman_task_evidence "$handoff" "$result")" && foreman_task_update_artifacts "$FOREMAN_TASK_FILE" "$result" "$handoff" null null; then status=0; else status=${status:-1}; fi
    else
      [ -z "$(git -C "$worktree" status --porcelain=v1 --untracked-files=all)" ] && [ "$(git -C "$worktree" rev-parse HEAD)" = "$(jq -r '.identity.base_commit' "$FOREMAN_TASK_FILE")" ] || status=1
      report="$FOREMAN_TASK_DIRECTORY/reports/report-$(jq -r '.plan.task_id' "$FOREMAN_TASK_FILE").html"
      findings="$FOREMAN_TASK_DIRECTORY/findings.json"
      if [ "${status:-0}" -eq 0 ] && foreman_task_write_research_artifacts "$FOREMAN_TASK_FILE" "$inspection" "$records" "$result" "$report" "$findings" && foreman_task_transition_with_event "$FOREMAN_TASK_FILE" "$task_type" "$project_slug" "$task_id" "$lock_id" report-ready foreman 'Prepared a standalone research report.' "$(foreman_task_evidence "$report" "$result" "$findings")" && foreman_task_update_artifacts "$FOREMAN_TASK_FILE" "$result" null "$report" "$findings"; then status=0; else status=${status:-1}; fi
    fi
  fi
  if [ "${status:-0}" -ne 0 ] && [ "$(jq -r '.lifecycle.condition // "null"' "$FOREMAN_TASK_FILE")" = null ]; then
    foreman_task_record_condition "$FOREMAN_TASK_FILE" "$task_type" failed || true
  fi
  foreman_lock_release task "$task_lock" "$project_slug" "$task_id" "$lock_id" || return 1
  [ "${status:-0}" -eq 0 ] || { foreman_task_command_error 'validation or local-output preparation failed; task work was preserved'; return 1; }
  printf 'Validated task %s\n' "$task_id"
  printf 'Lifecycle: %s\n' "$(jq -r '.lifecycle.status' "$FOREMAN_TASK_FILE")"
}
