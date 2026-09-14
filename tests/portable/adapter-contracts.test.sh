#!/usr/bin/env bash

set -u

repo_root="$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)"
FOREMAN_SOURCE_ROOT=$repo_root
export FOREMAN_SOURCE_ROOT
# shellcheck source=lib/foreman/adapters/registry.sh
. "$repo_root/lib/foreman/adapters/registry.sh"
# shellcheck source=tests/test-helper.sh
. "$repo_root/tests/test-helper.sh"

test_root=$(mktemp -d '/tmp/foreman-adapter-contracts.XXXXXX') || exit 1
trap 'rm -rf "$test_root"' EXIT HUP INT TERM

test_manifest_inventory_is_exact_and_valid() {
  local expected actual file kind id
  expected='agent claude
agent codex
agent gemini
agent opencode
agent pi
remote github
remote gitlab
runtime herdr
runtime tmux'
  actual=$(
    find "$repo_root/adapters" -mindepth 3 -maxdepth 3 -name manifest.json -type f |
      while IFS= read -r file; do
        jq -r '[.kind, .id] | @tsv' "$file" | tr '\t' ' '
      done | LC_ALL=C sort
  )
  test_assert_equal "$actual" "$expected" 'built-in adapter inventory differs from the approved set'
  while IFS=' ' read -r kind id; do
    file=$(foreman_adapter_require "$kind" "$id") \
      || test_fail "invalid manifest for $kind adapter $id"
    [ -f "$file" ] || test_fail "resolved manifest is missing for $kind adapter $id"
  done <<EOF
$expected
EOF
  test_pass 'adapter manifest inventory is exact and valid'
}

test_unknown_identity_and_operation_fail_closed() {
  if foreman_adapter_require agent unknown >/dev/null 2>&1; then
    test_fail 'unknown agent adapter identity was accepted'
  fi
  if foreman_adapter_validate_operation runtime tmux teleport >/dev/null 2>&1; then
    test_fail 'undeclared runtime operation was accepted'
  fi
  foreman_adapter_validate_operation remote github observe-checks \
    || test_fail 'declared remote operation was rejected'
  test_pass 'unknown adapter identities and operations fail closed'
}

test_normalized_request_and_result_validate() {
  local request result
  request="$repo_root/contracts/adapter/examples/request.json"
  result="$repo_root/contracts/adapter/examples/result.json"
  foreman_adapter_validate_request "$request" \
    || test_fail 'normalized request example did not validate'
  foreman_adapter_validate_result "$result" \
    || test_fail 'normalized result example did not validate'
  test_pass 'normalized adapter request and result examples validate'
}

test_malformed_result_is_rejected() {
  local invalid
  invalid="$test_root/invalid-result.json"
  jq '.ok = false | .status = "ok" | .diagnostics = []' \
    "$repo_root/contracts/adapter/examples/result.json" >"$invalid"
  if foreman_adapter_validate_result "$invalid" >/dev/null 2>&1; then
    test_fail 'contradictory adapter result was accepted'
  fi
  test_pass 'contradictory or diagnostic-free adapter failures are rejected'
}

test_profile_contract_requires_explicit_values() {
  foreman_adapter_validate_profile codex example-model high \
    || test_fail 'complete worker profile was rejected'
  if foreman_adapter_validate_profile codex '' high >/dev/null 2>&1; then
    test_fail 'empty model was accepted'
  fi
  if foreman_adapter_validate_profile codex example-model '' >/dev/null 2>&1; then
    test_fail 'empty reasoning value was accepted'
  fi
  test_pass 'agent profile contracts require model and reasoning values'
}

test_remote_host_matching_stays_in_remote_adapters() {
  "$repo_root/adapters/remotes/github/match-host.sh" github.com \
    || test_fail 'GitHub adapter did not recognize its public host'
  if "$repo_root/adapters/remotes/github/match-host.sh" gitlab.com; then
    test_fail 'GitHub adapter recognized a GitLab host'
  fi
  "$repo_root/adapters/remotes/gitlab/match-host.sh" gitlab.com \
    || test_fail 'GitLab adapter did not recognize its public host'
  test_pass 'remote host matching remains adapter-owned'
}

test_manifest_inventory_is_exact_and_valid
test_unknown_identity_and_operation_fail_closed
test_normalized_request_and_result_validate
test_malformed_result_is_rejected
test_profile_contract_requires_explicit_values
test_remote_host_matching_stays_in_remote_adapters
