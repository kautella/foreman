#!/usr/bin/env bash

set -u

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
runner="$repo_root/scripts/run-in-disposable-repository.sh"
# shellcheck source=tests/support/disposable-repository.sh
. "$repo_root/tests/support/disposable-repository.sh"

test_root=$(mktemp -d '/tmp/foreman-containment-test.XXXXXX') || exit 1
fixture_repository="$test_root/source"
outside_sentinel="$test_root/outside-sentinel"
runner_pid=

cleanup_test() {
  if [ -n "${runner_pid:-}" ] && kill -0 "$runner_pid" 2>/dev/null; then
    kill -TERM "$runner_pid" 2>/dev/null || true
    wait "$runner_pid" 2>/dev/null || true
  fi
  rm -rf -- "$test_root"
}
trap cleanup_test EXIT HUP INT TERM

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

pass() {
  printf 'ok - %s\n' "$1"
}

mkdir -p "$fixture_repository"
printf 'fixture\n' >"$fixture_repository/content.txt"
git -C "$fixture_repository" init -q
git -C "$fixture_repository" add content.txt
git -C "$fixture_repository" \
  -c user.name='Foreman Tests' \
  -c user.email='tests@example.invalid' \
  commit -qm 'Create fixture'
fixture_revision=$(git -C "$fixture_repository" rev-parse HEAD)

test_normal_execution_is_isolated() {
  local output
  output=$(
    "$runner" --source "$fixture_repository" --revision "$fixture_revision" -- \
      bash -c 'test "$HOME" != "${REAL_HOME:-}" && test -f content.txt && printf "fixture-ok\\n"'
  ) || fail 'a valid disposable command failed'
  printf '%s\n' "$output" | grep -q '^FOREMAN_DISPOSABLE_BEGIN ' \
    || fail 'the runner did not announce its exact disposable identity'
  printf '%s\n' "$output" | grep -q '^fixture-ok$' \
    || fail 'the command did not run inside the disposable checkout'
  printf '%s\n' "$output" | grep -q '^FOREMAN_DISPOSABLE_END .* exit=0$' \
    || fail 'the runner did not report a successful bounded result'
  pass 'normal execution uses an exact disposable checkout'
}

test_broad_and_ambiguous_targets_are_refused() {
  if foreman_disposable_assert_owned / invalid-token >/dev/null 2>&1; then
    fail 'the ownership check accepted the filesystem root'
  fi
  if foreman_disposable_assert_owned '' invalid-token >/dev/null 2>&1; then
    fail 'the ownership check accepted an empty target'
  fi
  if "$runner" --source "$fixture_repository" --revision HEAD -- true >/dev/null 2>&1; then
    fail 'the runner accepted an ambiguous revision'
  fi
  pass 'broad targets and ambiguous revisions are refused'
}

test_marker_tampering_blocks_cleanup() {
  local root token marker saved_marker
  foreman_disposable_create || fail 'could not create a disposable root for marker testing'
  root=$FOREMAN_DISPOSABLE_ROOT
  token=$FOREMAN_DISPOSABLE_TOKEN
  marker="$root/.foreman-disposable-root"
  saved_marker="$root/control/root-marker-copy"
  cp "$marker" "$saved_marker"
  printf 'tampered\n' >"$marker"
  if foreman_disposable_cleanup "$root" "$token" >/dev/null 2>&1; then
    fail 'cleanup accepted a tampered ownership marker'
  fi
  [ -d "$root" ] || fail 'cleanup mutated a root after marker validation failed'
  cp "$saved_marker" "$marker"
  chmod 0600 "$marker"
  foreman_disposable_cleanup "$root" "$token" \
    || fail 'cleanup refused the restored exact ownership marker'
  [ ! -e "$root" ] || fail 'exactly owned root survived explicit cleanup'
  pass 'marker tampering blocks recursive cleanup'
}

test_checkout_self_deletion_stays_contained() {
  local output status
  : >"$outside_sentinel"
  set +e
  output=$(
    "$runner" --source "$fixture_repository" --revision "$fixture_revision" -- \
      bash -c 'rm -rf -- "$PWD"' 2>&1
  )
  status=$?
  set -e
  [ "$status" -ne 0 ] || fail 'the runner accepted deletion of its checkout'
  printf '%s\n' "$output" | grep -q 'the command removed its disposable checkout' \
    || fail 'checkout deletion did not produce the expected containment failure'
  [ -f "$outside_sentinel" ] || fail 'checkout deletion escaped the disposable root'
  pass 'checkout self-deletion is detected and remains contained'
}

test_interruption_cleans_exact_owned_root() {
  local output root tries status
  output="$test_root/interruption-output"
  "$runner" --source "$fixture_repository" --revision "$fixture_revision" -- \
    bash -c 'while :; do sleep 1; done' >"$output" 2>&1 &
  runner_pid=$!

  tries=0
  root=
  while [ "$tries" -lt 100 ]; do
    if [ -s "$output" ]; then
      root=$(sed -n 's/^FOREMAN_DISPOSABLE_BEGIN root=\([^ ]*\) revision=.*/\1/p' "$output")
      [ -n "$root" ] && break
    fi
    sleep 0.05
    tries=$((tries + 1))
  done
  [ -n "$root" ] || fail 'the interrupted runner did not publish its owned root'
  [ -d "$root" ] || fail 'the published disposable root did not exist before interruption'

  kill -TERM "$runner_pid"
  set +e
  wait "$runner_pid"
  status=$?
  set -e
  runner_pid=
  [ "$status" -eq 143 ] || fail "interrupted runner exited with $status instead of 143"
  [ ! -e "$root" ] || fail 'the exact owned root survived interruption cleanup'
  [ -f "$outside_sentinel" ] || fail 'interruption cleanup escaped its owned root'
  pass 'interruption cleans only the exact owned root'
}

test_normal_execution_is_isolated
test_broad_and_ambiguous_targets_are_refused
test_marker_tampering_blocks_cleanup
test_checkout_self_deletion_stays_contained
test_interruption_cleans_exact_owned_root
