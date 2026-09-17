#!/usr/bin/env bash

set -u

repo_root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
FOREMAN_SOURCE_ROOT=$repo_root
export FOREMAN_SOURCE_ROOT

# shellcheck source=src/path.sh
. "$repo_root/src/path.sh"
# shellcheck source=src/adapters/runtimes/tmux/adapter.sh
. "$repo_root/src/adapters/runtimes/tmux/adapter.sh"

live_usage() {
  cat <<'EOF'
Usage: ./scripts/live-check.sh MODE --evidence-dir ABSOLUTE_PATH [options]

Modes:
  --tmux
      Exercise the real tmux adapter with a harmless fake worker. This does
      not invoke a coding agent or consume model usage.

  --codex-task
      Run one real, read-only Codex CLI research task in a newly created,
      disposable Git repository. This consumes account usage and requires
      --allow-codex-usage, --model, and --reasoning.

Options:
  --evidence-dir PATH     Required new absolute directory for durable evidence
  --model ID              Required with --codex-task
  --reasoning VALUE       Required with --codex-task
  --timeout SECONDS       Worker wait limit for --codex-task (30–1800; default 600)
  --allow-codex-usage     Explicitly authorize the real Codex CLI invocation
  -h, --help              Show this help

The script never uses a managed repository. It preserves the evidence directory
on success, failure, timeout, or an unavailable prerequisite.
EOF
}

live_error() {
  printf 'foreman live check: %s\n' "$*" >&2
}

live_write_result() {
  local evidence_dir=$1 mode=$2 status=$3 message=$4 task_id=${5:-null} report=${6:-null}

  jq -n \
    --arg mode "$mode" --arg status "$status" --arg message "$message" \
    --arg task_id "$task_id" --arg report "$report" \
    --arg completed_at "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" '
      {
        schema_version: 1,
        mode: $mode,
        status: $status,
        message: $message,
        task_id: (if $task_id == "null" then null else $task_id end),
        report: (if $report == "null" then null else $report end),
        completed_at: $completed_at
      }
    ' >"$evidence_dir/live-result.json"
}

live_prepare_evidence_dir() {
  local requested=$1 canonical parent

  case "$requested" in
    /*) ;;
    *) live_error 'evidence directory must be an absolute path'; return 1 ;;
  esac
  canonical=$(foreman_path_canonicalize "$requested") || return 1
  parent=${canonical%/*}
  [ -d "$parent" ] && [ ! -L "$parent" ] || {
    live_error "evidence directory parent is not safe: $parent"
    return 1
  }
  [ ! -e "$canonical" ] && [ ! -L "$canonical" ] || {
    live_error "evidence directory already exists and will not be replaced: $canonical"
    return 1
  }
  mkdir -m 700 "$canonical" || return 1
  printf '%s\n' "$canonical"
}

live_write_fake_worker() {
  local fake_bin=$1 executable=$2 worker

  mkdir -m 700 "$fake_bin" || return 1
  worker="$fake_bin/$executable"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf '\''{"type":"thread.started"}\n{"type":"turn.completed"}\n'\''' \
    'sleep 30' >"$worker" || return 1
  chmod 0700 "$worker"
}

live_write_launch_request() {
  local state_dir=$1 worktree=$2 request=$3

  jq -n \
    --arg worktree "$worktree" --arg prompt "$state_dir/brief.md" \
    --arg jsonl "$state_dir/worker-events.jsonl" --arg stderr_path "$state_dir/worker.stderr.log" \
    --arg final "$state_dir/worker-final.json" '
      {
        schema_version: 1,
        request_id: "codex-request-0123456789ab",
        task_id: "task-0123456789ab",
        task_type: "change",
        worktree_path: $worktree,
        profile: {model: "live-runtime-probe", reasoning: "none"},
        prompt_path: $prompt,
        jsonl_path: $jsonl,
        stderr_path: $stderr_path,
        final_output_path: $final
      }
    ' >"$request"
}

live_run_tmux() {
  local evidence_dir=$1 state_dir worktree fake_bin executable diagnosis request spec endpoint owner runner capture lock

  state_dir="$evidence_dir/tmux-state"
  worktree="$evidence_dir/tmux-worktree"
  fake_bin="$evidence_dir/fake-worker-bin"
  mkdir -m 700 "$state_dir" "$worktree" || return 1
  FOREMAN_TMUX_SERVER_NAME="foreman-live-$$-${RANDOM}"
  export FOREMAN_TMUX_SERVER_NAME
  unset TMUX
  diagnosis="$state_dir/tmux-diagnosis.json"
  foreman_tmux_diagnose live-tmux "$diagnosis" || return 1
  executable=$(foreman_adapter_executable agent codex) || return 1
  live_write_fake_worker "$fake_bin" "$executable" || return 1
  PATH="$fake_bin:$PATH"
  export PATH
  printf 'Run the harmless live runtime check.\n' >"$state_dir/brief.md" || return 1
  request="$state_dir/request.json"
  spec="$state_dir/launch.json"
  live_write_launch_request "$state_dir" "$worktree" "$request" || return 1
  foreman_codex_build_launch_spec "$request" "$spec" || return 1
  endpoint="$state_dir/endpoint.json"
  owner="$state_dir/endpoint-owner.json"
  runner="$state_dir/runner.sh"
  capture="$state_dir/capture.txt"
  lock="$state_dir/task.lock"
  foreman_lock_acquire task "$lock" live-check task-0123456789ab live-tmux-01 || return 1
  if foreman_tmux_reserve_endpoint task-0123456789ab "$endpoint" "$owner" live-check "$lock" live-tmux-01 && \
    foreman_tmux_start "$endpoint" "$spec" "$runner" live-check "$lock" live-tmux-01 && \
    foreman_tmux_inspect "$endpoint" live-check "$lock" live-tmux-01 && \
    foreman_tmux_capture "$endpoint" "$capture" live-check "$lock" live-tmux-01 && \
    foreman_tmux_close "$endpoint" live-check "$lock" live-tmux-01 && \
    foreman_task_validate_endpoint "$endpoint" && \
    jq -e '.state == "closed"' "$endpoint" >/dev/null 2>&1; then
    foreman_lock_release task "$lock" live-check task-0123456789ab live-tmux-01 || return 1
    return 0
  fi
  foreman_tmux_close "$endpoint" live-check "$lock" live-tmux-01 >/dev/null 2>&1 || true
  foreman_lock_release task "$lock" live-check task-0123456789ab live-tmux-01 >/dev/null 2>&1 || true
  return 1
}

live_write_research_plan() {
  local destination=$1

  jq -n '
    {
      schema_version: 1,
      title: "Live Codex research verification",
      objective: "Verify one bounded, read-only Foreman task through the real Codex CLI and tmux adapters.",
      scope: {included: ["Read the disposable repository README."], excluded: ["Repository edits, remote delivery, and local landing."]},
      constraints: ["Do not modify the disposable repository.", "Return the required structured final result."],
      tasks: [{
        id: "live-research",
        type: "research",
        title: "Summarize the disposable repository",
        objective: "Read README.md and return a concise summary without editing files.",
        depends_on: [],
        acceptance_criteria: ["The repository remains unchanged.", "The final result summarizes README.md."],
        validation: ["test -f README.md"],
        delivery_expectation: "project-default",
        worker_profile_hint: null
      }],
      acceptance_criteria: ["A standalone research report is produced from a clean detached worktree."],
      assumptions: [],
      risks: [],
      missing_information: [],
      unresolved_decisions: [],
      references: []
    }
  ' >"$destination"
}

live_run_codex_task() {
  local evidence_dir=$1 model=$2 reasoning=$3 timeout=$4 home repository input output plan_id task_id endpoint_state report deadline
  local foreman="$repo_root/foreman"

  home="$evidence_dir/home"
  repository="$evidence_dir/repository"
  mkdir -m 700 "$home" "$repository" || return 1
  git -C "$repository" init -q || return 1
  printf 'This repository exists only for a bounded Foreman live verification.\n' >"$repository/README.md" || return 1
  git -C "$repository" add README.md || return 1
  git -C "$repository" -c user.name='Foreman Live Check' -c user.email='live-check@example.invalid' commit -qm 'Create live verification fixture' || return 1
  foreman_codex_diagnose live-codex "$evidence_dir/codex-diagnosis.json" || return 1
  foreman_tmux_diagnose live-tmux "$evidence_dir/tmux-diagnosis.json" || return 1
  FOREMAN_HOME="$home" "$foreman" init --name 'Live Codex Check' --project "$repository" --agent codex \
    --model "$model" --reasoning "$reasoning" --runtime tmux --yes >"$evidence_dir/init.txt" || return 1
  input="$evidence_dir/live-research-plan.json"
  live_write_research_plan "$input" || return 1
  output=$(FOREMAN_HOME="$home" "$foreman" plan create --project live-codex-check --file "$input") || return 1
  printf '%s\n' "$output" >"$evidence_dir/plan-create.txt"
  plan_id=$(printf '%s\n' "$output" | sed -n 's/^Created proposed plan \(plan-[0-9a-f]*\)$/\1/p')
  [ -n "$plan_id" ] || return 1
  FOREMAN_HOME="$home" "$foreman" plan approve --project live-codex-check --plan "$plan_id" --yes >"$evidence_dir/plan-approve.txt" || return 1
  output=$(FOREMAN_HOME="$home" "$foreman" task start --project live-codex-check --plan "$plan_id" --task live-research) || return 1
  printf '%s\n' "$output" >"$evidence_dir/task-start.txt"
  task_id=$(printf '%s\n' "$output" | sed -n 's/^Started task \(task-[0-9a-f]*\)$/\1/p')
  [ -n "$task_id" ] || return 1
  deadline=$(( $(date +%s) + timeout ))
  while :; do
    output=$(FOREMAN_HOME="$home" "$foreman" task reconcile --project live-codex-check --task "$task_id" 2>&1) || return 1
    printf '%s\n' "$output" >"$evidence_dir/task-reconcile.txt"
    endpoint_state=$(jq -r '.state' "$home/projects/live-codex-check/tasks/$task_id/endpoint.json") || return 1
    [ "$endpoint_state" = missing ] && break
    [ "$(date +%s)" -lt "$deadline" ] || {
      live_error "real Codex task exceeded the ${timeout}-second wait limit; durable task state was preserved"
      return 1
    }
    sleep 2
  done
  FOREMAN_HOME="$home" "$foreman" task validate --project live-codex-check --task "$task_id" >"$evidence_dir/task-validate.txt" || return 1
  report=$(jq -r '.artifacts.report' "$home/projects/live-codex-check/tasks/$task_id/task.json") || return 1
  [ -f "$report" ] && [ ! -L "$report" ] || return 1
  FOREMAN_HOME="$home" "$foreman" task teardown --project live-codex-check --task "$task_id" --discard >"$evidence_dir/task-teardown.txt" || return 1
  printf '%s\n%s\n' "$task_id" "$report"
}

mode='' evidence_dir='' model='' reasoning='' timeout=600 allow_codex_usage=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --tmux|--codex-task)
      [ -z "$mode" ] || { live_error 'select exactly one mode'; exit 64; }
      mode=$1
      shift
      ;;
    --evidence-dir) [ "$#" -ge 2 ] || exit 64; evidence_dir=$2; shift 2 ;;
    --model) [ "$#" -ge 2 ] || exit 64; model=$2; shift 2 ;;
    --reasoning) [ "$#" -ge 2 ] || exit 64; reasoning=$2; shift 2 ;;
    --timeout) [ "$#" -ge 2 ] || exit 64; timeout=$2; shift 2 ;;
    --allow-codex-usage) allow_codex_usage=true; shift ;;
    -h|--help) live_usage; exit 0 ;;
    *) live_error "unknown option: $1"; exit 64 ;;
  esac
done

[ -n "$mode" ] && [ -n "$evidence_dir" ] || { live_usage >&2; exit 64; }
case "$timeout" in
  *[!0-9]*|'') live_error 'timeout must be a whole number of seconds'; exit 64 ;;
esac
[ "$timeout" -ge 30 ] && [ "$timeout" -le 1800 ] || { live_error 'timeout must be between 30 and 1800 seconds'; exit 64; }
if [ "$mode" = --tmux ]; then
  [ -z "$model" ] && [ -z "$reasoning" ] && [ "$allow_codex_usage" = false ] || {
    live_error '--tmux does not accept Codex usage options'
    exit 64
  }
else
  [ "$allow_codex_usage" = true ] && [ -n "$model" ] && [ -n "$reasoning" ] || {
    live_error '--codex-task requires --allow-codex-usage, --model, and --reasoning'
    exit 64
  }
fi

evidence_dir=$(live_prepare_evidence_dir "$evidence_dir") || exit 1
case "$mode" in
  --tmux)
    if live_run_tmux "$evidence_dir"; then
      live_write_result "$evidence_dir" tmux passed 'The real tmux adapter completed its owned endpoint lifecycle without agent usage.'
      printf 'Live tmux evidence: %s\n' "$evidence_dir"
    else
      live_write_result "$evidence_dir" tmux incomplete 'The tmux lifecycle could not be fully proven; inspect the preserved evidence.'
      live_error "tmux lifecycle was not proven; inspect $evidence_dir"
      exit 1
    fi
    ;;
  --codex-task)
    if output=$(live_run_codex_task "$evidence_dir" "$model" "$reasoning" "$timeout"); then
      task_id=$(printf '%s\n' "$output" | sed -n '1p')
      report=$(printf '%s\n' "$output" | sed -n '2p')
      live_write_result "$evidence_dir" codex-task passed 'A real read-only Codex CLI task completed through Foreman and produced a report.' "$task_id" "$report"
      printf 'Live Codex evidence: %s\n' "$evidence_dir"
    else
      live_write_result "$evidence_dir" codex-task incomplete 'The real Codex task could not be fully proven; durable evidence was preserved.'
      live_error "Codex task was not fully proven; inspect $evidence_dir"
      exit 1
    fi
    ;;
esac
