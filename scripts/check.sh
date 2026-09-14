#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$repo_root"

failed=0

fail() {
  printf 'check failed: %s\n' "$*" >&2
  failed=1
}

require_file() {
  if [ ! -f "$1" ]; then
    fail "required file is missing: $1"
  fi
}

check_json_files() {
  local file

  if ! command -v jq >/dev/null 2>&1; then
    fail "jq is required to validate JSON files"
    return
  fi

  while IFS= read -r -d '' file; do
    if ! jq empty "$file" >/dev/null 2>&1; then
      fail "invalid JSON: $file"
    fi
  done < <(
    find . \
      \( -path './.git' -o -path './.idea' -o -path './provenance' \) -prune -o \
      -type f -name '*.json' -print0
  )
}

check_bash_files() {
  local file

  while IFS= read -r -d '' file; do
    if ! bash -n "$file"; then
      fail "invalid Bash syntax: $file"
    fi
  done < <(
    find . \
      \( -path './.git' -o -path './.idea' -o -path './provenance' \) -prune -o \
      -type f -name '*.sh' -print0
  )

  if [ -f '.githooks/pre-commit' ] && ! bash -n '.githooks/pre-commit'; then
    fail 'invalid Bash syntax: .githooks/pre-commit'
  fi

  if [ -f 'foreman' ] && ! bash -n 'foreman'; then
    fail 'invalid Bash syntax: foreman'
  fi
}

check_tracked_ide_metadata() {
  local path

  while IFS= read -r -d '' path; do
    case "$path" in
      .idea/*|.vscode/*|.vs/*|.fleet/*|.zed/*|*.iml|.DS_Store)
        fail "IDE or operating-system metadata is tracked: $path"
        ;;
    esac
  done < <(git ls-files -z)
}

require_file 'AGENTS.md'
require_file 'CONTRIBUTING.md'
require_file 'LICENSE'
require_file 'README.md'
require_file 'brain/README.md'
require_file 'brain/vision.md'
require_file 'brain/prd.md'
require_file 'brain/architecture.md'
require_file 'brain/upstream-map.md'
require_file 'brain/phase-1-backlog.md'
require_file 'brain/current-focus.md'
require_file 'brain/progress.md'
require_file 'scripts/install.sh'
require_file 'src/main.sh'
require_file 'src/cli.sh'
require_file 'src/contracts/README.md'
require_file 'src/adapters/README.md'

if ! "$repo_root/scripts/install.sh" >/dev/null; then
  fail 'could not generate the repository launcher'
fi

if ! git check-ignore -q -- foreman; then
  fail 'the generated repository launcher is not ignored'
fi

if git ls-files --error-unmatch foreman >/dev/null 2>&1; then
  fail 'the generated repository launcher must not be tracked'
fi

if ! git diff --check; then
  fail 'unstaged changes contain whitespace errors'
fi

if ! git diff --cached --check; then
  fail 'staged changes contain whitespace errors'
fi

check_json_files
check_bash_files
check_tracked_ide_metadata

if ! "$repo_root/scripts/check-boundaries.sh"; then
  failed=1
fi

if ! "$repo_root/scripts/test.sh"; then
  failed=1
fi

if [ "$failed" -ne 0 ]; then
  exit 1
fi

printf 'all checks passed\n'
