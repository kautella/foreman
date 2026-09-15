#!/usr/bin/env bash

FOREMAN_REMOTE_PROVIDER=none
FOREMAN_REMOTE_NAME=
FOREMAN_REMOTE_URL=
FOREMAN_REMOTE_HOST=
FOREMAN_REMOTE_REPOSITORY=

foreman_remote_provider_for_host() {
  local host=$1 manifest provider matcher matched=

  for manifest in "$FOREMAN_SOURCE_ROOT"/src/adapters/remotes/*/manifest.json; do
    [ -f "$manifest" ] || continue
    provider=$(jq -r '.id' "$manifest")
    matcher=${manifest%/manifest.json}/match-host.sh
    [ -x "$matcher" ] || continue
    if "$matcher" "$host"; then
      [ -z "$matched" ] || {
        printf 'foreman: multiple remote adapters matched host: %s\n' "$host" >&2
        return 1
      }
      matched=$provider
    fi
  done
  [ -n "$matched" ] || return 1
  printf '%s\n' "$matched"
}

foreman_remote_parse_url() {
  local url=$1 remainder authority

  FOREMAN_REMOTE_HOST=
  FOREMAN_REMOTE_REPOSITORY=

  case "$url" in
    *://*)
      remainder=${url#*://}
      authority=${remainder%%/*}
      remainder=${remainder#*/}
      FOREMAN_REMOTE_HOST=${authority##*@}
      FOREMAN_REMOTE_HOST=${FOREMAN_REMOTE_HOST%%:*}
      FOREMAN_REMOTE_REPOSITORY=$remainder
      ;;
    *@*:*)
      authority=${url%%:*}
      FOREMAN_REMOTE_HOST=${authority##*@}
      FOREMAN_REMOTE_REPOSITORY=${url#*:}
      ;;
    *) return 1 ;;
  esac

  FOREMAN_REMOTE_REPOSITORY=${FOREMAN_REMOTE_REPOSITORY#/}
  FOREMAN_REMOTE_REPOSITORY=${FOREMAN_REMOTE_REPOSITORY%.git}
  [ -n "$FOREMAN_REMOTE_HOST" ] && [ -n "$FOREMAN_REMOTE_REPOSITORY" ]
}

foreman_remote_detect() {
  local repository=$1 requested_name=${2:-} provider_override=${3:-}
  local remotes count

  FOREMAN_REMOTE_PROVIDER=none
  FOREMAN_REMOTE_NAME=
  FOREMAN_REMOTE_URL=
  FOREMAN_REMOTE_HOST=
  FOREMAN_REMOTE_REPOSITORY=

  remotes=$(git -C "$repository" remote 2>/dev/null) || remotes=
  if [ -n "$requested_name" ]; then
    printf '%s\n' "$remotes" | grep -Fxq "$requested_name" || {
      printf 'foreman: configured remote does not exist: %s\n' "$requested_name" >&2
      return 1
    }
    FOREMAN_REMOTE_NAME=$requested_name
  elif printf '%s\n' "$remotes" | grep -Fxq origin; then
    FOREMAN_REMOTE_NAME=origin
  else
    count=$(printf '%s\n' "$remotes" | sed '/^$/d' | wc -l | tr -d ' ')
    case "$count" in
      0) return 0 ;;
      1) FOREMAN_REMOTE_NAME=$(printf '%s\n' "$remotes" | sed -n '1p') ;;
      *)
        printf 'foreman: multiple Git remotes are present; select one with --remote\n' >&2
        return 1
        ;;
    esac
  fi

  FOREMAN_REMOTE_URL=$(git -C "$repository" remote get-url "$FOREMAN_REMOTE_NAME" 2>/dev/null) || {
    printf 'foreman: could not read URL for remote %s\n' "$FOREMAN_REMOTE_NAME" >&2
    return 1
  }
  if ! foreman_remote_parse_url "$FOREMAN_REMOTE_URL"; then
    FOREMAN_REMOTE_PROVIDER=unsupported
    return 0
  fi

  if [ -n "$provider_override" ]; then
    foreman_adapter_require remote "$provider_override" >/dev/null || return 1
    FOREMAN_REMOTE_PROVIDER=$provider_override
  else
    if ! FOREMAN_REMOTE_PROVIDER=$(foreman_remote_provider_for_host "$FOREMAN_REMOTE_HOST"); then
      # Consumed by the caller after this file is sourced.
      # shellcheck disable=SC2034
      FOREMAN_REMOTE_PROVIDER=unsupported
    fi
  fi
}
