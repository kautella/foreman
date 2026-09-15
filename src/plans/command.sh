#!/usr/bin/env bash

# shellcheck source=src/path.sh
. "$FOREMAN_SOURCE_ROOT/src/path.sh"
# shellcheck source=src/state/atomic.sh
. "$FOREMAN_SOURCE_ROOT/src/state/atomic.sh"
# shellcheck source=src/configuration/validate.sh
. "$FOREMAN_SOURCE_ROOT/src/configuration/validate.sh"
# shellcheck source=src/plans/validate.sh
. "$FOREMAN_SOURCE_ROOT/src/plans/validate.sh"
# shellcheck source=src/artifacts/plan.sh
. "$FOREMAN_SOURCE_ROOT/src/artifacts/plan.sh"
# shellcheck source=src/text.sh
. "$FOREMAN_SOURCE_ROOT/src/text.sh"

foreman_plan_usage() {
  cat <<'EOF'
Usage: foreman plan <command> [options]

Commands:
  template                         Show the recommended plan input template
  create --project SLUG --file FILE
                                   Create a proposal from direct JSON input
  handover --project SLUG --file FILE
                                   Create a proposal from an external handover
  guided --project SLUG            Draft a one-task proposal interactively
  review --project SLUG --plan ID  Rebuild a proposal's HTML review
  approve --project SLUG --plan ID [--approved-by NAME] [--yes]
                                   Explicitly approve a complete proposal

Plan review never launches workers, creates task worktrees, or mutates the
managed repository or its remote.
EOF
}

foreman_plan_load_project() {
  local project_slug=$1 home global_file projects_root project_root project_file

  case "$project_slug" in
    ''|*[!a-z0-9-]*|-*|*-) foreman_plan_error 'project must be a registered project slug'; return 1 ;;
  esac
  home=$(foreman_path_canonicalize "${FOREMAN_HOME:-$HOME/.foreman}") || return 1
  global_file="$home/config.json"
  foreman_validate_global_configuration "$global_file" || return 1
  projects_root=$(jq -r '.projects_root' "$global_file")
  projects_root=$(foreman_path_canonicalize "$projects_root") || return 1
  [ "$projects_root" = "$(foreman_path_canonicalize "$home/projects")" ] || {
    foreman_plan_error "configured projects root is outside FOREMAN_HOME: $projects_root"
    return 1
  }
  project_root=$(foreman_path_canonicalize "$projects_root/$project_slug") || return 1
  project_file="$project_root/project.json"
  foreman_validate_project_configuration "$project_file" || return 1
  [ "$(jq -r '.project.slug' "$project_file")" = "$project_slug" ] || {
    foreman_plan_error 'requested project does not match its stored identity'
    return 1
  }
  [ -d "$project_root/plans" ] && [ ! -L "$project_root/plans" ] || {
    foreman_plan_error "project plan storage is unavailable: $project_root/plans"
    return 1
  }

  FOREMAN_PLAN_PROJECT_ROOT=$project_root
  FOREMAN_PLAN_PROJECT_FILE=$project_file
  export FOREMAN_PLAN_PROJECT_ROOT FOREMAN_PLAN_PROJECT_FILE
}

foreman_plan_require_policy() {
  local input_file=$1 policy
  policy=$(jq -r '.delivery.policy' "$FOREMAN_PLAN_PROJECT_FILE")
  if jq -e 'any(.tasks[]; .delivery_expectation == "automated-change-request")' "$input_file" >/dev/null && \
    [ "$policy" != automated-change-request ]; then
    foreman_plan_error 'a task requests automated remote delivery, but the registered project policy does not allow it'
    return 1
  fi
}

foreman_plan_store() {
  local project_slug=$1 input_file=$2 source_json=$3 temporary payload plan_id plan_slug
  local candidate plans_root destination staging review_file

  foreman_plan_validate_input "$input_file" || return 1
  foreman_plan_require_policy "$input_file" || return 1
  temporary=$(mktemp -d '/tmp/foreman-plan.XXXXXX') || return 1
  payload="$temporary/payload.json"
  candidate="$temporary/plan.json"

  jq -cS -n \
    --arg project_slug "$project_slug" \
    --argjson source "$source_json" \
    --slurpfile input "$input_file" \
    '{project_slug: $project_slug, source: $source, plan: $input[0]}' >"$payload" || {
      rm -rf -- "$temporary"
      return 1
    }
  plan_id="plan-$(git hash-object "$payload" | cut -c1-12)" || {
    rm -rf -- "$temporary"
    return 1
  }
  plan_slug=$(foreman_slugify "$(jq -r '.title' "$input_file")") || {
    rm -rf -- "$temporary"
    return 1
  }
  plan_slug=$(printf '%s' "$plan_slug" | cut -c1-80 | sed -E 's/-+$//')

  jq -S \
    --arg plan_id "$plan_id" \
    --arg slug "$plan_slug" \
    --arg project_slug "$project_slug" \
    --argjson source "$source_json" \
    '. + {
      plan_id: $plan_id,
      slug: $slug,
      project_slug: $project_slug,
      source: $source,
      status: "proposed",
      approval: null
    }' "$input_file" >"$candidate" || {
      rm -rf -- "$temporary"
      return 1
    }
  foreman_plan_validate_canonical "$candidate" || {
    rm -rf -- "$temporary"
    return 1
  }

  plans_root="$FOREMAN_PLAN_PROJECT_ROOT/plans"
  destination="$plans_root/$plan_id"
  [ ! -e "$destination" ] && [ ! -L "$destination" ] || {
    foreman_plan_error "plan already exists and will not be overwritten: $plan_id"
    rm -rf -- "$temporary"
    return 1
  }
  staging=$(mktemp -d "$plans_root/.foreman-plan.XXXXXX") || {
    rm -rf -- "$temporary"
    return 1
  }
  chmod 0700 "$staging" || {
    rm -rf -- "$staging" "$temporary"
    return 1
  }
  cp "$candidate" "$staging/plan.json" || {
    rm -rf -- "$staging" "$temporary"
    return 1
  }
  review_file="$staging/plan-$plan_slug.html"
  foreman_render_plan "$candidate" "$FOREMAN_PLAN_PROJECT_FILE" "$review_file" || {
    rm -rf -- "$staging" "$temporary"
    return 1
  }
  chmod 0600 "$staging/plan.json" "$review_file" || {
    rm -rf -- "$staging" "$temporary"
    return 1
  }
  mv "$staging" "$destination" || {
    rm -rf -- "$staging" "$temporary"
    return 1
  }
  rm -rf -- "$temporary"
  printf 'Created proposed plan %s\n' "$plan_id"
  printf 'Review: %s\n' "$destination/plan-$plan_slug.html"
  printf 'No work was started. Approve the plan explicitly when it is ready.\n'
}

foreman_plan_create_command() {
  local mode=$1 project_slug='' input_file='' temporary source_json status
  shift
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --project) [ "$#" -ge 2 ] || return 64; project_slug=$2; shift 2 ;;
      --file) [ "$#" -ge 2 ] || return 64; input_file=$2; shift 2 ;;
      -h|--help) foreman_plan_usage; return 0 ;;
      *) foreman_plan_error "unknown $mode option: $1"; return 64 ;;
    esac
  done
  [ -n "$project_slug" ] && [ -n "$input_file" ] || {
    foreman_plan_error "$mode requires --project and --file"
    return 64
  }
  foreman_plan_load_project "$project_slug" || return 1

  if [ "$mode" = create ]; then
    source_json='{"kind":"direct","system":null,"reference":null}'
    foreman_plan_store "$project_slug" "$input_file" "$source_json"
    return
  fi

  temporary=$(mktemp -d '/tmp/foreman-handover.XXXXXX') || return 1
  if ! foreman_plan_validate_handover "$input_file" "$temporary/input.json"; then
    rm -rf -- "$temporary"
    return 1
  fi
  source_json=$(jq -c '.source + {kind:"external-handover"} | {kind, system, reference}' "$input_file") || {
    rm -rf -- "$temporary"
    return 1
  }
  if foreman_plan_store "$project_slug" "$temporary/input.json" "$source_json"; then
    status=0
  else
    status=$?
  fi
  rm -rf -- "$temporary"
  return "$status"
}

foreman_plan_prompt_required() {
  local label=$1 value
  printf '%s: ' "$label" >&2
  IFS= read -r value || value=
  [ -n "$value" ] || {
    foreman_plan_error "$label is required"
    return 1
  }
  printf '%s\n' "$value"
}

foreman_plan_prompt_optional() {
  local label=$1 value
  printf '%s: ' "$label" >&2
  IFS= read -r value || value=
  printf '%s\n' "$value"
}

foreman_plan_guided_command() {
  local project_slug='' title objective included excluded constraint task_title task_type
  local task_objective task_acceptance validation delivery missing task_id temporary status

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --project) [ "$#" -ge 2 ] || return 64; project_slug=$2; shift 2 ;;
      -h|--help) foreman_plan_usage; return 0 ;;
      *) foreman_plan_error "unknown guided option: $1"; return 64 ;;
    esac
  done
  [ -n "$project_slug" ] || {
    foreman_plan_error 'guided requires --project'
    return 64
  }
  foreman_plan_load_project "$project_slug" || return 1

  printf 'Draft a bounded one-task proposal. Leave optional answers blank.\n' >&2
  title=$(foreman_plan_prompt_required 'Plan title') || return 1
  objective=$(foreman_plan_prompt_required 'Plan objective') || return 1
  included=$(foreman_plan_prompt_required 'Included scope') || return 1
  excluded=$(foreman_plan_prompt_optional 'Excluded scope')
  constraint=$(foreman_plan_prompt_optional 'Constraint')
  task_title=$(foreman_plan_prompt_required 'Task title') || return 1
  task_type=$(foreman_plan_prompt_optional 'Task type [change]')
  [ -n "$task_type" ] || task_type=change
  task_objective=$(foreman_plan_prompt_required 'Task objective') || return 1
  task_acceptance=$(foreman_plan_prompt_required 'Task acceptance criterion') || return 1
  validation=$(foreman_plan_prompt_optional 'Validation command or evidence')
  delivery=$(foreman_plan_prompt_optional 'Delivery expectation [project-default]')
  [ -n "$delivery" ] || delivery='project-default'
  missing=$(foreman_plan_prompt_optional 'Missing information')
  task_id=$(foreman_slugify "$task_title") || return 1

  temporary=$(mktemp -d '/tmp/foreman-guided.XXXXXX') || return 1
  jq -n \
    --arg title "$title" --arg objective "$objective" \
    --arg included "$included" --arg excluded "$excluded" --arg constraint "$constraint" \
    --arg task_id "$task_id" --arg task_title "$task_title" --arg task_type "$task_type" \
    --arg task_objective "$task_objective" --arg task_acceptance "$task_acceptance" \
    --arg validation "$validation" --arg delivery "$delivery" --arg missing "$missing" '
    def optional($value): if $value == "" then [] else [$value] end;
    {
      schema_version: 1,
      title: $title,
      objective: $objective,
      scope: {included: [$included], excluded: optional($excluded)},
      constraints: optional($constraint),
      tasks: [{
        id: $task_id,
        type: $task_type,
        title: $task_title,
        objective: $task_objective,
        depends_on: [],
        acceptance_criteria: [$task_acceptance],
        validation: optional($validation),
        delivery_expectation: $delivery,
        worker_profile_hint: null
      }],
      acceptance_criteria: [$task_acceptance],
      assumptions: [],
      risks: [],
      missing_information: optional($missing),
      unresolved_decisions: [],
      references: []
    }
  ' >"$temporary/input.json" || {
    rm -rf -- "$temporary"
    return 1
  }
  if foreman_plan_store "$project_slug" "$temporary/input.json" \
    '{"kind":"guided-draft","system":null,"reference":null}'; then
    status=0
  else
    status=$?
  fi
  rm -rf -- "$temporary"
  return "$status"
}

foreman_plan_load_stored() {
  local project_slug=$1 plan_id=$2 plan_dir plan_file plan_slug
  case "$plan_id" in
    plan-[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) ;;
    *) foreman_plan_error 'plan must be a complete plan ID'; return 1 ;;
  esac
  foreman_plan_load_project "$project_slug" || return 1
  plan_dir="$FOREMAN_PLAN_PROJECT_ROOT/plans/$plan_id"
  [ -d "$plan_dir" ] && [ ! -L "$plan_dir" ] || {
    foreman_plan_error "plan was not found: $plan_id"
    return 1
  }
  plan_file="$plan_dir/plan.json"
  foreman_plan_validate_canonical "$plan_file" || return 1
  [ "$(jq -r '.project_slug' "$plan_file")" = "$project_slug" ] || {
    foreman_plan_error 'stored plan project identity does not match the request'
    return 1
  }
  [ "$(jq -r '.plan_id' "$plan_file")" = "$plan_id" ] || {
    foreman_plan_error 'stored plan ID does not match its directory'
    return 1
  }
  plan_slug=$(jq -r '.slug' "$plan_file")
  FOREMAN_PLAN_DIR=$plan_dir
  FOREMAN_PLAN_FILE=$plan_file
  FOREMAN_PLAN_REVIEW_FILE="$plan_dir/plan-$plan_slug.html"
  export FOREMAN_PLAN_DIR FOREMAN_PLAN_FILE FOREMAN_PLAN_REVIEW_FILE
}

foreman_plan_review_command() {
  local project_slug='' plan_id='' temporary
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --project) [ "$#" -ge 2 ] || return 64; project_slug=$2; shift 2 ;;
      --plan) [ "$#" -ge 2 ] || return 64; plan_id=$2; shift 2 ;;
      *) foreman_plan_error "unknown review option: $1"; return 64 ;;
    esac
  done
  [ -n "$project_slug" ] && [ -n "$plan_id" ] || {
    foreman_plan_error 'review requires --project and --plan'
    return 64
  }
  foreman_plan_load_stored "$project_slug" "$plan_id" || return 1
  temporary=$(mktemp '/tmp/foreman-plan-review.XXXXXX') || return 1
  foreman_render_plan "$FOREMAN_PLAN_FILE" "$FOREMAN_PLAN_PROJECT_FILE" "$temporary" || {
    rm -f -- "$temporary"
    return 1
  }
  foreman_atomic_write "$temporary" "$FOREMAN_PLAN_REVIEW_FILE" || {
    rm -f -- "$temporary"
    return 1
  }
  rm -f -- "$temporary"
  printf 'Review: %s\n' "$FOREMAN_PLAN_REVIEW_FILE"
}

foreman_plan_approve_command() {
  local project_slug='' plan_id='' approved_by=user yes=0 confirmation temporary timestamp
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --project) [ "$#" -ge 2 ] || return 64; project_slug=$2; shift 2 ;;
      --plan) [ "$#" -ge 2 ] || return 64; plan_id=$2; shift 2 ;;
      --approved-by) [ "$#" -ge 2 ] || return 64; approved_by=$2; shift 2 ;;
      --yes) yes=1; shift ;;
      *) foreman_plan_error "unknown approve option: $1"; return 64 ;;
    esac
  done
  [ -n "$project_slug" ] && [ -n "$plan_id" ] || {
    foreman_plan_error 'approve requires --project and --plan'
    return 64
  }
  [ -n "$approved_by" ] || {
    foreman_plan_error 'approved-by must not be empty'
    return 64
  }
  foreman_plan_load_stored "$project_slug" "$plan_id" || return 1
  [ "$(jq -r '.status' "$FOREMAN_PLAN_FILE")" = proposed ] || {
    foreman_plan_error "plan is not awaiting approval: $plan_id"
    return 1
  }
  jq -e '(.missing_information | length) == 0' "$FOREMAN_PLAN_FILE" >/dev/null || {
    foreman_plan_error 'plan cannot be approved while information is missing'
    return 1
  }
  jq -e 'all(.unresolved_decisions[]; .blocking == false)' "$FOREMAN_PLAN_FILE" >/dev/null || {
    foreman_plan_error 'plan cannot be approved while a blocking decision is unresolved'
    return 1
  }

  printf 'Plan %s is complete and remains non-executable in Phase 1.\n' "$plan_id"
  if [ "$yes" -eq 0 ]; then
    printf 'Approve this plan? [y/N]: ' >&2
    IFS= read -r confirmation || confirmation=
    case "$confirmation" in
      y|Y|yes|YES) ;;
      *) printf 'Plan was not approved.\n'; return 1 ;;
    esac
  fi

  temporary=$(mktemp -d '/tmp/foreman-approval.XXXXXX') || return 1
  timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  jq -S --arg approved_at "$timestamp" --arg approved_by "$approved_by" '
    .status = "approved" |
    .approval = {approved_at: $approved_at, approved_by: $approved_by}
  ' "$FOREMAN_PLAN_FILE" >"$temporary/plan.json" || {
    rm -rf -- "$temporary"
    return 1
  }
  foreman_plan_validate_canonical "$temporary/plan.json" || {
    rm -rf -- "$temporary"
    return 1
  }
  foreman_render_plan "$temporary/plan.json" "$FOREMAN_PLAN_PROJECT_FILE" "$temporary/review.html" || {
    rm -rf -- "$temporary"
    return 1
  }
  foreman_atomic_write "$temporary/plan.json" "$FOREMAN_PLAN_FILE" || {
    rm -rf -- "$temporary"
    return 1
  }
  foreman_atomic_write "$temporary/review.html" "$FOREMAN_PLAN_REVIEW_FILE" || {
    rm -rf -- "$temporary"
    return 1
  }
  rm -rf -- "$temporary"
  printf 'Approved plan %s\n' "$plan_id"
  printf 'No work was started.\n'
}

foreman_plan_command() {
  local command=${1:-help}
  case "$command" in
    help|-h|--help) foreman_plan_usage ;;
    template) cat "$FOREMAN_SOURCE_ROOT/docs/plan-template.md" ;;
    create|handover) shift; foreman_plan_create_command "$command" "$@" ;;
    guided) shift; foreman_plan_guided_command "$@" ;;
    review) shift; foreman_plan_review_command "$@" ;;
    approve) shift; foreman_plan_approve_command "$@" ;;
    *) foreman_plan_error "unknown plan command: $command"; foreman_plan_usage >&2; return 64 ;;
  esac
}
