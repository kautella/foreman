#!/usr/bin/env bash

set -u

repo_root="$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)"
foreman="$repo_root/foreman"
# shellcheck source=tests/test-helper.sh
. "$repo_root/tests/test-helper.sh"

test_root=$(mktemp -d '/tmp/foreman-initialization.XXXXXX') || exit 1
trap 'rm -rf "$test_root"' EXIT HUP INT TERM
fakebin="$test_root/fakebin"
mkdir -p "$fakebin"
for executable in codex herdr gh; do
  printf '#!/usr/bin/env bash\nexit 0\n' >"$fakebin/$executable"
  chmod +x "$fakebin/$executable"
done
PATH="$fakebin:$PATH"
export PATH

create_repository() {
  local path=$1
  mkdir -p "$path"
  git -C "$path" init -q
  printf 'fixture\n' >"$path/README.md"
  git -C "$path" add README.md
  git -C "$path" \
    -c user.name='Foreman Tests' \
    -c user.email='tests@example.invalid' \
    commit -qm 'Create fixture'
}

init_project() {
  local home=$1 project=$2 name=$3
  FOREMAN_HOME="$home" "$foreman" init \
    --name "$name" \
    --project "$project" \
    --agent codex \
    --model test-model \
    --reasoning high \
    --runtime herdr \
    --yes
}

file_mode() {
  stat -f %Lp "$1" 2>/dev/null || stat -c %a "$1"
}

test_reviewed_initialization_persists_exact_configuration() {
  local home project project_canonical output config mode
  home="$test_root/home-success"
  project="$test_root/project-success"
  create_repository "$project"
  project_canonical=$(CDPATH='' cd -P -- "$project" && pwd -P)

  output=$(init_project "$home" "$project" 'Example Project') \
    || test_fail 'valid initialization failed'
  test_assert_contains "$output" 'Proposed global configuration:' \
    'initialization did not surface global configuration'
  test_assert_contains "$output" 'Proposed effective project configuration:' \
    'initialization did not surface effective project configuration'
  test_assert_contains "$output" 'Initialized project example-project' \
    'initialization did not report its durable project identity'

  [ -f "$home/config.json" ] || test_fail 'global configuration was not written'
  config="$home/projects/example-project/project.json"
  [ -f "$config" ] || test_fail 'project configuration was not written'
  jq -e --arg project "$project_canonical" '
    .schema_version == 1 and
    .project.slug == "example-project" and
    .project.repository_path == $project and
    .worker_profile == {agent:"codex", model:"test-model", reasoning:"high"} and
    .runtime == "herdr" and
    .remote.provider == "none" and
    .delivery == {policy:"draft-handoff", merge_authority:false}
  ' "$config" >/dev/null || test_fail 'persisted project configuration differs from the reviewed values'
  mode=$(file_mode "$config")
  case "$mode" in
    600|0600) ;;
    *) test_fail "project configuration mode is $mode instead of 0600" ;;
  esac
  test_pass 'reviewed initialization persists exact configuration atomically'
}

test_rejection_does_not_create_foreman_home() {
  local home project status output
  home="$test_root/home-rejected"
  project="$test_root/project-rejected"
  create_repository "$project"

  set +e
  output=$(printf 'n\n' | FOREMAN_HOME="$home" "$foreman" init \
    --name Rejected \
    --project "$project" \
    --agent codex \
    --model test-model \
    --reasoning high \
    --runtime herdr 2>&1)
  status=$?
  set -e
  [ "$status" -ne 0 ] || test_fail 'rejected configuration returned success'
  test_assert_contains "$output" 'Configuration was not persisted.' \
    'rejected initialization did not confirm non-persistence'
  [ ! -e "$home" ] || test_fail 'rejected initialization created Foreman state'
  test_pass 'configuration rejection leaves no Foreman home behind'
}

test_missing_worker_choice_is_requested_and_required() {
  local home project output status
  home="$test_root/home-missing-model"
  project="$test_root/project-missing-model"
  create_repository "$project"

  set +e
  output=$(FOREMAN_HOME="$home" "$foreman" init \
    --name MissingModel \
    --project "$project" \
    --agent codex \
    --reasoning high \
    --runtime herdr \
    --yes </dev/null 2>&1)
  status=$?
  set -e
  [ "$status" -ne 0 ] || test_fail 'initialization accepted a missing model'
  test_assert_contains "$output" 'Model is required' \
    'missing model did not produce an actionable prompt failure'
  [ ! -e "$home" ] || test_fail 'incomplete worker profile created Foreman state'
  test_pass 'missing worker-profile choices are requested before persistence'
}

test_unsafe_path_relationships_are_rejected() {
  local project nested_home worktree status output link
  project="$test_root/project-unsafe"
  create_repository "$project"
  nested_home="$project/.foreman"

  set +e
  output=$(FOREMAN_HOME="$nested_home" "$foreman" init \
    --name UnsafeHome --project "$project" --agent codex --model test-model \
    --reasoning high --runtime herdr --yes 2>&1)
  status=$?
  set -e
  [ "$status" -ne 0 ] || test_fail 'FOREMAN_HOME inside the project was accepted'
  test_assert_contains "$output" 'must not overlap' \
    'unsafe home failure did not explain the overlap'

  worktree="$project/worktrees"
  set +e
  output=$(FOREMAN_HOME="$test_root/home-unsafe-worktree" "$foreman" init \
    --name UnsafeWorktree --project "$project" --agent codex --model test-model \
    --reasoning high --runtime herdr --worktree-root "$worktree" --yes 2>&1)
  status=$?
  set -e
  [ "$status" -ne 0 ] || test_fail 'worktree root inside the project was accepted'

  link="$test_root/project-link"
  ln -s "$project" "$link"
  set +e
  output=$(FOREMAN_HOME="$test_root/home-symlink" "$foreman" init \
    --name Symlink --project "$link" --agent codex --model test-model \
    --reasoning high --runtime herdr --yes 2>&1)
  status=$?
  set -e
  [ "$status" -ne 0 ] || test_fail 'symbolic-link project path was accepted'
  test_assert_contains "$output" 'must not be a symbolic link' \
    'symbolic-link refusal was not actionable'
  test_pass 'unsafe home, worktree, and symbolic-link paths are rejected'
}

test_duplicate_repository_identity_is_rejected() {
  local home project output status
  home="$test_root/home-duplicate"
  project="$test_root/project-duplicate"
  create_repository "$project"
  init_project "$home" "$project" First >/dev/null \
    || test_fail 'first registration failed'

  set +e
  output=$(FOREMAN_HOME="$home" "$foreman" init \
    --name Second --project "$project" --agent codex --model test-model \
    --reasoning high --runtime herdr --yes 2>&1)
  status=$?
  set -e
  [ "$status" -ne 0 ] || test_fail 'duplicate repository identity was accepted'
  test_assert_contains "$output" 'repository is already registered' \
    'duplicate identity failure did not identify the collision'
  test_pass 'duplicate repository identity is rejected without auto-renaming'
}

test_remote_detection_is_read_only() {
  local home project config before after
  home="$test_root/home-remote"
  project="$test_root/project-remote"
  create_repository "$project"
  git -C "$project" remote add origin git@github.com:example/example.git
  before=$(git -C "$project" config --local --list | LC_ALL=C sort)

  FOREMAN_HOME="$home" "$foreman" init \
    --name Remote --project "$project" --agent codex --model test-model \
    --reasoning high --runtime herdr --delivery-policy automated-change-request \
    --merge-authority true --yes >/dev/null \
    || test_fail 'supported remote initialization failed'
  after=$(git -C "$project" config --local --list | LC_ALL=C sort)
  test_assert_equal "$after" "$before" 'remote detection mutated repository configuration'
  config="$home/projects/remote/project.json"
  jq -e '
    .remote.provider == "github" and
    .remote.host == "github.com" and
    .remote.repository == "example/example" and
    .delivery.policy == "automated-change-request" and
    .delivery.merge_authority == true
  ' "$config" >/dev/null || test_fail 'remote identity or delivery authority was persisted incorrectly'
  test_pass 'remote detection is read-only and policy remains explicit'
}

test_doctor_reports_uninitialized_and_initialized_state() {
  local home project output
  home="$test_root/home-doctor"
  project="$test_root/project-doctor"
  create_repository "$project"
  output=$(FOREMAN_HOME="$home" "$foreman" doctor) \
    || test_fail 'doctor failed before initialization'
  test_assert_contains "$output" 'Foreman is not initialized' \
    'doctor did not report uninitialized state'

  init_project "$home" "$project" Doctor >/dev/null \
    || test_fail 'doctor fixture initialization failed'
  output=$(FOREMAN_HOME="$home" "$foreman" doctor --project doctor) \
    || test_fail 'doctor failed after initialization'
  test_assert_contains "$output" 'project configuration and identity are valid' \
    'doctor did not validate project configuration and live identity'
  test_pass 'doctor distinguishes uninitialized and valid configured state'
}

test_reviewed_initialization_persists_exact_configuration
test_rejection_does_not_create_foreman_home
test_missing_worker_choice_is_requested_and_required
test_unsafe_path_relationships_are_rejected
test_duplicate_repository_identity_is_rejected
test_remote_detection_is_read_only
test_doctor_reports_uninitialized_and_initialized_state
