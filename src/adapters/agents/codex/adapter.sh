#!/usr/bin/env bash

# shellcheck source=src/adapters/registry.sh
. "$FOREMAN_SOURCE_ROOT/src/adapters/registry.sh"
# shellcheck source=src/state/atomic.sh
. "$FOREMAN_SOURCE_ROOT/src/state/atomic.sh"

foreman_codex_error() {
  printf 'foreman: codex adapter: %s\n' "$*" >&2
}

foreman_codex_output_path() {
  local path=$1 directory

  case "$path" in
    /*) ;;
    *) foreman_codex_error "output path must be absolute: $path"; return 1 ;;
  esac
  case "$path" in
    /|*'/../'*|*/..|*'/./'*|*/.)
      foreman_codex_error "output path is ambiguous: $path"
      return 1
      ;;
  esac
  directory=${path%/*}
  [ -d "$directory" ] && [ ! -L "$directory" ] || {
    foreman_codex_error "output directory is not a safe directory: $directory"
    return 1
  }
  [ ! -L "$path" ] || {
    foreman_codex_error "output path must not be a symbolic link: $path"
    return 1
  }
}

foreman_codex_regular_file() {
  local label=$1 path=$2

  [ -f "$path" ] && [ ! -L "$path" ] || {
    foreman_codex_error "$label is not a regular file: $path"
    return 1
  }
}

foreman_codex_write_result() {
  local destination=$1 request_id=$2 operation=$3 ok=$4 status=$5 data_json=$6 diagnostic_code=$7 diagnostic_message=$8
  local directory temporary

  foreman_codex_output_path "$destination" || return 1
  directory=${destination%/*}
  temporary=$(mktemp "$directory/.foreman-codex-result.XXXXXX") || return 1
  if ! jq -n \
    --arg request_id "$request_id" \
    --arg operation "$operation" \
    --argjson ok "$ok" \
    --arg status "$status" \
    --argjson data "$data_json" \
    --arg diagnostic_code "$diagnostic_code" \
    --arg diagnostic_message "$diagnostic_message" '
      {
        contract_version: 1,
        request_id: $request_id,
        adapter: {kind: "agent", id: "codex"},
        operation: $operation,
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

foreman_codex_diagnose() {
  local request_id=$1 destination=$2 executable version data

  foreman_adapter_validate_operation agent codex diagnose || return 1
  executable=$(foreman_adapter_executable agent codex) || return 1
  if ! command -v "$executable" >/dev/null 2>&1; then
    data=$(jq -n --arg executable "$executable" '{executable: $executable, version: null, authenticated: false}')
    foreman_codex_write_result "$destination" "$request_id" diagnose false unavailable "$data" \
      executable-not-found "Codex CLI executable '$executable' was not found"
    return 1
  fi
  version=$("$executable" --version 2>/dev/null) || version=unknown
  version=${version%%$'\n'*}
  version=${version:0:512}
  if "$executable" login status >/dev/null 2>&1; then
    data=$(jq -n --arg executable "$executable" --arg version "$version" '{executable: $executable, version: $version, authenticated: true}')
    foreman_codex_write_result "$destination" "$request_id" diagnose true ok "$data" '' ''
    return 0
  fi
  data=$(jq -n --arg executable "$executable" --arg version "$version" '{executable: $executable, version: $version, authenticated: false}')
  foreman_codex_write_result "$destination" "$request_id" diagnose false unavailable "$data" \
    authentication-not-ready 'Codex CLI is installed but not authenticated'
  return 1
}

foreman_codex_validate_launch_request() {
  local file=$1

  foreman_codex_regular_file 'launch request' "$file" || return 1
  jq -e '
    def exact($allowed): type == "object" and keys == ($allowed | sort);
    def nonempty: type == "string" and length > 0;
    def path: nonempty and startswith("/");
    def profile: exact(["model", "reasoning"]) and (.model | nonempty) and (.reasoning | nonempty);
    exact(["final_output_path", "jsonl_path", "profile", "prompt_path", "request_id", "schema_version", "stderr_path", "task_id", "task_type", "worktree_path"]) and
    .schema_version == 1 and
    (.request_id | type == "string" and test("^codex-request-[0-9a-f]{12}$")) and
    (.task_id | type == "string" and test("^task-[0-9a-f]{12}$")) and
    (.task_type | IN("change", "research")) and (.worktree_path | path) and (.profile | profile) and
    (.prompt_path | path) and (.jsonl_path | path) and (.stderr_path | path) and (.final_output_path | path) and
    .jsonl_path != .final_output_path and .jsonl_path != .stderr_path and .stderr_path != .final_output_path
  ' "$file" >/dev/null 2>&1 || {
    foreman_codex_error "launch request does not match codex/launch-request.schema.json: $file"
    return 1
  }
}

foreman_codex_validate_launch_spec() {
  local file=$1 output_schema_path

  foreman_codex_regular_file 'launch specification' "$file" || return 1
  output_schema_path="$FOREMAN_SOURCE_ROOT/src/adapters/agents/codex/final-output.schema.json"
  jq -e --arg output_schema_path "$output_schema_path" '
    def exact($allowed): type == "object" and keys == ($allowed | sort);
    def nonempty: type == "string" and length > 0;
    def path: nonempty and startswith("/");
    def profile: exact(["model", "reasoning"]) and (.model | nonempty) and (.reasoning | nonempty);
    exact(["adapter", "arguments", "command", "final_output_path", "jsonl_path", "output_schema_path", "profile", "request_id", "sandbox", "schema_version", "stderr_path", "stdin_path", "task_id", "task_type", "worktree_path"]) and
    .schema_version == 1 and .adapter == "codex" and
    (.request_id | type == "string" and test("^codex-request-[0-9a-f]{12}$")) and
    (.task_id | type == "string" and test("^task-[0-9a-f]{12}$")) and
    (.task_type | IN("change", "research")) and (.worktree_path | path) and (.profile | profile) and
    (.sandbox | IN("workspace-write", "read-only")) and .command == "codex" and
    (.arguments | type == "array" and all(.[]; nonempty)) and (.stdin_path | path) and
    (.jsonl_path | path) and (.stderr_path | path) and (.final_output_path | path) and
    .jsonl_path != .final_output_path and .jsonl_path != .stderr_path and .stderr_path != .final_output_path and
    (.output_schema_path == $output_schema_path) and
    .arguments == [
      "exec", "--json", "--sandbox", .sandbox, "--cd", .worktree_path, "--model", .profile.model,
      "--config", ("model_reasoning_effort=" + .profile.reasoning), "--output-schema", .output_schema_path,
      "--output-last-message", .final_output_path, "-"
    ] and
    (if .task_type == "change" then .sandbox == "workspace-write" else .sandbox == "read-only" end)
  ' "$file" >/dev/null 2>&1 || {
    foreman_codex_error "launch specification does not match codex/launch-spec.schema.json: $file"
    return 1
  }
}

foreman_codex_build_launch_spec() {
  local request_file=$1 spec_file=$2 task_type task_id request_id worktree profile_model profile_reasoning prompt jsonl stderr_path final sandbox output_schema directory temporary

  foreman_adapter_validate_operation agent codex launch || return 1
  foreman_codex_validate_launch_request "$request_file" || return 1
  task_type=$(jq -r '.task_type' "$request_file")
  task_id=$(jq -r '.task_id' "$request_file")
  request_id=$(jq -r '.request_id' "$request_file")
  worktree=$(jq -r '.worktree_path' "$request_file")
  profile_model=$(jq -r '.profile.model' "$request_file")
  profile_reasoning=$(jq -r '.profile.reasoning' "$request_file")
  prompt=$(jq -r '.prompt_path' "$request_file")
  jsonl=$(jq -r '.jsonl_path' "$request_file")
  stderr_path=$(jq -r '.stderr_path' "$request_file")
  final=$(jq -r '.final_output_path' "$request_file")
  foreman_adapter_validate_profile codex "$profile_model" "$profile_reasoning" || return 1
  [ -d "$worktree" ] && [ ! -L "$worktree" ] || {
    foreman_codex_error "task worktree is not a safe directory: $worktree"
    return 1
  }
  foreman_codex_regular_file 'task brief' "$prompt" || return 1
  foreman_codex_output_path "$jsonl" || return 1
  foreman_codex_output_path "$stderr_path" || return 1
  foreman_codex_output_path "$final" || return 1
  [ ! -e "$jsonl" ] && [ ! -e "$stderr_path" ] && [ ! -e "$final" ] || {
    foreman_codex_error 'Codex output paths already exist and will not be overwritten'
    return 1
  }
  foreman_codex_output_path "$spec_file" || return 1
  [ ! -e "$spec_file" ] || {
    foreman_codex_error "launch specification already exists and will not be overwritten: $spec_file"
    return 1
  }
  case "$task_type" in
    change) sandbox=workspace-write ;;
    research) sandbox=read-only ;;
  esac
  output_schema="$FOREMAN_SOURCE_ROOT/src/adapters/agents/codex/final-output.schema.json"
  foreman_codex_regular_file 'final output schema' "$output_schema" || return 1
  directory=${spec_file%/*}
  temporary=$(mktemp "$directory/.foreman-codex-spec.XXXXXX") || return 1
  if ! jq -n \
    --arg request_id "$request_id" \
    --arg task_id "$task_id" \
    --arg task_type "$task_type" \
    --arg worktree "$worktree" \
    --arg model "$profile_model" \
    --arg reasoning "$profile_reasoning" \
    --arg sandbox "$sandbox" \
    --arg prompt "$prompt" \
    --arg jsonl "$jsonl" \
    --arg stderr_path "$stderr_path" \
    --arg final "$final" \
    --arg output_schema "$output_schema" '
      {
        schema_version: 1,
        adapter: "codex",
        request_id: $request_id,
        task_id: $task_id,
        task_type: $task_type,
        worktree_path: $worktree,
        profile: {model: $model, reasoning: $reasoning},
        sandbox: $sandbox,
        command: "codex",
        arguments: [
          "exec", "--json", "--sandbox", $sandbox, "--cd", $worktree, "--model", $model,
          "--config", ("model_reasoning_effort=" + $reasoning), "--output-schema", $output_schema,
          "--output-last-message", $final, "-"
        ],
        stdin_path: $prompt,
        jsonl_path: $jsonl,
        stderr_path: $stderr_path,
        final_output_path: $final,
        output_schema_path: $output_schema
      }
    ' >"$temporary" || ! foreman_atomic_write "$temporary" "$spec_file"; then
    rm -f -- "$temporary"
    return 1
  fi
  rm -f -- "$temporary"
  foreman_codex_validate_launch_spec "$spec_file"
}

foreman_codex_validate_final_output() {
  local file=$1

  foreman_codex_regular_file 'structured final output' "$file" || return 1
  jq -e '
    def exact($allowed): type == "object" and keys == ($allowed | sort);
    def nonempty: type == "string" and length > 0;
    def strings: type == "array" and all(.[]; nonempty) and length == (unique | length);
    exact(["changed_files", "risks", "status", "summary"]) and
    (.status | IN("completed", "blocked", "failed")) and (.summary | nonempty) and
    (.changed_files | strings) and (.risks | strings)
  ' "$file" >/dev/null 2>&1 || {
    foreman_codex_error "structured final output does not match codex/final-output.schema.json: $file"
    return 1
  }
}

foreman_codex_stream_summary() {
  local stream_file=$1 line record_count=0 byte_count terminal_event='' type

  foreman_codex_regular_file 'JSONL event stream' "$stream_file" || return 1
  byte_count=$(wc -c <"$stream_file" | tr -d ' ')
  [ "$byte_count" -le 2097152 ] || {
    foreman_codex_error "JSONL event stream exceeds the 2 MiB bound: $stream_file"
    return 1
  }
  while IFS= read -r line || [ -n "$line" ]; do
    [ -n "$line" ] || {
      foreman_codex_error "JSONL event stream contains an empty record: $stream_file"
      return 1
    }
    record_count=$((record_count + 1))
    [ "$record_count" -le 2000 ] || {
      foreman_codex_error "JSONL event stream exceeds the 2000-record bound: $stream_file"
      return 1
    }
    printf '%s\n' "$line" | jq -e 'type == "object" and (.type | type == "string" and length > 0)' >/dev/null 2>&1 || {
      foreman_codex_error "JSONL event stream contains an invalid event: $stream_file"
      return 1
    }
    type=$(printf '%s\n' "$line" | jq -r '.type')
    case "$type" in
      turn.completed|turn.failed) terminal_event=$type ;;
    esac
  done <"$stream_file"
  [ "$record_count" -gt 0 ] || {
    foreman_codex_error "JSONL event stream has no events: $stream_file"
    return 1
  }
  jq -n --argjson bytes "$byte_count" --argjson records "$record_count" --arg terminal_event "$terminal_event" \
    '{bytes: $bytes, records: $records, terminal_event: (if $terminal_event == "" then null else $terminal_event end)}'
}

foreman_codex_collect_result() {
  local spec_file=$1 destination=$2 request_id stream_file final_file summary data terminal_event

  foreman_adapter_validate_operation agent codex inspect || return 1
  foreman_codex_validate_launch_spec "$spec_file" || return 1
  request_id=$(jq -r '.request_id' "$spec_file")
  stream_file=$(jq -r '.jsonl_path' "$spec_file")
  final_file=$(jq -r '.final_output_path' "$spec_file")
  if ! summary=$(foreman_codex_stream_summary "$stream_file"); then
    foreman_codex_write_result "$destination" "$request_id" inspect false ambiguous '{}' \
      event-stream-invalid 'Codex event stream is absent, malformed, or exceeds its bound'
    return 1
  fi
  terminal_event=$(printf '%s' "$summary" | jq -r '.terminal_event // empty')
  if [ "$terminal_event" != turn.completed ]; then
    data=$(jq -n --argjson stream "$summary" '{stream: $stream}')
    foreman_codex_write_result "$destination" "$request_id" inspect false ambiguous "$data" \
      terminal-event-missing 'Codex did not provide a completed terminal event'
    return 1
  fi
  if ! foreman_codex_validate_final_output "$final_file"; then
    data=$(jq -n --argjson stream "$summary" '{stream: $stream}')
    foreman_codex_write_result "$destination" "$request_id" inspect false ambiguous "$data" \
      final-output-invalid 'Codex final output is absent or does not match the structured contract'
    return 1
  fi
  data=$(jq -n --argjson stream "$summary" --slurpfile final "$final_file" '{stream: $stream, final: $final[0]}') || return 1
  foreman_codex_write_result "$destination" "$request_id" inspect true ok "$data" '' ''
}
