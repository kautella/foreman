#!/usr/bin/env bash

set -u

repo_root=${1:-"$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"}
failed=0

fail() {
  printf 'boundary check failed: %s\n' "$*" >&2
  failed=1
}

source_name=$(printf '%s%s' 'first' 'mate')
compat_home=$(printf '%s_%s' 'FM' 'HOME')
tree_tool=$(printf '%s%s' 'tree' 'house')
review_tool=$(printf '%s%s' 'lav' 'ish')
message_tool=$(printf '%s%s' 're' 'lay')
mistake_tool=$(printf '%s-%s' 'no' 'mistakes')
nautical_terms=$(printf '%s|%s|%s|%s|%s|%s|%s' 'captain' 'crew' 'deckhand' 'helm' 'nautical' 'shipmate' 'voyage')
prohibited_pattern="(^|[^[:alnum:]_])(${source_name}|${compat_home}|${tree_tool}|${review_tool}|${message_tool}|${mistake_tool}|${nautical_terms})([^[:alnum:]_]|$)"
provider_pattern='(^|[;&|({])[[:space:]]*(command[[:space:]]+)?(claude|codex|gemini|opencode|pi|tmux|herdr|gh|glab)([[:space:]]|$)'
external_pattern='(/Users/[^/]+/(Build|Projects)/[^[:space:]]*reference|/home/[^/]+/[^[:space:]]*reference|agentic-workflow-planning)'

scan_file() {
  local file=$1 relative=${1#"$repo_root"/}
  case "$relative" in
    scripts/check-boundaries.sh) return ;;
  esac
  if LC_ALL=C grep -Ein "$prohibited_pattern" "$file" >/dev/null 2>&1; then
    fail "prohibited source, integration, or themed terminology in $relative"
  fi
}

for directory in src docs scripts tests .githooks; do
  [ -d "$repo_root/$directory" ] || continue
  while IFS= read -r file; do
    case "$file" in
      *.sh|*.py|*.js|*.ts|*.json|*.md|*.css|*/pre-commit) scan_file "$file" ;;
    esac
  done < <(find "$repo_root/$directory" -type f -print)
done

while IFS= read -r file; do
  relative=${file#"$repo_root"/}
  case "$relative" in
    src/adapters/*|tests/*|scripts/check-boundaries.sh) continue ;;
  esac
  if LC_ALL=C grep -Ein "$provider_pattern" "$file" >/dev/null 2>&1; then
    fail "provider executable invocation outside an adapter in $relative"
  fi
done < <(find "$repo_root/src" "$repo_root/scripts" "$repo_root/.githooks" -type f -name '*.sh' -print)

while IFS= read -r file; do
  relative=${file#"$repo_root"/}
  [ "$relative" != scripts/check-boundaries.sh ] || continue
  if LC_ALL=C grep -Ein "$external_pattern" "$file" >/dev/null 2>&1; then
    fail "local external-source location is embedded in $relative"
  fi
done < <(find "$repo_root" -path "$repo_root/.git" -prune -o -type f -print)

instruction_count=0
while IFS= read -r instruction; do
  instruction_count=$((instruction_count + 1))
  [ "$instruction" = "$repo_root/AGENTS.md" ] || {
    fail "unexpected nested instruction file: ${instruction#"$repo_root"/}"
  }
done < <(find "$repo_root" -path "$repo_root/.git" -prune -o -name AGENTS.md -type f -print)
[ "$instruction_count" -eq 1 ] || fail 'the repository must contain exactly one Foreman-owned AGENTS.md'

if [ "$failed" -ne 0 ]; then
  exit 1
fi

printf 'boundary checks passed\n'
