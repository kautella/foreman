#!/usr/bin/env bash

# shellcheck source=src/state/atomic.sh
. "$FOREMAN_SOURCE_ROOT/src/state/atomic.sh"

foreman_lock_error() {
  printf 'foreman: lock: %s\n' "$*" >&2
}

foreman_lock_validate_path() {
  local scope=$1 lock_path=$2 parent name

  case "$scope" in
    project|task) ;;
    *) foreman_lock_error "unsupported lock scope: $scope"; return 1 ;;
  esac
  case "$lock_path" in
    /*) ;;
    *) foreman_lock_error "lock path must be absolute: $lock_path"; return 1 ;;
  esac
  case "$lock_path" in
    /|*'/../'*|*/..|*'/./'*|*/.)
      foreman_lock_error "lock path is ambiguous: $lock_path"
      return 1
      ;;
  esac
  name=${lock_path##*/}
  case "$scope:$name" in
    project:project.lock|task:task.lock) ;;
    *) foreman_lock_error "unexpected $scope lock name: $name"; return 1 ;;
  esac
  parent=${lock_path%/*}
  [ "$parent" != "$lock_path" ] || parent=/
  [ -d "$parent" ] && [ ! -L "$parent" ] || {
    foreman_lock_error "lock parent is not a safe directory: $parent"
    return 1
  }
  [ ! -L "$lock_path" ] || {
    foreman_lock_error "lock path must not be a symbolic link: $lock_path"
    return 1
  }
}

foreman_lock_validate_owner() {
  local owner_file=$1

  [ -f "$owner_file" ] && [ ! -L "$owner_file" ] || {
    foreman_lock_error "owner record is not a regular file: $owner_file"
    return 1
  }
  jq empty "$owner_file" >/dev/null 2>&1 || {
    foreman_lock_error "owner record is not valid JSON: $owner_file"
    return 1
  }
  jq -e '
    def exact($allowed): type == "object" and keys == ($allowed | sort);
    def nonempty: type == "string" and length > 0;
    def timestamp: type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$");
    exact(["acquired_at", "host", "lock_id", "pid", "project_slug", "scope", "task_id"]) and
    (.lock_id | nonempty and test("^[A-Za-z0-9][A-Za-z0-9._-]{7,}$")) and
    (.scope | IN("project", "task")) and
    (.project_slug | nonempty and test("^[a-z0-9]+(-[a-z0-9]+)*$")) and
    (.task_id == null or (.task_id | type == "string" and test("^task-[0-9a-f]{12}$"))) and
    (.host | nonempty) and (.pid | type == "number" and floor == . and . > 0) and
    (.acquired_at | timestamp) and
    (if .scope == "project" then .task_id == null else .task_id != null end)
  ' "$owner_file" >/dev/null 2>&1 || {
    foreman_lock_error "owner record has an invalid shape: $owner_file"
    return 1
  }
}

foreman_lock_validate_request() {
  local scope=$1 project_slug=$2 task_id=$3 lock_id=$4

  jq -en \
    --arg scope "$scope" \
    --arg project_slug "$project_slug" \
    --arg task_id "$task_id" \
    --arg lock_id "$lock_id" '
      ($scope | IN("project", "task")) and
      ($project_slug | test("^[a-z0-9]+(-[a-z0-9]+)*$")) and
      ($lock_id | test("^[A-Za-z0-9][A-Za-z0-9._-]{7,}$")) and
      (if $scope == "project" then $task_id == "null"
       else $task_id | test("^task-[0-9a-f]{12}$")
       end)
    ' >/dev/null 2>&1 || {
    foreman_lock_error "invalid identity for $scope lock"
    return 1
  }
}

foreman_lock_inspect() {
  local lock_path=$1 owner_file owner_host owner_pid local_host

  [ -e "$lock_path" ] || {
    printf 'missing\n'
    return 0
  }
  [ -d "$lock_path" ] && [ ! -L "$lock_path" ] || {
    printf 'unknown\n'
    return 0
  }
  owner_file="$lock_path/owner.json"
  foreman_lock_validate_owner "$owner_file" >/dev/null 2>&1 || {
    printf 'unknown\n'
    return 0
  }
  local_host=$(hostname 2>/dev/null) || {
    printf 'unknown\n'
    return 0
  }
  owner_host=$(jq -r '.host' "$owner_file")
  owner_pid=$(jq -r '.pid' "$owner_file")
  if [ "$owner_host" != "$local_host" ]; then
    printf 'unreachable\n'
  elif kill -0 "$owner_pid" >/dev/null 2>&1; then
    printf 'active\n'
  else
    printf 'stale\n'
  fi
}

foreman_lock_acquire() {
  local scope=$1 lock_path=$2 project_slug=$3 task_id=$4 lock_id=$5 owner_file temporary status

  foreman_lock_validate_path "$scope" "$lock_path" || return 1
  foreman_lock_validate_request "$scope" "$project_slug" "$task_id" "$lock_id" || return 1

  if ! mkdir -m 700 "$lock_path" 2>/dev/null; then
    status=$(foreman_lock_inspect "$lock_path") || status=unknown
    foreman_lock_error "lock already exists ($status); refusing automatic stale-lock recovery: $lock_path"
    return 1
  fi

  owner_file="$lock_path/owner.json"
  temporary=$(mktemp "$lock_path/.foreman-lock-owner.XXXXXX") || {
    foreman_lock_error "could not prepare owner record for newly acquired lock: $lock_path"
    return 1
  }
  if ! jq -n \
    --arg lock_id "$lock_id" \
    --arg scope "$scope" \
    --arg project_slug "$project_slug" \
    --arg task_id "$task_id" \
    --arg host "$(hostname)" \
    --argjson pid "$$" \
    --arg acquired_at "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" '
      {
        lock_id: $lock_id,
        scope: $scope,
        project_slug: $project_slug,
        task_id: (if $task_id == "null" then null else $task_id end),
        host: $host,
        pid: $pid,
        acquired_at: $acquired_at
      }
    ' >"$temporary" || ! foreman_atomic_write "$temporary" "$owner_file"; then
    rm -f -- "$temporary"
    foreman_lock_error "could not persist owner record; preserving ambiguous lock: $lock_path"
    return 1
  fi
  rm -f -- "$temporary"
  foreman_lock_validate_owner "$owner_file" || return 1
}

foreman_lock_assert_owned() {
  local scope=$1 lock_path=$2 project_slug=$3 task_id=$4 lock_id=$5 owner_file

  foreman_lock_validate_path "$scope" "$lock_path" || return 1
  [ -d "$lock_path" ] && [ ! -L "$lock_path" ] || {
    foreman_lock_error "lock is not a safe directory: $lock_path"
    return 1
  }
  owner_file="$lock_path/owner.json"
  foreman_lock_validate_owner "$owner_file" || return 1
  jq -e \
    --arg scope "$scope" \
    --arg project_slug "$project_slug" \
    --arg task_id "$task_id" \
    --arg lock_id "$lock_id" \
    --arg host "$(hostname)" \
    --argjson pid "$$" '
      .scope == $scope and .project_slug == $project_slug and .lock_id == $lock_id and
      .host == $host and .pid == $pid and
      (if $task_id == "null" then .task_id == null else .task_id == $task_id end)
    ' "$owner_file" >/dev/null 2>&1 || {
    foreman_lock_error "lock ownership does not match the requested operation: $lock_path"
    return 1
  }
}

foreman_lock_release() {
  local scope=$1 lock_path=$2 project_slug=$3 task_id=$4 lock_id=$5 owner_file entry

  foreman_lock_assert_owned "$scope" "$lock_path" "$project_slug" "$task_id" "$lock_id" || return 1
  owner_file="$lock_path/owner.json"
  entry=$(find "$lock_path" -mindepth 1 -maxdepth 1 ! -name owner.json -print -quit)
  [ -z "$entry" ] || {
    foreman_lock_error "lock contains unexpected state; preserving it: $lock_path"
    return 1
  }
  rm -f -- "$owner_file" || return 1
  rmdir "$lock_path" || {
    foreman_lock_error "could not remove exact owned lock; preserving remaining state: $lock_path"
    return 1
  }
}
