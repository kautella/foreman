#!/usr/bin/env bash

set -u

repo_root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
status=0
count=0

# Git exports repository-scoped variables to hooks. Portable tests create their
# own disposable repositories, so they must not inherit the invoking
# repository's index, object store, or worktree identity.
unset GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_CONFIG GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT
unset GIT_OBJECT_DIRECTORY GIT_DIR GIT_WORK_TREE GIT_IMPLICIT_WORK_TREE
unset GIT_GRAFT_FILE GIT_INDEX_FILE GIT_NO_REPLACE_OBJECTS GIT_REPLACE_REF_BASE
unset GIT_PREFIX GIT_SHALLOW_FILE GIT_COMMON_DIR

if ! "$repo_root/scripts/install.sh" >/dev/null; then
  printf 'test: could not generate the repository launcher\n' >&2
  exit 1
fi

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
