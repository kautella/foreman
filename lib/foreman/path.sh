#!/usr/bin/env bash

foreman_path_error() {
  printf 'foreman: unsafe path: %s\n' "$*" >&2
}

foreman_path_canonicalize() {
  local requested=$1 cursor suffix component physical

  case "$requested" in
    /*) ;;
    *)
      foreman_path_error "path must be absolute: $requested"
      return 1
      ;;
  esac
  case "$requested" in
    *$'\n'*|*$'\r'*|*$'\t'*)
      foreman_path_error 'path contains a control character'
      return 1
      ;;
  esac
  case "$requested" in
    */../*|*/..|*/./*|*/.)
      foreman_path_error "path contains an ambiguous component: $requested"
      return 1
      ;;
  esac

  while [ "$requested" != / ] && [ "${requested%/}" != "$requested" ]; do
    requested=${requested%/}
  done

  if [ -L "$requested" ]; then
    foreman_path_error "path must not be a symbolic link: $requested"
    return 1
  fi
  if [ -e "$requested" ]; then
    [ -d "$requested" ] || {
      foreman_path_error "path is not a directory: $requested"
      return 1
    }
    (CDPATH='' cd -P -- "$requested" 2>/dev/null && pwd -P) || {
      foreman_path_error "path cannot be resolved: $requested"
      return 1
    }
    return
  fi

  cursor=$requested
  suffix=
  while [ ! -e "$cursor" ]; do
    component=${cursor##*/}
    [ -n "$component" ] || {
      foreman_path_error "path has no existing ancestor: $requested"
      return 1
    }
    suffix="/$component$suffix"
    cursor=${cursor%/*}
    [ -n "$cursor" ] || cursor=/
  done
  [ -d "$cursor" ] || {
    foreman_path_error "path ancestor is not a directory: $cursor"
    return 1
  }
  physical=$(CDPATH='' cd -P -- "$cursor" 2>/dev/null && pwd -P) || {
    foreman_path_error "path ancestor cannot be resolved: $cursor"
    return 1
  }
  if [ "$physical" = / ]; then
    printf '/%s\n' "${suffix#/}"
  else
    printf '%s%s\n' "$physical" "$suffix"
  fi
}

foreman_path_is_within() {
  local candidate=$1 parent=$2
  [ "$candidate" = "$parent" ] && return 0
  case "$candidate" in
    "$parent"/*) return 0 ;;
  esac
  return 1
}

foreman_path_require_separate() {
  local first=$1 first_label=$2 second=$3 second_label=$4
  if foreman_path_is_within "$first" "$second" || foreman_path_is_within "$second" "$first"; then
    foreman_path_error "$first_label and $second_label must not overlap ($first, $second)"
    return 1
  fi
}

foreman_path_validate_home() {
  local home=$1 source_root=$2
  [ "$home" != / ] || {
    foreman_path_error 'FOREMAN_HOME must not be the filesystem root'
    return 1
  }
  foreman_path_require_separate "$home" 'FOREMAN_HOME' "$source_root" 'Foreman source root'
}

foreman_path_validate_project_layout() {
  local home=$1 project=$2 git_common_dir=$3 worktree_root=$4

  foreman_path_require_separate "$home" 'FOREMAN_HOME' "$project" 'project repository' || return 1
  foreman_path_require_separate "$worktree_root" 'worktree root' "$project" 'project repository' || return 1
  if foreman_path_is_within "$worktree_root" "$git_common_dir" || \
    foreman_path_is_within "$git_common_dir" "$worktree_root"; then
    foreman_path_error "worktree root and Git common directory must not overlap ($worktree_root, $git_common_dir)"
    return 1
  fi
}
