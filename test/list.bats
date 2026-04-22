load 'helpers'

@test "single mode outside git repo exits 1 with error" {
  cd "$REAL_TMPDIR"
  run git-fork-list 0
  [ "$status" -eq 1 ]
  [[ "$output" == *"not in a git repository"* ]]
}

@test "single mode with missing base_dir exits 1 with error" {
  make_repo myrepo
  cd "$REAL_TMPDIR/src/myrepo"
  unset GIT_WORKTREE_BASE
  # HOME points to tempdir; default base doesn't exist because we override HOME
  export HOME="$REAL_TMPDIR/nohome"
  run git-fork-list 0
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
}

@test "single mode lists two worktrees for current repo" {
  make_repo myrepo
  make_fork myrepo seedA
  make_fork myrepo seedB
  cd "$REAL_TMPDIR/src/myrepo"
  run git-fork-list 0
  [ "$status" -eq 0 ]
  [[ "$output" == *"seedA"* ]]
  [[ "$output" == *"seedB"* ]]
}

@test "all mode with only default base scans that base" {
  make_repo myrepo
  local default_base="$HOME/Development/.worktrees"
  mkdir -p "$default_base/myrepo"
  command git -C "$REAL_TMPDIR/src/myrepo" worktree add -q --detach \
    "$default_base/myrepo/seedX"
  # Set GIT_WORKTREE_BASE == default_base to avoid dual-scan
  export GIT_WORKTREE_BASE="$default_base"
  run git-fork-list 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"myrepo"* ]]
  [[ "$output" == *"seedX"* ]]
}

@test "all mode dual-scan dedups same repo appearing under both bases" {
  make_repo myrepo
  make_fork myrepo seedA
  local default_base="$HOME/Development/.worktrees"
  mkdir -p "$default_base/myrepo"
  command git -C "$REAL_TMPDIR/src/myrepo" worktree add -q --detach \
    "$default_base/myrepo/seedB"
  run git-fork-list 1
  [ "$status" -eq 0 ]
  # repo name should appear exactly once (deduped by main-repo path)
  local count
  count=$(echo "$output" | grep -c "^myrepo$")
  [ "$count" -eq 1 ]
  # both seeds should be visible under the single header
  [[ "$output" == *"seedA"* ]]
  [[ "$output" == *"seedB"* ]]
}

@test "all mode skips empty seed subdirs" {
  make_repo myrepo
  make_fork myrepo seedA
  # Create an empty subdir — should be skipped by -not -empty
  mkdir -p "$GIT_WORKTREE_BASE/emptyrepo"
  run git-fork-list 1
  [ "$status" -eq 0 ]
  [[ "$output" != *"emptyrepo"* ]]
}

@test "all mode: repo dir with no nested .git shows no active worktrees" {
  # Create a non-empty dir that has no worktrees (just a file, no .git)
  mkdir -p "$GIT_WORKTREE_BASE/fakerepo"
  echo "dummy" > "$GIT_WORKTREE_BASE/fakerepo/file.txt"
  run git-fork-list 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"fakerepo"* ]]
  [[ "$output" == *"(no active worktrees found)"* ]]
}

@test "all mode with nothing anywhere prints no repositories message" {
  # Both bases are empty dirs (created in setup but no repos)
  run git-fork-list 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"(no repositories with worktrees found)"* ]]
}
