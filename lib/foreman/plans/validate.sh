#!/usr/bin/env bash

foreman_plan_error() {
  printf 'foreman: plan: %s\n' "$*" >&2
}

foreman_plan_validate_input() {
  local file=$1

  [ -f "$file" ] && [ ! -L "$file" ] || {
    foreman_plan_error "input is not a regular file: $file"
    return 1
  }
  jq empty "$file" >/dev/null 2>&1 || {
    foreman_plan_error "input is not valid JSON: $file"
    return 1
  }

  jq -e '
    def exact($allowed): type == "object" and keys == ($allowed | sort);
    def nonempty: type == "string" and length > 0;
    def strings: type == "array" and all(.[]; nonempty) and length == (unique | length);
    def nonempty_strings: strings and length > 0;
    def profile:
      exact(["agent", "model", "reasoning"]) and
      (.agent | IN("claude", "codex", "gemini", "opencode", "pi")) and
      (.model | nonempty) and (.reasoning | nonempty);
    def task:
      exact(["acceptance_criteria", "delivery_expectation", "depends_on", "id", "objective", "title", "type", "validation", "worker_profile_hint"]) and
      (.id | nonempty and test("^[a-z][a-z0-9-]*$")) and
      (.type | IN("change", "research")) and
      (.title | nonempty) and (.objective | nonempty) and
      (.depends_on | strings) and
      (.acceptance_criteria | nonempty_strings) and
      (.validation | strings) and
      (.delivery_expectation | IN("project-default", "draft-handoff", "automated-change-request")) and
      (.worker_profile_hint == null or (.worker_profile_hint | profile));
    def risk:
      exact(["description", "mitigation"]) and
      (.description | nonempty) and (.mitigation | nonempty);
    def decision:
      exact(["blocking", "id", "question"]) and
      (.id | nonempty and test("^[a-z][a-z0-9-]*$")) and
      (.question | nonempty) and (.blocking | type == "boolean");
    def reference:
      exact(["label", "uri"]) and (.label | nonempty) and (.uri | nonempty);

    exact(["acceptance_criteria", "assumptions", "constraints", "missing_information", "objective", "references", "risks", "schema_version", "scope", "tasks", "title", "unresolved_decisions"]) and
    .schema_version == 1 and
    (.title | nonempty) and (.objective | nonempty) and
    (.scope | exact(["excluded", "included"]) and (.included | strings) and (.excluded | strings)) and
    (.constraints | strings) and
    (.tasks | type == "array" and length > 0 and all(.[]; task)) and
    ([.tasks[].id] | length == (unique | length)) and
    (.acceptance_criteria | nonempty_strings) and
    (.assumptions | strings) and
    (.risks | type == "array" and all(.[]; risk)) and
    (.missing_information | strings) and
    (.unresolved_decisions | type == "array" and all(.[]; decision)) and
    ([.unresolved_decisions[].id] | length == (unique | length)) and
    (.references | type == "array" and all(.[]; reference))
  ' "$file" >/dev/null 2>&1 || {
    foreman_plan_error "input does not match contracts/plan/input.schema.json: $file"
    return 1
  }

  jq -e '
    [.tasks[].id] as $ids |
    all(.tasks[].depends_on[]; . as $dependency | $ids | index($dependency) != null)
  ' "$file" >/dev/null 2>&1 || {
    foreman_plan_error 'a task dependency names an unknown task'
    return 1
  }

  jq -e '
    .tasks as $tasks |
    def acyclic($id; $path):
      if ($path | index($id)) != null then false
      else all($tasks[] | select(.id == $id) | .depends_on[]; acyclic(.; $path + [$id]))
      end;
    all($tasks[].id; acyclic(.; []))
  ' "$file" >/dev/null 2>&1 || {
    foreman_plan_error 'task dependencies contain a cycle'
    return 1
  }
}

foreman_plan_validate_handover() {
  local file=$1 input_file=$2

  [ -f "$file" ] && [ ! -L "$file" ] || {
    foreman_plan_error "handover is not a regular file: $file"
    return 1
  }
  jq -e '
    def exact($allowed): type == "object" and keys == ($allowed | sort);
    def nonempty: type == "string" and length > 0;
    exact(["handover_version", "plan", "source"]) and
    .handover_version == 1 and
    (.source | exact(["reference", "system"]) and (.system | nonempty) and (.reference | nonempty)) and
    (.plan | type == "object")
  ' "$file" >/dev/null 2>&1 || {
    foreman_plan_error "handover does not match contracts/plan/handover.schema.json: $file"
    return 1
  }
  jq -S '.plan' "$file" >"$input_file" || return 1
  foreman_plan_validate_input "$input_file"
}

foreman_plan_validate_canonical() {
  local file=$1 body_file

  jq -e '
    def exact($allowed): type == "object" and keys == ($allowed | sort);
    def nonempty: type == "string" and length > 0;
    exact(["acceptance_criteria", "approval", "assumptions", "constraints", "missing_information", "objective", "plan_id", "project_slug", "references", "risks", "schema_version", "scope", "slug", "source", "status", "tasks", "title", "unresolved_decisions"]) and
    .schema_version == 1 and
    (.plan_id | type == "string" and test("^plan-[0-9a-f]{12}$")) and
    (.slug | type == "string" and test("^[a-z0-9]+(-[a-z0-9]+)*$")) and
    (.project_slug | type == "string" and test("^[a-z0-9]+(-[a-z0-9]+)*$")) and
    (.source |
      exact(["kind", "reference", "system"]) and
      (.kind | IN("direct", "external-handover", "guided-draft")) and
      (if .kind == "external-handover" then
        (.system | nonempty) and (.reference | nonempty)
      else .system == null and .reference == null end)) and
    (.status | IN("proposed", "approved")) and
    (if .status == "proposed" then .approval == null
     else (.approval |
       exact(["approved_at", "approved_by"]) and
       (.approved_at | nonempty) and (.approved_by | nonempty))
     end)
  ' "$file" >/dev/null 2>&1 || {
    foreman_plan_error "canonical plan does not match contracts/plan/plan.schema.json: $file"
    return 1
  }

  body_file=$(mktemp '/tmp/foreman-plan-body.XXXXXX') || return 1
  jq -S 'del(.plan_id, .slug, .project_slug, .source, .status, .approval)' "$file" >"$body_file" || {
    rm -f -- "$body_file"
    return 1
  }
  if ! foreman_plan_validate_input "$body_file"; then
    rm -f -- "$body_file"
    return 1
  fi
  rm -f -- "$body_file"
}
