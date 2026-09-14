#!/usr/bin/env bash

# shellcheck source=lib/foreman/path.sh
. "$FOREMAN_SOURCE_ROOT/lib/foreman/path.sh"
# shellcheck source=lib/foreman/configuration/validate.sh
. "$FOREMAN_SOURCE_ROOT/lib/foreman/configuration/validate.sh"
# shellcheck source=lib/foreman/adapters/registry.sh
. "$FOREMAN_SOURCE_ROOT/lib/foreman/adapters/registry.sh"

foreman_doctor_check_command() {
  local command=$1
  if command -v "$command" >/dev/null 2>&1; then
    printf 'ok    %s is available\n' "$command"
    return 0
  fi
  printf 'error %s is required but was not found\n' "$command" >&2
  return 1
}

foreman_doctor_command() {
  local home requested_project='' status=0 global project_file projects_root expected_projects_root
  local repository stored_repository git_common_dir stored_git_common_dir worktree_root stored_worktree_root stored_slug
  local agent runtime delivery_policy remote_provider

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --project)
        [ "$#" -ge 2 ] || {
          printf 'foreman: doctor --project requires a project slug\n' >&2
          return 64
        }
        requested_project=$2
        shift 2
        ;;
      *)
        printf 'foreman: unknown doctor option: %s\n' "$1" >&2
        return 64
        ;;
    esac
  done

  foreman_doctor_check_command bash || status=1
  foreman_doctor_check_command git || status=1
  foreman_doctor_check_command jq || status=1

  home=$(foreman_path_canonicalize "${FOREMAN_HOME:-$HOME/.foreman}") || return 1
  foreman_path_validate_home "$home" "$FOREMAN_SOURCE_ROOT" || return 1
  global="$home/config.json"

  if [ -f "$global" ]; then
    if foreman_validate_global_configuration "$global"; then
      projects_root=$(jq -r '.projects_root' "$global")
      projects_root=$(foreman_path_canonicalize "$projects_root") || return 1
      expected_projects_root=$(foreman_path_canonicalize "$home/projects") || return 1
      if [ "$projects_root" = "$expected_projects_root" ]; then
        printf 'ok    global configuration is valid\n'
      else
        printf 'foreman: global projects_root must be inside FOREMAN_HOME: %s\n' \
          "$expected_projects_root" >&2
        status=1
      fi
    else
      status=1
    fi
  else
    printf 'info  Foreman is not initialized at %s\n' "$home"
  fi

  if [ -n "$requested_project" ]; then
    case "$requested_project" in
      ''|*[!a-z0-9-]*|-*|*-)
        printf 'foreman: invalid project slug: %s\n' "$requested_project" >&2
        return 1
        ;;
    esac
    [ -f "$global" ] || {
      printf 'error project diagnostics require an initialized Foreman home\n' >&2
      return 1
    }
    project_file="$home/projects/$requested_project/project.json"
    [ -f "$project_file" ] && [ ! -L "$project_file" ] || {
      printf 'foreman: project configuration is missing or unsafe: %s\n' "$project_file" >&2
      status=1
      return "$status"
    }
    if ! foreman_validate_project_configuration "$project_file"; then
      status=1
      return "$status"
    fi

    stored_slug=$(jq -r '.project.slug' "$project_file")
    stored_repository=$(jq -r '.project.repository_path' "$project_file")
    stored_git_common_dir=$(jq -r '.project.git_common_dir' "$project_file")
    stored_worktree_root=$(jq -r '.worktree_root' "$project_file")
    repository=$(foreman_path_canonicalize "$stored_repository") || return 1
    git_common_dir=$(foreman_path_canonicalize "$stored_git_common_dir") || return 1
    worktree_root=$(foreman_path_canonicalize "$stored_worktree_root") || return 1
    if [ "$stored_slug" != "$requested_project" ] || \
      [ "$repository" != "$stored_repository" ] || \
      [ "$git_common_dir" != "$stored_git_common_dir" ] || \
      [ "$worktree_root" != "$stored_worktree_root" ]; then
      printf 'foreman: project configuration contains non-canonical or mismatched identity\n' >&2
      status=1
    elif [ "$(git -C "$repository" rev-parse --show-toplevel 2>/dev/null || true)" != "$repository" ]; then
      printf 'foreman: configured project repository identity is no longer valid\n' >&2
      status=1
    elif ! foreman_path_validate_project_layout \
      "$home" "$repository" "$git_common_dir" "$worktree_root"; then
      status=1
    else
      printf 'ok    project configuration and identity are valid: %s\n' "$requested_project"
    fi

    agent=$(jq -r '.worker_profile.agent' "$project_file")
    runtime=$(jq -r '.runtime' "$project_file")
    delivery_policy=$(jq -r '.delivery.policy' "$project_file")
    remote_provider=$(jq -r '.remote.provider' "$project_file")
    if foreman_adapter_require_available agent "$agent"; then
      printf 'ok    configured agent adapter is available: %s\n' "$agent"
    else
      status=1
    fi
    if foreman_adapter_require_available runtime "$runtime"; then
      printf 'ok    configured runtime adapter is available: %s\n' "$runtime"
    else
      status=1
    fi
    if [ "$delivery_policy" = automated-change-request ]; then
      if foreman_adapter_require_available remote "$remote_provider"; then
        printf 'ok    configured remote adapter is available: %s\n' "$remote_provider"
      else
        status=1
      fi
    fi
  fi

  return "$status"
}
