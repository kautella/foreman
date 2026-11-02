#!/usr/bin/env bash
# Behavior tests for Gemini CLI primary hook wiring.
set -u

. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMP_ROOT=$(fm_test_tmproot fm-gemini-primary)

make_home() {
  local home=$1
  mkdir -p "$home/bin" "$home/state"
  cp "$ROOT/bin/fm-gemini-primary-hook.sh" "$ROOT/bin/fm-primary-scope-lib.sh" "$home/bin/"
  chmod +x "$home/bin/"*.sh
  git init -q "$home"
  git -C "$home" commit -q --allow-empty -m init
  : > "$home/AGENTS.md"
}

test_hook_stands_down_outside_firstmate() {
  local home="$TMP_ROOT/outside" out status
  make_home "$home"
  out=$(printf '%s' '{"cwd":"/not/firstmate","stop_hook_active":false}' | FM_HOME="$home" "$home/bin/fm-gemini-primary-hook.sh" after 2>&1)
  status=$?
  expect_code 0 "$status" "Gemini hook outside Firstmate should be allowed"
  [ "$out" = '{"decision":"allow"}' ] || fail "outside hook did not emit Gemini allow JSON: $out"
  pass "Gemini primary hook stands down outside Firstmate"
}

test_after_hook_allows_a_retry_turn() {
  local home="$TMP_ROOT/retry" out status
  make_home "$home"
  out=$(printf '{"cwd":"%s","stop_hook_active":true}' "$home" | FM_HOME="$home" "$home/bin/fm-gemini-primary-hook.sh" after 2>&1)
  status=$?
  expect_code 0 "$status" "Gemini retry turn should be allowed"
  [ "$out" = '{"decision":"allow"}' ] || fail "retry turn did not emit Gemini allow JSON: $out"
  pass "Gemini primary hook allows the bounded retry turn"
}

test_hook_stands_down_outside_firstmate
test_after_hook_allows_a_retry_turn
