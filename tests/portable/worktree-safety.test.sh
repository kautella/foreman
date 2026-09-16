#!/usr/bin/env bash

set -u

repo_root="$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)"
FOREMAN_SOURCE_ROOT=$repo_root
export FOREMAN_SOURCE_ROOT
# shellcheck source=src/tasks/worktree.sh
. "$repo_root/src/tasks/worktree.sh"
# shellcheck source=tests/test-helper.sh
. "$repo_root/tests/test-helper.sh"

test_root=$(mktemp -d '/tmp/foreman-worktree-safety.XXXXXX') || exit 1
trap 'rm -rf "$test_root"' EXIT HUP INT TERM
repository="$test_root/repository"
worktree_root="$test_root/worktrees"
state_root="$test_root/state"
project_lock="$state_root/project.lock"
project_slug='sample-project'
mkdir -p "$repository" "$worktree_root" "$state_root"
git -C "$repository" init -q
printf 'fixture\n' >"$repository/README.md"
git -C "$repository" add README.md
git -C "$repository" -c user.name='Foreman Tests' -c user.email='tests@example.invalid' \
  commit -qm 'Create fixture'
base_commit=$(git -C "$repository" rev-parse HEAD)

marker_for() {
  local task_id=$1 directory
  directory="$state_root/tasks/$task_id"
  mkdir -p "$directory"
  printf '%s/worktree.json\n' "$directory"
}

acquire_project_lock() {
  local owner=$1
  foreman_lock_acquire project "$project_lock" "$project_slug" null "$owner" \
    || test_fail "could not acquire project lock: $owner"
}

release_project_lock() {
  local owner=$1
  foreman_lock_release project "$project_lock" "$project_slug" null "$owner" \
    || test_fail "could not release project lock: $owner"
}

test_change_worktree_has_exact_branch_base_and_external_marker() {
  local task_id branch marker target
  task_id='task-111111111111'
  branch='feat/task-111111111111'
  marker=$(marker_for "$task_id")
  acquire_project_lock owner-worktree-01
  target=$(foreman_worktree_allocate change "$repository" "$worktree_root" "$project_slug" "$task_id" "$branch" "$base_commit" "$marker" "$project_lock" owner-worktree-01) \
    || test_fail 'change worktree allocation failed'
  test_assert_equal "$target" "$(foreman_path_canonicalize "$worktree_root/$task_id")" \
    'change worktree target is incorrect'
  test_assert_equal "$(git -C "$target" rev-parse HEAD)" "$base_commit" 'change worktree base is incorrect'
  test_assert_equal "$(git -C "$target" symbolic-ref --quiet --short HEAD)" "$branch" 'change worktree branch is incorrect'
  [ -z "$(git -C "$target" status --porcelain=v1 --untracked-files=all)" ] \
    || test_fail 'change worktree contains unexpected Foreman files'
  foreman_worktree_validate_marker "$marker" \
    || test_fail 'external change-worktree marker did not validate'
  jq -e --arg branch "$branch" --arg base "$base_commit" '
    .task_type == "change" and .branch == $branch and .base_commit == $base
  ' "$marker" >/dev/null || test_fail 'change marker does not bind exact branch and base'
  [ -z "$(git -C "$repository" status --porcelain=v1 --untracked-files=all)" ] \
    || test_fail 'source repository became dirty during allocation'
  release_project_lock owner-worktree-01
  test_pass 'change worktree binds exact branch and base with external ownership marker'
}

test_research_worktree_is_detached_and_clean() {
  local task_id marker target
  task_id='task-222222222222'
  marker=$(marker_for "$task_id")
  acquire_project_lock owner-worktree-02
  target=$(foreman_worktree_allocate research "$repository" "$worktree_root" "$project_slug" "$task_id" null "$base_commit" "$marker" "$project_lock" owner-worktree-02) \
    || test_fail 'research worktree allocation failed'
  test_assert_equal "$(git -C "$target" rev-parse HEAD)" "$base_commit" 'research worktree base is incorrect'
  if git -C "$target" symbolic-ref --quiet HEAD >/dev/null 2>&1; then
    test_fail 'research worktree is attached to a branch'
  fi
  [ -z "$(git -C "$target" status --porcelain=v1 --untracked-files=all)" ] \
    || test_fail 'research worktree contains unexpected Foreman files'
  jq -e '.task_type == "research" and .branch == null' "$marker" >/dev/null \
    || test_fail 'research marker does not record detached ownership'
  release_project_lock owner-worktree-02
  test_pass 'research worktree is detached, exact-base, and clean'
}

test_unsafe_or_ambiguous_worktree_requests_are_refused() {
  local task_id marker output status existing_target dirty_file
  task_id='task-333333333333'
  marker=$(marker_for "$task_id")
  dirty_file="$repository/untracked.txt"
  printf 'dirty\n' >"$dirty_file"
  acquire_project_lock owner-worktree-03
  set +e
  output=$(foreman_worktree_allocate change "$repository" "$worktree_root" "$project_slug" "$task_id" feat/task-333333333333 "$base_commit" "$marker" "$project_lock" owner-worktree-03 2>&1)
  status=$?
  set -e
  [ "$status" -ne 0 ] || test_fail 'dirty source repository was accepted'
  test_assert_contains "$output" 'repository is dirty' 'dirty repository refusal was unclear'
  [ ! -e "$worktree_root/$task_id" ] || test_fail 'dirty repository created a worktree'
  [ ! -e "$marker" ] || test_fail 'dirty repository wrote a marker'
  rm -f -- "$dirty_file"
  release_project_lock owner-worktree-03

  task_id='task-444444444444'
  marker=$(marker_for "$task_id")
  existing_target="$worktree_root/$task_id"
  mkdir -p "$existing_target"
  acquire_project_lock owner-worktree-04
  if foreman_worktree_allocate change "$repository" "$worktree_root" "$project_slug" "$task_id" feat/task-444444444444 "$base_commit" "$marker" "$project_lock" owner-worktree-04 >/dev/null 2>&1; then
    test_fail 'existing unowned target was adopted'
  fi
  [ ! -e "$marker" ] || test_fail 'existing unowned target wrote a marker'
  release_project_lock owner-worktree-04

  task_id='task-555555555555'
  marker=$(marker_for "$task_id")
  git -C "$repository" branch feat/task-555555555555
  acquire_project_lock owner-worktree-05
  if foreman_worktree_allocate change "$repository" "$worktree_root" "$project_slug" "$task_id" feat/task-555555555555 "$base_commit" "$marker" "$project_lock" owner-worktree-05 >/dev/null 2>&1; then
    test_fail 'existing branch was adopted for a new task'
  fi
  [ ! -e "$worktree_root/$task_id" ] || test_fail 'existing branch created a task worktree'
  release_project_lock owner-worktree-05
  test_pass 'dirty, colliding, and unowned worktree requests are refused without mutation'
}

test_nested_roots_and_marker_targets_are_refused() {
  local nested_root marker_inside_root task_id marker
  task_id='task-666666666666'
  nested_root="$repository/nested-worktrees"
  marker=$(marker_for "$task_id")
  mkdir -p "$nested_root"
  acquire_project_lock owner-worktree-06
  if foreman_worktree_allocate change "$repository" "$nested_root" "$project_slug" "$task_id" feat/task-666666666666 "$base_commit" "$marker" "$project_lock" owner-worktree-06 >/dev/null 2>&1; then
    test_fail 'worktree root nested inside repository was accepted'
  fi
  release_project_lock owner-worktree-06

  task_id='task-777777777777'
  marker_inside_root="$worktree_root/marker-state/worktree.json"
  mkdir -p "${marker_inside_root%/*}"
  acquire_project_lock owner-worktree-07
  if foreman_worktree_allocate change "$repository" "$worktree_root" "$project_slug" "$task_id" feat/task-777777777777 "$base_commit" "$marker_inside_root" "$project_lock" owner-worktree-07 >/dev/null 2>&1; then
    test_fail 'marker path inside worktree root was accepted'
  fi
  release_project_lock owner-worktree-07
  test_pass 'nested worktree roots and in-worktree markers are refused'
}

test_change_worktree_has_exact_branch_base_and_external_marker
test_research_worktree_is_detached_and_clean
test_unsafe_or_ambiguous_worktree_requests_are_refused
test_nested_roots_and_marker_targets_are_refused
