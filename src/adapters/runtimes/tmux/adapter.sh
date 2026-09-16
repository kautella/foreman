#!/usr/bin/env bash

# shellcheck source=src/adapters/registry.sh
. "$FOREMAN_SOURCE_ROOT/src/adapters/registry.sh"
# shellcheck source=src/state/atomic.sh
. "$FOREMAN_SOURCE_ROOT/src/state/atomic.sh"
# shellcheck source=src/state/lock.sh
. "$FOREMAN_SOURCE_ROOT/src/state/lock.sh"
# shellcheck source=src/tasks/validate.sh
. "$FOREMAN_SOURCE_ROOT/src/tasks/validate.sh"
# shellcheck source=src/adapters/agents/codex/adapter.sh
. "$FOREMAN_SOURCE_ROOT/src/adapters/agents/codex/adapter.sh"

foreman_tmux_error() {
  printf 'foreman: tmux adapter: %s\n' "$*" >&2
}

foreman_tmux_output_path() {
  local path=$1 directory

  case "$path" in
    /*) ;;
    *) foreman_tmux_error "path must be absolute: $path"; return 1 ;;
  esac
  case "$path" in
    /|*'/../'*|*/..|*'/./'*|*/.)
      foreman_tmux_error "path is ambiguous: $path"
      return 1
      ;;
  esac
  directory=${path%/*}
  [ -d "$directory" ] && [ ! -L "$directory" ] || {
    foreman_tmux_error "parent is not a safe directory: $directory"
    return 1
  }
  [ ! -L "$path" ] || {
    foreman_tmux_error "path must not be a symbolic link: $path"
    return 1
  }
}

foreman_tmux_regular_file() {
  local label=$1 path=$2

  [ -f "$path" ] && [ ! -L "$path" ] || {
    foreman_tmux_error "$label is not a regular file: $path"
    return 1
  }
}

foreman_tmux_write_result() {
  local destination=$1 request_id=$2 ok=$3 status=$4 data_json=$5 diagnostic_code=$6 diagnostic_message=$7 directory temporary

  foreman_tmux_output_path "$destination" || return 1
  directory=${destination%/*}
  temporary=$(mktemp "$directory/.foreman-tmux-result.XXXXXX") || return 1
  if ! jq -n \
    --arg request_id "$request_id" \
    --argjson ok "$ok" \
    --arg status "$status" \
    --argjson data "$data_json" \
    --arg diagnostic_code "$diagnostic_code" \
    --arg diagnostic_message "$diagnostic_message" '
      {
        contract_version: 1,
        request_id: $request_id,
        adapter: {kind: "runtime", id: "tmux"},
        operation: "diagnose",
        ok: $ok,
        status: $status,
        data: $data,
        diagnostics: (if $ok then [] else [{code: $diagnostic_code, message: $diagnostic_message, retryable: false}] end)
      }
    ' >"$temporary" || ! foreman_atomic_write "$temporary" "$destination"; then
    rm -f -- "$temporary"
    return 1
  fi
  rm -f -- "$temporary"
  foreman_adapter_validate_result "$destination"
}

foreman_tmux_executable() {
  foreman_adapter_executable runtime tmux
}

foreman_tmux_require_available() {
  local executable

  executable=$(foreman_tmux_executable) || return 1
  command -v "$executable" >/dev/null 2>&1 || {
    foreman_tmux_error "tmux executable is not available: $executable"
    return 1
  }
  printf '%s\n' "$executable"
}

foreman_tmux_diagnose() {
  local request_id=$1 destination=$2 executable version data

  foreman_adapter_validate_operation runtime tmux diagnose || return 1
  executable=$(foreman_tmux_executable) || return 1
  if ! command -v "$executable" >/dev/null 2>&1; then
    data=$(jq -n --arg executable "$executable" '{executable: $executable, version: null}')
    foreman_tmux_write_result "$destination" "$request_id" false unavailable "$data" \
      executable-not-found "tmux executable '$executable' was not found"
    return 1
  fi
  version=$("$executable" -V 2>/dev/null) || version=unknown
  version=${version%%$'\n'*}
  version=${version:0:512}
  data=$(jq -n --arg executable "$executable" --arg version "$version" '{executable: $executable, version: $version}')
  foreman_tmux_write_result "$destination" "$request_id" true ok "$data" '' ''
}

foreman_tmux_validate_owner_marker() {
  local marker_file=$1

  foreman_tmux_regular_file 'endpoint owner marker' "$marker_file" || return 1
  jq -e '
    def exact($allowed): type == "object" and keys == ($allowed | sort);
    def nonempty: type == "string" and length > 0;
    def timestamp: type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$");
    exact(["endpoint_id", "reserved_at", "runtime", "schema_version", "session", "task_id"]) and
    .schema_version == 1 and (.endpoint_id | type == "string" and test("^endpoint-[0-9a-f]{12}$")) and
    (.task_id | type == "string" and test("^task-[0-9a-f]{12}$")) and .runtime == "tmux" and
    (.session | nonempty) and (.reserved_at | timestamp)
  ' "$marker_file" >/dev/null 2>&1 || {
    foreman_tmux_error "endpoint owner marker has an invalid shape: $marker_file"
    return 1
  }
}

foreman_tmux_write_owner_marker() {
  local marker_file=$1 task_id=$2 endpoint_id=$3 session=$4 directory temporary

  foreman_tmux_output_path "$marker_file" || return 1
  [ ! -e "$marker_file" ] || {
    foreman_tmux_error "endpoint owner marker already exists and will not be adopted: $marker_file"
    return 1
  }
  directory=${marker_file%/*}
  temporary=$(mktemp "$directory/.foreman-tmux-owner.XXXXXX") || return 1
  if ! jq -n \
    --arg task_id "$task_id" \
    --arg endpoint_id "$endpoint_id" \
    --arg session "$session" \
    --arg reserved_at "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" '
      {schema_version: 1, task_id: $task_id, endpoint_id: $endpoint_id, runtime: "tmux", session: $session, reserved_at: $reserved_at}
    ' >"$temporary" || ! foreman_atomic_write "$temporary" "$marker_file"; then
    rm -f -- "$temporary"
    return 1
  fi
  rm -f -- "$temporary"
  foreman_tmux_validate_owner_marker "$marker_file"
}

foreman_tmux_update_endpoint() {
  local endpoint_file=$1 state=$2 observed_at=$3 directory temporary

  foreman_tmux_regular_file 'runtime endpoint' "$endpoint_file" || return 1
  case "$state" in
    reserved|active|exited|missing|unreachable|unknown|closed) ;;
    *) foreman_tmux_error "unknown endpoint state: $state"; return 1 ;;
  esac
  directory=${endpoint_file%/*}
  temporary=$(mktemp "$directory/.foreman-tmux-endpoint.XXXXXX") || return 1
  if ! jq --arg state "$state" --arg observed_at "$observed_at" '
      .state = $state |
      .last_observed_at = (if $state == "reserved" then null else $observed_at end)
    ' "$endpoint_file" >"$temporary" || ! foreman_atomic_write "$temporary" "$endpoint_file"; then
    rm -f -- "$temporary"
    return 1
  fi
  rm -f -- "$temporary"
  foreman_task_validate_endpoint "$endpoint_file"
}

foreman_tmux_validate_endpoint_ownership() {
  local endpoint_file=$1 task_id=$2 owner_marker endpoint_id session expected_endpoint_id expected_session

  foreman_task_validate_endpoint "$endpoint_file" || return 1
  endpoint_id=$(jq -r '.endpoint_id' "$endpoint_file")
  session=$(jq -r '.location.session' "$endpoint_file")
  owner_marker=$(jq -r '.owner.marker_path' "$endpoint_file")
  expected_endpoint_id="endpoint-${task_id#task-}"
  expected_session="foreman-task-${task_id#task-}"
  jq -e --arg task_id "$task_id" --arg endpoint_id "$expected_endpoint_id" --arg session "$expected_session" '
    .task_id == $task_id and .runtime == "tmux" and .kind == "tmux-session" and
    .endpoint_id == $endpoint_id and .owner.task_id == $task_id and .location.session == $session
  ' "$endpoint_file" >/dev/null 2>&1 || {
    foreman_tmux_error "runtime endpoint does not prove task ownership: $endpoint_file"
    return 1
  }
  foreman_tmux_validate_owner_marker "$owner_marker" || return 1
  jq -e --arg task_id "$task_id" --arg endpoint_id "$endpoint_id" --arg session "$session" '
    .task_id == $task_id and .endpoint_id == $endpoint_id and .runtime == "tmux" and .session == $session
  ' "$owner_marker" >/dev/null 2>&1 || {
    foreman_tmux_error "endpoint owner marker does not match endpoint: $owner_marker"
    return 1
  }
}

foreman_tmux_reserve_endpoint() {
  local task_id=$1 endpoint_file=$2 owner_marker=$3 project_slug=$4 task_lock=$5 lock_id=$6
  local endpoint_id session directory temporary

  foreman_adapter_validate_operation runtime tmux create || return 1
  foreman_lock_assert_owned task "$task_lock" "$project_slug" "$task_id" "$lock_id" || return 1
  jq -en --arg task_id "$task_id" '
    $task_id | test("^task-[0-9a-f]{12}$")
  ' >/dev/null 2>&1 || {
    foreman_tmux_error "invalid task identity: $task_id"
    return 1
  }
  foreman_tmux_output_path "$endpoint_file" || return 1
  [ "$endpoint_file" != "$owner_marker" ] || {
    foreman_tmux_error 'runtime endpoint and owner marker paths must be distinct'
    return 1
  }
  [ ! -e "$endpoint_file" ] || {
    foreman_tmux_error "runtime endpoint already exists and will not be adopted: $endpoint_file"
    return 1
  }
  endpoint_id="endpoint-${task_id#task-}"
  session="foreman-task-${task_id#task-}"
  foreman_tmux_write_owner_marker "$owner_marker" "$task_id" "$endpoint_id" "$session" || return 1
  directory=${endpoint_file%/*}
  temporary=$(mktemp "$directory/.foreman-tmux-endpoint.XXXXXX") || return 1
  if ! jq -n \
    --arg task_id "$task_id" \
    --arg endpoint_id "$endpoint_id" \
    --arg owner_marker "$owner_marker" \
    --arg session "$session" \
    --arg reserved_at "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" '
      {
        schema_version: 1,
        task_id: $task_id,
        endpoint_id: $endpoint_id,
        runtime: "tmux",
        kind: "tmux-session",
        state: "reserved",
        reserved_at: $reserved_at,
        owner: {task_id: $task_id, marker_path: $owner_marker},
        location: {session: $session, pane: null},
        last_observed_at: null
      }
    ' >"$temporary" || ! foreman_atomic_write "$temporary" "$endpoint_file"; then
    rm -f -- "$temporary"
    foreman_tmux_error "could not persist endpoint after owner reservation; preserving owner marker: $owner_marker"
    return 1
  fi
  rm -f -- "$temporary"
  foreman_tmux_validate_endpoint_ownership "$endpoint_file" "$task_id"
}

foreman_tmux_write_runner() {
  local runner_file=$1 spec_file=$2 directory temporary

  foreman_tmux_output_path "$runner_file" || return 1
  [ ! -e "$runner_file" ] || {
    foreman_tmux_error "runner file already exists and will not be overwritten: $runner_file"
    return 1
  }
  directory=${runner_file%/*}
  temporary=$(mktemp "$directory/.foreman-tmux-runner.XXXXXX") || return 1
  if ! printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -eu' \
    '[ "$#" -eq 1 ]' \
    'spec_file=$1' \
    'command=$(jq -r ".command" "$spec_file")' \
    'stdin_path=$(jq -r ".stdin_path" "$spec_file")' \
    'jsonl_path=$(jq -r ".jsonl_path" "$spec_file")' \
    'stderr_path=$(jq -r ".stderr_path" "$spec_file")' \
    'argument_count=$(jq -r ".arguments | length" "$spec_file")' \
    'set --' \
    'index=0' \
    'while [ "$index" -lt "$argument_count" ]; do' \
    '  argument=$(jq -r --argjson index "$index" ".arguments[$index]" "$spec_file")' \
    '  set -- "$@" "$argument"' \
    '  index=$((index + 1))' \
    'done' \
    'exec "$command" "$@" < "$stdin_path" > "$jsonl_path" 2> "$stderr_path"' >"$temporary" || \
    ! chmod 0700 "$temporary" || ! foreman_atomic_write "$temporary" "$runner_file" || ! chmod 0700 "$runner_file"; then
    rm -f -- "$temporary"
    return 1
  fi
  rm -f -- "$temporary"
  [ -x "$runner_file" ] && [ ! -L "$runner_file" ] || {
    foreman_tmux_error "generated runner is not executable and safe: $runner_file"
    return 1
  }
}

foreman_tmux_start() {
  local endpoint_file=$1 spec_file=$2 runner_file=$3 project_slug=$4 task_lock=$5 lock_id=$6
  local task_id state session executable observed_at spec_task spec_worktree

  foreman_adapter_validate_operation runtime tmux create || return 1
  task_id=$(jq -r '.task_id' "$endpoint_file" 2>/dev/null) || return 1
  foreman_lock_assert_owned task "$task_lock" "$project_slug" "$task_id" "$lock_id" || return 1
  foreman_tmux_validate_endpoint_ownership "$endpoint_file" "$task_id" || return 1
  state=$(jq -r '.state' "$endpoint_file")
  [ "$state" = reserved ] || {
    foreman_tmux_error "endpoint is not reserved for launch: $endpoint_file"
    return 1
  }
  foreman_codex_validate_launch_spec "$spec_file" || return 1
  spec_task=$(jq -r '.task_id' "$spec_file")
  spec_worktree=$(jq -r '.worktree_path' "$spec_file")
  [ "$spec_task" = "$task_id" ] || {
    foreman_tmux_error "launch specification does not match endpoint task identity: $spec_file"
    return 1
  }
  [ -d "$spec_worktree" ] && [ ! -L "$spec_worktree" ] || {
    foreman_tmux_error "launch specification worktree is not a safe directory: $spec_worktree"
    return 1
  }
  session=$(jq -r '.location.session' "$endpoint_file")
  executable=$(foreman_tmux_require_available) || return 1
  if "$executable" has-session -t "$session" >/dev/null 2>&1; then
    foreman_tmux_error "tmux session already exists and will not be adopted: $session"
    return 1
  fi
  foreman_tmux_write_runner "$runner_file" "$spec_file" || return 1
  foreman_lock_assert_owned task "$task_lock" "$project_slug" "$task_id" "$lock_id" || return 1
  "$executable" new-session -d -s "$session" -c "$spec_worktree" "$runner_file" "$spec_file" >/dev/null 2>&1 || {
    foreman_tmux_error "tmux could not create task-owned session: $session"
    return 1
  }
  observed_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  if ! "$executable" has-session -t "$session" >/dev/null 2>&1; then
    foreman_tmux_update_endpoint "$endpoint_file" unknown "$observed_at" || return 1
    foreman_tmux_error "tmux launch did not yield a proven session; endpoint is unknown: $session"
    return 1
  fi
  foreman_tmux_update_endpoint "$endpoint_file" active "$observed_at"
}

foreman_tmux_inspect() {
  local endpoint_file=$1 project_slug=$2 task_lock=$3 lock_id=$4 task_id state session executable observed_at

  foreman_adapter_validate_operation runtime tmux inspect || return 1
  task_id=$(jq -r '.task_id' "$endpoint_file" 2>/dev/null) || return 1
  foreman_lock_assert_owned task "$task_lock" "$project_slug" "$task_id" "$lock_id" || return 1
  foreman_tmux_validate_endpoint_ownership "$endpoint_file" "$task_id" || return 1
  state=$(jq -r '.state' "$endpoint_file")
  [ "$state" != unknown ] && [ "$state" != closed ] || {
    foreman_tmux_error "endpoint state requires preservation rather than inspection mutation: $state"
    return 1
  }
  session=$(jq -r '.location.session' "$endpoint_file")
  executable=$(foreman_tmux_require_available) || return 1
  observed_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  if "$executable" has-session -t "$session" >/dev/null 2>&1; then
    foreman_tmux_update_endpoint "$endpoint_file" active "$observed_at"
  else
    foreman_tmux_update_endpoint "$endpoint_file" missing "$observed_at"
  fi
}

foreman_tmux_capture() {
  local endpoint_file=$1 destination=$2 project_slug=$3 task_lock=$4 lock_id=$5 task_id session executable directory temporary capture_status tail_status
  local -a pipeline_status

  foreman_adapter_validate_operation runtime tmux capture || return 1
  task_id=$(jq -r '.task_id' "$endpoint_file" 2>/dev/null) || return 1
  foreman_lock_assert_owned task "$task_lock" "$project_slug" "$task_id" "$lock_id" || return 1
  foreman_tmux_validate_endpoint_ownership "$endpoint_file" "$task_id" || return 1
  foreman_tmux_output_path "$destination" || return 1
  [ ! -e "$destination" ] || {
    foreman_tmux_error "capture destination already exists and will not be overwritten: $destination"
    return 1
  }
  session=$(jq -r '.location.session' "$endpoint_file")
  executable=$(foreman_tmux_require_available) || return 1
  "$executable" has-session -t "$session" >/dev/null 2>&1 || {
    foreman_tmux_error "cannot capture an absent task-owned session: $session"
    return 1
  }
  directory=${destination%/*}
  temporary=$(mktemp "$directory/.foreman-tmux-capture.XXXXXX") || return 1
  "$executable" capture-pane -p -t "$session" -S -200 2>/dev/null | tail -c 65536 >"$temporary"
  pipeline_status=("${PIPESTATUS[@]}")
  capture_status=${pipeline_status[0]}
  tail_status=${pipeline_status[1]}
  if [ "$capture_status" -ne 0 ] || [ "$tail_status" -ne 0 ] || ! foreman_atomic_write "$temporary" "$destination"; then
    rm -f -- "$temporary"
    foreman_tmux_error "could not capture bounded task output: $session"
    return 1
  fi
  rm -f -- "$temporary"
}

foreman_tmux_close() {
  local endpoint_file=$1 project_slug=$2 task_lock=$3 lock_id=$4 task_id state session executable observed_at

  foreman_adapter_validate_operation runtime tmux close || return 1
  task_id=$(jq -r '.task_id' "$endpoint_file" 2>/dev/null) || return 1
  foreman_lock_assert_owned task "$task_lock" "$project_slug" "$task_id" "$lock_id" || return 1
  foreman_tmux_validate_endpoint_ownership "$endpoint_file" "$task_id" || return 1
  state=$(jq -r '.state' "$endpoint_file")
  [ "$state" != unknown ] && [ "$state" != closed ] || {
    foreman_tmux_error "endpoint state does not permit closure: $state"
    return 1
  }
  session=$(jq -r '.location.session' "$endpoint_file")
  executable=$(foreman_tmux_require_available) || return 1
  observed_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  "$executable" has-session -t "$session" >/dev/null 2>&1 || {
    foreman_tmux_update_endpoint "$endpoint_file" missing "$observed_at" || return 1
    foreman_tmux_error "task-owned session is absent; endpoint remains preserved as missing: $session"
    return 1
  }
  "$executable" kill-session -t "$session" >/dev/null 2>&1 || {
    foreman_tmux_error "tmux could not close task-owned session: $session"
    return 1
  }
  if "$executable" has-session -t "$session" >/dev/null 2>&1; then
    foreman_tmux_update_endpoint "$endpoint_file" unknown "$observed_at" || return 1
    foreman_tmux_error "tmux session remained after closure request; endpoint is unknown: $session"
    return 1
  fi
  foreman_tmux_update_endpoint "$endpoint_file" closed "$observed_at"
}
