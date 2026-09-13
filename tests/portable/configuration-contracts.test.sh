#!/usr/bin/env bash

set -u

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
FOREMAN_SOURCE_ROOT=$repo_root
export FOREMAN_SOURCE_ROOT
# shellcheck source=lib/foreman/configuration/validate.sh
. "$repo_root/lib/foreman/configuration/validate.sh"
# shellcheck source=tests/test-helper.sh
. "$repo_root/tests/test-helper.sh"

test_root=$(mktemp -d '/tmp/foreman-configuration-contracts.XXXXXX') || exit 1
trap 'rm -rf "$test_root"' EXIT HUP INT TERM

global_example="$repo_root/contracts/configuration/examples/global.json"
project_example="$repo_root/contracts/configuration/examples/project-local.json"

test_examples_are_valid() {
  foreman_validate_global_configuration "$global_example" \
    || test_fail 'global configuration example did not validate'
  foreman_validate_project_configuration "$project_example" \
    || test_fail 'project configuration example did not validate'
  test_pass 'configuration examples satisfy the versioned contracts'
}

test_unknown_fields_are_rejected() {
  local candidate
  candidate="$test_root/unknown-field.json"
  jq '.unexpected = true' "$project_example" >"$candidate"
  if foreman_validate_project_configuration "$candidate" >/dev/null 2>&1; then
    test_fail 'project configuration accepted an unknown field'
  fi
  test_pass 'unknown configuration fields are rejected'
}

test_local_policy_cannot_grant_remote_authority() {
  local candidate
  candidate="$test_root/local-authority.json"
  jq '.delivery.policy = "automated-change-request" | .delivery.merge_authority = true' \
    "$project_example" >"$candidate"
  if foreman_validate_project_configuration "$candidate" >/dev/null 2>&1; then
    test_fail 'local-only configuration accepted remote delivery authority'
  fi
  test_pass 'local-only configuration cannot grant remote delivery or merge authority'
}

test_worker_profile_is_required_and_closed() {
  local missing unsupported
  missing="$test_root/missing-profile.json"
  unsupported="$test_root/unsupported-agent.json"
  jq 'del(.worker_profile)' "$project_example" >"$missing"
  jq '.worker_profile.agent = "unknown"' "$project_example" >"$unsupported"
  if foreman_validate_project_configuration "$missing" >/dev/null 2>&1; then
    test_fail 'project configuration accepted a missing worker profile'
  fi
  if foreman_validate_project_configuration "$unsupported" >/dev/null 2>&1; then
    test_fail 'project configuration accepted an unsupported agent identity'
  fi
  test_pass 'worker profile is required and uses a closed agent set'
}

test_schema_documents_are_valid_json() {
  local schema
  for schema in "$repo_root"/contracts/configuration/*.schema.json; do
    jq empty "$schema" || test_fail "invalid schema JSON: $schema"
  done
  test_pass 'configuration schema documents are valid JSON'
}

test_examples_are_valid
test_unknown_fields_are_rejected
test_local_policy_cannot_grant_remote_authority
test_worker_profile_is_required_and_closed
test_schema_documents_are_valid_json
