bats_require_minimum_version 1.5.0
load 'helpers'

# U1: -la expands to -l -a
@test "_git_fork_parse_cluster -la produces -l and -a" {
  run _git_fork_parse_cluster "-la"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "-l" ]
  [ "${lines[1]}" = "-a" ]
}

# U2: -lj is valid (value-taking flag -j last)
@test "_git_fork_parse_cluster -lj produces -l and -j" {
  run _git_fork_parse_cluster "-lj"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "-l" ]
  [ "${lines[1]}" = "-j" ]
}

# U3: -jl is invalid (-j mid-cluster)
@test "_git_fork_parse_cluster -jl errors with flag name and must be last" {
  run --separate-stderr _git_fork_parse_cluster "-jl"
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"-j"* ]]
  [[ "$stderr" == *"must be last"* ]]
}

# U4: -ladj produces -l -a -d -j (many flags, value-taking last)
@test "_git_fork_parse_cluster -ladj produces four flags" {
  run _git_fork_parse_cluster "-ladj"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "-l" ]
  [ "${lines[1]}" = "-a" ]
  [ "${lines[2]}" = "-d" ]
  [ "${lines[3]}" = "-j" ]
}

# U5: _git_fork_is_dirty returns 0 on dirty repo, 1 on clean
@test "_git_fork_is_dirty returns 0 for a repo with uncommitted changes" {
  make_repo myrepo
  echo "dirty" > "$REAL_TMPDIR/src/myrepo/untracked.txt"
  _git_fork_is_dirty "$REAL_TMPDIR/src/myrepo"
  [ "$?" -eq 0 ]
}

@test "_git_fork_is_dirty returns 1 for a clean repo" {
  make_repo myrepo
  run _git_fork_is_dirty "$REAL_TMPDIR/src/myrepo"
  [ "$status" -eq 1 ]
}

# U6: _git_fork_is_merged
@test "_git_fork_is_merged returns 0 when fork sha is ancestor of main HEAD" {
  make_repo myrepo
  local main_sha
  main_sha=$(command git -C "$REAL_TMPDIR/src/myrepo" rev-parse HEAD)
  _git_fork_is_merged "$main_sha" "$REAL_TMPDIR/src/myrepo"
  [ "$?" -eq 0 ]
}

@test "_git_fork_is_merged returns 1 when fork has commits ahead of main" {
  make_repo myrepo
  make_fork myrepo seedA
  command git -C "$GIT_WORKTREE_BASE/myrepo/seedA" config user.email "test@example.com"
  command git -C "$GIT_WORKTREE_BASE/myrepo/seedA" config user.name "Test User"
  command git -C "$GIT_WORKTREE_BASE/myrepo/seedA" commit --allow-empty -q -m "fork commit"
  local fork_sha
  fork_sha=$(command git -C "$GIT_WORKTREE_BASE/myrepo/seedA" rev-parse HEAD)
  run _git_fork_is_merged "$fork_sha" "$REAL_TMPDIR/src/myrepo"
  [ "$status" -eq 1 ]
}

@test "_git_fork_is_merged returns non-zero on a bogus sha" {
  make_repo myrepo
  run _git_fork_is_merged "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef" "$REAL_TMPDIR/src/myrepo"
  [ "$status" -ne 0 ]
}
