#!/usr/bin/env bash

foreman_render_plan() {
  local plan_file=$1 project_file=$2 output_file=$3 css_file
  css_file="$FOREMAN_SOURCE_ROOT/src/artifacts/plan.css"

  [ -f "$css_file" ] || {
    printf 'foreman: plan: rendering style is missing: %s\n' "$css_file" >&2
    return 1
  }

  jq -r --slurpfile project "$project_file" --rawfile css "$css_file" '
    def esc: tostring | @html;
    def list($values):
      if ($values | length) == 0 then "<p class=\"plain\">None</p>"
      else "<ul>" + ($values | map("<li>" + (. | esc) + "</li>") | join("")) + "</ul>"
      end;
    def value_or_none($value):
      if $value == null or $value == "" then "<span class=\"plain\">None</span>" else ($value | esc) end;
    def profile($value):
      if $value == null then "Project default"
      else ($value.agent + " / " + $value.model + " / " + $value.reasoning) end;
    def source_label:
      if .source.kind == "external-handover" then
        "External handover from " + (.source.system | esc)
      elif .source.kind == "guided-draft" then "Guided draft"
      else "Direct plan" end;
    def task_card($task):
      "<article><div class=\"meta\"><span class=\"badge\">" + ($task.type | esc) + "</span><span class=\"badge\"><code>" + ($task.id | esc) + "</code></span></div>" +
      "<h3>" + ($task.title | esc) + "</h3><p>" + ($task.objective | esc) + "</p>" +
      "<dl><dt>Depends on</dt><dd>" + (if ($task.depends_on | length) == 0 then "None" else ($task.depends_on | map(esc) | join(", ")) end) + "</dd>" +
      "<dt>Delivery</dt><dd>" + ($task.delivery_expectation | esc) + "</dd>" +
      "<dt>Worker profile</dt><dd>" + (profile($task.worker_profile_hint) | esc) + "</dd></dl>" +
      "<h3>Acceptance criteria</h3>" + list($task.acceptance_criteria) +
      "<h3>Validation</h3>" + list($task.validation) + "</article>";
    def risk_card($risk):
      "<article><h3>" + ($risk.description | esc) + "</h3><p><strong>Mitigation:</strong> " + ($risk.mitigation | esc) + "</p></article>";
    def decision_card($decision):
      "<article><div class=\"meta\"><span class=\"badge" + (if $decision.blocking then " warning" else "" end) + "\">" +
      (if $decision.blocking then "Blocking" else "Non-blocking" end) + "</span><span class=\"badge\"><code>" + ($decision.id | esc) + "</code></span></div>" +
      "<h3>" + ($decision.question | esc) + "</h3></article>";
    def references:
      if (.references | length) == 0 then "<p class=\"plain\">None</p>"
      else "<ul>" + (.references | map("<li><strong>" + (.label | esc) + ":</strong> <code>" + (.uri | esc) + "</code></li>") | join("")) + "</ul>" end;
    def approval_badge:
      if .status == "approved" then "<span class=\"badge\">Approved</span>"
      else "<span class=\"badge warning\">Awaiting approval</span>" end;

    "<!doctype html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n" +
    "<title>" + (.title | esc) + " · Foreman plan</title>\n<style>\n" + $css + "\n</style>\n</head>\n<body>\n<main>" +
    "<header><p class=\"eyebrow\">Foreman execution plan</p><h1>" + (.title | esc) + "</h1><p>" + (.objective | esc) + "</p>" +
    "<div class=\"meta\">" + approval_badge + "<span class=\"badge\"><code>" + (.plan_id | esc) + "</code></span><span class=\"badge\">" + (source_label) + "</span></div></header>" +
    "<section><h2>Project policy</h2><dl><dt>Project</dt><dd>" + ($project[0].project.name | esc) + "</dd><dt>Delivery policy</dt><dd>" + ($project[0].delivery.policy | esc) + "</dd><dt>Merge authority</dt><dd>" + ($project[0].delivery.merge_authority | tostring | esc) + "</dd><dt>Default worker</dt><dd>" + (profile($project[0].worker_profile) | esc) + "</dd><dt>Runtime</dt><dd>" + ($project[0].runtime | esc) + "</dd></dl></section>" +
    "<section><h2>Scope</h2><div class=\"grid\"><div><h3>Included</h3>" + list(.scope.included) + "</div><div><h3>Excluded</h3>" + list(.scope.excluded) + "</div></div></section>" +
    "<section><h2>Tasks and dependencies</h2>" + (.tasks | map(task_card(.)) | join("")) + "</section>" +
    "<section><h2>Plan acceptance criteria</h2>" + list(.acceptance_criteria) + "</section>" +
    "<section><div class=\"grid\"><div><h2>Constraints</h2>" + list(.constraints) + "</div><div><h2>Assumptions</h2>" + list(.assumptions) + "</div></div></section>" +
    "<section><h2>Risks</h2>" + (if (.risks | length) == 0 then "<p class=\"plain\">None</p>" else (.risks | map(risk_card(.)) | join("")) end) + "</section>" +
    "<section><h2>Missing information</h2>" + list(.missing_information) + "</section>" +
    "<section><h2>Unresolved decisions</h2>" + (if (.unresolved_decisions | length) == 0 then "<p class=\"plain\">None</p>" else (.unresolved_decisions | map(decision_card(.)) | join("")) end) + "</section>" +
    "<section><h2>References and provenance</h2>" + references + "<dl><dt>Source kind</dt><dd>" + (.source.kind | esc) + "</dd><dt>Source system</dt><dd>" + value_or_none(.source.system) + "</dd><dt>Source reference</dt><dd>" + value_or_none(.source.reference) + "</dd></dl></section>" +
    (if .approval == null then "" else "<section><h2>Approval</h2><dl><dt>Approved by</dt><dd>" + (.approval.approved_by | esc) + "</dd><dt>Approved at</dt><dd>" + (.approval.approved_at | esc) + "</dd></dl></section>" end) +
    "<footer>Standalone review artifact. No external styles or scripts are required.</footer></main>\n</body>\n</html>"
  ' "$plan_file" >"$output_file"
}
