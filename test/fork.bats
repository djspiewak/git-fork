bats_require_minimum_version 1.5.0
load 'helpers'

@test "--help exits 0 and prints usage" {
  run git-fork --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"usage: git fork"* ]]
}

@test "-h is equivalent to --help" {
  run git-fork -h
  [ "$status" -eq 0 ]
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

@test "default fork on unborn repo fails with clear error" {
  command git init "$REAL_TMPDIR/src/unborn"
  cd "$REAL_TMPDIR/src/unborn"
  run git-fork
  [ "$status" -eq 1 ]
  [[ "$output" == *"unborn"* ]]
}

# -m tests (ported from unfork.bats)

@test "-m fast-forwards main to fork HEAD, worktree removed, cwd = main root" {
  make_repo myrepo
  make_fork myrepo seedA
  cd "$GIT_WORKTREE_BASE/myrepo/seedA"
  command git config user.email "test@example.com"
  command git config user.name "Test User"
  command git commit --allow-empty -q -m "fork commit"
  local fork_sha
  fork_sha=$(command git rev-parse HEAD)
  git-fork -m
  local main_sha
  main_sha=$(command git -C "$REAL_TMPDIR/src/myrepo" rev-parse HEAD)
  [ "$main_sha" = "$fork_sha" ]
  [ ! -d "$GIT_WORKTREE_BASE/myrepo/seedA" ]
  [ "$PWD" = "$REAL_TMPDIR/src/myrepo" ]
}

@test "-m --no-ff creates a merge commit; fork sha reachable from new main HEAD; worktree removed" {
  make_repo myrepo
  make_fork myrepo seedA
  cd "$GIT_WORKTREE_BASE/myrepo/seedA"
  command git config user.email "test@example.com"
  command git config user.name "Test User"
  command git commit --allow-empty -q -m "fork commit"
  local fork_sha
  fork_sha=$(command git rev-parse HEAD)
  git-fork -m --no-ff
  local merge_sha
  merge_sha=$(command git -C "$REAL_TMPDIR/src/myrepo" rev-parse HEAD)
  [ "$merge_sha" != "$fork_sha" ]
  command git -C "$REAL_TMPDIR/src/myrepo" merge-base --is-ancestor "$fork_sha" HEAD
  [ ! -d "$GIT_WORKTREE_BASE/myrepo/seedA" ]
}

@test "-m rejects dirty worktree; status 1, worktree intact, main HEAD unchanged" {
  make_repo myrepo
  local main_sha_before
  main_sha_before=$(command git -C "$REAL_TMPDIR/src/myrepo" rev-parse HEAD)
  make_fork myrepo seedA
  cd "$GIT_WORKTREE_BASE/myrepo/seedA"
  echo "dirty" > untracked.txt
  run --separate-stderr git-fork -m
  [ "$status" -eq 1 ]
  [ -d "$GIT_WORKTREE_BASE/myrepo/seedA" ]
  local main_sha_after
  main_sha_after=$(command git -C "$REAL_TMPDIR/src/myrepo" rev-parse HEAD)
  [ "$main_sha_after" = "$main_sha_before" ]
}

@test "-m on merge conflict: exits non-zero, worktree intact, MERGE_HEAD exists in main" {
  make_repo myrepo
  local main_root="$REAL_TMPDIR/src/myrepo"
  # Fork created at initial commit; then both branches add conflicting content
  make_fork myrepo seedA
  command git -C "$main_root" config user.email "test@example.com"
  command git -C "$main_root" config user.name "Test User"
  echo "main line" > "$main_root/conflict.txt"
  command git -C "$main_root" add conflict.txt
  command git -C "$main_root" commit -q -m "main: add conflict.txt"
  cd "$GIT_WORKTREE_BASE/myrepo/seedA"
  command git config user.email "test@example.com"
  command git config user.name "Test User"
  echo "fork line" > conflict.txt
  command git add conflict.txt
  command git commit -q -m "fork: add conflicting conflict.txt"
  run --separate-stderr git-fork -m
  [ "$status" -ne 0 ]
  [ -d "$GIT_WORKTREE_BASE/myrepo/seedA" ]
  [ -f "$main_root/.git/MERGE_HEAD" ]
}

@test "-m outside a worktree exits 1 with not-in-fork message" {
  make_repo myrepo
  cd "$REAL_TMPDIR/src/myrepo"
  run --separate-stderr git-fork -m
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"not inside a fork worktree"* ]]
}

@test "--help output mentions -d, -D, --delete-unmerged, --delete-and-skip-checks, and -m" {
  run git-fork --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"-d"* ]]
  [[ "$output" == *"-D"* ]]
  [[ "$output" == *"--delete-unmerged"* ]]
  [[ "$output" == *"--delete-and-skip-checks"* ]]
  [[ "$output" == *"-m"* ]]
}
