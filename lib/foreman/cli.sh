#!/usr/bin/env bash

# shellcheck source=lib/foreman/version.sh
. "$FOREMAN_SOURCE_ROOT/lib/foreman/version.sh"

foreman_cli_usage() {
  cat <<'EOF'
Usage: foreman <command> [options]

Commands:
  doctor     Check core prerequisites and stored configuration
  init       Review and register a Git project
  plan       Create, review, and approve execution plans
  version    Print the Foreman version
  help       Show this help

Worker execution is intentionally unavailable in Phase 1.
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
      # shellcheck source=lib/foreman/doctor.sh
      . "$FOREMAN_SOURCE_ROOT/lib/foreman/doctor.sh"
      foreman_doctor_command "$@"
      ;;
    init)
      shift
      # shellcheck source=lib/foreman/projects/init.sh
      . "$FOREMAN_SOURCE_ROOT/lib/foreman/projects/init.sh"
      foreman_init_command "$@"
      ;;
    plan)
      shift
      # shellcheck source=lib/foreman/plans/command.sh
      . "$FOREMAN_SOURCE_ROOT/lib/foreman/plans/command.sh"
      foreman_plan_command "$@"
      ;;
    *)
      foreman_cli_error "unknown command: $command"
      foreman_cli_usage >&2
      return 64
      ;;
  esac
}
