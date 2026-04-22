bats_require_minimum_version 1.5.0
load 'helpers'

# 1: -la ≡ --list --all
@test "-la is equivalent to --list --all" {
  make_repo repo1
  make_repo repo2
  make_fork repo1 seedA
  make_fork repo2 seedB
  cd "$REAL_TMPDIR/src/repo1"
  run git-fork -la
  [ "$status" -eq 0 ]
  # All-mode output contains repo names as headers
  [[ "$output" == *"repo1"* || "$output" == *"repo2"* ]]
}

# 2: -lj <seed> jumps to the seed's worktree
@test "-lj seedA jumps to seedA worktree" {
  make_repo myrepo
  make_fork myrepo seedA
  cd "$REAL_TMPDIR/src/myrepo"
  git-fork -lj seedA
  [ "$PWD" = "$GIT_WORKTREE_BASE/myrepo/seedA" ]
}

# 3: -jl errors with flag name and must be last
@test "-jl seedA errors: -j must be last in cluster" {
  make_repo myrepo
  make_fork myrepo seedA
  cd "$REAL_TMPDIR/src/myrepo"
  run --separate-stderr git-fork -jl seedA
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"-j"* ]]
  [[ "$stderr" == *"must be last"* ]]
}

# 4: -ld parses as -l -d and the mutual-exclusion validator rejects it
@test "-ld is rejected by mutual-exclusion validator" {
  make_repo myrepo
  make_fork myrepo seedA
  cd "$GIT_WORKTREE_BASE/myrepo/seedA"
  run --separate-stderr git-fork -ld
  [ "$status" -ne 0 ]
}

# 5: -- terminates flag parsing
@test "-- stops flag parsing; subsequent tokens treated as positional" {
  make_repo myrepo
  cd "$REAL_TMPDIR/src/myrepo"
  local head_sha
  head_sha=$(command git -C "$REAL_TMPDIR/src/myrepo" rev-parse HEAD)
  git-fork -- "$head_sha"
  [[ "$PWD" == "$GIT_WORKTREE_BASE/myrepo/"* ]]
}
