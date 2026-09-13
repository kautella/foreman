#!/usr/bin/env bash

test_fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

test_pass() {
  printf 'ok - %s\n' "$1"
}

test_assert_contains() {
  local value=$1 expected=$2 message=$3
  case "$value" in
    *"$expected"*) ;;
    *) test_fail "$message" ;;
  esac
}

test_assert_equal() {
  local actual=$1 expected=$2 message=$3
  [ "$actual" = "$expected" ] || {
    test_fail "$message (expected '$expected', got '$actual')"
  }
}
