load 'helpers'

@test "--help exits 255" {
  run git-unfork --help
  [ "$status" -eq 255 ]
  [[ "$output" == *"usage: git unfork"* ]]
}

@test "not in a worktree prints error and exits 255" {
  make_repo myrepo
  cd "$REAL_TMPDIR/src/myrepo"
  run git-unfork
  [ "$status" -eq 255 ]
  [[ "$output" == *"Not in worktree"* ]]
}

@test "unfork removes worktree dir and git worktree entry" {
  make_repo myrepo
  make_fork myrepo seedA
  cd "$GIT_WORKTREE_BASE/myrepo/seedA"
  git-unfork
  # worktree directory is gone
  [ ! -d "$GIT_WORKTREE_BASE/myrepo/seedA" ]
  # git no longer lists this worktree
  run command git -C "$REAL_TMPDIR/src/myrepo" worktree list
  [[ "$output" != *"seedA"* ]]
}

@test "unfork cwd moves to main repo root" {
  make_repo myrepo
  make_fork myrepo seedA
  cd "$GIT_WORKTREE_BASE/myrepo/seedA"
  git-unfork
  [ "$PWD" = "$REAL_TMPDIR/src/myrepo" ]
}

@test "unfork --merge fast-forwards base HEAD to fork HEAD" {
  make_repo myrepo
  make_fork myrepo seedA
  cd "$GIT_WORKTREE_BASE/myrepo/seedA"
  command git config user.email "test@example.com"
  command git config user.name "Test User"
  command git commit --allow-empty -q -m "fork commit"
  local fork_sha
  fork_sha=$(command git rev-parse HEAD)
  git-unfork --merge
  local main_sha
  main_sha=$(command git -C "$REAL_TMPDIR/src/myrepo" rev-parse HEAD)
  [ "$main_sha" = "$fork_sha" ]
}

@test "unfork --merge --no-ff creates a merge commit" {
  make_repo myrepo
  make_fork myrepo seedA
  cd "$GIT_WORKTREE_BASE/myrepo/seedA"
  command git config user.email "test@example.com"
  command git config user.name "Test User"
  command git commit --allow-empty -q -m "fork commit"
  local fork_sha
  fork_sha=$(command git rev-parse HEAD)
  git-unfork --merge --no-ff
  local merge_sha
  merge_sha=$(command git -C "$REAL_TMPDIR/src/myrepo" rev-parse HEAD)
  # --no-ff always creates a new merge commit, so HEAD differs from fork's HEAD
  [ "$merge_sha" != "$fork_sha" ]
  # but fork's sha is reachable from the new HEAD
  command git -C "$REAL_TMPDIR/src/myrepo" merge-base --is-ancestor "$fork_sha" HEAD
}

@test "dead variable rm -rf regression: unfork succeeds without referencing undeclared dir" {
  # The original code had `rm -rf "$dir" || :` where $dir was never set in scope.
  # That line has been deleted. This test pins that unfork does not fail due to
  # any residual reference to an undeclared variable in that code path.
  make_repo myrepo
  make_fork myrepo seedA
  cd "$GIT_WORKTREE_BASE/myrepo/seedA"
  run git-unfork
  [ "$status" -eq 0 ]
  [ ! -d "$GIT_WORKTREE_BASE/myrepo/seedA" ]
}
