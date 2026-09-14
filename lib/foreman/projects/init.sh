#!/usr/bin/env bash

# shellcheck source=lib/foreman/path.sh
. "$FOREMAN_SOURCE_ROOT/lib/foreman/path.sh"
# shellcheck source=lib/foreman/state/atomic.sh
. "$FOREMAN_SOURCE_ROOT/lib/foreman/state/atomic.sh"
# shellcheck source=lib/foreman/projects/remote.sh
. "$FOREMAN_SOURCE_ROOT/lib/foreman/projects/remote.sh"
# shellcheck source=lib/foreman/configuration/validate.sh
. "$FOREMAN_SOURCE_ROOT/lib/foreman/configuration/validate.sh"
# shellcheck source=lib/foreman/adapters/registry.sh
. "$FOREMAN_SOURCE_ROOT/lib/foreman/adapters/registry.sh"
# shellcheck source=lib/foreman/text.sh
. "$FOREMAN_SOURCE_ROOT/lib/foreman/text.sh"

foreman_init_usage() {
  cat <<'EOF'
Usage: foreman init [options]

Options:
  --name NAME                 Project display name
  --project PATH              Existing Git repository root
  --agent ID                  claude, codex, gemini, opencode, or pi
  --model ID                  Provider model identifier
  --reasoning VALUE           Provider reasoning or effort value
  --runtime ID                tmux or herdr
  --worktree-root PATH        Task worktree root
  --remote NAME               Git remote to inspect
  --remote-provider ID        github or gitlab; required for supported self-hosted GitLab
  --delivery-policy POLICY    draft-handoff or automated-change-request
  --merge-authority BOOL      true or false
  --validation-command CMD    Required validation command; repeatable
  --yes                       Confirm the rendered configuration
EOF
}

foreman_init_die() {
  printf 'foreman: init: %s\n' "$*" >&2
  return 1
}

foreman_init_prompt_required() {
  local label=$1 value
  printf '%s: ' "$label" >&2
  IFS= read -r value || value=
  [ -n "$value" ] || {
    printf 'foreman: init: %s is required\n' "$label" >&2
    return 1
  }
  printf '%s\n' "$value"
}

foreman_init_slug() {
  foreman_slugify "$1" || {
    foreman_init_die 'project name does not produce a storage-safe slug'
    return 1
  }
}

foreman_init_absolute_input() {
  case "$1" in
    /*) printf '%s\n' "$1" ;;
    *) printf '%s/%s\n' "$PWD" "$1" ;;
  esac
}

foreman_init_git_common_dir() {
  local repository=$1 common
  common=$(git -C "$repository" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || {
    common=$(git -C "$repository" rev-parse --git-common-dir 2>/dev/null) || return 1
    case "$common" in
      /*) ;;
      *) common="$repository/$common" ;;
    esac
  }
  foreman_path_canonicalize "$common"
}

foreman_init_check_existing_identity() {
  local projects_root=$1 repository=$2 git_common_dir=$3 file existing_repository existing_git

  [ -d "$projects_root" ] || return 0
  for file in "$projects_root"/*/project.json; do
    [ -f "$file" ] || continue
    foreman_validate_project_configuration "$file" >/dev/null 2>&1 || continue
    existing_repository=$(jq -r '.project.repository_path' "$file")
    existing_git=$(jq -r '.project.git_common_dir' "$file")
    if [ "$existing_repository" = "$repository" ] || [ "$existing_git" = "$git_common_dir" ]; then
      printf 'foreman: init: repository is already registered by %s\n' "$file" >&2
      return 1
    fi
  done
}

foreman_init_command() {
  local name='' project_input='' agent='' model='' reasoning='' runtime='' worktree_input=''
  local remote_name='' remote_provider='' delivery_policy='' merge_authority='' yes=0
  local home projects_root global_file global_exists=0 slug repository git_top git_common_dir
  local project_root worktree_root temporary global_proposal project_proposal confirmation
  local default_profile default_runtime default_worktree_root validation_json command
  local -a validation_commands
  validation_commands=()

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --name) [ "$#" -ge 2 ] || return 64; name=$2; shift 2 ;;
      --project) [ "$#" -ge 2 ] || return 64; project_input=$2; shift 2 ;;
      --agent) [ "$#" -ge 2 ] || return 64; agent=$2; shift 2 ;;
      --model) [ "$#" -ge 2 ] || return 64; model=$2; shift 2 ;;
      --reasoning) [ "$#" -ge 2 ] || return 64; reasoning=$2; shift 2 ;;
      --runtime) [ "$#" -ge 2 ] || return 64; runtime=$2; shift 2 ;;
      --worktree-root) [ "$#" -ge 2 ] || return 64; worktree_input=$2; shift 2 ;;
      --remote) [ "$#" -ge 2 ] || return 64; remote_name=$2; shift 2 ;;
      --remote-provider) [ "$#" -ge 2 ] || return 64; remote_provider=$2; shift 2 ;;
      --delivery-policy) [ "$#" -ge 2 ] || return 64; delivery_policy=$2; shift 2 ;;
      --merge-authority) [ "$#" -ge 2 ] || return 64; merge_authority=$2; shift 2 ;;
      --validation-command)
        [ "$#" -ge 2 ] || return 64
        validation_commands+=("$2")
        shift 2
        ;;
      --yes) yes=1; shift ;;
      -h|--help) foreman_init_usage; return 0 ;;
      *)
        printf 'foreman: unknown init option: %s\n' "$1" >&2
        foreman_init_usage >&2
        return 64
        ;;
    esac
  done

  command -v git >/dev/null 2>&1 || foreman_init_die 'git is required' || return 1
  command -v jq >/dev/null 2>&1 || foreman_init_die 'jq is required' || return 1

  home=$(foreman_path_canonicalize "${FOREMAN_HOME:-$HOME/.foreman}") || return 1
  foreman_path_validate_home "$home" "$FOREMAN_SOURCE_ROOT" || return 1
  global_file="$home/config.json"

  if [ -e "$global_file" ]; then
    [ -f "$global_file" ] && [ ! -L "$global_file" ] || {
      foreman_init_die "global configuration is not a regular file: $global_file"
      return 1
    }
    foreman_validate_global_configuration "$global_file" || return 1
    global_exists=1
    projects_root=$(jq -r '.projects_root' "$global_file")
    projects_root=$(foreman_path_canonicalize "$projects_root") || return 1
    [ "$projects_root" = "$(foreman_path_canonicalize "$home/projects")" ] || {
      foreman_init_die "global projects_root must be inside FOREMAN_HOME: $home/projects"
      return 1
    }
    default_profile=$(jq -c '.defaults.worker_profile' "$global_file")
    default_runtime=$(jq -r '.defaults.runtime // empty' "$global_file")
    default_worktree_root=$(jq -r '.defaults.worktree_root // empty' "$global_file")
    [ -n "$delivery_policy" ] || delivery_policy=$(jq -r '.defaults.delivery_policy' "$global_file")
    [ -n "$merge_authority" ] || merge_authority=$(jq -r '.defaults.merge_authority' "$global_file")
  else
    projects_root=$(foreman_path_canonicalize "$home/projects") || return 1
    default_profile=null
    default_runtime=
    default_worktree_root=
    [ -n "$delivery_policy" ] || delivery_policy=draft-handoff
    [ -n "$merge_authority" ] || merge_authority=false
  fi

  [ -n "$name" ] || name=$(foreman_init_prompt_required 'Project name') || return 1
  [ -n "$project_input" ] || project_input=$(foreman_init_prompt_required 'Project folder') || return 1
  slug=$(foreman_init_slug "$name") || return 1

  project_input=$(foreman_init_absolute_input "$project_input")
  repository=$(foreman_path_canonicalize "$project_input") || return 1
  git_top=$(git -C "$repository" rev-parse --show-toplevel 2>/dev/null) || {
    foreman_init_die "project folder is not inside a Git repository: $repository"
    return 1
  }
  git_top=$(foreman_path_canonicalize "$git_top") || return 1
  [ "$repository" = "$git_top" ] || {
    foreman_init_die "project folder must be the Git repository root: $git_top"
    return 1
  }
  git_common_dir=$(foreman_init_git_common_dir "$repository") || {
    foreman_init_die 'could not resolve the Git common directory'
    return 1
  }

  if [ -z "$agent" ] && [ "$default_profile" != null ]; then
    agent=$(printf '%s' "$default_profile" | jq -r '.agent')
  fi
  if [ -z "$model" ] && [ "$default_profile" != null ]; then
    model=$(printf '%s' "$default_profile" | jq -r '.model')
  fi
  if [ -z "$reasoning" ] && [ "$default_profile" != null ]; then
    reasoning=$(printf '%s' "$default_profile" | jq -r '.reasoning')
  fi
  [ -n "$agent" ] || agent=$(foreman_init_prompt_required 'Agent adapter') || return 1
  [ -n "$model" ] || model=$(foreman_init_prompt_required 'Model') || return 1
  [ -n "$reasoning" ] || reasoning=$(foreman_init_prompt_required 'Reasoning or effort') || return 1
  [ -n "$runtime" ] || runtime=$default_runtime
  [ -n "$runtime" ] || runtime=$(foreman_init_prompt_required 'Runtime adapter') || return 1
  foreman_adapter_validate_profile "$agent" "$model" "$reasoning" || return 1
  foreman_adapter_require runtime "$runtime" >/dev/null || return 1
  foreman_adapter_require_available agent "$agent" || return 1
  foreman_adapter_require_available runtime "$runtime" || return 1

  project_root=$(foreman_path_canonicalize "$projects_root/$slug") || return 1
  if [ -n "$worktree_input" ]; then
    worktree_input=$(foreman_init_absolute_input "$worktree_input")
    worktree_root=$(foreman_path_canonicalize "$worktree_input") || return 1
  elif [ -n "$default_worktree_root" ]; then
    worktree_root=$(foreman_path_canonicalize "$default_worktree_root/$slug") || return 1
  else
    worktree_root=$(foreman_path_canonicalize "$project_root/worktrees") || return 1
  fi

  foreman_path_validate_project_layout "$home" "$repository" "$git_common_dir" "$worktree_root" || return 1
  [ ! -e "$project_root" ] || {
    foreman_init_die "project slug is already registered: $slug"
    return 1
  }
  foreman_init_check_existing_identity "$projects_root" "$repository" "$git_common_dir" || return 1
  foreman_remote_detect "$repository" "$remote_name" "$remote_provider" || return 1

  case "$delivery_policy" in
    draft-handoff|automated-change-request) ;;
    *) foreman_init_die 'unsupported delivery policy' || return 1 ;;
  esac
  case "$merge_authority" in
    true|false) ;;
    *) foreman_init_die '--merge-authority must be true or false' || return 1 ;;
  esac
  if [ "$FOREMAN_REMOTE_PROVIDER" = none ] || [ "$FOREMAN_REMOTE_PROVIDER" = unsupported ]; then
    [ "$delivery_policy" = draft-handoff ] && [ "$merge_authority" = false ] || {
      foreman_init_die 'local-only or unsupported remotes require draft-handoff with merge authority disabled'
      return 1
    }
  fi
  if [ "$merge_authority" = true ] && [ "$delivery_policy" != automated-change-request ]; then
    foreman_init_die 'merge authority requires automated-change-request delivery'
    return 1
  fi
  if [ "$delivery_policy" = automated-change-request ]; then
    foreman_adapter_require remote "$FOREMAN_REMOTE_PROVIDER" >/dev/null || return 1
    foreman_adapter_require_available remote "$FOREMAN_REMOTE_PROVIDER" || return 1
  fi

  if [ "${#validation_commands[@]}" -eq 0 ] && [ -x "$repository/scripts/check.sh" ]; then
    validation_commands+=("./scripts/check.sh")
  fi
  validation_json='[]'
  for command in "${validation_commands[@]+"${validation_commands[@]}"}"; do
    [ -n "$command" ] || {
      foreman_init_die 'validation commands must not be empty'
      return 1
    }
    validation_json=$(printf '%s' "$validation_json" | jq --arg command "$command" '. + [$command]')
  done

  temporary=$(mktemp -d '/tmp/foreman-init.XXXXXX') || return 1
  trap 'rm -rf "$temporary"' EXIT HUP INT TERM
  global_proposal="$temporary/config.json"
  project_proposal="$temporary/project.json"

  jq -n --arg projects_root "$projects_root" '{
    schema_version: 1,
    projects_root: $projects_root,
    defaults: {
      worker_profile: null,
      runtime: null,
      worktree_root: null,
      delivery_policy: "draft-handoff",
      merge_authority: false
    }
  }' >"$global_proposal"

  jq -n \
    --arg name "$name" \
    --arg slug "$slug" \
    --arg repository_path "$repository" \
    --arg git_common_dir "$git_common_dir" \
    --arg worktree_root "$worktree_root" \
    --arg remote_provider "$FOREMAN_REMOTE_PROVIDER" \
    --arg remote_name "$FOREMAN_REMOTE_NAME" \
    --arg remote_url "$FOREMAN_REMOTE_URL" \
    --arg remote_host "$FOREMAN_REMOTE_HOST" \
    --arg remote_repository "$FOREMAN_REMOTE_REPOSITORY" \
    --arg agent "$agent" \
    --arg model "$model" \
    --arg reasoning "$reasoning" \
    --arg runtime "$runtime" \
    --arg delivery_policy "$delivery_policy" \
    --argjson merge_authority "$merge_authority" \
    --argjson validation_commands "$validation_json" '{
      schema_version: 1,
      project: {
        name: $name,
        slug: $slug,
        repository_path: $repository_path,
        git_common_dir: $git_common_dir
      },
      worktree_root: $worktree_root,
      remote: {
        provider: $remote_provider,
        name: (if $remote_name == "" then null else $remote_name end),
        url: (if $remote_url == "" then null else $remote_url end),
        host: (if $remote_host == "" then null else $remote_host end),
        repository: (if $remote_repository == "" then null else $remote_repository end)
      },
      worker_profile: {
        agent: $agent,
        model: $model,
        reasoning: $reasoning
      },
      runtime: $runtime,
      delivery: {
        policy: $delivery_policy,
        merge_authority: $merge_authority
      },
      validation: {
        commands: $validation_commands,
        require_clean_worktree: true
      }
    }' >"$project_proposal"

  foreman_validate_global_configuration "$global_proposal" || return 1
  foreman_validate_project_configuration "$project_proposal" || return 1

  if [ "$global_exists" -eq 0 ]; then
    printf 'Proposed global configuration:\n'
    jq -S . "$global_proposal"
  fi
  printf 'Proposed effective project configuration:\n'
  jq -S . "$project_proposal"

  if [ "$yes" -eq 0 ]; then
    printf 'Persist this configuration? [y/N]: ' >&2
    IFS= read -r confirmation || confirmation=
    case "$confirmation" in
      y|Y|yes|YES) ;;
      *)
        printf 'Configuration was not persisted.\n'
        return 1
        ;;
    esac
  fi

  umask 077
  mkdir -p "$home" "$projects_root" "$project_root" \
    "$project_root/plans" "$project_root/state" "$project_root/tasks" "$worktree_root" || return 1
  [ "$(foreman_path_canonicalize "$home")" = "$home" ] || return 1
  [ "$(foreman_path_canonicalize "$projects_root")" = "$projects_root" ] || return 1
  [ "$(foreman_path_canonicalize "$project_root")" = "$project_root" ] || return 1
  [ "$(foreman_path_canonicalize "$worktree_root")" = "$worktree_root" ] || return 1

  if [ "$global_exists" -eq 0 ]; then
    foreman_atomic_write "$global_proposal" "$global_file" || return 1
  fi
  foreman_atomic_write "$project_proposal" "$project_root/project.json" || return 1

  trap - EXIT HUP INT TERM
  rm -rf -- "$temporary"
  printf 'Initialized project %s at %s\n' "$slug" "$project_root"
}
