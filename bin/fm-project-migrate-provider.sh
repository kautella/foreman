#!/usr/bin/env bash
# Preview or apply a reversible explicit-provider migration for data/projects.md.
# Usage: fm-project-migrate-provider.sh --dry-run|--apply
# Legacy rows remain supported. This command only adds provider= values after an
# operator reviews the dry run, and --apply saves projects.md.pre-provider-migration.
set -eu
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FM_ROOT="${FM_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
FM_HOME="${FM_HOME:-${FM_ROOT_OVERRIDE:-$FM_ROOT}}"
REG="${FM_DATA_OVERRIDE:-$FM_HOME/data}/projects.md"
mode=${1:-}
case "$mode" in --dry-run|--apply) ;; *) echo "usage: fm-project-migrate-provider.sh --dry-run|--apply" >&2; exit 1 ;; esac
[ -f "$REG" ] || { echo "error: no project registry at $REG" >&2; exit 1; }
[ ! -L "$REG" ] || { echo "error: refusing symlinked project registry" >&2; exit 1; }
out=$(mktemp "${TMPDIR:-/tmp}/fm-project-provider.XXXXXX")
trap 'rm -f "$out"' EXIT HUP INT TERM
awk '
  /^- / && / \[/ && /\]/ && $0 !~ /provider=/ {
    provider="github"
    if ($0 ~ /forge=gitlab/) provider="gitlab"
    else if ($0 ~ /forge=gerrit/) provider="gerrit"
    else if ($0 ~ /forge=forgejo/) provider="forgejo"
    else if ($0 ~ /forge=external/) provider="external"
    else if ($0 ~ /\[local-only([ ]|\])/) provider="local"
    sub(/\]/, " provider=" provider "]")
  }
  { print }
' "$REG" > "$out"
if cmp -s "$REG" "$out"; then
  echo "no legacy provider rows need migration"
  exit 0
fi
if [ "$mode" = --dry-run ]; then
  diff -u "$REG" "$out" || true
  exit 0
fi
backup="$REG.pre-provider-migration"
[ ! -e "$backup" ] || { echo "error: backup already exists at $backup; review or restore it before another migration" >&2; exit 1; }
cp "$REG" "$backup"
mv "$out" "$REG"
trap - EXIT HUP INT TERM
echo "migrated explicit providers; restore with: mv '$backup' '$REG'"
