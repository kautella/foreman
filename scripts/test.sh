#!/usr/bin/env bash

set -u

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
status=0
count=0

for test_file in "$repo_root"/tests/portable/*.test.sh; do
  [ -f "$test_file" ] || continue
  count=$((count + 1))
  printf 'test: %s\n' "${test_file#"$repo_root/"}"
  if ! bash "$test_file"; then
    status=1
  fi
done

if [ "$count" -eq 0 ]; then
  printf 'test: no portable tests found\n' >&2
  exit 1
fi

if [ "$status" -ne 0 ]; then
  exit "$status"
fi

printf 'test: %s portable test files passed\n' "$count"
