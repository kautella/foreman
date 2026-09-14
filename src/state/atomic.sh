#!/usr/bin/env bash

foreman_atomic_write() {
  local source=$1 destination=$2 directory temporary

  [ -f "$source" ] || {
    printf 'foreman: atomic write source is missing: %s\n' "$source" >&2
    return 1
  }
  directory=${destination%/*}
  [ "$directory" != "$destination" ] || directory=.
  [ -d "$directory" ] || {
    printf 'foreman: atomic write directory is missing: %s\n' "$directory" >&2
    return 1
  }
  [ ! -L "$directory" ] || {
    printf 'foreman: refusing a symbolic-link state directory: %s\n' "$directory" >&2
    return 1
  }
  [ ! -L "$destination" ] || {
    printf 'foreman: refusing a symbolic-link state file: %s\n' "$destination" >&2
    return 1
  }

  temporary=$(mktemp "$directory/.foreman-write.XXXXXX") || return 1
  if ! cp "$source" "$temporary" || ! chmod 0600 "$temporary"; then
    rm -f -- "$temporary"
    return 1
  fi
  if ! mv -f -- "$temporary" "$destination"; then
    rm -f -- "$temporary"
    return 1
  fi
}
