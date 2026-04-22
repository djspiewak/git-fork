bats_require_minimum_version 1.5.0
load 'helpers'

# Helper: commit an empty change in a worktree
_commit_in_fork() {
  local fork_dir="$1"
  command git -C "$fork_dir" config user.email "test@example.com"
  command git -C "$fork_dir" config user.name "Test User"
  command git -C "$fork_dir" commit --allow-empty -q -m "fork commit"
}

# 6: -d happy path
@test "-d removes worktree when fork HEAD equals main HEAD (merged, clean)" {
  make_repo myrepo
  make_fork myrepo seedA
  cd "$GIT_WORKTREE_BASE/myrepo/seedA"
  git-fork -d
  [ ! -d "$GIT_WORKTREE_BASE/myrepo/seedA" ]
  [ "$PWD" = "$REAL_TMPDIR/src/myrepo" ]
  run command git -C "$REAL_TMPDIR/src/myrepo" worktree list
  [[ "$output" != *"seedA"* ]]
}

# 7: -d rejects dirty worktree
@test "-d fails on dirty worktree, names --delete-and-skip-checks" {
  make_repo myrepo
  make_fork myrepo seedA
  cd "$GIT_WORKTREE_BASE/myrepo/seedA"
  echo "dirty" > untracked.txt
  run --separate-stderr git-fork -d
  [ "$status" -eq 1 ]
  [ -d "$GIT_WORKTREE_BASE/myrepo/seedA" ]
  [[ "$stderr" == *"uncommitted"* ]]
  [[ "$stderr" == *"--delete-and-skip-checks"* ]]
}

# 8: -d rejects unmerged fork
@test "-d fails when fork has unmerged commits, suggests -D" {
  make_repo myrepo
  make_fork myrepo seedA
  cd "$GIT_WORKTREE_BASE/myrepo/seedA"
  _commit_in_fork "$PWD"
  run --separate-stderr git-fork -d
  [ "$status" -eq 1 ]
  [ -d "$GIT_WORKTREE_BASE/myrepo/seedA" ]
  [[ "$stderr" == *"not merged"* ]]
  [[ "$stderr" == *"-D"* ]]
}

# 9: -D removes unmerged fork without merging
@test "-D removes worktree with unmerged commits; main HEAD unchanged" {
  make_repo myrepo
  local main_sha_before
  main_sha_before=$(command git -C "$REAL_TMPDIR/src/myrepo" rev-parse HEAD)
  make_fork myrepo seedA
  cd "$GIT_WORKTREE_BASE/myrepo/seedA"
  _commit_in_fork "$PWD"
  git-fork -D
  [ ! -d "$GIT_WORKTREE_BASE/myrepo/seedA" ]
  local main_sha_after
  main_sha_after=$(command git -C "$REAL_TMPDIR/src/myrepo" rev-parse HEAD)
  [ "$main_sha_after" = "$main_sha_before" ]
}

# 10: -D still rejects dirty worktree
@test "-D fails on dirty worktree, names --delete-and-skip-checks" {
  make_repo myrepo
  make_fork myrepo seedA
  cd "$GIT_WORKTREE_BASE/myrepo/seedA"
  _commit_in_fork "$PWD"
  echo "dirty" > untracked.txt
  run --separate-stderr git-fork -D
  [ "$status" -eq 1 ]
  [ -d "$GIT_WORKTREE_BASE/myrepo/seedA" ]
  [[ "$stderr" == *"--delete-and-skip-checks"* ]]
}

# 11: --delete-and-skip-checks with dirty + unmerged succeeds
@test "--delete-and-skip-checks removes dirty unmerged worktree; main HEAD unchanged" {
  make_repo myrepo
  local main_sha_before
  main_sha_before=$(command git -C "$REAL_TMPDIR/src/myrepo" rev-parse HEAD)
  make_fork myrepo seedA
  cd "$GIT_WORKTREE_BASE/myrepo/seedA"
  _commit_in_fork "$PWD"
  echo "dirty" > untracked.txt
  git-fork --delete-and-skip-checks
  [ ! -d "$GIT_WORKTREE_BASE/myrepo/seedA" ]
  local main_sha_after
  main_sha_after=$(command git -C "$REAL_TMPDIR/src/myrepo" rev-parse HEAD)
  [ "$main_sha_after" = "$main_sha_before" ]
}

# 12: --delete-and-skip-checks has no short form; -d -D combo is a parse error
@test "--delete-and-skip-check (typo) is treated as unknown flag" {
  make_repo myrepo
  make_fork myrepo seedA
  cd "$GIT_WORKTREE_BASE/myrepo/seedA"
  run --separate-stderr git-fork --delete-and-skip-check
  [ "$status" -ne 0 ]
}

@test "-d -D combination is rejected as conflicting flags" {
  make_repo myrepo
  make_fork myrepo seedA
  cd "$GIT_WORKTREE_BASE/myrepo/seedA"
  run --separate-stderr git-fork -d -D
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"conflicting"* ]]
}

# 13: -d outside a worktree errors with clear message
@test "-d outside a worktree exits 1 with not-in-fork message" {
  make_repo myrepo
  cd "$REAL_TMPDIR/src/myrepo"
  run --separate-stderr git-fork -d
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"not inside a fork worktree"* ]]
}
