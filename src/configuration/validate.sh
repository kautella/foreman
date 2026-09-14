#!/usr/bin/env bash

foreman_configuration_error() {
  printf 'foreman: invalid %s configuration: %s\n' "$1" "$2" >&2
}

foreman_validate_global_configuration() {
  local file=$1

  [ -f "$file" ] || {
    foreman_configuration_error global "file not found: $file"
    return 1
  }

  jq -e '
    def exact_keys($allowed):
      type == "object" and ((keys - $allowed) | length == 0);
    def nonempty: type == "string" and length > 0;
    def absolute: nonempty and startswith("/");
    def worker_profile:
      exact_keys(["agent", "model", "reasoning"]) and
      (.agent | IN("claude", "codex", "gemini", "opencode", "pi")) and
      (.model | nonempty) and
      (.reasoning | nonempty);

    exact_keys(["defaults", "projects_root", "schema_version"]) and
    .schema_version == 1 and
    (.projects_root | absolute) and
    (.defaults |
      exact_keys(["delivery_policy", "merge_authority", "runtime", "worker_profile", "worktree_root"]) and
      (.worker_profile == null or (.worker_profile | worker_profile)) and
      (.runtime == null or (.runtime | IN("tmux", "herdr"))) and
      (.worktree_root == null or (.worktree_root | absolute)) and
      .delivery_policy == "draft-handoff" and
      .merge_authority == false)
  ' "$file" >/dev/null 2>&1 || {
    foreman_configuration_error global 'schema validation failed'
    return 1
  }
}

foreman_validate_project_configuration() {
  local file=$1

  [ -f "$file" ] || {
    foreman_configuration_error project "file not found: $file"
    return 1
  }

  jq -e '
    def exact_keys($allowed):
      type == "object" and ((keys - $allowed) | length == 0);
    def nonempty: type == "string" and length > 0;
    def nullable_string: . == null or type == "string";
    def absolute: nonempty and startswith("/");
    def agent: IN("claude", "codex", "gemini", "opencode", "pi");
    def runtime: IN("tmux", "herdr");
    def provider: IN("none", "github", "gitlab", "unsupported");

    exact_keys(["delivery", "project", "remote", "runtime", "schema_version", "validation", "worker_profile", "worktree_root"]) and
    .schema_version == 1 and
    (.project |
      exact_keys(["git_common_dir", "name", "repository_path", "slug"]) and
      (.name | nonempty) and
      (.slug | nonempty and test("^[a-z0-9]+(-[a-z0-9]+)*$")) and
      (.repository_path | absolute) and
      (.git_common_dir | absolute)) and
    (.worktree_root | absolute) and
    (.remote |
      exact_keys(["host", "name", "provider", "repository", "url"]) and
      (.provider | provider) and
      (.name | nullable_string) and
      (.url | nullable_string) and
      (.host | nullable_string) and
      (.repository | nullable_string) and
      (if .provider == "none" then
        .name == null and .url == null and .host == null and .repository == null
      elif (.provider == "github" or .provider == "gitlab") then
        (.name | nonempty) and (.url | nonempty) and (.host | nonempty) and (.repository | nonempty)
      else
        true
      end)) and
    (.worker_profile |
      exact_keys(["agent", "model", "reasoning"]) and
      (.agent | agent) and
      (.model | nonempty) and
      (.reasoning | nonempty)) and
    (.runtime | runtime) and
    (.delivery |
      exact_keys(["merge_authority", "policy"]) and
      (.policy | IN("draft-handoff", "automated-change-request")) and
      (.merge_authority | type == "boolean")) and
    (.validation |
      exact_keys(["commands", "require_clean_worktree"]) and
      (.commands | type == "array") and
      (all(.commands[]; nonempty)) and
      ((.commands | unique | length) == (.commands | length)) and
      (.require_clean_worktree | type == "boolean")) and
    (if (.remote.provider == "none" or .remote.provider == "unsupported") then
      .delivery.policy == "draft-handoff" and .delivery.merge_authority == false
    else true end) and
    (if .delivery.policy == "automated-change-request" then
      (.remote.provider == "github" or .remote.provider == "gitlab")
    else true end) and
    (if .delivery.merge_authority then
      .delivery.policy == "automated-change-request"
    else true end)
  ' "$file" >/dev/null 2>&1 || {
    foreman_configuration_error project 'schema validation failed'
    return 1
  }
}
