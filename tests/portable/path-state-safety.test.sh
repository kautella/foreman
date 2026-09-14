#!/usr/bin/env bash

set -u

repo_root="$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)"
FOREMAN_SOURCE_ROOT=$repo_root
export FOREMAN_SOURCE_ROOT
# shellcheck source=src/path.sh
. "$repo_root/src/path.sh"
# shellcheck source=src/state/atomic.sh
. "$repo_root/src/state/atomic.sh"
# shellcheck source=tests/test-helper.sh
. "$repo_root/tests/test-helper.sh"

test_root=$(mktemp -d '/tmp/foreman-path-state.XXXXXX') || exit 1
trap 'rm -rf "$test_root"' EXIT HUP INT TERM

test_broad_and_ambiguous_paths_are_rejected() {
  if foreman_path_validate_home / "$repo_root" >/dev/null 2>&1; then
    test_fail 'filesystem root was accepted as FOREMAN_HOME'
  fi
  if foreman_path_canonicalize "$test_root/missing/../escape" >/dev/null 2>&1; then
    test_fail 'path with parent traversal was accepted'
  fi
  if foreman_path_canonicalize relative/path >/dev/null 2>&1; then
    test_fail 'relative path was accepted by the canonical path boundary'
  fi
  test_pass 'broad, relative, and traversal paths are rejected'
}

test_symbolic_link_state_targets_are_rejected() {
  local source target link
  source="$test_root/source.json"
  target="$test_root/target.json"
  link="$test_root/link.json"
  printf '{"value":"new"}\n' >"$source"
  printf '{"value":"original"}\n' >"$target"
  ln -s "$target" "$link"
  if foreman_atomic_write "$source" "$link" >/dev/null 2>&1; then
    test_fail 'atomic write accepted a symbolic-link destination'
  fi
  test_assert_equal "$(jq -r '.value' "$target")" original \
    'atomic write changed the symbolic-link target after refusal'
  test_pass 'atomic writes refuse symbolic-link state targets'
}

test_malformed_and_unsupported_configuration_fails_closed() {
  local home config output status
  home="$test_root/home-invalid"
  mkdir -p "$home"
  config="$home/config.json"
  printf '{not-json}\n' >"$config"
  set +e
  output=$(FOREMAN_HOME="$home" "$repo_root/foreman" doctor 2>&1)
  status=$?
  set -e
  [ "$status" -ne 0 ] || test_fail 'doctor accepted malformed global configuration'
  test_assert_contains "$output" 'schema validation failed' \
    'malformed configuration failure was not actionable'

  jq -n --arg root "$home/projects" '{
    schema_version: 2,
    projects_root: $root,
    defaults: {
      worker_profile:null,
      runtime:null,
      worktree_root:null,
      delivery_policy:"draft-handoff",
      merge_authority:false
    }
  }' >"$config"
  set +e
  output=$(FOREMAN_HOME="$home" "$repo_root/foreman" doctor 2>&1)
  status=$?
  set -e
  [ "$status" -ne 0 ] || test_fail 'doctor accepted an unsupported schema version'
  test_pass 'malformed and unsupported configuration fails closed'
}

test_broad_and_ambiguous_paths_are_rejected
test_symbolic_link_state_targets_are_rejected
test_malformed_and_unsupported_configuration_fails_closed
