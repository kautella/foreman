#!/usr/bin/env bash

# Shared containment primitives for tests that must execute untrusted or
# inherited repository tooling. This is a safety boundary for development
# tests, not an operating-system sandbox.

FOREMAN_DISPOSABLE_FORMAT=1
FOREMAN_DISPOSABLE_ROOT=
FOREMAN_DISPOSABLE_TOKEN=
FOREMAN_DISPOSABLE_CHILD_PID=

foreman_disposable_error() {
  printf 'disposable repository: %s\n' "$*" >&2
}

foreman_disposable_canonical_directory() {
  [ "$#" -eq 1 ] || return 1
  [ -d "$1" ] || return 1
  (CDPATH= cd -P -- "$1" 2>/dev/null && pwd -P)
}

foreman_disposable_path_is_safe() {
  local candidate=$1 canonical parent base

  [ -n "$candidate" ] || return 1
  [ -d "$candidate" ] || return 1
  [ ! -L "$candidate" ] || return 1

  canonical=$(foreman_disposable_canonical_directory "$candidate") || return 1
  [ "$canonical" = "$candidate" ] || return 1

  base=${canonical##*/}
  parent=${canonical%/*}
  case "$base" in
    foreman-disposable.*) ;;
    *) return 1 ;;
  esac

  case "$parent" in
    /tmp|/private/tmp) ;;
    *) return 1 ;;
  esac

  [ "$canonical" != / ] || return 1
  if [ -n "${HOME:-}" ]; then
    [ "$canonical" != "$HOME" ] || return 1
  fi
}

foreman_disposable_marker_text() {
  local root=$1 token=$2
  printf 'format=%s\nroot=%s\ntoken=%s\nowner_pid=%s\n' \
    "$FOREMAN_DISPOSABLE_FORMAT" "$root" "$token" "$$"
}

foreman_disposable_write_markers() {
  local root=$1 token=$2 marker control_marker
  marker="$root/.foreman-disposable-root"
  control_marker="$root/control/.foreman-disposable-control"

  foreman_disposable_marker_text "$root" "$token" >"$marker" || return 1
  foreman_disposable_marker_text "$root" "$token" >"$control_marker" || return 1
  chmod 0600 "$marker" "$control_marker" || return 1
}

foreman_disposable_marker_matches() {
  local root=$1 token=$2 marker=$3 actual expected

  [ -f "$marker" ] || return 1
  [ ! -L "$marker" ] || return 1
  actual=$(sed -n '1,4p' "$marker") || return 1
  expected=$(foreman_disposable_marker_text "$root" "$token") || return 1
  [ "$actual" = "$expected" ]
}

foreman_disposable_assert_owned() {
  local root=${1:-${FOREMAN_DISPOSABLE_ROOT:-}}
  local token=${2:-${FOREMAN_DISPOSABLE_TOKEN:-}}

  [ -n "$root" ] || {
    foreman_disposable_error 'refusing an empty cleanup target'
    return 1
  }
  [ -n "$token" ] || {
    foreman_disposable_error 'refusing cleanup without an ownership token'
    return 1
  }
  foreman_disposable_path_is_safe "$root" || {
    foreman_disposable_error "refusing unsafe cleanup target: $root"
    return 1
  }
  foreman_disposable_marker_matches \
    "$root" "$token" "$root/.foreman-disposable-root" || {
    foreman_disposable_error "root ownership marker does not match: $root"
    return 1
  }
  foreman_disposable_marker_matches \
    "$root" "$token" "$root/control/.foreman-disposable-control" || {
    foreman_disposable_error "control marker does not match: $root"
    return 1
  }
}

foreman_disposable_create() {
  local root token

  [ -z "${FOREMAN_DISPOSABLE_ROOT:-}" ] || {
    foreman_disposable_error 'a disposable root is already active'
    return 1
  }

  root=$(mktemp -d '/tmp/foreman-disposable.XXXXXX') || return 1
  root=$(foreman_disposable_canonical_directory "$root") || return 1
  chmod 0700 "$root" || return 1

  token="$$-$(date +%s)-${RANDOM:-0}-${RANDOM:-0}"
  mkdir -p "$root/control" "$root/home" "$root/tmp" || return 1
  chmod 0700 "$root/control" "$root/home" "$root/tmp" || return 1

  FOREMAN_DISPOSABLE_ROOT=$root
  FOREMAN_DISPOSABLE_TOKEN=$token
  export FOREMAN_DISPOSABLE_ROOT FOREMAN_DISPOSABLE_TOKEN

  if ! foreman_disposable_write_markers "$root" "$token"; then
    foreman_disposable_error "could not write ownership markers under $root"
    return 1
  fi
  foreman_disposable_assert_owned "$root" "$token"
}

foreman_disposable_control_survived() {
  foreman_disposable_assert_owned \
    "${FOREMAN_DISPOSABLE_ROOT:-}" "${FOREMAN_DISPOSABLE_TOKEN:-}"
}

foreman_disposable_cleanup() {
  local root=${1:-${FOREMAN_DISPOSABLE_ROOT:-}}
  local token=${2:-${FOREMAN_DISPOSABLE_TOKEN:-}}

  foreman_disposable_assert_owned "$root" "$token" || return 1
  rm -rf -- "$root" || return 1

  if [ "$root" = "${FOREMAN_DISPOSABLE_ROOT:-}" ]; then
    FOREMAN_DISPOSABLE_ROOT=
    FOREMAN_DISPOSABLE_TOKEN=
    export FOREMAN_DISPOSABLE_ROOT FOREMAN_DISPOSABLE_TOKEN
  fi
}

foreman_disposable_stop_child() {
  local signal=${1:-TERM}

  case "${FOREMAN_DISPOSABLE_CHILD_PID:-}" in
    ''|*[!0-9]*) return 0 ;;
  esac
  if kill -0 "$FOREMAN_DISPOSABLE_CHILD_PID" 2>/dev/null; then
    kill -"$signal" "$FOREMAN_DISPOSABLE_CHILD_PID" 2>/dev/null || true
    wait "$FOREMAN_DISPOSABLE_CHILD_PID" 2>/dev/null || true
  fi
  FOREMAN_DISPOSABLE_CHILD_PID=
}
