#!/usr/bin/env bash
# Gemini CLI primary lifecycle hook.
#
# Installed from the user's Gemini settings, this hook first proves that the
# payload's cwd is this Firstmate home.  BeforeAgent takes the session-start
# path.  AfterAgent parks on one verified watcher cycle and uses Gemini's
# exit-2 retry turn to deliver a wake.  SessionEnd is a harmless allow.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FM_ROOT="${FM_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
FM_HOME="${FM_HOME:-${FM_ROOT_OVERRIDE:-$FM_ROOT}}"
STATE="${FM_STATE_OVERRIDE:-$FM_HOME/state}"
CONFIG="${FM_CONFIG_OVERRIDE:-$FM_HOME/config}"
MODE=${1:-}

allow() { printf '{"decision":"allow"}\n'; exit 0; }

case "$MODE" in before|after|session-end) ;; *) allow ;; esac
PAYLOAD=$(cat 2>/dev/null || true)

# Gemini requires JSON on stdout even when a hook merely stands down.
command -v jq >/dev/null 2>&1 || allow
printf '%s' "$PAYLOAD" | jq -e 'type == "object"' >/dev/null 2>&1 || allow

# A user-level Gemini hook runs for every project.  Never infer its target from
# this script's location alone: only an exact, physical cwd match authorizes
# Firstmate behavior for this home.
PAYLOAD_CWD=$(printf '%s' "$PAYLOAD" | jq -r 'if (.cwd | type) == "string" then .cwd else empty end' 2>/dev/null || true)
ROOT_REAL=$(cd -P "$FM_ROOT" 2>/dev/null && pwd -P || true)
CWD_REAL=$(cd -P "$PAYLOAD_CWD" 2>/dev/null && pwd -P || true)
[ -n "$ROOT_REAL" ] && [ "$CWD_REAL" = "$ROOT_REAL" ] || allow

# shellcheck source=bin/fm-primary-scope-lib.sh
. "$SCRIPT_DIR/fm-primary-scope-lib.sh"
fm_primary_scope_matches "$FM_ROOT" "$STATE" || allow

case "$MODE" in
  before)
    # Gemini has no session-open hook that reliably injects the startup digest.
    # BeforeAgent is the earliest verified primary boundary, but later prompts
    # in the same Gemini session must not repeat the full startup digest.
    # shellcheck source=bin/fm-session-lock-lib.sh
    . "$SCRIPT_DIR/fm-session-lock-lib.sh"
    context=''
    lock_pid=$(cat "$STATE/.lock" 2>/dev/null || true)
    complete_pid=$(cat "$STATE/.session-start-complete" 2>/dev/null || true)
    if ! fm_session_lock_owned_by_self "$STATE" || [ -z "$lock_pid" ] || [ "$lock_pid" != "$complete_pid" ]; then
      context=$("$SCRIPT_DIR/fm-sessionstart-run.sh" --source startup 2>&1 || true)
    fi
    if [ -n "$context" ]; then
      jq -cn --arg context "$context" '{decision:"allow",additionalContext:$context}'
    else
      printf '{"decision":"allow"}\n'
    fi
    exit 0
    ;;
  session-end)
    allow
    ;;
esac

# AfterAgent only parks a normal completed turn.  Gemini retries the hook after
# an exit-2 wake with stop_hook_active=true; that follow-up is the handling turn
# and must be allowed to finish rather than immediately re-parking it.
active=$(printf '%s' "$PAYLOAD" | jq -r 'if (.stop_hook_active // false) | type == "boolean" then (.stop_hook_active // false) else false end' 2>/dev/null || printf false)
[ "$active" = true ] && allow

# shellcheck source=bin/fm-supervision-lib.sh
. "$SCRIPT_DIR/fm-supervision-lib.sh"
# shellcheck source=bin/fm-session-lock-lib.sh
. "$SCRIPT_DIR/fm-session-lock-lib.sh"

GRACE=${FM_GUARD_GRACE:-300}
fm_supervision_needed "$STATE" "$GRACE" || allow

if ! fm_session_lock_owned_by_self "$STATE"; then
  "$SCRIPT_DIR/fm-lock.sh" >/dev/null 2>&1 || allow
  fm_session_lock_owned_by_self "$STATE" || allow
fi

[ -e "$STATE/.afk" ] && allow

out=$(mktemp "$STATE/.gemini-primary-watch.XXXXXX") || allow
trap 'rm -f "$out"' EXIT
"$SCRIPT_DIR/fm-watch-arm.sh" >"$out" 2>&1
rc=$?

if grep -Eq '^(signal:|stale:|check:|heartbeat($|:))' "$out"; then
  wake=$(grep -E '^(signal:|stale:|check:|heartbeat)' "$out" | head -8)
  printf '{"decision":"allow"}\n'
  printf '%s\n' 'firstmate watcher wake - handle this notification now.' >&2
  printf '%s\n' "$wake" >&2
  printf '%s\n' 'Run bin/fm-wake-drain.sh first, handle the result, then run its printed acknowledgement command. The next normal turn end resumes watcher supervision automatically.' >&2
  exit 2
fi

if [ "$rc" -ne 0 ]; then
  printf '{"decision":"allow"}\n'
  printf '%s\n' 'Firstmate supervision could not be started. Inspect the watcher startup result before ending another turn.' >&2
  sed -n '1,8p' "$out" >&2
  exit 2
fi
allow
