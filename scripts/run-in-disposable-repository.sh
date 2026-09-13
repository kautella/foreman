#!/usr/bin/env bash

set -u

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
# shellcheck source=tests/support/disposable-repository.sh
. "$repo_root/tests/support/disposable-repository.sh"

source_repository=
revision=

usage() {
  cat >&2 <<'EOF'
Usage: run-in-disposable-repository.sh --source PATH --revision COMMIT -- COMMAND [ARG...]

Clone an exact local Git revision into an owned temporary root, isolate common
home and temporary paths, run one command, verify that the control directory
survived, and remove only the exact marked root.
EOF
}

die() {
  printf 'run-in-disposable-repository: %s\n' "$*" >&2
  exit 2
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --source)
      [ "$#" -ge 2 ] || die '--source requires a path'
      source_repository=$2
      shift 2
      ;;
    --revision)
      [ "$#" -ge 2 ] || die '--revision requires a full commit identifier'
      revision=$2
      shift 2
      ;;
    --)
      shift
      break
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *) die "unknown argument: $1" ;;
  esac
done

[ -n "$source_repository" ] || die '--source is required'
[ -n "$revision" ] || die '--revision is required'
[ "$#" -gt 0 ] || die 'a command is required after --'

case "$revision" in
  *[!0-9a-f]*|'') die '--revision must be a full lowercase hexadecimal commit identifier' ;;
esac
[ "${#revision}" -eq 40 ] || die '--revision must contain exactly 40 hexadecimal characters'

source_repository=$(foreman_disposable_canonical_directory "$source_repository") \
  || die 'source must be an existing, unambiguous directory'
git -C "$source_repository" rev-parse --git-dir >/dev/null 2>&1 \
  || die 'source must be a Git repository'
resolved_revision=$(git -C "$source_repository" rev-parse --verify "$revision^{commit}" 2>/dev/null) \
  || die 'revision does not identify a commit in the source repository'
[ "$resolved_revision" = "$revision" ] || die 'revision did not resolve to the exact requested commit'

cleanup_and_exit() {
  local code=$1
  trap - EXIT HUP INT TERM
  foreman_disposable_stop_child TERM
  if [ -n "${FOREMAN_DISPOSABLE_ROOT:-}" ]; then
    foreman_disposable_cleanup || {
      foreman_disposable_error "cleanup refused; preserving evidence at $FOREMAN_DISPOSABLE_ROOT"
      exit 1
    }
  fi
  exit "$code"
}

trap 'cleanup_and_exit $?' EXIT
trap 'cleanup_and_exit 129' HUP
trap 'cleanup_and_exit 130' INT
trap 'cleanup_and_exit 143' TERM

foreman_disposable_create || die 'could not create a validated disposable root'
checkout="$FOREMAN_DISPOSABLE_ROOT/checkout"

git clone --quiet --no-hardlinks "$source_repository" "$checkout" \
  || die 'could not clone the source repository into the disposable root'
git -C "$checkout" checkout --quiet --detach "$revision" \
  || die 'could not check out the requested revision'
actual_revision=$(git -C "$checkout" rev-parse HEAD 2>/dev/null) \
  || die 'could not verify the disposable checkout identity'
[ "$actual_revision" = "$revision" ] || die 'disposable checkout identity differs from the requested revision'

printf 'FOREMAN_DISPOSABLE_BEGIN root=%s revision=%s\n' \
  "$FOREMAN_DISPOSABLE_ROOT" "$revision"

(
  cd "$checkout" || exit 1
  env -i \
    HOME="$FOREMAN_DISPOSABLE_ROOT/home" \
    TMPDIR="$FOREMAN_DISPOSABLE_ROOT/tmp" \
    TMP="$FOREMAN_DISPOSABLE_ROOT/tmp" \
    XDG_CONFIG_HOME="$FOREMAN_DISPOSABLE_ROOT/home/.config" \
    XDG_CACHE_HOME="$FOREMAN_DISPOSABLE_ROOT/home/.cache" \
    PATH="$PATH" \
    LC_ALL=C \
    "$@"
) &
FOREMAN_DISPOSABLE_CHILD_PID=$!
wait "$FOREMAN_DISPOSABLE_CHILD_PID"
command_status=$?
FOREMAN_DISPOSABLE_CHILD_PID=

foreman_disposable_control_survived \
  || die 'the command damaged the disposable control boundary'
[ -d "$checkout" ] || die 'the command removed its disposable checkout'

printf 'FOREMAN_DISPOSABLE_END revision=%s exit=%s\n' "$revision" "$command_status"
cleanup_and_exit "$command_status"
