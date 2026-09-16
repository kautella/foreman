#!/usr/bin/env bash

# shellcheck source=src/path.sh
. "$FOREMAN_SOURCE_ROOT/src/path.sh"
# shellcheck source=src/state/lock.sh
. "$FOREMAN_SOURCE_ROOT/src/state/lock.sh"

foreman_worktree_error() {
  printf 'foreman: worktree: %s\n' "$*" >&2
}

foreman_worktree_validate_request() {
  local task_type=$1 project_slug=$2 task_id=$3 branch=$4 base_commit=$5

  jq -en \
    --arg task_type "$task_type" \
    --arg project_slug "$project_slug" \
    --arg task_id "$task_id" \
    --arg branch "$branch" \
    --arg base_commit "$base_commit" '
      ($task_type | IN("change", "research")) and
      ($project_slug | test("^[a-z0-9]+(-[a-z0-9]+)*$")) and
      ($task_id | test("^task-[0-9a-f]{12}$")) and
      ($base_commit | test("^[0-9a-f]{40}([0-9a-f]{24})?$")) and
      (if $task_type == "change" then $branch != "null" and ($branch | length > 0)
       else $branch == "null"
       end)
    ' >/dev/null 2>&1 || {
    foreman_worktree_error 'task type, identity, branch, or base commit is invalid'
    return 1
  }
}

foreman_worktree_canonical_git_path() {
  local repository=$1 value=$2 requested

  case "$value" in
    /*) requested=$value ;;
    *) requested="$repository/$value" ;;
  esac
  foreman_path_canonicalize "$requested"
}

foreman_worktree_validate_marker() {
  local marker_file=$1

  [ -f "$marker_file" ] && [ ! -L "$marker_file" ] || {
    foreman_worktree_error "worktree marker is not a regular file: $marker_file"
    return 1
  }
  jq empty "$marker_file" >/dev/null 2>&1 || {
    foreman_worktree_error "worktree marker is not valid JSON: $marker_file"
    return 1
  }
  jq -e '
    def exact($allowed): type == "object" and keys == ($allowed | sort);
    def nonempty: type == "string" and length > 0;
    def path: nonempty and startswith("/");
    def commit: type == "string" and test("^[0-9a-f]{40}([0-9a-f]{24})?$");
    def timestamp: type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$");
    exact(["base_commit", "branch", "created_at", "git_common_dir", "git_dir", "project_slug", "repository_path", "schema_version", "task_id", "task_type", "worktree_path"]) and
    .schema_version == 1 and
    (.task_id | type == "string" and test("^task-[0-9a-f]{12}$")) and
    (.project_slug | type == "string" and test("^[a-z0-9]+(-[a-z0-9]+)*$")) and
    (.task_type | IN("change", "research")) and
    (.repository_path | path) and (.git_common_dir | path) and (.worktree_path | path) and (.git_dir | path) and
    (.base_commit | commit) and (.branch == null or (.branch | nonempty)) and (.created_at | timestamp) and
    (if .task_type == "change" then .branch != null else .branch == null end)
  ' "$marker_file" >/dev/null 2>&1 || {
    foreman_worktree_error "worktree marker does not match src/contracts/task/worktree-marker.schema.json: $marker_file"
    return 1
  }
}

foreman_worktree_validate_marker_path() {
  local marker_file=$1 repository=$2 worktree_root=$3 marker_path directory

  case "$marker_file" in
    /*) ;;
    *) foreman_worktree_error "marker path must be absolute: $marker_file"; return 1 ;;
  esac
  marker_path=$(foreman_path_canonicalize "$marker_file") || return 1
  [ "${marker_path##*/}" = worktree.json ] || {
    foreman_worktree_error "unexpected worktree marker name: ${marker_path##*/}"
    return 1
  }
  directory=${marker_path%/*}
  [ -d "$directory" ] && [ ! -L "$directory" ] || {
    foreman_worktree_error "marker directory is not a safe directory: $directory"
    return 1
  }
  [ ! -e "$marker_path" ] && [ ! -L "$marker_path" ] || {
    foreman_worktree_error "worktree marker already exists and will not be adopted: $marker_path"
    return 1
  }
  foreman_path_require_separate "$marker_path" 'worktree marker' "$repository" 'project repository' || return 1
  foreman_path_require_separate "$marker_path" 'worktree marker' "$worktree_root" 'worktree root' || return 1
  printf '%s\n' "$marker_path"
}

foreman_worktree_validate_repository() {
  local repository=$1 root common_raw common top_raw top status

  root=$(foreman_path_canonicalize "$repository") || return 1
  [ -d "$root" ] || {
    foreman_worktree_error "repository is not a directory: $root"
    return 1
  }
  [ "$(git -C "$root" rev-parse --is-inside-work-tree 2>/dev/null)" = true ] || {
    foreman_worktree_error "repository is not a Git worktree: $root"
    return 1
  }
  top_raw=$(git -C "$root" rev-parse --show-toplevel 2>/dev/null) || return 1
  top=$(foreman_path_canonicalize "$top_raw") || return 1
  [ "$root" = "$top" ] || {
    foreman_worktree_error "repository must be its Git worktree root: $root"
    return 1
  }
  common_raw=$(git -C "$root" rev-parse --git-common-dir 2>/dev/null) || return 1
  common=$(foreman_worktree_canonical_git_path "$root" "$common_raw") || return 1
  status=$(git -C "$root" status --porcelain=v1 --untracked-files=all) || return 1
  [ -z "$status" ] || {
    foreman_worktree_error "repository is dirty and cannot allocate a task worktree: $root"
    return 1
  }
  printf '%s\t%s\n' "$root" "$common"
}

foreman_worktree_validate_root() {
  local repository=$1 git_common_dir=$2 worktree_root=$3 root

  root=$(foreman_path_canonicalize "$worktree_root") || return 1
  [ -d "$root" ] || {
    foreman_worktree_error "worktree root is not a directory: $root"
    return 1
  }
  foreman_path_require_separate "$root" 'worktree root' "$repository" 'project repository' || return 1
  foreman_path_require_separate "$root" 'worktree root' "$git_common_dir" 'Git common directory' || return 1
  printf '%s\n' "$root"
}

foreman_worktree_validate_target() {
  local repository=$1 worktree_root=$2 task_id=$3 target registered canonical_registered

  target=$(foreman_path_canonicalize "$worktree_root/$task_id") || return 1
  foreman_path_is_within "$target" "$worktree_root" && [ "$target" != "$worktree_root" ] || {
    foreman_worktree_error "task worktree target is not contained by its configured root: $target"
    return 1
  }
  [ ! -e "$target" ] && [ ! -L "$target" ] || {
    foreman_worktree_error "task worktree target already exists and will not be adopted: $target"
    return 1
  }
  while IFS= read -r registered; do
    [ -n "$registered" ] || continue
    canonical_registered=$(foreman_path_canonicalize "$registered") || return 1
    if foreman_path_is_within "$target" "$canonical_registered" || \
      foreman_path_is_within "$canonical_registered" "$target" || \
      foreman_path_is_within "$worktree_root" "$canonical_registered"; then
      foreman_worktree_error "task worktree target or root overlaps a registered Git worktree: $canonical_registered"
      return 1
    fi
  done <<EOF
$(git -C "$repository" worktree list --porcelain | sed -n 's/^worktree //p')
EOF
  printf '%s\n' "$target"
}

foreman_worktree_validate_branch_and_base() {
  local task_type=$1 repository=$2 branch=$3 base_commit=$4 resolved normalized

  resolved=$(git -C "$repository" rev-parse --verify "${base_commit}^{commit}" 2>/dev/null) || {
    foreman_worktree_error "base commit is unavailable in repository: $base_commit"
    return 1
  }
  [ "$resolved" = "$base_commit" ] || {
    foreman_worktree_error "base commit must be an exact full Git identity: $base_commit"
    return 1
  }
  [ "$task_type" = change ] || return 0
  normalized=$(git check-ref-format --branch "$branch" 2>/dev/null) || {
    foreman_worktree_error "task branch name is invalid: $branch"
    return 1
  }
  [ "$normalized" = "$branch" ] || {
    foreman_worktree_error "task branch name is not canonical: $branch"
    return 1
  }
  if git -C "$repository" show-ref --verify --quiet "refs/heads/$branch"; then
    foreman_worktree_error "task branch already exists and will not be adopted: $branch"
    return 1
  fi
}

foreman_worktree_write_marker() {
  local marker_file=$1 task_type=$2 task_id=$3 project_slug=$4 repository=$5 git_common_dir=$6 worktree_path=$7 git_dir=$8 base_commit=$9 branch=${10}
  local marker_directory temporary

  marker_directory=${marker_file%/*}
  temporary=$(mktemp "$marker_directory/.foreman-worktree-marker.XXXXXX") || return 1
  if ! jq -n \
    --arg task_type "$task_type" \
    --arg task_id "$task_id" \
    --arg project_slug "$project_slug" \
    --arg repository_path "$repository" \
    --arg git_common_dir "$git_common_dir" \
    --arg worktree_path "$worktree_path" \
    --arg git_dir "$git_dir" \
    --arg base_commit "$base_commit" \
    --arg branch "$branch" \
    --arg created_at "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" '
      {
        schema_version: 1,
        task_id: $task_id,
        project_slug: $project_slug,
        task_type: $task_type,
        repository_path: $repository_path,
        git_common_dir: $git_common_dir,
        worktree_path: $worktree_path,
        git_dir: $git_dir,
        base_commit: $base_commit,
        branch: (if $branch == "null" then null else $branch end),
        created_at: $created_at
      }
    ' >"$temporary" || ! foreman_atomic_write "$temporary" "$marker_file"; then
    rm -f -- "$temporary"
    foreman_worktree_error "could not persist worktree marker; preserving task worktree: $worktree_path"
    return 1
  fi
  rm -f -- "$temporary"
  foreman_worktree_validate_marker "$marker_file"
}

foreman_worktree_allocate() {
  local task_type=$1 repository_input=$2 worktree_root_input=$3 project_slug=$4 task_id=$5 branch=$6 base_commit=$7 marker_input=$8 project_lock=$9 lock_id=${10}
  local repository_details repository git_common_dir worktree_root marker_file target target_head target_branch target_top target_common_raw target_common target_git_raw target_git

  foreman_worktree_validate_request "$task_type" "$project_slug" "$task_id" "$branch" "$base_commit" || return 1
  foreman_lock_assert_owned project "$project_lock" "$project_slug" null "$lock_id" || return 1
  repository_details=$(foreman_worktree_validate_repository "$repository_input") || return 1
  repository=${repository_details%%$'\t'*}
  git_common_dir=${repository_details#*$'\t'}
  worktree_root=$(foreman_worktree_validate_root "$repository" "$git_common_dir" "$worktree_root_input") || return 1
  marker_file=$(foreman_worktree_validate_marker_path "$marker_input" "$repository" "$worktree_root") || return 1
  target=$(foreman_worktree_validate_target "$repository" "$worktree_root" "$task_id") || return 1
  foreman_worktree_validate_branch_and_base "$task_type" "$repository" "$branch" "$base_commit" || return 1

  foreman_lock_assert_owned project "$project_lock" "$project_slug" null "$lock_id" || return 1
  if [ "$task_type" = change ]; then
    git -C "$repository" worktree add -b "$branch" "$target" "$base_commit" >/dev/null 2>&1 || {
      foreman_worktree_error "Git could not create task worktree: $target"
      return 1
    }
  else
    git -C "$repository" worktree add --detach "$target" "$base_commit" >/dev/null 2>&1 || {
      foreman_worktree_error "Git could not create detached research worktree: $target"
      return 1
    }
  fi

  target_top=$(git -C "$target" rev-parse --show-toplevel 2>/dev/null) || return 1
  target_top=$(foreman_path_canonicalize "$target_top") || return 1
  [ "$target_top" = "$target" ] || {
    foreman_worktree_error "new task worktree has an unexpected root; preserving it: $target"
    return 1
  }
  target_head=$(git -C "$target" rev-parse HEAD 2>/dev/null) || return 1
  [ "$target_head" = "$base_commit" ] || {
    foreman_worktree_error "new task worktree has an unexpected base; preserving it: $target"
    return 1
  }
  target_common_raw=$(git -C "$target" rev-parse --git-common-dir 2>/dev/null) || return 1
  target_common=$(foreman_worktree_canonical_git_path "$target" "$target_common_raw") || return 1
  [ "$target_common" = "$git_common_dir" ] || {
    foreman_worktree_error "new task worktree has an unexpected Git common directory; preserving it: $target"
    return 1
  }
  target_git_raw=$(git -C "$target" rev-parse --git-dir 2>/dev/null) || return 1
  target_git=$(foreman_worktree_canonical_git_path "$target" "$target_git_raw") || return 1
  if [ "$task_type" = change ]; then
    target_branch=$(git -C "$target" symbolic-ref --quiet --short HEAD 2>/dev/null) || {
      foreman_worktree_error "new change worktree is detached; preserving it: $target"
      return 1
    }
    [ "$target_branch" = "$branch" ] || {
      foreman_worktree_error "new change worktree has an unexpected branch; preserving it: $target"
      return 1
    }
  elif git -C "$target" symbolic-ref --quiet HEAD >/dev/null 2>&1; then
    foreman_worktree_error "new research worktree is not detached; preserving it: $target"
    return 1
  fi
  [ -z "$(git -C "$target" status --porcelain=v1 --untracked-files=all)" ] || {
    foreman_worktree_error "new task worktree is unexpectedly dirty; preserving it: $target"
    return 1
  }
  foreman_worktree_write_marker "$marker_file" "$task_type" "$task_id" "$project_slug" "$repository" "$git_common_dir" "$target" "$target_git" "$base_commit" "$branch" || return 1
  printf '%s\n' "$target"
}
