#!/usr/bin/env bash

set -u

repo_root="$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)"
FOREMAN_SOURCE_ROOT=$repo_root
export FOREMAN_SOURCE_ROOT
# shellcheck source=src/adapters/agents/codex/adapter.sh
. "$repo_root/src/adapters/agents/codex/adapter.sh"
# shellcheck source=tests/test-helper.sh
. "$repo_root/tests/test-helper.sh"

test_root=$(mktemp -d '/tmp/foreman-codex-adapter.XXXXXX') || exit 1
trap 'rm -rf "$test_root"' EXIT HUP INT TERM
fakebin="$test_root/fakebin"
worktree="$test_root/worktree"
state="$test_root/state"
mkdir -p "$fakebin" "$worktree" "$state"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'case "${1:-}" in' \
  '  --version)' \
  '    printf "codex-cli fake 1.0\\n"' \
  '    ;;' \
  '  login)' \
  '    [ "${2:-}" = status ] || exit 64' \
  '    if [ "${FAKE_CODEX_AUTH:-}" = yes ]; then' \
  '      printf "Logged in\\n"' \
  '      exit 0' \
  '    fi' \
  '    printf "Not logged in\\n" >&2' \
  '    exit 1' \
  '    ;;' \
  '  *)' \
  '    printf "unexpected fake codex command\\n" >&2' \
  '    exit 64' \
  '    ;;' \
  'esac' >"$fakebin/codex"
chmod +x "$fakebin/codex"
PATH="$fakebin:$PATH"
export PATH
printf 'Complete the bounded task and return the required JSON result.\n' >"$state/brief.md"

write_request() {
  local destination=$1 request_id=$2 task_type=$3 jsonl=$4 final=$5 stderr_path
  stderr_path="${jsonl%.jsonl}.stderr.log"
  jq -n \
    --arg request_id "$request_id" \
    --arg task_type "$task_type" \
    --arg jsonl "$jsonl" \
    --arg stderr_path "$stderr_path" \
    --arg final "$final" \
    --arg worktree "$worktree" \
    --arg prompt "$state/brief.md" '
      {
        schema_version: 1,
        request_id: $request_id,
        task_id: "task-0123456789ab",
        task_type: $task_type,
        worktree_path: $worktree,
        profile: {model: "gpt-5.6-terra", reasoning: "medium"},
        prompt_path: $prompt,
        jsonl_path: $jsonl,
        stderr_path: $stderr_path,
        final_output_path: $final
      }
    ' >"$destination"
}

test_diagnose_distinguishes_authenticated_and_unready_cli() {
  local authenticated unauthenticated status
  authenticated="$state/diagnose-authenticated.json"
  unauthenticated="$state/diagnose-unauthenticated.json"

  FAKE_CODEX_AUTH=yes foreman_codex_diagnose diagnose-authenticated "$authenticated" \
    || test_fail 'authenticated Codex CLI diagnosis failed'
  foreman_adapter_validate_result "$authenticated" \
    || test_fail 'authenticated diagnosis did not produce a normalized adapter result'
  jq -e '.ok == true and .status == "ok" and .data.authenticated == true and .data.version == "codex-cli fake 1.0"' \
    "$authenticated" >/dev/null || test_fail 'authenticated diagnosis data is incorrect'

  set +e
  FAKE_CODEX_AUTH=no foreman_codex_diagnose diagnose-unauthenticated "$unauthenticated" >/dev/null 2>&1
  status=$?
  set -e
  [ "$status" -ne 0 ] || test_fail 'unauthenticated Codex CLI diagnosis returned success'
  jq -e '.ok == false and .status == "unavailable" and .data.authenticated == false and .diagnostics[0].code == "authentication-not-ready"' \
    "$unauthenticated" >/dev/null || test_fail 'unauthenticated diagnosis is not actionable'
  test_pass 'Codex diagnosis distinguishes installed authenticated and unready CLI state'
}

test_launch_spec_resolves_profile_and_least_writable_sandbox() {
  local change_request change_spec research_request research_spec
  change_request="$state/change-request.json"
  change_spec="$state/change-launch.json"
  research_request="$state/research-request.json"
  research_spec="$state/research-launch.json"
  write_request "$change_request" codex-request-0123456789ab change "$state/change-events.jsonl" "$state/change-final.json"
  foreman_codex_build_launch_spec "$change_request" "$change_spec" \
    || test_fail 'change launch specification was not created'
  foreman_codex_validate_launch_spec "$change_spec" \
    || test_fail 'change launch specification did not validate'
  jq -e '
    .sandbox == "workspace-write" and
    .arguments == ["exec", "--json", "--sandbox", "workspace-write", "--cd", .worktree_path, "--model", "gpt-5.6-terra", "--config", "model_reasoning_effort=medium", "--output-schema", .output_schema_path, "--output-last-message", .final_output_path, "-"]
  ' "$change_spec" >/dev/null || test_fail 'change launch specification did not preserve exact Codex arguments'

  write_request "$research_request" codex-request-0123456789ac research "$state/research-events.jsonl" "$state/research-final.json"
  foreman_codex_build_launch_spec "$research_request" "$research_spec" \
    || test_fail 'research launch specification was not created'
  jq -e '.sandbox == "read-only"' "$research_spec" >/dev/null \
    || test_fail 'research launch specification was not read-only'
  test_pass 'Codex launch specifications persist profile and task-appropriate sandbox'
}

test_launch_spec_refuses_tampering_and_existing_output_paths() {
  local request spec tampered existing_request existing_spec
  request="$state/tamper-request.json"
  spec="$state/tamper-launch.json"
  tampered="$state/tampered-launch.json"
  existing_request="$state/existing-request.json"
  existing_spec="$state/existing-launch.json"
  write_request "$request" codex-request-0123456789ad change "$state/tamper-events.jsonl" "$state/tamper-final.json"
  foreman_codex_build_launch_spec "$request" "$spec" \
    || test_fail 'tamper fixture launch specification was not created'
  jq '.arguments[3] = "danger-full-access"' "$spec" >"$tampered"
  if foreman_codex_validate_launch_spec "$tampered" >/dev/null 2>&1; then
    test_fail 'tampered launch specification was accepted'
  fi

  touch "$state/existing-events.jsonl"
  write_request "$existing_request" codex-request-0123456789ae change "$state/existing-events.jsonl" "$state/existing-final.json"
  if foreman_codex_build_launch_spec "$existing_request" "$existing_spec" >/dev/null 2>&1; then
    test_fail 'launch specification accepted an existing JSONL output path'
  fi
  test_pass 'Codex launch specifications reject tampering and accidental output replacement'
}

test_bounded_jsonl_and_structured_final_output_are_collected() {
  local spec stream final result duplicate_final invalid_request invalid_spec invalid_stream invalid_final invalid_result status
  spec="$state/change-launch.json"
  stream=$(jq -r '.jsonl_path' "$spec")
  final=$(jq -r '.final_output_path' "$spec")
  result="$state/inspect-result.json"
  printf '%s\n%s\n' '{"type":"thread.started","thread_id":"example"}' '{"type":"turn.completed","usage":{}}' >"$stream"
  printf '%s\n' '{"status":"completed","summary":"Bounded work is complete.","changed_files":["README.md"],"risks":[]}' >"$final"
  foreman_codex_collect_result "$spec" "$result" \
    || test_fail 'valid Codex event stream and structured final output were not collected'
  foreman_adapter_validate_result "$result" \
    || test_fail 'collection did not produce a normalized adapter result'
  jq -e '.ok == true and .data.stream.records == 2 and .data.stream.terminal_event == "turn.completed" and .data.final.status == "completed"' \
    "$result" >/dev/null || test_fail 'collection result lost bounded stream or structured final evidence'

  jq -e '[.. | objects | select(has("uniqueItems"))] | length == 0' \
    "$repo_root/src/adapters/agents/codex/final-output.schema.json" >/dev/null \
    || test_fail 'Codex output schema contains an unsupported uniqueItems constraint'
  duplicate_final="$state/duplicate-final.json"
  printf '%s\n' '{"status":"completed","summary":"Duplicate paths are invalid.","changed_files":["README.md","README.md"],"risks":[]}' >"$duplicate_final"
  if foreman_codex_validate_final_output "$duplicate_final" >/dev/null 2>&1; then
    test_fail 'Foreman accepted duplicate values after removing the API-incompatible schema constraint'
  fi

  invalid_stream="$state/invalid-events.jsonl"
  invalid_final="$state/invalid-final.json"
  invalid_result="$state/invalid-inspect-result.json"
  invalid_request="$state/invalid-request.json"
  invalid_spec="$state/invalid-launch.json"
  write_request "$invalid_request" codex-request-0123456789af change "$invalid_stream" "$invalid_final"
  foreman_codex_build_launch_spec "$invalid_request" "$invalid_spec" \
    || test_fail 'invalid terminal-event launch specification was not created'
  printf '%s\n' '{"type":"turn.failed"}' >"$invalid_stream"
  printf '%s\n' '{"status":"completed","summary":"Not enough stream evidence.","changed_files":[],"risks":[]}' >"$invalid_final"
  set +e
  foreman_codex_collect_result "$invalid_spec" "$invalid_result" >/dev/null 2>&1
  status=$?
  set -e
  [ "$status" -ne 0 ] || test_fail 'missing completed terminal event was accepted'
  jq -e '.ok == false and .status == "ambiguous" and .diagnostics[0].code == "terminal-event-missing"' \
    "$invalid_result" >/dev/null || test_fail 'missing terminal event did not produce a durable ambiguity result'
  test_pass 'Codex JSONL collection is bounded and requires structured completion evidence'
}

test_diagnose_distinguishes_authenticated_and_unready_cli
test_launch_spec_resolves_profile_and_least_writable_sandbox
test_launch_spec_refuses_tampering_and_existing_output_paths
test_bounded_jsonl_and_structured_final_output_are_collected
