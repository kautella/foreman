#!/usr/bin/env bash
# Create, update, inspect, or ready a provider-hosted review without selecting a
# provider from a Git remote. Usage:
#   fm-review-provider.sh gitlab open-or-update --repo <host>/<group[/subgroup]/project> --source <branch> --base <branch> --title <title> --description-file <file>
#   fm-review-provider.sh gitlab status --url <canonical-mr-url>
#   fm-review-provider.sh gitlab ready --url <canonical-mr-url>
# The GitLab adapter deliberately takes the host and complete project path from
# explicit task configuration. It sets GITLAB_HOST for each glab invocation so
# an ambient glab default cannot redirect a nested-group or self-hosted project.
set -eu

provider=${1:-}
action=${2:-}
shift 2 || true

[ "$provider" = gitlab ] || { echo "error: supported provider: gitlab" >&2; exit 1; }
command -v glab >/dev/null 2>&1 || { echo "error: GitLab delivery requires glab on PATH" >&2; exit 1; }

repo= source= base= title= description= url=
while [ $# -gt 0 ]; do
  case "$1" in
    --repo|--source|--base|--title|--description-file|--url)
      [ $# -ge 2 ] || { echo "error: $1 requires a value" >&2; exit 1; }
      case "$1" in
        --repo) repo=$2 ;; --source) source=$2 ;; --base) base=$2 ;;
        --title) title=$2 ;; --description-file) description=$2 ;; --url) url=$2 ;;
      esac
      shift 2 ;;
    *) echo "error: unknown argument: $1" >&2; exit 1 ;;
  esac
done

parse_repo() { # host/group[/subgroup]/project
  host=${repo%%/*}
  project=${repo#*/}
  [ -n "$host" ] && [ "$project" != "$repo" ] && [ -n "$project" ] || {
    echo "error: --repo must be <host>/<group[/subgroup]/project>" >&2; exit 1;
  }
}

parse_url() { # https://host/group[/subgroup]/project/-/merge_requests/n
  case "$url" in https://*/*/-/merge_requests/[0-9]*) ;; *)
    echo "error: --url must be a canonical GitLab merge-request URL" >&2; exit 1 ;;
  esac
  rest=${url#https://}
  host=${rest%%/*}
  rest=${rest#*/}
  project=${rest%/-/merge_requests/*}
  number=${rest##*/}
}

case "$action" in
  open-or-update)
    [ -n "$repo" ] && [ -n "$source" ] && [ -n "$base" ] && [ -n "$title" ] && [ -f "$description" ] || {
      echo "error: open-or-update requires --repo, --source, --base, --title, and --description-file" >&2; exit 1;
    }
    parse_repo
    existing=$(GITLAB_HOST="$host" glab mr list --repo "$project" --source-branch "$source" --output json 2>/dev/null || true)
    number=$(printf '%s' "$existing" | jq -r '.[0].iid // empty' 2>/dev/null || true)
    if [ -n "$number" ]; then
      GITLAB_HOST="$host" glab mr update "$number" --repo "$project" --title "$title" --description-file "$description" >/dev/null
    else
      GITLAB_HOST="$host" glab mr create --repo "$project" --source-branch "$source" --target-branch "$base" --title "$title" --description-file "$description" >/dev/null
      existing=$(GITLAB_HOST="$host" glab mr list --repo "$project" --source-branch "$source" --output json)
      number=$(printf '%s' "$existing" | jq -r '.[0].iid // empty')
    fi
    [ -n "$number" ] || { echo "error: GitLab did not return a merge request for $source" >&2; exit 1; }
    printf 'https://%s/%s/-/merge_requests/%s\n' "$host" "$project" "$number"
    ;;
  status)
    [ -n "$url" ] || { echo "error: status requires --url" >&2; exit 1; }
    parse_url
    json=$(GITLAB_HOST="$host" glab mr view "$number" --repo "$project" --output json)
    draft=$(printf '%s' "$json" | jq -r '.draft // false')
    printf 'draft: %s\n' "$draft"
    ;;
  ready)
    [ -n "$url" ] || { echo "error: ready requires --url" >&2; exit 1; }
    parse_url
    GITLAB_HOST="$host" glab mr update "$number" --repo "$project" --ready >/dev/null
    ;;
  *) echo "error: supported action: open-or-update, status, ready" >&2; exit 1 ;;
esac
