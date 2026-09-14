#!/usr/bin/env bash

foreman_slugify() {
  local value=$1 slug
  slug=$(printf '%s' "$value" |
    LC_ALL=C tr '[:upper:]' '[:lower:]' |
    LC_ALL=C sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')
  [ -n "$slug" ] || {
    printf 'foreman: value does not produce a storage-safe slug\n' >&2
    return 1
  }
  printf '%s\n' "$slug"
}
