#!/usr/bin/env bash

foreman_task_error() {
  printf 'foreman: task contract: %s\n' "$*" >&2
}

foreman_task_require_json() {
  local file=$1 contract=$2

  [ -f "$file" ] && [ ! -L "$file" ] || {
    foreman_task_error "$contract is not a regular file: $file"
    return 1
  }
  jq empty "$file" >/dev/null 2>&1 || {
    foreman_task_error "$contract is not valid JSON: $file"
    return 1
  }
}

foreman_task_validate_metadata() {
  local file=$1

  foreman_task_require_json "$file" 'task metadata' || return 1
  jq -e '
    def exact($allowed): type == "object" and keys == ($allowed | sort);
    def nonempty: type == "string" and length > 0;
    def path: nonempty and startswith("/");
    def commit: type == "string" and test("^[0-9a-f]{40}([0-9a-f]{24})?$");
    def sha256: type == "string" and test("^[0-9a-f]{64}$");
    def timestamp: type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$");
    def strings: type == "array" and all(.[]; nonempty) and length == (unique | length);
    def nonempty_strings: strings and length > 0;
    def profile:
      exact(["agent", "model", "reasoning"]) and
      (.agent | IN("claude", "codex", "gemini", "opencode", "pi")) and
      (.model | nonempty) and (.reasoning | nonempty);
    def delivery:
      exact(["merge_authority", "policy"]) and
      (.policy | IN("draft-handoff", "automated-change-request")) and
      (.merge_authority | type == "boolean") and
      (if .policy == "draft-handoff" then .merge_authority == false else true end);
    def reference: exact(["path", "sha256"]) and (.path | path) and (.sha256 | sha256);
    def worktree:
      exact(["base_commit", "branch", "git_dir", "ownership_marker", "path"]) and
      (.path | path) and (.git_dir | path) and (.ownership_marker | path) and
      (.base_commit | commit) and (.branch == null or (.branch | nonempty));
    def lifecycle:
      exact(["condition", "sequence", "status", "updated_at"]) and
      (.status | IN("planned", "approved", "prepared", "running", "awaiting-reconciliation", "validated", "delivery-ready", "change-request-ready", "report-ready", "landed", "teardown-ready", "closed")) and
      (.condition == null or (.condition | IN("blocked", "failed", "missing", "unreachable", "unknown"))) and
      (.updated_at | timestamp) and (.sequence | type == "number" and floor == . and . >= 0);
    def nullable_path: . == null or path;
    def artifacts:
      exact(["brief", "events", "findings", "handoff", "report", "result", "teardown", "validation_directory"]) and
      (.brief | nullable_path) and (.events | path) and
      (.validation_directory | nullable_path) and (.result | nullable_path) and
      (.handoff | nullable_path) and (.report | nullable_path) and (.findings | nullable_path) and
      (.teardown | nullable_path);

    exact(["artifacts", "configuration_snapshot", "identity", "lifecycle", "plan", "project_slug", "runtime_endpoint", "schema_version", "task", "task_id", "worktree"]) and
    .schema_version == 1 and
    (.task_id | type == "string" and test("^task-[0-9a-f]{12}$")) and
    (.project_slug | type == "string" and test("^[a-z0-9]+(-[a-z0-9]+)*$")) and
    (.plan | exact(["plan_id", "task_id"]) and
      (.plan_id | type == "string" and test("^plan-[0-9a-f]{12}$")) and
      (.task_id | type == "string" and test("^[a-z][a-z0-9-]*$"))) and
    (.task | exact(["acceptance_criteria", "objective", "title", "type", "validation_commands"]) and
      (.type | IN("change", "research")) and (.title | nonempty) and (.objective | nonempty) and
      (.acceptance_criteria | nonempty_strings) and (.validation_commands | strings)) and
    (.identity | exact(["base_commit", "delivery", "git_common_dir", "repository_path", "runtime", "worker_profile"]) and
      (.repository_path | path) and (.git_common_dir | path) and (.base_commit | commit) and
      (.worker_profile | profile) and (.runtime | IN("tmux", "herdr")) and (.delivery | delivery)) and
    (.configuration_snapshot == null or (.configuration_snapshot | reference)) and
    (.worktree == null or (.worktree | worktree)) and
    (.runtime_endpoint == null or (.runtime_endpoint | reference)) and
    (.lifecycle | lifecycle) and (.artifacts | artifacts) and
    (if .task.type == "change" and .worktree != null then (.worktree.branch | nonempty)
     elif .task.type == "research" and .worktree != null then .worktree.branch == null
     else true end) and
    (if .lifecycle.status | IN("prepared", "running", "awaiting-reconciliation", "validated", "delivery-ready", "change-request-ready", "report-ready", "landed", "teardown-ready", "closed") then
      .configuration_snapshot != null and .worktree != null and .runtime_endpoint != null and
      (.artifacts.brief | path) and (.artifacts.validation_directory | path)
     else true end) and
    (if .lifecycle.status == "closed" then .lifecycle.condition == null and (.artifacts.teardown | path) else true end)
  ' "$file" >/dev/null 2>&1 || {
    foreman_task_error "task metadata does not match src/contracts/task/task.schema.json: $file"
    return 1
  }
}

foreman_task_validate_configuration_snapshot() {
  local file=$1

  foreman_task_require_json "$file" 'configuration snapshot' || return 1
  jq -e '
    def exact($allowed): type == "object" and keys == ($allowed | sort);
    def nonempty: type == "string" and length > 0;
    def path: nonempty and startswith("/");
    def commit: type == "string" and test("^[0-9a-f]{40}([0-9a-f]{24})?$");
    def timestamp: type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$");
    def profile:
      exact(["agent", "model", "reasoning"]) and
      (.agent | IN("claude", "codex", "gemini", "opencode", "pi")) and
      (.model | nonempty) and (.reasoning | nonempty);
    def commands: type == "array" and all(.[]; nonempty) and length == (unique | length);

    exact(["captured_at", "delivery", "project", "runtime", "schema_version", "task_id", "validation", "worker_profile"]) and
    .schema_version == 1 and
    (.task_id | type == "string" and test("^task-[0-9a-f]{12}$")) and (.captured_at | timestamp) and
    (.project | exact(["base_commit", "git_common_dir", "repository_path", "slug", "worktree_root"]) and
      (.slug | type == "string" and test("^[a-z0-9]+(-[a-z0-9]+)*$")) and
      (.repository_path | path) and (.git_common_dir | path) and (.worktree_root | path) and (.base_commit | commit)) and
    (.worker_profile | profile) and (.runtime | IN("tmux", "herdr")) and
    (.delivery | exact(["merge_authority", "policy"]) and
      (.policy | IN("draft-handoff", "automated-change-request")) and
      (.merge_authority | type == "boolean") and
      (if .policy == "draft-handoff" then .merge_authority == false else true end)) and
    (.validation | exact(["commands", "require_clean_worktree"]) and
      (.commands | commands) and (.require_clean_worktree | type == "boolean"))
  ' "$file" >/dev/null 2>&1 || {
    foreman_task_error "configuration snapshot does not match src/contracts/task/configuration-snapshot.schema.json: $file"
    return 1
  }
}

foreman_task_validate_endpoint() {
  local file=$1

  foreman_task_require_json "$file" 'runtime endpoint' || return 1
  jq -e '
    def exact($allowed): type == "object" and keys == ($allowed | sort);
    def nonempty: type == "string" and length > 0;
    def path: nonempty and startswith("/");
    def timestamp: type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$");
    .task_id as $task_id |
    exact(["endpoint_id", "kind", "last_observed_at", "location", "owner", "reserved_at", "runtime", "schema_version", "state", "task_id"]) and
    .schema_version == 1 and
    (.task_id | type == "string" and test("^task-[0-9a-f]{12}$")) and
    (.endpoint_id | type == "string" and test("^endpoint-[0-9a-f]{12}$")) and
    (.runtime | IN("tmux", "herdr")) and
    (.kind | IN("tmux-session", "herdr-session")) and
    ((.runtime == "tmux" and .kind == "tmux-session") or (.runtime == "herdr" and .kind == "herdr-session")) and
    (.state | IN("reserved", "active", "exited", "missing", "unreachable", "unknown", "closed")) and
    (.reserved_at | timestamp) and
    (.owner | exact(["marker_path", "task_id"]) and (.task_id == $task_id) and (.marker_path | path)) and
    (.location | exact(["pane", "session"]) and (.session | nonempty) and (.pane == null or (.pane | nonempty))) and
    (.last_observed_at == null or (.last_observed_at | timestamp)) and
    (if .state | IN("active", "exited", "missing", "unreachable", "unknown", "closed") then .last_observed_at != null else true end)
  ' "$file" >/dev/null 2>&1 || {
    foreman_task_error "runtime endpoint does not match src/contracts/task/endpoint.schema.json: $file"
    return 1
  }
}

foreman_task_validate_teardown_record() {
  local file=$1

  foreman_task_require_json "$file" 'teardown record' || return 1
  jq -e '
    def exact($allowed): type == "object" and keys == ($allowed | sort);
    def nonempty: type == "string" and length > 0;
    def path: nonempty and startswith("/");
    def commit: type == "string" and test("^[0-9a-f]{40}([0-9a-f]{24})?$");
    def timestamp: type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$");
    exact(["authority", "completed_at", "outcome", "requested_at", "runtime_endpoint", "schema_version", "task_id", "teardown_id", "worktree"]) and
    .schema_version == 1 and
    (.teardown_id | type == "string" and test("^teardown-[0-9a-f]{12}$")) and
    (.task_id | type == "string" and test("^task-[0-9a-f]{12}$")) and (.requested_at | timestamp) and
    (.authority | exact(["kind", "landing_commit"]) and
      (.kind | IN("confirmed-local-landing", "explicit-discard")) and
      (.landing_commit == null or (.landing_commit | commit)) and
      (if .kind == "confirmed-local-landing" then (.landing_commit | commit) else .landing_commit == null end)) and
    (.worktree | exact(["base_commit", "branch", "git_dir", "head_commit", "ownership_marker", "path"]) and
      (.path | path) and (.git_dir | path) and (.branch == null or (.branch | nonempty)) and
      (.base_commit | commit) and (.head_commit | commit) and (.ownership_marker | path)) and
    (.runtime_endpoint | exact(["path", "state"]) and (.path | path) and (.state | IN("missing", "exited", "closed"))) and
    (.outcome | IN("authorized", "closed")) and
    (.completed_at == null or (.completed_at | timestamp)) and
    (if .outcome == "authorized" then .completed_at == null else (.completed_at | timestamp) end)
  ' "$file" >/dev/null 2>&1 || {
    foreman_task_error "teardown record does not match src/contracts/task/teardown-record.schema.json: $file"
    return 1
  }
}

foreman_task_validate_lifecycle_transition() {
  local task_type=$1 from_status=$2 from_condition=$3 to_status=$4 to_condition=$5

  case "$task_type" in
    change|research) ;;
    *) foreman_task_error "unsupported task type for lifecycle transition: $task_type"; return 1 ;;
  esac
  case "$from_status" in
    planned|approved|prepared|running|awaiting-reconciliation|validated|delivery-ready|change-request-ready|report-ready|landed|teardown-ready|closed) ;;
    *) foreman_task_error "unknown lifecycle status: $from_status"; return 1 ;;
  esac
  case "$to_status" in
    planned|approved|prepared|running|awaiting-reconciliation|validated|delivery-ready|change-request-ready|report-ready|landed|teardown-ready|closed) ;;
    *) foreman_task_error "unknown lifecycle status: $to_status"; return 1 ;;
  esac
  case "$from_condition" in
    null|blocked|failed|missing|unreachable|unknown) ;;
    *) foreman_task_error "unknown lifecycle condition: $from_condition"; return 1 ;;
  esac
  case "$to_condition" in
    null|blocked|failed|missing|unreachable|unknown) ;;
    *) foreman_task_error "unknown lifecycle condition: $to_condition"; return 1 ;;
  esac

  [ "$from_status" != closed ] || {
    foreman_task_error 'a closed task cannot transition'
    return 1
  }

  if [ "$from_condition" != null ]; then
    [ "$to_status" = awaiting-reconciliation ] && [ "$to_condition" = null ] || {
      foreman_task_error 'a conditioned task can resume only through awaiting-reconciliation'
      return 1
    }
    return 0
  fi

  if [ "$to_condition" != null ]; then
    case "$from_status" in
      prepared|running|awaiting-reconciliation|validated|delivery-ready|change-request-ready|report-ready|landed|teardown-ready) ;;
      *) foreman_task_error "cannot record a lifecycle condition from $from_status"; return 1 ;;
    esac
    [ "$to_status" = "$from_status" ] || {
      foreman_task_error 'recording a lifecycle condition must preserve the last stable status'
      return 1
    }
    return 0
  fi

  case "$task_type:$from_status:$to_status" in
    change:planned:approved|research:planned:approved|\
    change:approved:prepared|research:approved:prepared|\
    change:prepared:running|research:prepared:running|\
    change:running:awaiting-reconciliation|research:running:awaiting-reconciliation|\
    change:awaiting-reconciliation:running|research:awaiting-reconciliation:running|\
    change:awaiting-reconciliation:validated|research:awaiting-reconciliation:validated|\
    change:validated:delivery-ready|change:validated:change-request-ready|\
    research:validated:report-ready|\
    change:delivery-ready:landed|change:change-request-ready:landed|\
    change:delivery-ready:teardown-ready|change:change-request-ready:teardown-ready|\
    change:landed:teardown-ready|research:report-ready:teardown-ready|\
    change:teardown-ready:closed|research:teardown-ready:closed)
      return 0
      ;;
    *)
      foreman_task_error "invalid lifecycle transition: $task_type $from_status -> $to_status"
      return 1
      ;;
  esac
}

foreman_task_validate_event() {
  local file=$1 task_type kind from_status from_condition to_status to_condition

  task_type=${2:-}
  foreman_task_require_json "$file" 'task event' || return 1
  case "$task_type" in
    change|research) ;;
    *) foreman_task_error "unsupported task type for event: $task_type"; return 1 ;;
  esac

  jq -e '
    def exact($allowed): type == "object" and keys == ($allowed | sort);
    def nonempty: type == "string" and length > 0;
    def timestamp: type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$");
    def lifecycle:
      exact(["condition", "status"]) and
      (.status | IN("planned", "approved", "prepared", "running", "awaiting-reconciliation", "validated", "delivery-ready", "change-request-ready", "report-ready", "landed", "teardown-ready", "closed")) and
      (.condition == null or (.condition | IN("blocked", "failed", "missing", "unreachable", "unknown")));
    exact(["actor", "at", "evidence", "event_id", "from", "kind", "message", "schema_version", "sequence", "task_id", "to"]) and
    .schema_version == 1 and
    (.event_id | type == "string" and test("^event-[0-9a-f]{12}$")) and
    (.task_id | type == "string" and test("^task-[0-9a-f]{12}$")) and
    (.sequence | type == "number" and floor == . and . >= 1) and
    (.at | timestamp) and
    (.kind | IN("lifecycle-transition", "condition-observed", "reconciliation")) and
    (.actor | IN("foreman", "agent-adapter", "runtime-adapter", "validation", "recovery")) and
    (.from | lifecycle) and (.to | lifecycle) and (.message | nonempty) and
    (.evidence | type == "array" and all(.[]; type == "string" and startswith("/")) and length == (unique | length))
  ' "$file" >/dev/null 2>&1 || {
    foreman_task_error "task event does not match src/contracts/task/event.schema.json: $file"
    return 1
  }

  kind=$(jq -r '.kind' "$file")
  from_status=$(jq -r '.from.status' "$file")
  from_condition=$(jq -r '.from.condition // "null"' "$file")
  to_status=$(jq -r '.to.status' "$file")
  to_condition=$(jq -r '.to.condition // "null"' "$file")

  case "$kind" in
    lifecycle-transition)
      [ "$from_condition" = null ] && [ "$to_condition" = null ] || {
        foreman_task_error 'a lifecycle-transition event cannot add or clear a condition'
        return 1
      }
      ;;
    condition-observed)
      [ "$from_condition" = null ] && [ "$to_condition" != null ] && [ "$from_status" = "$to_status" ] || {
        foreman_task_error 'a condition-observed event must preserve status and add one condition'
        return 1
      }
      ;;
    reconciliation)
      [ "$from_condition" != null ] && [ "$to_condition" = null ] && [ "$to_status" = awaiting-reconciliation ] || {
        foreman_task_error 'a reconciliation event must clear a condition into awaiting-reconciliation'
        return 1
      }
      ;;
  esac

  foreman_task_validate_lifecycle_transition "$task_type" "$from_status" "$from_condition" "$to_status" "$to_condition"
}

foreman_task_validate_validation_record() {
  local file=$1

  foreman_task_require_json "$file" 'validation record' || return 1
  jq -e '
    def exact($allowed): type == "object" and keys == ($allowed | sort);
    def nonempty: type == "string" and length > 0;
    def path: nonempty and startswith("/");
    def timestamp: type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$");
    def output: exact(["bytes", "path", "sha256"]) and (.path | path) and
      (.sha256 | type == "string" and test("^[0-9a-f]{64}$")) and
      (.bytes | type == "number" and floor == . and . >= 0);
    exact(["command", "evidence", "exit_status", "finished_at", "outcome", "output", "schema_version", "sequence", "started_at", "task_id", "validation_id", "working_directory"]) and
    .schema_version == 1 and
    (.validation_id | type == "string" and test("^validation-[0-9a-f]{12}$")) and
    (.task_id | type == "string" and test("^task-[0-9a-f]{12}$")) and
    (.sequence | type == "number" and floor == . and . >= 1) and
    (.command | nonempty) and (.working_directory | path) and (.started_at | timestamp) and
    (.finished_at == null or (.finished_at | timestamp)) and
    (.exit_status == null or (.exit_status | type == "number" and floor == . and . >= 0 and . <= 255)) and
    (.outcome | IN("passed", "failed", "paused", "blocked", "missing", "unreachable", "unknown")) and
    (.output == null or (.output | output)) and
    (.evidence | type == "array" and all(.[]; path) and length == (unique | length)) and
    (if .outcome == "passed" then .finished_at != null and .exit_status == 0 and .output != null
     elif .outcome == "failed" then .finished_at != null and (.exit_status | type == "number" and . > 0) and .output != null
     else .exit_status == null end)
  ' "$file" >/dev/null 2>&1 || {
    foreman_task_error "validation record does not match src/contracts/task/validation-record.schema.json: $file"
    return 1
  }
}

foreman_task_validate_result() {
  local file=$1

  foreman_task_require_json "$file" 'task result' || return 1
  jq -e '
    def exact($allowed): type == "object" and keys == ($allowed | sort);
    def nonempty: type == "string" and length > 0;
    def path: nonempty and startswith("/");
    def commit: type == "string" and test("^[0-9a-f]{40}([0-9a-f]{24})?$");
    def timestamp: type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$");
    def nullable_path: . == null or path;
    def lifecycle:
      exact(["condition", "status"]) and
      (.status | IN("awaiting-reconciliation", "validated", "delivery-ready", "change-request-ready", "report-ready", "landed")) and
      (.condition == null or (.condition | IN("blocked", "failed", "missing", "unreachable", "unknown")));
    def git:
      exact(["base_commit", "branch", "head_commit"]) and
      (.base_commit | commit) and (.head_commit | commit) and (.branch | nonempty);
    exact(["artifacts", "created_at", "git", "lifecycle", "outcome", "result_id", "schema_version", "summary", "task_id", "task_type", "validation_records"]) and
    .schema_version == 1 and
    (.result_id | type == "string" and test("^result-[0-9a-f]{12}$")) and
    (.task_id | type == "string" and test("^task-[0-9a-f]{12}$")) and
    (.created_at | timestamp) and (.task_type | IN("change", "research")) and (.lifecycle | lifecycle) and
    (.outcome | IN("handoff-ready", "change-request-ready", "landed", "report-ready", "blocked", "failed", "missing", "unreachable", "unknown")) and
    (.summary | nonempty) and (.git == null or (.git | git)) and
    (.validation_records | type == "array" and all(.[]; path) and length == (unique | length)) and
    (.artifacts | exact(["findings", "handoff", "report"]) and
      (.handoff | nullable_path) and (.report | nullable_path) and (.findings | nullable_path)) and
    (if .lifecycle.condition == null and .task_type == "change" then
      (.outcome | IN("handoff-ready", "change-request-ready", "landed")) and .git != null and .artifacts.report == null
     elif .lifecycle.condition == null and .task_type == "research" then
      .outcome == "report-ready" and .git == null and .artifacts.handoff == null and
      (.artifacts.report | path) and (.artifacts.findings | path)
     else (.outcome | IN("blocked", "failed", "missing", "unreachable", "unknown"))
     end)
  ' "$file" >/dev/null 2>&1 || {
    foreman_task_error "task result does not match src/contracts/task/result.schema.json: $file"
    return 1
  }
}

foreman_task_validate_handoff() {
  local file=$1

  foreman_task_require_json "$file" 'local handoff' || return 1
  jq -e '
    def exact($allowed): type == "object" and keys == ($allowed | sort);
    def nonempty: type == "string" and length > 0;
    def path: nonempty and startswith("/");
    def commit: type == "string" and test("^[0-9a-f]{40}([0-9a-f]{24})?$");
    def timestamp: type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$");
    def strings: type == "array" and all(.[]; nonempty) and length == (unique | length);
    exact(["base_commit", "branch", "created_at", "handoff_id", "head_commit", "instructions", "kind", "risks", "schema_version", "task_id", "validation_records"]) and
    .schema_version == 1 and
    (.handoff_id | type == "string" and test("^handoff-[0-9a-f]{12}$")) and
    (.task_id | type == "string" and test("^task-[0-9a-f]{12}$")) and (.created_at | timestamp) and
    .kind == "local-change" and (.branch | nonempty) and (.base_commit | commit) and (.head_commit | commit) and
    (.validation_records | type == "array" and all(.[]; path) and length == (unique | length)) and
    (.risks | strings) and (.instructions | strings and length > 0)
  ' "$file" >/dev/null 2>&1 || {
    foreman_task_error "local handoff does not match src/contracts/task/handoff.schema.json: $file"
    return 1
  }
}

foreman_task_validate_research_finding() {
  local file=$1

  foreman_task_require_json "$file" 'research finding' || return 1
  jq -e '
    def exact($allowed): type == "object" and keys == ($allowed | sort);
    def nonempty: type == "string" and length > 0;
    def path: nonempty and startswith("/");
    def timestamp: type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$");
    def evidence:
      exact(["description", "kind", "reference"]) and
      (.kind | IN("file", "url", "command-output")) and
      (.reference | nonempty) and (.description | nonempty);
    exact(["confidence", "created_at", "evidence", "finding_id", "report_path", "schema_version", "summary", "task_id", "title"]) and
    .schema_version == 1 and
    (.finding_id | type == "string" and test("^finding-[0-9a-f]{12}$")) and
    (.task_id | type == "string" and test("^task-[0-9a-f]{12}$")) and (.created_at | timestamp) and
    (.title | nonempty) and (.summary | nonempty) and (.confidence | IN("low", "medium", "high")) and
    (.evidence | type == "array" and length > 0 and all(.[]; evidence)) and
    (.report_path | path)
  ' "$file" >/dev/null 2>&1 || {
    foreman_task_error "research finding does not match src/contracts/task/research-finding.schema.json: $file"
    return 1
  }
}
