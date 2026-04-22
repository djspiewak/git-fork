bats_require_minimum_version 1.5.0
load 'helpers'

@test "--help exits 255" {
  run git-fork --help
  [ "$status" -eq 255 ]
  [[ "$output" == *"usage: git fork"* ]]
}

@test "--list delegates to git-fork-list" {
  make_repo myrepo
  make_fork myrepo seedA
  cd "$REAL_TMPDIR/src/myrepo"
  run git-fork --list
  [ "$status" -eq 0 ]
  [[ "$output" == *"seedA"* ]]
}

@test "default fork creates worktree dir under GIT_WORKTREE_BASE and changes cwd" {
  make_repo myrepo
  cd "$REAL_TMPDIR/src/myrepo"
  git-fork
  [[ "$PWD" == "$GIT_WORKTREE_BASE/myrepo/"* ]]
  # HEAD is detached (symbolic-ref fails)
  run command git symbolic-ref HEAD
  [ "$status" -ne 0 ]
}

@test "default fork creates exactly one new directory under GIT_WORKTREE_BASE/repo" {
  make_repo myrepo
  cd "$REAL_TMPDIR/src/myrepo"
  git-fork
  local count
  count=$(command find "$GIT_WORKTREE_BASE/myrepo" -maxdepth 1 -mindepth 1 -type d | wc -l)
  [ "$count" -eq 1 ]
}

@test "positional commitish is honored" {
  make_repo myrepo
  cd "$REAL_TMPDIR/src/myrepo"
  local commit_sha
  commit_sha=$(command git rev-parse HEAD)
  git-fork "$commit_sha"
  local fork_sha
  fork_sha=$(command git rev-parse HEAD)
  [ "$fork_sha" = "$commit_sha" ]
}

@test "--jump exact hit in current repo dir" {
  make_repo myrepo
  make_fork myrepo mySeed
  cd "$REAL_TMPDIR/src/myrepo"
  git-fork --jump mySeed
  [ "$PWD" = "$GIT_WORKTREE_BASE/myrepo/mySeed" ]
}

@test "--jump find-fallback locates unique match across repos" {
  make_repo repo1
  make_repo repo2
  make_fork repo2 targetSeed
  # cd outside any git repo so exact-hit path is skipped
  cd "$REAL_TMPDIR"
  git-fork --jump targetSeed
  [ "$PWD" = "$GIT_WORKTREE_BASE/repo2/targetSeed" ]
}

@test "--jump ambiguous seed lists matches on stderr and exits 1" {
  make_repo repo1
  make_repo repo2
  make_fork repo1 common
  make_fork repo2 common
  cd "$REAL_TMPDIR"
  run --separate-stderr git-fork --jump common
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"ambiguous"* ]]
}

@test "--jump missing seed exits 1 with error" {
  make_repo myrepo
  cd "$REAL_TMPDIR"
  run --separate-stderr git-fork --jump nosuchseed
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"not found"* ]]
}

@test "submodule-init failure is tolerated and git-fork returns 0" {
  make_repo_with_bad_submodule badmod
  cd "$REAL_TMPDIR/src/badmod"
  run git-fork
  [ "$status" -eq 0 ]
}
