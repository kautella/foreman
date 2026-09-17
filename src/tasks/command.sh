#!/usr/bin/env bash

# shellcheck source=src/plans/command.sh
. "$FOREMAN_SOURCE_ROOT/src/plans/command.sh"
# shellcheck source=src/state/atomic.sh
. "$FOREMAN_SOURCE_ROOT/src/state/atomic.sh"
# shellcheck source=src/state/lock.sh
. "$FOREMAN_SOURCE_ROOT/src/state/lock.sh"
# shellcheck source=src/state/events.sh
. "$FOREMAN_SOURCE_ROOT/src/state/events.sh"
# shellcheck source=src/tasks/validate.sh
. "$FOREMAN_SOURCE_ROOT/src/tasks/validate.sh"
# shellcheck source=src/tasks/worktree.sh
. "$FOREMAN_SOURCE_ROOT/src/tasks/worktree.sh"
# shellcheck source=src/adapters/agents/codex/adapter.sh
. "$FOREMAN_SOURCE_ROOT/src/adapters/agents/codex/adapter.sh"
# shellcheck source=src/adapters/runtimes/tmux/adapter.sh
. "$FOREMAN_SOURCE_ROOT/src/adapters/runtimes/tmux/adapter.sh"

foreman_task_usage() {
  cat <<'EOF'
Usage: foreman task <command> [options]

Commands:
  start --project SLUG --plan ID --task PLAN_TASK_ID [--branch BRANCH]
                                   Reserve and start one approved local task
  status --project SLUG --task TASK_ID
                                   Show durable task and endpoint state
  reconcile --project SLUG --task TASK_ID
                                   Reconcile one task against its tmux endpoint
  validate --project SLUG --task TASK_ID
                                   Validate terminal work and prepare local output
  teardown --project SLUG --task TASK_ID (--landed-at COMMIT | --discard)
                                   Remove only a proven-landed or explicitly discarded worktree

A change task requires an explicit, new branch name. A research task must not
receive a branch. Task start never pushes, publishes, merges, lands, discards,
or tears down work.
EOF
}

foreman_task_command_error() {
  printf 'foreman: task: %s\n' "$*" >&2
}

foreman_task_require_directory() {
  local label=$1 directory=$2

  [ -d "$directory" ] && [ ! -L "$directory" ] || {
    foreman_task_command_error "$label is not a safe directory: $directory"
    return 1
  }
}

foreman_task_require_regular_file() {
  local label=$1 file=$2

  [ -f "$file" ] && [ ! -L "$file" ] || {
    foreman_task_command_error "$label is not a regular file: $file"
    return 1
  }
}

foreman_task_validate_id() {
  local task_id=$1

  jq -en --arg task_id "$task_id" '$task_id | test("^task-[0-9a-f]{12}$")' >/dev/null 2>&1 || {
    foreman_task_command_error 'task must be a complete task ID'
    return 1
  }
}

foreman_task_sha256() {
  local file=$1 digest

  foreman_task_require_regular_file 'document to hash' "$file" || return 1
  command -v shasum >/dev/null 2>&1 || {
    foreman_task_command_error 'shasum is required to preserve task-document identity'
    return 1
  }
  digest=$(shasum -a 256 "$file" | awk '{print $1}') || return 1
  jq -en --arg digest "$digest" '$digest | test("^[0-9a-f]{64}$")' >/dev/null 2>&1 || return 1
  printf '%s\n' "$digest"
}

foreman_task_hash_prefix() {
  local value=$1 digest

  command -v shasum >/dev/null 2>&1 || {
    foreman_task_command_error 'shasum is required to create durable task identities'
    return 1
  }
  digest=$(printf '%s' "$value" | shasum -a 256 | awk '{print $1}') || return 1
  printf '%s\n' "${digest:0:12}"
}

foreman_task_event_id() {
  local task_id=$1 sequence=$2

  printf 'event-%s\n' "$(foreman_task_hash_prefix "$task_id:event:$sequence")"
}

foreman_task_evidence() {
  jq -cn '$ARGS.positional' --args "$@"
}

foreman_task_load_project() {
  local project_slug=$1

  foreman_plan_load_project "$project_slug" || return 1
  FOREMAN_TASK_PROJECT_ROOT=$FOREMAN_PLAN_PROJECT_ROOT
  FOREMAN_TASK_PROJECT_FILE=$FOREMAN_PLAN_PROJECT_FILE
  export FOREMAN_TASK_PROJECT_ROOT FOREMAN_TASK_PROJECT_FILE
  foreman_task_require_directory 'project task storage' "$FOREMAN_TASK_PROJECT_ROOT/tasks"
  foreman_task_require_directory 'project state storage' "$FOREMAN_TASK_PROJECT_ROOT/state"
}

foreman_task_load_metadata() {
  local project_slug=$1 task_id=$2 task_directory task_file

  foreman_task_validate_id "$task_id" || return 1
  foreman_task_load_project "$project_slug" || return 1
  task_directory=$(foreman_path_canonicalize "$FOREMAN_TASK_PROJECT_ROOT/tasks/$task_id") || return 1
  foreman_path_is_within "$task_directory" "$FOREMAN_TASK_PROJECT_ROOT/tasks" && [ "$task_directory" != "$FOREMAN_TASK_PROJECT_ROOT/tasks" ] || {
    foreman_task_command_error "task path escapes project storage: $task_id"
    return 1
  }
  foreman_task_require_directory 'task storage' "$task_directory" || return 1
  task_file="$task_directory/task.json"
  foreman_task_validate_metadata "$task_file" || return 1
  jq -e --arg project_slug "$project_slug" --arg task_id "$task_id" '
    .project_slug == $project_slug and .task_id == $task_id
  ' "$task_file" >/dev/null 2>&1 || {
    foreman_task_command_error 'task metadata does not match the requested project and task identity'
    return 1
  }
  FOREMAN_TASK_DIRECTORY=$task_directory
  FOREMAN_TASK_FILE=$task_file
  export FOREMAN_TASK_DIRECTORY FOREMAN_TASK_FILE
  foreman_task_validate_loaded_references "$task_directory" "$task_file"
}

foreman_task_validate_loaded_references() {
  local task_directory=$1 task_file=$2 task_id task_type snapshot snapshot_sha endpoint endpoint_sha
  local event_file marker worktree_path teardown event_sequence lifecycle_sequence

  task_id=$(jq -r '.task_id' "$task_file")
  task_type=$(jq -r '.task.type' "$task_file")
  snapshot=$(jq -r '.configuration_snapshot.path' "$task_file")
  snapshot_sha=$(jq -r '.configuration_snapshot.sha256' "$task_file")
  endpoint=$(jq -r '.runtime_endpoint.path' "$task_file")
  endpoint_sha=$(jq -r '.runtime_endpoint.sha256' "$task_file")
  event_file=$(jq -r '.artifacts.events' "$task_file")
  marker=$(jq -r '.worktree.ownership_marker' "$task_file")
  worktree_path=$(jq -r '.worktree.path' "$task_file")

  teardown=$(jq -r '.artifacts.teardown // "null"' "$task_file")

  [ "$snapshot" = "$task_directory/configuration.json" ] && [ "$endpoint" = "$task_directory/endpoint.json" ] && \
    [ "$event_file" = "$task_directory/events.jsonl" ] && [ "$marker" = "$task_directory/worktree.json" ] || {
    foreman_task_command_error 'task metadata references state outside its exact task directory'
    return 1
  }
  [ "$teardown" = null ] || [ "$teardown" = "$task_directory/teardown.json" ] || {
    foreman_task_command_error 'task metadata references teardown state outside its exact task directory'
    return 1
  }
  foreman_task_validate_configuration_snapshot "$snapshot" || return 1
  jq -e --arg task_id "$task_id" '.task_id == $task_id' "$snapshot" >/dev/null 2>&1 || {
    foreman_task_command_error 'configuration snapshot does not match task identity'
    return 1
  }
  [ "$(foreman_task_sha256 "$snapshot")" = "$snapshot_sha" ] || {
    foreman_task_command_error 'configuration snapshot content no longer matches task metadata'
    return 1
  }
  foreman_task_validate_endpoint "$endpoint" || return 1
  jq -e --arg task_id "$task_id" --arg runtime "$(jq -r '.identity.runtime' "$task_file")" '
    .task_id == $task_id and .owner.task_id == $task_id and .runtime == $runtime
  ' "$endpoint" >/dev/null 2>&1 || {
    foreman_task_command_error 'runtime endpoint does not match task identity'
    return 1
  }
  [ "$(foreman_task_sha256 "$endpoint")" = "$endpoint_sha" ] || {
    foreman_task_command_error 'runtime endpoint content no longer matches task metadata'
    return 1
  }
  foreman_worktree_validate_marker "$marker" || return 1
  jq -e --arg task_id "$task_id" --arg worktree_path "$worktree_path" '
    .task_id == $task_id and .worktree_path == $worktree_path
  ' "$marker" >/dev/null 2>&1 || {
    foreman_task_command_error 'worktree marker does not match task metadata'
    return 1
  }
  if [ "$teardown" != null ]; then
    foreman_task_validate_teardown_record "$teardown" || return 1
    jq -e --arg task_id "$task_id" '.task_id == $task_id' "$teardown" >/dev/null 2>&1 || {
      foreman_task_command_error 'teardown record does not match task identity'
      return 1
    }
  fi
  event_sequence=$(foreman_events_validate_existing "$event_file" "$task_type" "$task_id") || return 1
  lifecycle_sequence=$(jq -r '.lifecycle.sequence' "$task_file")
  [ "$event_sequence" = "$lifecycle_sequence" ] || {
    foreman_task_command_error 'task event history does not match lifecycle sequence; preserving state for recovery'
    return 1
  }
}

foreman_task_assert_project_idle() {
  local entry task_file status

  for entry in "$FOREMAN_TASK_PROJECT_ROOT"/tasks/*; do
    [ -e "$entry" ] || [ -L "$entry" ] || continue
    [ -d "$entry" ] && [ ! -L "$entry" ] || {
      foreman_task_command_error "task storage contains an unsafe entry and will not be adopted: $entry"
      return 1
    }
    task_file="$entry/task.json"
    foreman_task_validate_metadata "$task_file" || {
      foreman_task_command_error "task storage contains invalid metadata and will not be bypassed: $entry"
      return 1
    }
    status=$(jq -r '.lifecycle.status' "$task_file")
    [ "$status" = closed ] || {
      foreman_task_command_error "another task is not closed and must be reconciled first: $(jq -r '.task_id' "$task_file")"
      return 1
    }
  done
}

foreman_task_validate_start_policy() {
  local plan_file=$1 plan_task_id=$2 agent runtime policy merge_authority delivery_expectation dependencies

  agent=$(jq -r '.worker_profile.agent' "$FOREMAN_TASK_PROJECT_FILE")
  runtime=$(jq -r '.runtime' "$FOREMAN_TASK_PROJECT_FILE")
  policy=$(jq -r '.delivery.policy' "$FOREMAN_TASK_PROJECT_FILE")
  merge_authority=$(jq -r '.delivery.merge_authority' "$FOREMAN_TASK_PROJECT_FILE")
  delivery_expectation=$(jq -r --arg plan_task_id "$plan_task_id" '.tasks[] | select(.id == $plan_task_id) | .delivery_expectation' "$plan_file")
  dependencies=$(jq -r --arg plan_task_id "$plan_task_id" '.tasks[] | select(.id == $plan_task_id) | (.depends_on | length)' "$plan_file")
  [ "$agent" = codex ] || {
    foreman_task_command_error "Phase 2 can start only the Codex adapter, not configured agent '$agent'"
    return 1
  }
  [ "$runtime" = tmux ] || {
    foreman_task_command_error "Phase 2 can start only the tmux runtime, not configured runtime '$runtime'"
    return 1
  }
  [ "$policy" = draft-handoff ] && [ "$merge_authority" = false ] || {
    foreman_task_command_error 'Phase 2 task start requires local draft-handoff delivery with merge authority disabled'
    return 1
  }
  case "$delivery_expectation" in
    project-default|draft-handoff) ;;
    *)
      foreman_task_command_error 'the plan task requests delivery outside the local Phase 2 boundary'
      return 1
      ;;
  esac
  [ "$dependencies" -eq 0 ] || {
    foreman_task_command_error 'dependent plan tasks cannot start until their prerequisite results are validated'
    return 1
  }
}

foreman_task_preflight_adapters() {
  local temporary codex_diagnosis tmux_diagnosis status

  temporary=$(mktemp -d '/tmp/foreman-task-preflight.XXXXXX') || return 1
  codex_diagnosis="$temporary/codex.json"
  tmux_diagnosis="$temporary/tmux.json"
  if foreman_codex_diagnose preflight-codex "$codex_diagnosis" && \
    foreman_tmux_diagnose preflight-tmux "$tmux_diagnosis"; then
    status=0
  else
    status=$?
  fi
  rm -rf -- "$temporary"
  if [ "$status" -ne 0 ]; then
    foreman_task_command_error 'configured Codex CLI or tmux runtime is unavailable; no task state was created'
    return "$status"
  fi
}

foreman_task_write_snapshot() {
  local destination=$1 task_id=$2 base_commit=$3 directory temporary

  directory=${destination%/*}
  temporary=$(mktemp "$directory/.foreman-task-configuration.XXXXXX") || return 1
  if ! jq -n \
    --arg task_id "$task_id" \
    --arg captured_at "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    --arg base_commit "$base_commit" \
    --slurpfile project "$FOREMAN_TASK_PROJECT_FILE" '
      $project[0] as $configuration |
      {
        schema_version: 1,
        task_id: $task_id,
        captured_at: $captured_at,
        project: {
          slug: $configuration.project.slug,
          repository_path: $configuration.project.repository_path,
          git_common_dir: $configuration.project.git_common_dir,
          worktree_root: $configuration.worktree_root,
          base_commit: $base_commit
        },
        worker_profile: $configuration.worker_profile,
        runtime: $configuration.runtime,
        delivery: $configuration.delivery,
        validation: $configuration.validation
      }
    ' >"$temporary" || ! foreman_atomic_write "$temporary" "$destination"; then
    rm -f -- "$temporary"
    return 1
  fi
  rm -f -- "$temporary"
  foreman_task_validate_configuration_snapshot "$destination"
}

foreman_task_write_brief() {
  local destination=$1 task_id=$2 plan_file=$3 plan_task_id=$4 directory temporary

  directory=${destination%/*}
  temporary=$(mktemp "$directory/.foreman-task-brief.XXXXXX") || return 1
  if ! jq -r --arg task_id "$task_id" --arg plan_task_id "$plan_task_id" '
    . as $plan |
    ($plan.tasks[] | select(.id == $plan_task_id)) as $task |
    "# Task \($task_id)\n\n" +
    "## Objective\n\n\($task.objective)\n\n" +
    "## Acceptance criteria\n\n" +
    ($task.acceptance_criteria | map("- " + .) | join("\n")) + "\n\n" +
    "## Constraints\n\n" +
    (($plan.constraints + $plan.scope.excluded) | if length == 0 then "- None recorded." else map("- " + .) | join("\n") end) + "\n\n" +
    "## Required validation\n\n" +
    ($task.validation | if length == 0 then "- No task-specific command declared." else map("- " + .) | join("\n") end) + "\n\n" +
    "Work only in the assigned worktree. Do not change Foreman state, delivery policy, remotes, or project planning. Return the required structured final result when the work is complete.\n"
  ' "$plan_file" >"$temporary" || ! foreman_atomic_write "$temporary" "$destination"; then
    rm -f -- "$temporary"
    return 1
  fi
  rm -f -- "$temporary"
  foreman_task_require_regular_file 'task brief' "$destination"
}

foreman_task_write_metadata() {
  local destination=$1 task_id=$2 plan_id=$3 plan_task_id=$4 plan_file=$5 snapshot=$6 worktree_marker=$7 endpoint=$8 status=$9 sequence=${10}
  local worktree_path git_dir branch base_commit snapshot_sha endpoint_sha directory temporary

  worktree_path=$(jq -r '.worktree_path' "$worktree_marker") || return 1
  git_dir=$(jq -r '.git_dir' "$worktree_marker") || return 1
  branch=$(jq -r '.branch // "null"' "$worktree_marker") || return 1
  base_commit=$(jq -r '.base_commit' "$worktree_marker") || return 1
  snapshot_sha=$(foreman_task_sha256 "$snapshot") || return 1
  endpoint_sha=$(foreman_task_sha256 "$endpoint") || return 1
  directory=${destination%/*}
  temporary=$(mktemp "$directory/.foreman-task-metadata.XXXXXX") || return 1
  if ! jq -S \
    --arg task_id "$task_id" \
    --arg plan_id "$plan_id" \
    --arg plan_task_id "$plan_task_id" \
    --arg snapshot "$snapshot" \
    --arg snapshot_sha "$snapshot_sha" \
    --arg worktree_path "$worktree_path" \
    --arg git_dir "$git_dir" \
    --arg branch "$branch" \
    --arg base_commit "$base_commit" \
    --arg worktree_marker "$worktree_marker" \
    --arg endpoint "$endpoint" \
    --arg endpoint_sha "$endpoint_sha" \
    --arg lifecycle_status "$status" \
    --argjson sequence "$sequence" \
    --arg updated_at "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    --arg task_directory "$directory" \
    --slurpfile configuration "$FOREMAN_TASK_PROJECT_FILE" '
      $configuration[0] as $configuration |
      (.tasks[] | select(.id == $plan_task_id)) as $task |
      {
        schema_version: 1,
        task_id: $task_id,
        project_slug: .project_slug,
        plan: {plan_id: $plan_id, task_id: $plan_task_id},
        task: {
          type: $task.type,
          title: $task.title,
          objective: $task.objective,
          acceptance_criteria: $task.acceptance_criteria,
          validation_commands: $task.validation
        },
        identity: {
          repository_path: $configuration.project.repository_path,
          git_common_dir: $configuration.project.git_common_dir,
          base_commit: $base_commit,
          worker_profile: $configuration.worker_profile,
          runtime: $configuration.runtime,
          delivery: $configuration.delivery
        },
        configuration_snapshot: {path: $snapshot, sha256: $snapshot_sha},
        worktree: {
          path: $worktree_path,
          git_dir: $git_dir,
          branch: (if $branch == "null" then null else $branch end),
          base_commit: $base_commit,
          ownership_marker: $worktree_marker
        },
        runtime_endpoint: {path: $endpoint, sha256: $endpoint_sha},
        lifecycle: {status: $lifecycle_status, condition: null, updated_at: $updated_at, sequence: $sequence},
        artifacts: {
          brief: ($task_directory + "/brief.md"),
          events: ($task_directory + "/events.jsonl"),
          validation_directory: ($task_directory + "/validation"),
          result: null,
          handoff: null,
          report: null,
          findings: null,
          teardown: null
        }
      }
    ' "$plan_file" >"$temporary" ||
    ! foreman_atomic_write "$temporary" "$destination"; then
    rm -f -- "$temporary"
    return 1
  fi
  rm -f -- "$temporary"
  foreman_task_validate_metadata "$destination"
}

foreman_task_write_event() {
  local destination=$1 task_id=$2 sequence=$3 kind=$4 actor=$5 from_status=$6 from_condition=$7 to_status=$8 to_condition=$9 message=${10} evidence_json=${11}

  jq -n \
    --arg event_id "$(foreman_task_event_id "$task_id" "$sequence")" \
    --arg task_id "$task_id" \
    --argjson sequence "$sequence" \
    --arg at "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    --arg kind "$kind" \
    --arg actor "$actor" \
    --arg from_status "$from_status" \
    --arg from_condition "$from_condition" \
    --arg to_status "$to_status" \
    --arg to_condition "$to_condition" \
    --arg message "$message" \
    --argjson evidence "$evidence_json" '
      {
        schema_version: 1,
        event_id: $event_id,
        task_id: $task_id,
        sequence: $sequence,
        at: $at,
        kind: $kind,
        actor: $actor,
        from: {status: $from_status, condition: (if $from_condition == "null" then null else $from_condition end)},
        to: {status: $to_status, condition: (if $to_condition == "null" then null else $to_condition end)},
        message: $message,
        evidence: $evidence
      }
    ' >"$destination"
}

foreman_task_append_event() {
  local task_directory=$1 task_type=$2 project_slug=$3 task_id=$4 lock_id=$5 sequence=$6 kind=$7 actor=$8 from_status=$9 from_condition=${10} to_status=${11} to_condition=${12} message=${13} evidence_json=${14}
  local temporary

  temporary=$(mktemp "$task_directory/.foreman-task-event.XXXXXX") || return 1
  if ! foreman_task_write_event "$temporary" "$task_id" "$sequence" "$kind" "$actor" "$from_status" "$from_condition" "$to_status" "$to_condition" "$message" "$evidence_json" || \
    ! foreman_events_append "$task_directory/events.jsonl" "$temporary" "$task_type" task "$task_directory/task.lock" "$project_slug" "$task_id" "$lock_id"; then
    rm -f -- "$temporary"
    return 1
  fi
  rm -f -- "$temporary"
}

foreman_task_refresh_endpoint_reference() {
  local task_file=$1 endpoint=$2 directory temporary endpoint_sha

  endpoint_sha=$(foreman_task_sha256 "$endpoint") || return 1
  directory=${task_file%/*}
  temporary=$(mktemp "$directory/.foreman-task-endpoint-reference.XXXXXX") || return 1
  if ! jq -S --arg endpoint "$endpoint" --arg endpoint_sha "$endpoint_sha" '
      .runtime_endpoint = {path: $endpoint, sha256: $endpoint_sha}
    ' "$task_file" >"$temporary" || ! foreman_atomic_write "$temporary" "$task_file"; then
    rm -f -- "$temporary"
    return 1
  fi
  rm -f -- "$temporary"
  foreman_task_validate_metadata "$task_file"
}

foreman_task_transition() {
  local task_file=$1 task_type=$2 to_status=$3 to_condition=$4 directory temporary
  local from_status from_condition sequence updated_at

  foreman_task_validate_metadata "$task_file" || return 1
  from_status=$(jq -r '.lifecycle.status' "$task_file")
  from_condition=$(jq -r '.lifecycle.condition // "null"' "$task_file")
  foreman_task_validate_lifecycle_transition "$task_type" "$from_status" "$from_condition" "$to_status" "$to_condition" || return 1
  sequence=$(jq '.lifecycle.sequence + 1' "$task_file")
  updated_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  directory=${task_file%/*}
  temporary=$(mktemp "$directory/.foreman-task-transition.XXXXXX") || return 1
  if ! jq -S \
    --arg status "$to_status" \
    --arg condition "$to_condition" \
    --arg updated_at "$updated_at" \
    --argjson sequence "$sequence" '
      .lifecycle = {
        status: $status,
        condition: (if $condition == "null" then null else $condition end),
        updated_at: $updated_at,
        sequence: $sequence
      }
    ' "$task_file" >"$temporary" || ! foreman_atomic_write "$temporary" "$task_file"; then
    rm -f -- "$temporary"
    return 1
  fi
  rm -f -- "$temporary"
  foreman_task_validate_metadata "$task_file"
}

foreman_task_record_condition() {
  local task_file=$1 task_type=$2 condition=$3 actor=${4:-runtime-adapter} message=${5:-}
  local evidence_json=${6:-} from_status from_condition sequence

  from_status=$(jq -r '.lifecycle.status' "$task_file")
  from_condition=$(jq -r '.lifecycle.condition // "null"' "$task_file")
  [ "$from_condition" = null ] || {
    [ "$from_condition" = "$condition" ]
    return
  }
  [ -n "$message" ] || message="Observed a $condition condition; task work was preserved."
  [ -n "$evidence_json" ] || evidence_json="$(foreman_task_evidence "$(jq -r '.runtime_endpoint.path' "$task_file")")"
  sequence=$(jq '.lifecycle.sequence + 1' "$task_file")
  foreman_task_transition "$task_file" "$task_type" "$from_status" "$condition" || return 1
  foreman_task_append_event "${task_file%/*}" "$task_type" "$(jq -r '.project_slug' "$task_file")" "$(jq -r '.task_id' "$task_file")" \
    "$FOREMAN_TASK_LOCK_ID" "$sequence" condition-observed "$actor" "$from_status" null "$from_status" "$condition" \
    "$message" "$evidence_json"
}

foreman_task_start_command() {
  local project_slug='' plan_id='' plan_task_id='' branch='' task_type plan_task task_id base_commit current_base
  local project_lock project_lock_id task_lock task_lock_id task_directory snapshot brief marker endpoint request spec runner
  local status worktree_path

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --project) [ "$#" -ge 2 ] || return 64; project_slug=$2; shift 2 ;;
      --plan) [ "$#" -ge 2 ] || return 64; plan_id=$2; shift 2 ;;
      --task) [ "$#" -ge 2 ] || return 64; plan_task_id=$2; shift 2 ;;
      --branch) [ "$#" -ge 2 ] || return 64; branch=$2; shift 2 ;;
      -h|--help) foreman_task_usage; return 0 ;;
      *) foreman_task_command_error "unknown start option: $1"; return 64 ;;
    esac
  done
  [ -n "$project_slug" ] && [ -n "$plan_id" ] && [ -n "$plan_task_id" ] || {
    foreman_task_command_error 'start requires --project, --plan, and --task'
    return 64
  }
  foreman_task_load_project "$project_slug" || return 1
  foreman_plan_load_stored "$project_slug" "$plan_id" || return 1
  [ "$(jq -r '.status' "$FOREMAN_PLAN_FILE")" = approved ] || {
    foreman_task_command_error "plan is not approved: $plan_id"
    return 1
  }
  plan_task=$(jq -c --arg task_id "$plan_task_id" '.tasks[] | select(.id == $task_id)' "$FOREMAN_PLAN_FILE") || return 1
  [ -n "$plan_task" ] || {
    foreman_task_command_error "plan task was not found: $plan_task_id"
    return 1
  }
  task_type=$(printf '%s' "$plan_task" | jq -r '.type')
  foreman_task_validate_start_policy "$FOREMAN_PLAN_FILE" "$plan_task_id" || return 1
  case "$task_type:$branch" in
    change:'') foreman_task_command_error 'a change task requires an explicit --branch'; return 64 ;;
    research:'') ;;
    research:*) foreman_task_command_error 'a research task must not receive --branch'; return 64 ;;
  esac
  foreman_task_preflight_adapters || return 1

  base_commit=$(git -C "$(jq -r '.project.repository_path' "$FOREMAN_TASK_PROJECT_FILE")" rev-parse HEAD 2>/dev/null) || {
    foreman_task_command_error 'could not resolve the current repository base commit'
    return 1
  }
  task_id="task-$(foreman_task_hash_prefix "$(jq -r '.project.slug' "$FOREMAN_TASK_PROJECT_FILE"):$plan_id:$plan_task_id:$task_type:$branch:$base_commit")" || return 1
  project_lock="$FOREMAN_TASK_PROJECT_ROOT/state/project.lock"
  project_lock_id="start-project-${task_id#task-}-$$"
  task_directory="$FOREMAN_TASK_PROJECT_ROOT/tasks/$task_id"
  task_lock="$task_directory/task.lock"
  task_lock_id="start-task-${task_id#task-}-$$"

  foreman_lock_acquire project "$project_lock" "$project_slug" null "$project_lock_id" || return 1
  if ! foreman_task_assert_project_idle; then
    status=$?
    foreman_lock_release project "$project_lock" "$project_slug" null "$project_lock_id" || return 1
    return "$status"
  fi
  current_base=$(git -C "$(jq -r '.project.repository_path' "$FOREMAN_TASK_PROJECT_FILE")" rev-parse HEAD 2>/dev/null) || status=1
  if [ "${status:-0}" -ne 0 ] || [ "$current_base" != "$base_commit" ]; then
    foreman_task_command_error 'repository base changed while task start was being prepared; no task was created'
    foreman_lock_release project "$project_lock" "$project_slug" null "$project_lock_id" || return 1
    return 1
  fi
  [ ! -e "$task_directory" ] && [ ! -L "$task_directory" ] || {
    foreman_task_command_error "task identity already exists and will not be replaced: $task_id"
    foreman_lock_release project "$project_lock" "$project_slug" null "$project_lock_id" || return 1
    return 1
  }
  mkdir -m 700 "$task_directory" "$task_directory/validation" "$task_directory/delivery" "$task_directory/reports" || {
    foreman_lock_release project "$project_lock" "$project_slug" null "$project_lock_id" || return 1
    return 1
  }
  foreman_lock_acquire task "$task_lock" "$project_slug" "$task_id" "$task_lock_id" || {
    foreman_lock_release project "$project_lock" "$project_slug" null "$project_lock_id" || return 1
    return 1
  }

  snapshot="$task_directory/configuration.json"
  brief="$task_directory/brief.md"
  marker="$task_directory/worktree.json"
  endpoint="$task_directory/endpoint.json"
  request="$task_directory/codex-request.json"
  spec="$task_directory/codex-launch.json"
  runner="$task_directory/runner.sh"
  if foreman_task_write_snapshot "$snapshot" "$task_id" "$base_commit" && \
    foreman_task_write_brief "$brief" "$task_id" "$FOREMAN_PLAN_FILE" "$plan_task_id" && \
    foreman_worktree_allocate "$task_type" "$(jq -r '.project.repository_path' "$FOREMAN_TASK_PROJECT_FILE")" \
      "$(jq -r '.worktree_root' "$FOREMAN_TASK_PROJECT_FILE")" "$project_slug" "$task_id" "${branch:-null}" "$base_commit" "$marker" "$project_lock" "$project_lock_id" >/dev/null && \
    foreman_tmux_reserve_endpoint "$task_id" "$endpoint" "$task_directory/endpoint-owner.json" "$project_slug" "$task_lock" "$task_lock_id" && \
    foreman_codex_diagnose "codex-diagnose-${task_id#task-}" "$task_directory/codex-diagnosis.json" && \
    foreman_tmux_diagnose "tmux-diagnose-${task_id#task-}" "$task_directory/tmux-diagnosis.json"; then
    status=0
  else
    status=$?
  fi
  if [ "$status" -eq 0 ]; then
    worktree_path=$(jq -r '.worktree_path' "$marker")
    if ! jq -n \
      --arg request_id "codex-request-${task_id#task-}" \
      --arg task_id "$task_id" \
      --arg task_type "$task_type" \
      --arg worktree "$worktree_path" \
      --arg prompt "$brief" \
      --arg jsonl "$task_directory/codex-events.jsonl" \
      --arg stderr_path "$task_directory/codex.stderr.log" \
      --arg final "$task_directory/codex-final.json" \
      --slurpfile configuration "$snapshot" '
        {
          schema_version: 1,
          request_id: $request_id,
          task_id: $task_id,
          task_type: $task_type,
          worktree_path: $worktree,
          profile: {
            model: $configuration[0].worker_profile.model,
            reasoning: $configuration[0].worker_profile.reasoning
          },
          prompt_path: $prompt,
          jsonl_path: $jsonl,
          stderr_path: $stderr_path,
          final_output_path: $final
        }
      ' >"$request" || ! foreman_codex_build_launch_spec "$request" "$spec" || \
      ! foreman_task_write_metadata "$task_directory/task.json" "$task_id" "$plan_id" "$plan_task_id" "$FOREMAN_PLAN_FILE" "$snapshot" "$marker" "$endpoint" prepared 2 || \
      ! foreman_task_append_event "$task_directory" "$task_type" "$project_slug" "$task_id" "$task_lock_id" 1 lifecycle-transition foreman planned null approved null \
        'Recorded explicit approval for the task.' "$(foreman_task_evidence "$FOREMAN_PLAN_FILE")" || \
      ! foreman_task_append_event "$task_directory" "$task_type" "$project_slug" "$task_id" "$task_lock_id" 2 lifecycle-transition foreman approved null prepared null \
        'Persisted task identity, configuration, worktree, and runtime reservation.' "$(foreman_task_evidence "$snapshot" "$marker" "$endpoint")"; then
      status=$?
    fi
  fi
  if [ "$status" -eq 0 ]; then
    if foreman_tmux_start "$endpoint" "$spec" "$runner" "$project_slug" "$task_lock" "$task_lock_id" && \
      foreman_task_refresh_endpoint_reference "$task_directory/task.json" "$endpoint" && \
      foreman_task_transition "$task_directory/task.json" "$task_type" running null && \
      foreman_task_append_event "$task_directory" "$task_type" "$project_slug" "$task_id" "$task_lock_id" 3 lifecycle-transition runtime-adapter prepared null running null \
        'Started the task-owned tmux endpoint.' "$(foreman_task_evidence "$endpoint" "$spec")"; then
      status=0
    else
      status=$?
    fi
  fi
  if ! foreman_lock_release task "$task_lock" "$project_slug" "$task_id" "$task_lock_id"; then
    return 1
  fi
  if ! foreman_lock_release project "$project_lock" "$project_slug" null "$project_lock_id"; then
    return 1
  fi
  [ "$status" -eq 0 ] || {
    foreman_task_command_error "task preparation did not complete; preserved state for $task_id"
    return "$status"
  }
  printf 'Started task %s\n' "$task_id"
  printf 'Worktree: %s\n' "$(jq -r '.worktree.path' "$task_directory/task.json")"
  printf 'Runtime endpoint: %s\n' "$(jq -r '.runtime_endpoint.path' "$task_directory/task.json")"
}

foreman_task_status_command() {
  local project_slug='' task_id='' condition

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --project) [ "$#" -ge 2 ] || return 64; project_slug=$2; shift 2 ;;
      --task) [ "$#" -ge 2 ] || return 64; task_id=$2; shift 2 ;;
      -h|--help) foreman_task_usage; return 0 ;;
      *) foreman_task_command_error "unknown status option: $1"; return 64 ;;
    esac
  done
  [ -n "$project_slug" ] && [ -n "$task_id" ] || {
    foreman_task_command_error 'status requires --project and --task'
    return 64
  }
  foreman_task_load_metadata "$project_slug" "$task_id" || return 1
  condition=$(jq -r '.lifecycle.condition // "none"' "$FOREMAN_TASK_FILE")
  printf 'Task: %s\n' "$task_id"
  printf 'Lifecycle: %s\n' "$(jq -r '.lifecycle.status' "$FOREMAN_TASK_FILE")"
  printf 'Condition: %s\n' "$condition"
  printf 'Endpoint: %s\n' "$(jq -r '.runtime_endpoint.path' "$FOREMAN_TASK_FILE")"
  printf 'Endpoint state: %s\n' "$(jq -r '.state' "$(jq -r '.runtime_endpoint.path' "$FOREMAN_TASK_FILE")")"
  printf 'Worktree: %s\n' "$(jq -r '.worktree.path' "$FOREMAN_TASK_FILE")"
}

foreman_task_reconcile_command() {
  local project_slug='' task_id='' task_type endpoint task_lock lock_id endpoint_state current_condition current_status sequence worktree_head
  local status inspection evidence_state

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --project) [ "$#" -ge 2 ] || return 64; project_slug=$2; shift 2 ;;
      --task) [ "$#" -ge 2 ] || return 64; task_id=$2; shift 2 ;;
      -h|--help) foreman_task_usage; return 0 ;;
      *) foreman_task_command_error "unknown reconcile option: $1"; return 64 ;;
    esac
  done
  [ -n "$project_slug" ] && [ -n "$task_id" ] || {
    foreman_task_command_error 'reconcile requires --project and --task'
    return 64
  }
  foreman_task_load_metadata "$project_slug" "$task_id" || return 1
  task_type=$(jq -r '.task.type' "$FOREMAN_TASK_FILE")
  current_status=$(jq -r '.lifecycle.status' "$FOREMAN_TASK_FILE")
  if [ "$current_status" = closed ]; then
    printf 'Task %s is already closed\n' "$task_id"
    return 0
  fi
  endpoint=$(jq -r '.runtime_endpoint.path' "$FOREMAN_TASK_FILE")
  task_lock="$FOREMAN_TASK_DIRECTORY/task.lock"
  lock_id="reconcile-task-${task_id#task-}-$$"
  foreman_lock_acquire task "$task_lock" "$project_slug" "$task_id" "$lock_id" || return 1
  FOREMAN_TASK_LOCK_ID=$lock_id
  export FOREMAN_TASK_LOCK_ID
  if worktree_head=$(foreman_task_recovery_worktree_head "$FOREMAN_TASK_FILE"); then
    status=0
  else
    status=$?
  fi
  if [ "$status" -ne 0 ]; then
    current_condition=$(jq -r '.lifecycle.condition // "null"' "$FOREMAN_TASK_FILE")
    if [ "$current_condition" = null ]; then
      foreman_task_record_condition "$FOREMAN_TASK_FILE" "$task_type" unknown recovery \
        'Could not prove the exact task-owned Git worktree identity; task work was preserved.' \
        "$(foreman_task_evidence "$(jq -r '.worktree.ownership_marker' "$FOREMAN_TASK_FILE")")" || status=$?
    fi
    foreman_lock_release task "$task_lock" "$project_slug" "$task_id" "$lock_id" || return 1
    foreman_task_command_error "Git reconciliation could not prove task identity; preserved task as unknown: $task_id"
    return "${status:-1}"
  fi
  case "$current_status" in
    delivery-ready|change-request-ready|report-ready|landed|teardown-ready)
      endpoint_state=$(jq -r '.state' "$endpoint")
      case "$endpoint_state" in
        missing|exited|closed) ;;
        *)
          foreman_task_record_condition "$FOREMAN_TASK_FILE" "$task_type" unknown recovery \
            'A terminal task retained an unproven runtime endpoint; task work was preserved.' \
            "$(foreman_task_evidence "$endpoint")" || status=$?
          status=1
          foreman_lock_release task "$task_lock" "$project_slug" "$task_id" "$lock_id" || return 1
          foreman_task_command_error "terminal task has an unproven runtime endpoint; preserved task as unknown: $task_id"
          return "${status:-1}"
          ;;
      esac
      foreman_lock_release task "$task_lock" "$project_slug" "$task_id" "$lock_id" || return 1
      printf 'Reconciled task %s\n' "$task_id"
      printf 'Lifecycle: %s\n' "$current_status"
      printf 'Condition: none\n'
      printf 'Endpoint state: %s\n' "$endpoint_state"
      return 0
      ;;
  esac
  if foreman_tmux_inspect "$endpoint" "$project_slug" "$task_lock" "$lock_id"; then
    status=0
  else
    status=$?
  fi
  if [ "$status" -ne 0 ]; then
    current_condition=$(jq -r '.lifecycle.condition // "null"' "$FOREMAN_TASK_FILE")
    if [ "$current_condition" = null ]; then
      foreman_task_record_condition "$FOREMAN_TASK_FILE" "$task_type" unreachable || status=$?
    fi
    foreman_lock_release task "$task_lock" "$project_slug" "$task_id" "$lock_id" || return 1
    foreman_task_command_error "runtime inspection could not prove task state; preserved task as unreachable: $task_id"
    return "${status:-1}"
  fi
  foreman_task_refresh_endpoint_reference "$FOREMAN_TASK_FILE" "$endpoint" || status=$?
  endpoint_state=$(jq -r '.state' "$endpoint")
  current_condition=$(jq -r '.lifecycle.condition // "null"' "$FOREMAN_TASK_FILE")
  current_status=$(jq -r '.lifecycle.status' "$FOREMAN_TASK_FILE")
  if [ "${status:-0}" -eq 0 ] && [ "$endpoint_state" = missing ] && [ "$current_condition" = null ]; then
    foreman_task_record_condition "$FOREMAN_TASK_FILE" "$task_type" missing || status=$?
    inspection="$FOREMAN_TASK_DIRECTORY/recovery-codex-inspection.json"
    if foreman_codex_collect_result "$FOREMAN_TASK_DIRECTORY/codex-launch.json" "$inspection" >/dev/null 2>&1; then
      evidence_state=available
    else
      evidence_state=incomplete
    fi
  elif [ "${status:-0}" -eq 0 ] && [ "$endpoint_state" = active ] && [ "$current_condition" != null ]; then
    sequence=$(jq '.lifecycle.sequence + 1' "$FOREMAN_TASK_FILE")
    if foreman_task_transition "$FOREMAN_TASK_FILE" "$task_type" awaiting-reconciliation null && \
      foreman_task_append_event "$FOREMAN_TASK_DIRECTORY" "$task_type" "$project_slug" "$task_id" "$lock_id" "$sequence" reconciliation recovery "$current_status" "$current_condition" awaiting-reconciliation null \
        'Reconciliation cleared the prior runtime condition.' "$(foreman_task_evidence "$endpoint")"; then
      sequence=$(jq '.lifecycle.sequence + 1' "$FOREMAN_TASK_FILE")
        foreman_task_transition "$FOREMAN_TASK_FILE" "$task_type" running null && \
        foreman_task_append_event "$FOREMAN_TASK_DIRECTORY" "$task_type" "$project_slug" "$task_id" "$lock_id" "$sequence" lifecycle-transition recovery awaiting-reconciliation null running null \
          'Runtime endpoint is active; task supervision resumed.' "$(foreman_task_evidence "$endpoint")" || status=$?
    else
      status=$?
    fi
  fi
  foreman_lock_release task "$task_lock" "$project_slug" "$task_id" "$lock_id" || return 1
  [ "${status:-0}" -eq 0 ] || return "$status"
  printf 'Reconciled task %s\n' "$task_id"
  printf 'Lifecycle: %s\n' "$(jq -r '.lifecycle.status' "$FOREMAN_TASK_FILE")"
  printf 'Condition: %s\n' "$(jq -r '.lifecycle.condition // "none"' "$FOREMAN_TASK_FILE")"
  printf 'Endpoint state: %s\n' "$(jq -r '.state' "$endpoint")"
  if [ "${evidence_state:-}" = available ]; then
    printf 'Worker evidence: terminal result is ready for validation\n'
  elif [ "${evidence_state:-}" = incomplete ]; then
    printf 'Worker evidence: terminal result is not yet complete\n'
  fi
}

# shellcheck source=src/tasks/complete.sh
. "$FOREMAN_SOURCE_ROOT/src/tasks/complete.sh"
# shellcheck source=src/tasks/teardown.sh
. "$FOREMAN_SOURCE_ROOT/src/tasks/teardown.sh"

foreman_task_command() {
  local command=${1:-help}

  case "$command" in
    help|-h|--help) foreman_task_usage ;;
    start) shift; foreman_task_start_command "$@" ;;
    status) shift; foreman_task_status_command "$@" ;;
  reconcile) shift; foreman_task_reconcile_command "$@" ;;
  validate) shift; foreman_task_validate_command "$@" ;;
  teardown) shift; foreman_task_teardown_command "$@" ;;
    *) foreman_task_command_error "unknown task command: $command"; foreman_task_usage >&2; return 64 ;;
  esac
}
