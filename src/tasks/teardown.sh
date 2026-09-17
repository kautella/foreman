#!/usr/bin/env bash

# This file is loaded after src/tasks/complete.sh defines shared task helpers.

foreman_task_teardown_error() {
  printf 'foreman: task teardown: %s\n' "$*" >&2
}

foreman_task_recovery_worktree_head() {
  local task_file=$1 marker_file worktree repository git_common_dir marker_repository marker_common marker_path
  local marker_git_dir marker_branch marker_base task_type top common_raw common git_raw git_dir branch head status

  marker_file=$(jq -r '.worktree.ownership_marker' "$task_file") || return 1
  worktree=$(jq -r '.worktree.path' "$task_file") || return 1
  repository=$(jq -r '.identity.repository_path' "$task_file") || return 1
  git_common_dir=$(jq -r '.identity.git_common_dir' "$task_file") || return 1
  task_type=$(jq -r '.task.type' "$task_file") || return 1
  foreman_worktree_validate_marker "$marker_file" || return 1
  marker_repository=$(jq -r '.repository_path' "$marker_file") || return 1
  marker_common=$(jq -r '.git_common_dir' "$marker_file") || return 1
  marker_path=$(jq -r '.worktree_path' "$marker_file") || return 1
  marker_git_dir=$(jq -r '.git_dir' "$marker_file") || return 1
  marker_branch=$(jq -r '.branch // "null"' "$marker_file") || return 1
  marker_base=$(jq -r '.base_commit' "$marker_file") || return 1

  [ "$marker_repository" = "$repository" ] && [ "$marker_common" = "$git_common_dir" ] && \
    [ "$marker_path" = "$worktree" ] && [ "$marker_git_dir" = "$(jq -r '.worktree.git_dir' "$task_file")" ] && \
    [ "$marker_branch" = "$(jq -r '.worktree.branch // "null"' "$task_file")" ] && \
    [ "$marker_base" = "$(jq -r '.identity.base_commit' "$task_file")" ] || {
    foreman_task_teardown_error 'worktree marker does not match the immutable task identity'
    return 1
  }
  [ -d "$worktree" ] && [ ! -L "$worktree" ] || {
    foreman_task_teardown_error "task-owned worktree is unavailable and will be preserved: $worktree"
    return 1
  }
  top=$(git -C "$worktree" rev-parse --show-toplevel 2>/dev/null) || return 1
  top=$(foreman_path_canonicalize "$top") || return 1
  [ "$top" = "$worktree" ] || {
    foreman_task_teardown_error 'worktree root no longer matches the recorded task worktree'
    return 1
  }
  common_raw=$(git -C "$worktree" rev-parse --git-common-dir 2>/dev/null) || return 1
  common=$(foreman_worktree_canonical_git_path "$worktree" "$common_raw") || return 1
  [ "$common" = "$git_common_dir" ] || {
    foreman_task_teardown_error 'worktree Git common directory no longer matches the task identity'
    return 1
  }
  git_raw=$(git -C "$worktree" rev-parse --git-dir 2>/dev/null) || return 1
  git_dir=$(foreman_worktree_canonical_git_path "$worktree" "$git_raw") || return 1
  [ "$git_dir" = "$marker_git_dir" ] || {
    foreman_task_teardown_error 'worktree Git directory no longer matches the task ownership marker'
    return 1
  }
  case "$task_type" in
    change)
      branch=$(git -C "$worktree" symbolic-ref --quiet --short HEAD 2>/dev/null) || {
        foreman_task_teardown_error 'change task worktree is unexpectedly detached'
        return 1
      }
      [ "$branch" = "$marker_branch" ] || {
        foreman_task_teardown_error 'change task branch no longer matches the task ownership marker'
        return 1
      }
      ;;
    research)
      ! git -C "$worktree" symbolic-ref --quiet HEAD >/dev/null 2>&1 || {
        foreman_task_teardown_error 'research task worktree is unexpectedly attached to a branch'
        return 1
      }
      ;;
    *) return 1 ;;
  esac
  head=$(git -C "$worktree" rev-parse HEAD 2>/dev/null) || return 1
  git -C "$worktree" merge-base --is-ancestor "$marker_base" "$head" >/dev/null 2>&1 || {
    foreman_task_teardown_error 'task worktree history no longer descends from its exact base commit'
    return 1
  }
  if [ "$task_type" = research ]; then
    status=$(git -C "$worktree" status --porcelain=v1 --untracked-files=all) || return 1
    [ "$head" = "$marker_base" ] && [ -z "$status" ] || {
      foreman_task_teardown_error 'research task worktree changed despite its read-only contract'
      return 1
    }
  fi
  printf '%s\n' "$head"
}

foreman_task_teardown_worktree_is_removed() {
  local task_file=$1 marker_file worktree repository git_common_dir task_id project_slug task_type branch base git_dir
  local registered canonical_registered

  marker_file=$(jq -r '.worktree.ownership_marker' "$task_file") || return 1
  worktree=$(jq -r '.worktree.path' "$task_file") || return 1
  repository=$(jq -r '.identity.repository_path' "$task_file") || return 1
  git_common_dir=$(jq -r '.identity.git_common_dir' "$task_file") || return 1
  task_id=$(jq -r '.task_id' "$task_file") || return 1
  project_slug=$(jq -r '.project_slug' "$task_file") || return 1
  task_type=$(jq -r '.task.type' "$task_file") || return 1
  branch=$(jq -r '.worktree.branch // "null"' "$task_file") || return 1
  base=$(jq -r '.identity.base_commit' "$task_file") || return 1
  git_dir=$(jq -r '.worktree.git_dir' "$task_file") || return 1
  foreman_worktree_validate_marker "$marker_file" || return 1
  jq -e --arg task_id "$task_id" --arg project_slug "$project_slug" --arg task_type "$task_type" \
    --arg repository "$repository" --arg common "$git_common_dir" --arg worktree "$worktree" --arg git_dir "$git_dir" \
    --arg branch "$branch" --arg base "$base" '
      .task_id == $task_id and .project_slug == $project_slug and .task_type == $task_type and
      .repository_path == $repository and .git_common_dir == $common and .worktree_path == $worktree and
      .git_dir == $git_dir and (.branch // "null") == $branch and .base_commit == $base
    ' "$marker_file" >/dev/null 2>&1 || {
    foreman_task_teardown_error 'worktree marker no longer matches the immutable task identity'
    return 1
  }
  [ ! -e "$worktree" ] && [ ! -L "$worktree" ] || {
    foreman_task_teardown_error "task-owned worktree remains present: $worktree"
    return 1
  }
  while IFS= read -r registered; do
    [ -n "$registered" ] || continue
    canonical_registered=$(foreman_path_canonicalize "$registered") || return 1
    [ "$canonical_registered" != "$worktree" ] || {
      foreman_task_teardown_error "task-owned worktree remains registered with Git: $worktree"
      return 1
    }
  done <<EOF
$(git -C "$repository" worktree list --porcelain | sed -n 's/^worktree //p')
EOF
}

foreman_task_teardown_validate_landing() {
  local task_file=$1 landing_commit=$2 handoff worktree_head repository_details repository current_head handoff_head handoff_base

  jq -en --arg commit "$landing_commit" '$commit | test("^[0-9a-f]{40}([0-9a-f]{24})?$")' >/dev/null 2>&1 || {
    foreman_task_teardown_error 'landing commit must be an exact full Git commit identity'
    return 1
  }
  handoff=$(jq -r '.artifacts.handoff' "$task_file") || return 1
  foreman_task_require_regular_file 'local change handoff' "$handoff" || return 1
  foreman_task_validate_handoff "$handoff" || return 1
  worktree_head=$(foreman_task_recovery_worktree_head "$task_file") || return 1
  handoff_head=$(jq -r '.head_commit' "$handoff") || return 1
  handoff_base=$(jq -r '.base_commit' "$handoff") || return 1
  [ "$handoff_head" = "$worktree_head" ] && [ "$handoff_base" = "$(jq -r '.identity.base_commit' "$task_file")" ] || {
    foreman_task_teardown_error 'local handoff no longer matches the exact task worktree history'
    return 1
  }
  repository_details=$(foreman_worktree_validate_repository "$(jq -r '.identity.repository_path' "$task_file")") || return 1
  repository=${repository_details%%$'\t'*}
  current_head=$(git -C "$repository" rev-parse HEAD 2>/dev/null) || return 1
  [ "$current_head" = "$landing_commit" ] || {
    foreman_task_teardown_error 'landing commit is not the managed repository current HEAD'
    return 1
  }
  git -C "$repository" merge-base --is-ancestor "$worktree_head" "$landing_commit" >/dev/null 2>&1 || {
    foreman_task_teardown_error 'landing commit does not contain the exact task handoff commit'
    return 1
  }
}

foreman_task_teardown_write_record() {
  local destination=$1 task_file=$2 authority_kind=$3 landing_commit=$4 head_commit=$5 endpoint_state=$6 outcome=$7
  local directory temporary task_id worktree git_dir branch base marker completed_at

  task_id=$(jq -r '.task_id' "$task_file") || return 1
  worktree=$(jq -r '.worktree.path' "$task_file") || return 1
  git_dir=$(jq -r '.worktree.git_dir' "$task_file") || return 1
  branch=$(jq -r '.worktree.branch // "null"' "$task_file") || return 1
  base=$(jq -r '.identity.base_commit' "$task_file") || return 1
  marker=$(jq -r '.worktree.ownership_marker' "$task_file") || return 1
  case "$outcome" in
    authorized) completed_at=null ;;
    closed) completed_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ') ;;
    *) return 1 ;;
  esac
  directory=${destination%/*}
  temporary=$(mktemp "$directory/.foreman-teardown-record.XXXXXX") || return 1
  if ! jq -n \
    --arg teardown_id "teardown-$(foreman_task_hash_prefix "$task_id:$authority_kind:$landing_commit:$head_commit")" \
    --arg task_id "$task_id" --arg requested_at "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    --arg authority_kind "$authority_kind" --arg landing_commit "$landing_commit" \
    --arg worktree "$worktree" --arg git_dir "$git_dir" --arg branch "$branch" --arg base "$base" \
    --arg head "$head_commit" --arg marker "$marker" --arg endpoint "$(jq -r '.runtime_endpoint.path' "$task_file")" \
    --arg endpoint_state "$endpoint_state" --arg outcome "$outcome" --arg completed_at "$completed_at" '
      {
        schema_version: 1,
        teardown_id: $teardown_id,
        task_id: $task_id,
        requested_at: $requested_at,
        authority: {kind: $authority_kind, landing_commit: (if $landing_commit == "null" then null else $landing_commit end)},
        worktree: {path: $worktree, git_dir: $git_dir, branch: (if $branch == "null" then null else $branch end), base_commit: $base, head_commit: $head, ownership_marker: $marker},
        runtime_endpoint: {path: $endpoint, state: $endpoint_state},
        outcome: $outcome,
        completed_at: (if $completed_at == "null" then null else $completed_at end)
      }
    ' >"$temporary" || ! foreman_atomic_write "$temporary" "$destination"; then
    rm -f -- "$temporary"
    return 1
  fi
  rm -f -- "$temporary"
  foreman_task_validate_teardown_record "$destination"
}

foreman_task_teardown_update_artifact() {
  local task_file=$1 teardown_record=$2 directory temporary

  directory=${task_file%/*}
  temporary=$(mktemp "$directory/.foreman-task-teardown-artifact.XXXXXX") || return 1
  if ! jq -S --arg teardown_record "$teardown_record" '.artifacts.teardown = $teardown_record' "$task_file" >"$temporary" || \
    ! foreman_atomic_write "$temporary" "$task_file"; then
    rm -f -- "$temporary"
    return 1
  fi
  rm -f -- "$temporary"
  foreman_task_validate_metadata "$task_file"
}

foreman_task_teardown_prepare_record() {
  local task_file=$1 authority_kind=$2 landing_commit=$3 head_commit=$4 endpoint_state=$5 record=$6

  if [ -e "$record" ] || [ -L "$record" ]; then
    foreman_task_require_regular_file 'teardown record' "$record" || return 1
    foreman_task_validate_teardown_record "$record" || return 1
    jq -e --arg task_id "$(jq -r '.task_id' "$task_file")" --arg kind "$authority_kind" \
      --arg landing_commit "$landing_commit" --arg head "$head_commit" --arg endpoint_state "$endpoint_state" '
        .task_id == $task_id and .outcome == "authorized" and
        .authority.kind == $kind and (.authority.landing_commit // "null") == $landing_commit and
        .worktree.head_commit == $head and .runtime_endpoint.state == $endpoint_state
      ' "$record" >/dev/null 2>&1 || {
      foreman_task_teardown_error 'existing teardown record does not match this exact authorized operation'
      return 1
    }
    return 0
  fi
  foreman_task_teardown_write_record "$record" "$task_file" "$authority_kind" "$landing_commit" "$head_commit" "$endpoint_state" authorized
}

foreman_task_teardown_transition_to_ready() {
  local task_file=$1 task_type=$2 project_slug=$3 task_id=$4 lock_id=$5 authority_kind=$6 landing_commit=$7 record=$8 status

  status=$(jq -r '.lifecycle.status' "$task_file") || return 1
  case "$task_type:$authority_kind:$status" in
    change:confirmed-local-landing:delivery-ready)
      foreman_task_transition_with_event "$task_file" "$task_type" "$project_slug" "$task_id" "$lock_id" landed foreman \
        'Verified the exact local handoff is incorporated in the managed repository current HEAD.' \
        "$(foreman_task_evidence "$record" "$(jq -r '.artifacts.handoff' "$task_file")")" || return 1
      ;;
    change:explicit-discard:delivery-ready|research:explicit-discard:report-ready) ;;
    change:confirmed-local-landing:landed) ;;
    change:confirmed-local-landing:teardown-ready|change:explicit-discard:teardown-ready|\
    research:explicit-discard:teardown-ready) return 0 ;;
    *)
      foreman_task_teardown_error "task lifecycle cannot accept this teardown authority: $status"
      return 1
      ;;
  esac
  status=$(jq -r '.lifecycle.status' "$task_file") || return 1
  [ "$status" = teardown-ready ] || \
    foreman_task_transition_with_event "$task_file" "$task_type" "$project_slug" "$task_id" "$lock_id" teardown-ready foreman \
      'Recorded explicit authority to remove the exact task-owned worktree.' "$(foreman_task_evidence "$record")"
}

foreman_task_teardown_remove_worktree() {
  local task_file=$1 authority_kind=$2 worktree repository

  worktree=$(jq -r '.worktree.path' "$task_file") || return 1
  repository=$(jq -r '.identity.repository_path' "$task_file") || return 1
  case "$authority_kind" in
    confirmed-local-landing)
      git -C "$repository" worktree remove "$worktree" >/dev/null 2>&1 || {
        foreman_task_teardown_error 'Git refused to remove the landed task worktree; all work was preserved'
        return 1
      }
      ;;
    explicit-discard)
      git -C "$repository" worktree remove --force "$worktree" >/dev/null 2>&1 || {
        foreman_task_teardown_error 'Git refused to discard the exact task-owned worktree; all work was preserved'
        return 1
      }
      ;;
    *) return 1 ;;
  esac
  foreman_task_teardown_worktree_is_removed "$task_file"
}

foreman_task_teardown_command() {
  local project_slug='' task_id='' landing_commit='' discard=false task_type status condition task_lock project_lock lock_id project_lock_id
  local endpoint endpoint_state authority_kind worktree_head record operation_status

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --project) [ "$#" -ge 2 ] || return 64; project_slug=$2; shift 2 ;;
      --task) [ "$#" -ge 2 ] || return 64; task_id=$2; shift 2 ;;
      --landed-at) [ "$#" -ge 2 ] || return 64; landing_commit=$2; shift 2 ;;
      --discard) discard=true; shift ;;
      -h|--help) foreman_task_usage; return 0 ;;
      *) foreman_task_command_error "unknown teardown option: $1"; return 64 ;;
    esac
  done
  [ -n "$project_slug" ] && [ -n "$task_id" ] || {
    foreman_task_command_error 'teardown requires --project and --task'
    return 64
  }
  if [ -n "$landing_commit" ]; then
    [ "$discard" = false ] || {
      foreman_task_command_error 'teardown requires exactly one of --landed-at or --discard'
      return 64
    }
  else
    [ "$discard" = true ] || {
      foreman_task_command_error 'teardown requires exactly one of --landed-at or --discard'
      return 64
    }
  fi
  foreman_task_load_metadata "$project_slug" "$task_id" || return 1
  task_type=$(jq -r '.task.type' "$FOREMAN_TASK_FILE") || return 1
  status=$(jq -r '.lifecycle.status' "$FOREMAN_TASK_FILE") || return 1
  condition=$(jq -r '.lifecycle.condition // "null"' "$FOREMAN_TASK_FILE") || return 1
  [ "$status" != closed ] || {
    foreman_task_teardown_error 'task is already closed; no teardown mutation was performed'
    return 1
  }
  [ "$condition" = null ] || {
    foreman_task_teardown_error "task has unresolved $condition condition; worktree was preserved"
    return 1
  }
  case "$task_type:$landing_commit:$discard" in
    change:*:false) authority_kind=confirmed-local-landing ;;
    change::true|research::true) authority_kind=explicit-discard ;;
    research:*:false)
      foreman_task_teardown_error 'research tasks have no landing path and require explicit --discard'
      return 1
      ;;
    *) return 1 ;;
  esac

  project_lock="$FOREMAN_TASK_PROJECT_ROOT/state/project.lock"
  task_lock="$FOREMAN_TASK_DIRECTORY/task.lock"
  project_lock_id="teardown-project-${task_id#task-}-$$"
  lock_id="teardown-task-${task_id#task-}-$$"
  foreman_lock_acquire project "$project_lock" "$project_slug" null "$project_lock_id" || return 1
  if ! foreman_lock_acquire task "$task_lock" "$project_slug" "$task_id" "$lock_id"; then
    foreman_lock_release project "$project_lock" "$project_slug" null "$project_lock_id" || return 1
    return 1
  fi
  FOREMAN_TASK_LOCK_ID=$lock_id
  export FOREMAN_TASK_LOCK_ID
  operation_status=0
  record="$FOREMAN_TASK_DIRECTORY/teardown.json"
  endpoint=$(jq -r '.runtime_endpoint.path' "$FOREMAN_TASK_FILE") || operation_status=1
  endpoint_state=$(jq -r '.state' "$endpoint" 2>/dev/null) || operation_status=1

  if [ "$operation_status" -eq 0 ] && [ "$status" = teardown-ready ] && [ ! -e "$(jq -r '.worktree.path' "$FOREMAN_TASK_FILE")" ] && [ ! -L "$(jq -r '.worktree.path' "$FOREMAN_TASK_FILE")" ]; then
    if foreman_task_teardown_worktree_is_removed "$FOREMAN_TASK_FILE" && \
      foreman_task_teardown_prepare_record "$FOREMAN_TASK_FILE" "$authority_kind" "${landing_commit:-null}" \
        "$(jq -r '.worktree.head_commit' "$record" 2>/dev/null)" "$(jq -r '.runtime_endpoint.state' "$record" 2>/dev/null)" "$record" && \
      foreman_task_teardown_write_record "$record" "$FOREMAN_TASK_FILE" "$authority_kind" "${landing_commit:-null}" \
        "$(jq -r '.worktree.head_commit' "$record")" "$(jq -r '.runtime_endpoint.state' "$record")" closed && \
      foreman_task_teardown_update_artifact "$FOREMAN_TASK_FILE" "$record" && \
      foreman_task_transition_with_event "$FOREMAN_TASK_FILE" "$task_type" "$project_slug" "$task_id" "$lock_id" closed foreman \
        'Recovered a completed exact worktree removal and closed the task.' "$(foreman_task_evidence "$record")"; then
      operation_status=0
    else
      operation_status=1
    fi
  elif [ "$operation_status" -eq 0 ]; then
    if [ "$endpoint_state" = closed ]; then
      operation_status=0
    elif foreman_tmux_inspect "$endpoint" "$project_slug" "$task_lock" "$lock_id" && foreman_task_refresh_endpoint_reference "$FOREMAN_TASK_FILE" "$endpoint"; then
      endpoint_state=$(jq -r '.state' "$endpoint")
      operation_status=0
    else
      operation_status=1
    fi
    case "$endpoint_state" in
      missing|exited|closed) ;;
      *)
        foreman_task_teardown_error "runtime endpoint is $endpoint_state; task worktree was preserved"
        operation_status=1
        ;;
    esac
    if [ "$operation_status" -eq 0 ]; then
      if [ "$authority_kind" = confirmed-local-landing ]; then
        foreman_task_teardown_validate_landing "$FOREMAN_TASK_FILE" "$landing_commit" || operation_status=1
        worktree_head=$(foreman_task_recovery_worktree_head "$FOREMAN_TASK_FILE" 2>/dev/null) || operation_status=1
      else
        worktree_head=$(foreman_task_recovery_worktree_head "$FOREMAN_TASK_FILE") || operation_status=1
      fi
    fi
    if [ "$operation_status" -eq 0 ] && \
      foreman_task_teardown_prepare_record "$FOREMAN_TASK_FILE" "$authority_kind" "${landing_commit:-null}" "$worktree_head" "$endpoint_state" "$record" && \
      foreman_task_teardown_update_artifact "$FOREMAN_TASK_FILE" "$record" && \
      foreman_task_teardown_transition_to_ready "$FOREMAN_TASK_FILE" "$task_type" "$project_slug" "$task_id" "$lock_id" "$authority_kind" "${landing_commit:-null}" "$record" && \
      foreman_task_teardown_remove_worktree "$FOREMAN_TASK_FILE" "$authority_kind" && \
      foreman_task_teardown_write_record "$record" "$FOREMAN_TASK_FILE" "$authority_kind" "${landing_commit:-null}" "$worktree_head" "$endpoint_state" closed && \
      foreman_task_teardown_update_artifact "$FOREMAN_TASK_FILE" "$record" && \
      foreman_task_transition_with_event "$FOREMAN_TASK_FILE" "$task_type" "$project_slug" "$task_id" "$lock_id" closed foreman \
        'Removed the exact task-owned worktree after recorded authority.' "$(foreman_task_evidence "$record")"; then
      operation_status=0
    else
      operation_status=1
    fi
  fi
  foreman_lock_release task "$task_lock" "$project_slug" "$task_id" "$lock_id" || return 1
  foreman_lock_release project "$project_lock" "$project_slug" null "$project_lock_id" || return 1
  [ "$operation_status" -eq 0 ] || {
    foreman_task_teardown_error 'teardown could not be proven safe; task state and any remaining worktree were preserved'
    return 1
  }
  printf 'Closed task %s\n' "$task_id"
  printf 'Teardown record: %s\n' "$record"
}
