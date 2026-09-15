#!/usr/bin/env bash

set -eu

FOREMAN_SOURCE_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
export FOREMAN_SOURCE_ROOT

# shellcheck source=src/cli.sh
. "$FOREMAN_SOURCE_ROOT/src/cli.sh"

foreman_cli_main "$@"
