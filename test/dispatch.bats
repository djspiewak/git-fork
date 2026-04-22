bats_require_minimum_version 1.5.0
load 'helpers'

# The alias git="__git__" is a one-liner verified by test 1.
# Tests 2-5 exercise __git__'s routing logic directly, which is what matters.

@test "alias git is defined and points to __git__" {
  # After sourcing, git should be an alias for __git__
  # alias is not visible in subshells so check via the shopt trick
  shopt -s expand_aliases
  [[ "$(type -t __git__)" == "function" ]]
  # Verify the alias text is set
  local alias_def
  alias_def=$(alias git 2>/dev/null) || true
  [[ "$alias_def" == *"__git__"* ]]
}

@test "git fork --list routes to git-fork-list" {
  make_repo myrepo
  make_fork myrepo seedA
  cd "$REAL_TMPDIR/src/myrepo"
  run __git__ fork --list
  [ "$status" -eq 0 ]
  [[ "$output" == *"seedA"* ]]
}

@test "git unfork routes to git-unfork (not-in-worktree path)" {
  make_repo myrepo
  cd "$REAL_TMPDIR/src/myrepo"
  run __git__ unfork
  [ "$status" -eq 255 ]
  [[ "$output" == *"Not in worktree"* ]]
}

@test "git status falls through to real git" {
  make_repo myrepo
  cd "$REAL_TMPDIR/src/myrepo"
  run __git__ status
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to commit"* || "$output" == *"working tree clean"* ]]
}

@test "bare git with no args runs real git (no infinite loop)" {
  # real git with no args exits 1 and prints usage
  run __git__
  [ "$status" -eq 1 ]
  [[ "$output" == *"usage"* || "$output" == *"Usage"* ]]
}
