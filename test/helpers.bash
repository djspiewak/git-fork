setup() {
  # Resolve /tmp → /private/tmp on macOS so git-stored paths match our variables.
  # git always canonicalises paths; $BATS_TEST_TMPDIR may hold the symlink form.
  REAL_TMPDIR="$(cd "$BATS_TEST_TMPDIR" && pwd -P)"
  export REAL_TMPDIR
  export GIT_WORKTREE_BASE="$REAL_TMPDIR/.worktrees"
  export HOME="$REAL_TMPDIR/home"
  mkdir -p "$GIT_WORKTREE_BASE" "$HOME/.worktrees"
  # Prevent git from prompting for credentials or reading system-level helpers
  # (osxkeychain on macOS CI can hang indefinitely waiting for user input).
  export GIT_TERMINAL_PROMPT=0
  export GIT_CONFIG_NOSYSTEM=1
  # shellcheck disable=SC1090
  source "$BATS_TEST_DIRNAME/../git-fork.sh"
}

# make_repo <name>: create a fresh git repo with one empty commit
make_repo() {
  local name="$1"
  local repo_dir="$REAL_TMPDIR/src/$name"
  mkdir -p "$repo_dir"
  command git -C "$repo_dir" init -q
  command git -C "$repo_dir" config user.email "test@example.com"
  command git -C "$repo_dir" config user.name "Test User"
  command git -C "$repo_dir" commit --allow-empty -q -m "initial"
}

# make_fork <repo_name> <seed> [commitish]: create a detached worktree under GIT_WORKTREE_BASE
make_fork() {
  local repo_name="$1"
  local seed="$2"
  local commitish="${3:-HEAD}"
  local repo_dir="$REAL_TMPDIR/src/$repo_name"
  local fork_dir="$GIT_WORKTREE_BASE/$repo_name/$seed"
  mkdir -p "$GIT_WORKTREE_BASE/$repo_name"
  command git -C "$repo_dir" worktree add -q --detach "$fork_dir" "$commitish"
}

# make_repo_with_bad_submodule <name>: repo whose submodule update will fail
make_repo_with_bad_submodule() {
  local name="$1"
  make_repo "$name"
  local repo_dir="$REAL_TMPDIR/src/$name"
  cat > "$repo_dir/.gitmodules" << 'GITMODULES'
[submodule "bad"]
	path = bad
	url = /tmp/nonexistent-submodule-repo-xyz
GITMODULES
  command git -C "$repo_dir" add .gitmodules
  command git -C "$repo_dir" commit -q -m "add bad submodule"
}
