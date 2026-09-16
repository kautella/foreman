#!/usr/bin/env bash

# shellcheck source=src/state/atomic.sh
. "$FOREMAN_SOURCE_ROOT/src/state/atomic.sh"

foreman_render_research_report() {
  local task_file=$1 inspection_file=$2 validation_records_json=$3 destination=$4 directory temporary

  directory=${destination%/*}
  [ -d "$directory" ] && [ ! -L "$directory" ] || return 1
  [ ! -e "$destination" ] && [ ! -L "$destination" ] || {
    printf 'foreman: research report already exists and will not be overwritten: %s\n' "$destination" >&2
    return 1
  }
  temporary=$(mktemp "$directory/.foreman-research-report.XXXXXX") || return 1
  if ! jq -nr --slurpfile task "$task_file" --slurpfile inspection "$inspection_file" --argjson validation_records "$validation_records_json" '
    def esc: tostring | gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub(">"; "&gt;") | gsub("\""; "&quot;") | gsub("\u0027"; "&#39;");
    def list($values): if ($values | length) == 0 then "<li>None recorded.</li>" else $values | map("<li>" + esc + "</li>") | join("") end;
    $task[0] as $task |
    $inspection[0].data.final as $final |
    "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\"><title>" + ($task.task.title | esc) + "</title><style>\n" +
    ":root{color-scheme:dark}*{box-sizing:border-box}body{margin:0;background:#10131a;color:#e9edf5;font:16px/1.55 -apple-system,BlinkMacSystemFont,Segoe UI,sans-serif}main{max-width:960px;margin:auto;padding:48px 24px}header,section{background:#181d27;border:1px solid #2c3444;border-radius:14px;padding:24px;margin:18px 0}h1{font-size:2rem;line-height:1.18;margin:0 0 10px}h2{font-size:1.1rem;margin:0 0 12px;color:#b8c7e8}.eyebrow{color:#85aaff;font-weight:700;text-transform:uppercase;font-size:.78rem;letter-spacing:.08em}.meta{color:#aab4c5}ul{margin:0;padding-left:22px}code{background:#252d3c;padding:2px 5px;border-radius:4px;overflow-wrap:anywhere}.summary{font-size:1.08rem;white-space:pre-wrap}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:14px}.card{background:#121722;border:1px solid #293246;border-radius:10px;padding:14px}.label{font-size:.75rem;color:#8fa1be;text-transform:uppercase;letter-spacing:.07em}</style></head><body><main>" +
    "<header><div class=\"eyebrow\">Foreman research report</div><h1>" + ($task.task.title | esc) + "</h1><p class=\"meta\">Task <code>" + ($task.task_id | esc) + "</code> · Plan <code>" + ($task.plan.plan_id | esc) + "</code></p></header>" +
    "<section><h2>Objective</h2><p>" + ($task.task.objective | esc) + "</p><h2>Summary</h2><p class=\"summary\">" + ($final.summary | esc) + "</p></section>" +
    "<section><h2>Acceptance criteria</h2><ul>" + list($task.task.acceptance_criteria) + "</ul></section>" +
    "<section><h2>Reported risks</h2><ul>" + list($final.risks) + "</ul></section>" +
    "<section><h2>Validation evidence</h2><ul>" + list($validation_records) + "</ul></section>" +
    "</main></body></html>"
  ' >"$temporary" || ! foreman_atomic_write "$temporary" "$destination"; then
    rm -f -- "$temporary"
    return 1
  fi
  rm -f -- "$temporary"
}
