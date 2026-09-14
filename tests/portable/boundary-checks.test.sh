#!/usr/bin/env bash

set -u

repo_root="$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)"
checker="$repo_root/scripts/check-boundaries.sh"
# shellcheck source=tests/test-helper.sh
. "$repo_root/tests/test-helper.sh"

test_root=$(mktemp -d '/tmp/foreman-boundaries.XXXXXX') || exit 1
trap 'rm -rf "$test_root"' EXIT HUP INT TERM

make_fixture() {
  local root=$1
  mkdir -p "$root/src/adapters" "$root/tests" "$root/docs" "$root/scripts" \
    "$root/.githooks"
  printf '# Project instructions\n' >"$root/AGENTS.md"
  printf '#!/usr/bin/env bash\nprintf "safe\\n"\n' >"$root/src/core.sh"
}

assert_rejected() {
  local root=$1 expected=$2 output status
  set +e
  output=$(bash "$checker" "$root" 2>&1)
  status=$?
  set -e
  [ "$status" -ne 0 ] || test_fail "boundary checker accepted $expected"
  test_assert_contains "$output" "$expected" "boundary refusal did not identify $expected"
}

test_clean_active_tree_passes() {
  local root="$test_root/clean"
  make_fixture "$root"
  bash "$checker" "$root" >/dev/null || test_fail 'clean active tree failed boundary checks'
  test_pass 'clean active tree passes boundary checks'
}

test_prohibited_terms_and_compatibility_are_rejected() {
  local root="$test_root/terms"
  make_fixture "$root"
  printf 'Legacy %s%s behavior\n' 'FIRST' 'MATE' >"$root/docs/legacy.md"
  assert_rejected "$root" 'prohibited source, integration, or themed terminology'
  test_pass 'prohibited terminology is rejected from active surfaces'
}

test_direct_provider_invocation_is_rejected() {
  local root="$test_root/provider"
  make_fixture "$root"
  printf '#!/usr/bin/env bash\ncodex exec task\n' >"$root/src/core.sh"
  assert_rejected "$root" 'provider executable invocation outside an adapter'
  test_pass 'direct provider invocation is rejected outside adapters'
}

test_local_reference_paths_and_nested_instructions_are_rejected() {
  local root="$test_root/reference"
  make_fixture "$root"
  printf '/Users/example/%s/tool-reference\n' 'Build' >"$root/docs/location.md"
  mkdir -p "$root/src/nested"
  printf '# Unexpected\n' >"$root/src/nested/AGENTS.md"
  assert_rejected "$root" 'local external-source location'
  assert_rejected "$root" 'unexpected nested instruction file'
  test_pass 'local reference paths and nested instructions are rejected'
}

test_clean_active_tree_passes
test_prohibited_terms_and_compatibility_are_rejected
test_direct_provider_invocation_is_rejected
test_local_reference_paths_and_nested_instructions_are_rejected
