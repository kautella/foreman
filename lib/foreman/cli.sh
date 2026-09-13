#!/usr/bin/env bash

# shellcheck source=lib/foreman/version.sh
. "$FOREMAN_SOURCE_ROOT/lib/foreman/version.sh"

foreman_cli_usage() {
  cat <<'EOF'
Usage: foreman <command> [options]

Commands:
  version    Print the Foreman version
  help       Show this help

Foreman is in early development. Project initialization and plan review are
added during Phase 1; worker execution is intentionally unavailable.
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
    *)
      foreman_cli_error "unknown command: $command"
      foreman_cli_usage >&2
      return 64
      ;;
  esac
}
