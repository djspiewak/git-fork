load 'helpers'

# Feed canned porcelain via heredoc to git-fork-show-worktrees.

@test "empty input prints (no worktrees)" {
  run git-fork-show-worktrees "/base/repo" <<< ""
  [ "$status" -eq 0 ]
  [[ "$output" == *"(no worktrees)"* ]]
}

@test "entry outside repo_dir is filtered out" {
  local repo_dir="$REAL_TMPDIR/worktrees/myrepo"
  run git-fork-show-worktrees "$repo_dir" << 'EOF'
worktree /some/other/path/seed1
HEAD abcdef1234567890abcdef1234567890abcdef12
branch refs/heads/main

EOF
  [ "$status" -eq 0 ]
  [[ "$output" == *"(no worktrees)"* ]]
}

@test "branch entry shows branch name as slug" {
  local repo_dir="$REAL_TMPDIR/worktrees/myrepo"
  local wt_dir="$repo_dir/seedA"
  mkdir -p "$wt_dir"
  run git-fork-show-worktrees "$repo_dir" << EOF
worktree $wt_dir
HEAD abcdef1234567890abcdef1234567890abcdef12
branch refs/heads/feature-x

EOF
  [ "$status" -eq 0 ]
  [[ "$output" == *"feature-x"* ]]
  [[ "$output" != *"abcdef1"* ]]
}

@test "detached entry shows sha prefix slug" {
  local repo_dir="$REAL_TMPDIR/worktrees/myrepo"
  local wt_dir="$repo_dir/seedB"
  mkdir -p "$wt_dir"
  run git-fork-show-worktrees "$repo_dir" << EOF
worktree $wt_dir
HEAD 1234567890abcdef1234567890abcdef12345678

EOF
  [ "$status" -eq 0 ]
  [[ "$output" == *"(1234567...)"* ]]
}

@test "missing directory prints PROBLEM line without timestamp column" {
  local repo_dir="$REAL_TMPDIR/worktrees/myrepo"
  run git-fork-show-worktrees "$repo_dir" << EOF
worktree $repo_dir/nonexistent
HEAD abcdef1234567890abcdef1234567890abcdef12
branch refs/heads/main

EOF
  [ "$status" -eq 0 ]
  [[ "$output" == *"[PROBLEM: directory not found]"* ]]
  [[ "$output" != *"[PROBLEM"*"20"* ]]  # no timestamp
}

@test "ANSI bold escape present in output" {
  local repo_dir="$REAL_TMPDIR/worktrees/myrepo"
  local wt_dir="$repo_dir/seedC"
  mkdir -p "$wt_dir"
  actual=$(git-fork-show-worktrees "$repo_dir" << EOF
worktree $wt_dir
HEAD abcdef1234567890abcdef1234567890abcdef12
branch refs/heads/main

EOF
)
  [[ "$actual" == *$'\033[1m'* ]]
}

@test "dynamic column width: names padded to longest" {
  local repo_dir="$REAL_TMPDIR/worktrees/myrepo"
  local short_dir="$repo_dir/ab"
  local long_dir="$repo_dir/alongername"
  mkdir -p "$short_dir" "$long_dir"
  run git-fork-show-worktrees "$repo_dir" << EOF
worktree $short_dir
HEAD aaaa1234567890abcdef1234567890abcdef1234
branch refs/heads/x

worktree $long_dir
HEAD bbbb1234567890abcdef1234567890abcdef1234
branch refs/heads/y

EOF
  [ "$status" -eq 0 ]
  # Both lines should have the same-width name field (padded to "alongername" width)
  local line1 line2
  line1=$(echo "$output" | grep "ab ")
  line2=$(echo "$output" | grep "alongername")
  # line1's name field should be padded to match "alongername" (10 chars)
  [[ "$line1" == *"ab        "* ]]
}

# --- __git_fork_mtime unit tests ---

@test "__git_fork_mtime: system stat returns well-formed timestamp" {
  local tmp_file="$REAL_TMPDIR/mtime_test_file"
  touch "$tmp_file"
  local result
  result=$(__git_fork_mtime "$tmp_file")
  [[ "$result" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}$ ]]
}

@test "__git_fork_mtime: GNU branch returns well-formed timestamp when BSD stat fails" {
  local tmp_file="$REAL_TMPDIR/mtime_gnu_test_file"
  touch "$tmp_file"
  # Shadow stat so -f form fails (GNU has no -f) but -c form succeeds.
  stat() {
    for a in "$@"; do [[ "$a" == "-f" ]] && return 1; done
    echo "2024-03-15 10:30:45.123456789 +0000"
  }
  export -f stat
  local result
  result=$(__git_fork_mtime "$tmp_file")
  unset -f stat
  [[ "$result" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}$ ]]
}

@test "__git_fork_mtime: returns 'unknown' and no stderr when both stat forms fail" {
  local tmp_file="$REAL_TMPDIR/mtime_fail_test_file"
  touch "$tmp_file"
  # Shadow stat to always fail.
  stat() { return 1; }
  export -f stat
  local result stderr_output
  result=$(__git_fork_mtime "$tmp_file" 2>"$REAL_TMPDIR/mtime_stderr_$$")
  stderr_output=$(cat "$REAL_TMPDIR/mtime_stderr_$$"; rm -f "$REAL_TMPDIR/mtime_stderr_$$")
  unset -f stat
  [[ "$result" == "unknown" ]]
  [[ -z "$stderr_output" ]]
}

@test "mixed ok and broken entries both rendered" {
  local repo_dir="$REAL_TMPDIR/worktrees/myrepo"
  local ok_dir="$repo_dir/goodseed"
  mkdir -p "$ok_dir"
  run git-fork-show-worktrees "$repo_dir" << EOF
worktree $ok_dir
HEAD abcdef1234567890abcdef1234567890abcdef12
branch refs/heads/main

worktree $repo_dir/badseed
HEAD 1234567890abcdef1234567890abcdef12345678
branch refs/heads/broken

EOF
  [ "$status" -eq 0 ]
  [[ "$output" == *"goodseed"* ]]
  [[ "$output" == *"badseed"* ]]
  [[ "$output" == *"[PROBLEM: directory not found]"* ]]
  [[ "$output" == *"main"* ]]
}
