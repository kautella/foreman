#!/usr/bin/env bash

# shellcheck source=src/version.sh
. "$FOREMAN_SOURCE_ROOT/src/version.sh"

foreman_cli_usage() {
  cat <<'EOF'
Usage: foreman <command> [options]

Commands:
  doctor     Check core prerequisites and stored configuration
  init       Review and register a Git project
  plan       Create, review, and approve execution plans
  task       Start, inspect, and reconcile local task state
  version    Print the Foreman version
  help       Show this help

Task execution is implemented for the Phase 2 local-only path but remains
unverified against live Codex CLI and tmux environments.
EOF
}

foreman_cli_error() {
  printf 'foreman: %s\n' "$*" >&2
}

foreman_cli_main() {
  local command=${1:-help}

  case "$command" in
    help|-h|--help)
      foreman_cli_usage
      ;;
    version|-V|--version)
      printf 'foreman %s\n' "$FOREMAN_VERSION"
      ;;
    doctor)
      shift
      # shellcheck source=src/doctor.sh
      . "$FOREMAN_SOURCE_ROOT/src/doctor.sh"
      foreman_doctor_command "$@"
      ;;
    init)
      shift
      # shellcheck source=src/projects/init.sh
      . "$FOREMAN_SOURCE_ROOT/src/projects/init.sh"
      foreman_init_command "$@"
      ;;
    plan)
      shift
      # shellcheck source=src/plans/command.sh
      . "$FOREMAN_SOURCE_ROOT/src/plans/command.sh"
      foreman_plan_command "$@"
      ;;
    task)
      shift
      # shellcheck source=src/tasks/command.sh
      . "$FOREMAN_SOURCE_ROOT/src/tasks/command.sh"
      foreman_task_command "$@"
      ;;
    *)
      foreman_cli_error "unknown command: $command"
      foreman_cli_usage >&2
      return 64
      ;;
  esac
}
