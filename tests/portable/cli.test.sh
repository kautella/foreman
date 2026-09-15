#!/usr/bin/env bash

set -u

repo_root="$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)"
foreman="$repo_root/foreman"
# shellcheck source=tests/test-helper.sh
. "$repo_root/tests/test-helper.sh"

test_help_is_neutral_and_actionable() {
  local output
  output=$("$foreman" --help) || test_fail 'help command failed'
  test_assert_contains "$output" 'Usage: foreman <command> [options]' \
    'help omitted command usage'
  test_assert_contains "$output" 'Worker execution is intentionally unavailable' \
    'help did not state the current capability boundary'
  test_pass 'help describes the current neutral command surface'
}

test_version_is_stable() {
  local output
  output=$("$foreman" version) || test_fail 'version command failed'
  test_assert_equal "$output" 'foreman 0.1.0-dev' 'unexpected version output'
  test_pass 'version output is stable'
}

test_unknown_command_fails() {
  local output status
  set +e
  output=$("$foreman" unsupported 2>&1)
  status=$?
  set -e
  test_assert_equal "$status" 64 'unknown command used the wrong exit status'
  test_assert_contains "$output" 'unknown command: unsupported' \
    'unknown command failure was not actionable'
  test_pass 'unknown commands fail clearly'
}

test_help_is_neutral_and_actionable
test_version_is_stable
test_unknown_command_fails
