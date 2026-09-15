#!/usr/bin/env bash

foreman_adapter_error() {
  printf 'foreman: adapter: %s\n' "$*" >&2
}

foreman_adapter_manifest_file() {
  local kind=$1 id=$2 collection
  case "$kind" in
    agent) collection=agents ;;
    runtime) collection=runtimes ;;
    remote) collection=remotes ;;
    *)
      foreman_adapter_error "unknown adapter kind: $kind"
      return 1
      ;;
  esac
  case "$id" in
    ''|*[!a-z0-9-]*|-*|*-)
      foreman_adapter_error "invalid $kind adapter identity: $id"
      return 1
      ;;
  esac
  printf '%s/src/adapters/%s/%s/manifest.json\n' "$FOREMAN_SOURCE_ROOT" "$collection" "$id"
}

foreman_adapter_validate_manifest() {
  local file=$1 expected_kind=${2:-} expected_id=${3:-}

  [ -f "$file" ] && [ ! -L "$file" ] || {
    foreman_adapter_error "manifest is missing or unsafe: $file"
    return 1
  }
  jq -e --arg kind "$expected_kind" --arg id "$expected_id" '
    def exact_keys($allowed):
      type == "object" and ((keys - $allowed) | length == 0);
    def nonempty: type == "string" and length > 0;
    def slug: nonempty and test("^[a-z][a-z0-9-]*$");
    exact_keys(["capabilities", "contract_version", "display_name", "executable", "id", "kind", "operations", "profile", "status"]) and
    .contract_version == 1 and
    (.kind | IN("agent", "runtime", "remote")) and
    ($kind == "" or .kind == $kind) and
    (.id | slug) and
    ($id == "" or .id == $id) and
    (.display_name | nonempty) and
    (.executable | nonempty and test("^[a-zA-Z0-9._+-]+$")) and
    .status == "contract-only" and
    (.operations | type == "array" and length > 0) and
    (all(.operations[]; slug)) and
    ((.operations | unique | length) == (.operations | length)) and
    (.capabilities | type == "object" and all(.[]; type == "boolean")) and
    (if .kind == "agent" then
      (.profile |
        exact_keys(["model_required", "reasoning_required", "validation"]) and
        (.model_required | type == "boolean") and
        (.reasoning_required | type == "boolean") and
        .validation == "provider-adapter")
    else
      .profile == null
    end)
  ' "$file" >/dev/null 2>&1 || {
    foreman_adapter_error "manifest validation failed: $file"
    return 1
  }
}

foreman_adapter_require() {
  local kind=$1 id=$2 file
  file=$(foreman_adapter_manifest_file "$kind" "$id") || return 1
  foreman_adapter_validate_manifest "$file" "$kind" "$id" || return 1
  printf '%s\n' "$file"
}

foreman_adapter_validate_operation() {
  local kind=$1 id=$2 operation=$3 file
  file=$(foreman_adapter_require "$kind" "$id") || return 1
  jq -e --arg operation "$operation" '.operations | index($operation) != null' \
    "$file" >/dev/null 2>&1 || {
    foreman_adapter_error "$kind adapter '$id' does not declare operation '$operation'"
    return 1
  }
}

foreman_adapter_executable() {
  local kind=$1 id=$2 file
  file=$(foreman_adapter_require "$kind" "$id") || return 1
  jq -r '.executable' "$file"
}

foreman_adapter_require_available() {
  local kind=$1 id=$2 executable
  executable=$(foreman_adapter_executable "$kind" "$id") || return 1
  command -v "$executable" >/dev/null 2>&1 || {
    foreman_adapter_error "$kind adapter '$id' requires executable '$executable', but it was not found"
    return 1
  }
}

foreman_adapter_validate_profile() {
  local id=$1 model=$2 reasoning=$3 file
  file=$(foreman_adapter_require agent "$id") || return 1
  [ -n "$model" ] || {
    foreman_adapter_error "agent adapter '$id' requires a model"
    return 1
  }
  [ -n "$reasoning" ] || {
    foreman_adapter_error "agent adapter '$id' requires a reasoning or effort value"
    return 1
  }
  jq -e '.capabilities.model_selection == true and .capabilities.reasoning_selection == true' \
    "$file" >/dev/null 2>&1 || {
    foreman_adapter_error "agent adapter '$id' cannot accept the configured worker profile"
    return 1
  }
}

foreman_adapter_validate_request() {
  local file=$1 kind id operation
  jq -e '
    def exact_keys($allowed): type == "object" and ((keys - $allowed) | length == 0);
    def nonempty: type == "string" and length > 0;
    exact_keys(["adapter", "contract_version", "operation", "payload", "request_id"]) and
    .contract_version == 1 and
    (.request_id | nonempty and test("^[a-zA-Z0-9][a-zA-Z0-9._-]*$")) and
    (.adapter | exact_keys(["id", "kind"])) and
    (.adapter.kind | IN("agent", "runtime", "remote")) and
    (.adapter.id | nonempty) and
    (.operation | nonempty) and
    (.payload | type == "object")
  ' "$file" >/dev/null 2>&1 || {
    foreman_adapter_error "request validation failed: $file"
    return 1
  }
  kind=$(jq -r '.adapter.kind' "$file")
  id=$(jq -r '.adapter.id' "$file")
  operation=$(jq -r '.operation' "$file")
  foreman_adapter_validate_operation "$kind" "$id" "$operation"
}

foreman_adapter_validate_result() {
  local file=$1 kind id operation
  jq -e '
    def exact_keys($allowed): type == "object" and ((keys - $allowed) | length == 0);
    def nonempty: type == "string" and length > 0;
    def diagnostic:
      exact_keys(["code", "message", "retryable"]) and
      (.code | nonempty) and (.message | nonempty) and (.retryable | type == "boolean");
    exact_keys(["adapter", "contract_version", "data", "diagnostics", "ok", "operation", "request_id", "status"]) and
    .contract_version == 1 and
    (.request_id | nonempty) and
    (.adapter | exact_keys(["id", "kind"])) and
    (.adapter.kind | IN("agent", "runtime", "remote")) and
    (.adapter.id | nonempty) and
    (.operation | nonempty) and
    (.ok | type == "boolean") and
    (.status | IN("ok", "error", "unavailable", "unsupported", "ambiguous")) and
    (.data | type == "object") and
    (.diagnostics | type == "array" and all(.[]; diagnostic)) and
    (if .ok then .status == "ok" else (.status != "ok" and (.diagnostics | length > 0)) end)
  ' "$file" >/dev/null 2>&1 || {
    foreman_adapter_error "result validation failed: $file"
    return 1
  }
  kind=$(jq -r '.adapter.kind' "$file")
  id=$(jq -r '.adapter.id' "$file")
  operation=$(jq -r '.operation' "$file")
  foreman_adapter_validate_operation "$kind" "$id" "$operation"
}
