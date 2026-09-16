#!/usr/bin/env bash

# shellcheck source=src/state/lock.sh
. "$FOREMAN_SOURCE_ROOT/src/state/lock.sh"
# shellcheck source=src/tasks/validate.sh
. "$FOREMAN_SOURCE_ROOT/src/tasks/validate.sh"

foreman_events_error() {
  printf 'foreman: events: %s\n' "$*" >&2
}

foreman_events_validate_path() {
  local event_file=$1 directory name

  case "$event_file" in
    /*) ;;
    *) foreman_events_error "event file must be absolute: $event_file"; return 1 ;;
  esac
  case "$event_file" in
    /|*'/../'*|*/..|*'/./'*|*/.)
      foreman_events_error "event file path is ambiguous: $event_file"
      return 1
      ;;
  esac
  name=${event_file##*/}
  [ "$name" = events.jsonl ] || {
    foreman_events_error "unexpected event file name: $name"
    return 1
  }
  directory=${event_file%/*}
  [ "$directory" != "$event_file" ] || directory=/
  [ -d "$directory" ] && [ ! -L "$directory" ] || {
    foreman_events_error "event directory is not a safe directory: $directory"
    return 1
  }
  [ ! -L "$event_file" ] || {
    foreman_events_error "event file must not be a symbolic link: $event_file"
    return 1
  }
  [ ! -e "$event_file" ] || [ -f "$event_file" ] || {
    foreman_events_error "event path is not a regular file: $event_file"
    return 1
  }
}

foreman_events_create_if_missing() {
  local event_file=$1 directory temporary

  foreman_events_validate_path "$event_file" || return 1
  [ ! -e "$event_file" ] || return 0
  directory=${event_file%/*}
  temporary=$(mktemp "$directory/.foreman-events.XXXXXX") || return 1
  if ! chmod 0600 "$temporary" || ! ln "$temporary" "$event_file"; then
    rm -f -- "$temporary"
    foreman_events_error "could not atomically create event file: $event_file"
    return 1
  fi
  rm -f -- "$temporary"
  foreman_events_validate_path "$event_file"
}

foreman_events_validate_existing() {
  local event_file=$1 task_type=$2 task_id=$3 directory temporary line event_id event_task event_sequence last_sequence=0 seen_event_ids=''

  foreman_events_validate_path "$event_file" || return 1
  [ -e "$event_file" ] || {
    printf '0\n'
    return 0
  }
  directory=${event_file%/*}
  temporary=$(mktemp "$directory/.foreman-event-validate.XXXXXX") || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    [ -n "$line" ] || {
      rm -f -- "$temporary"
      foreman_events_error "event log contains an empty record: $event_file"
      return 1
    }
    printf '%s\n' "$line" >"$temporary" || {
      rm -f -- "$temporary"
      return 1
    }
    if ! foreman_task_validate_event "$temporary" "$task_type" >/dev/null 2>&1; then
      rm -f -- "$temporary"
      foreman_events_error "event log contains an invalid record: $event_file"
      return 1
    fi
    event_task=$(jq -r '.task_id' "$temporary")
    event_id=$(jq -r '.event_id' "$temporary")
    event_sequence=$(jq -r '.sequence' "$temporary")
    [ "$event_task" = "$task_id" ] || {
      rm -f -- "$temporary"
      foreman_events_error "event log contains another task identity: $event_file"
      return 1
    }
    [ "$event_sequence" -eq $((last_sequence + 1)) ] || {
      rm -f -- "$temporary"
      foreman_events_error "event log sequence is not contiguous: $event_file"
      return 1
    }
    case " $seen_event_ids " in
      *" $event_id "*)
        rm -f -- "$temporary"
        foreman_events_error "event log contains a duplicate event identity: $event_file"
        return 1
        ;;
    esac
    seen_event_ids="$seen_event_ids $event_id"
    last_sequence=$event_sequence
  done <"$event_file"
  rm -f -- "$temporary"
  printf '%s\n' "$last_sequence"
}

foreman_events_append() {
  local event_file=$1 source_file=$2 task_type=$3 scope=$4 lock_path=$5 project_slug=$6 task_id=$7 lock_id=$8
  local source_event_id source_task source_sequence last_sequence line line_bytes

  foreman_lock_assert_owned "$scope" "$lock_path" "$project_slug" "$task_id" "$lock_id" || return 1
  foreman_events_validate_path "$event_file" || return 1
  foreman_task_validate_event "$source_file" "$task_type" || return 1
  source_task=$(jq -r '.task_id' "$source_file")
  source_event_id=$(jq -r '.event_id' "$source_file")
  source_sequence=$(jq -r '.sequence' "$source_file")
  [ "$source_task" = "$task_id" ] || {
    foreman_events_error "event task identity does not match the owned lock: $source_file"
    return 1
  }

  foreman_events_create_if_missing "$event_file" || return 1
  last_sequence=$(foreman_events_validate_existing "$event_file" "$task_type" "$task_id") || return 1
  if jq -s -e --arg event_id "$source_event_id" 'any(.[]; .event_id == $event_id)' "$event_file" >/dev/null 2>&1; then
    foreman_events_error "event identity already exists in the durable log: $source_file"
    return 1
  fi
  [ "$source_sequence" -eq $((last_sequence + 1)) ] || {
    foreman_events_error "event sequence must follow $last_sequence exactly: $source_file"
    return 1
  }
  line=$(jq -cS . "$source_file") || return 1
  line_bytes=$(printf '%s' "$line" | wc -c | tr -d ' ')
  [ "$line_bytes" -le 8192 ] || {
    foreman_events_error "event record exceeds the 8192-byte append bound: $source_file"
    return 1
  }

  foreman_lock_assert_owned "$scope" "$lock_path" "$project_slug" "$task_id" "$lock_id" || return 1
  foreman_events_validate_path "$event_file" || return 1
  printf '%s\n' "$line" >>"$event_file" || {
    foreman_events_error "could not append event: $event_file"
    return 1
  }
}
