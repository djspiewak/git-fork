bats_require_minimum_version 1.5.0
load 'helpers'

# Write a hook that appends GIT_FORK_* env vars and cwd to <out_file>.
_install_env_hook() {
  local git_dir="$1" phase="$2" out_file="$3"
  mkdir -p "$git_dir/hooks"
  cat > "$git_dir/hooks/fork-$phase" << HOOK
#!/usr/bin/env bash
echo "WORKTREE=\$GIT_FORK_WORKTREE" >> "$out_file"
echo "MAIN=\$GIT_FORK_MAIN"         >> "$out_file"
echo "SEED=\$GIT_FORK_SEED"         >> "$out_file"
echo "SHA=\$GIT_FORK_SHA"           >> "$out_file"
pwd -P                               >> "$out_file"
HOOK
  chmod +x "$git_dir/hooks/fork-$phase"
}

# ── post-create ──────────────────────────────────────────────────────────────

@test "fork-post-create: fires with correct env and cwd" {
  make_repo myrepo
  local repo_dir="$REAL_TMPDIR/src/myrepo"
  local out="$REAL_TMPDIR/hook.out"
  _install_env_hook "$repo_dir/.git" post-create "$out"
  local expected_sha
  expected_sha=$(command git -C "$repo_dir" rev-parse HEAD)

  cd "$repo_dir"
  run git-fork
  [ "$status" -eq 0 ]
  [ -f "$out" ]

  local seed
  seed=$(grep '^SEED=' "$out" | cut -d= -f2)
  [ -n "$seed" ]

  grep -qF "WORKTREE=$GIT_WORKTREE_BASE/myrepo/$seed" "$out"
  grep -qF "MAIN=$repo_dir"                           "$out"
  grep -qF "SHA=$expected_sha"                        "$out"

  # cwd during hook == new worktree
  local last_line
  last_line=$(tail -1 "$out")
  [ "$last_line" = "$GIT_WORKTREE_BASE/myrepo/$seed" ]
}

@test "fork-post-create: missing hook is silent and create succeeds" {
  make_repo myrepo
  cd "$REAL_TMPDIR/src/myrepo"
  run git-fork
  [ "$status" -eq 0 ]
  [[ "$output" != *"hook"* ]]
}

@test "fork-post-create: non-executable hook is silent" {
  make_repo myrepo
  local repo_dir="$REAL_TMPDIR/src/myrepo"
  mkdir -p "$repo_dir/.git/hooks"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$repo_dir/.git/hooks/fork-post-create"
  # intentionally NOT chmod +x

  cd "$repo_dir"
  run git-fork
  [ "$status" -eq 0 ]
  [[ "$output" != *"ermission denied"* ]]
  [[ "$output" != *"hook"* ]]
}

@test "fork-post-create: non-zero hook exit warns on stderr and create returns 0" {
  make_repo myrepo
  local repo_dir="$REAL_TMPDIR/src/myrepo"
  mkdir -p "$repo_dir/.git/hooks"
  printf '#!/usr/bin/env bash\nexit 42\n' > "$repo_dir/.git/hooks/fork-post-create"
  chmod +x "$repo_dir/.git/hooks/fork-post-create"

  cd "$repo_dir"
  run --separate-stderr git-fork
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"hook 'fork-post-create' exited 42 (continuing)"* ]]
  local count
  count=$(command find "$GIT_WORKTREE_BASE/myrepo" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
  [ "$count" -eq 1 ]
}

@test "fork-post-create: submodule init runs before post-create hook (bad submodule tolerated)" {
  make_repo_with_bad_submodule myrepo
  local repo_dir="$REAL_TMPDIR/src/myrepo"
  local out="$REAL_TMPDIR/hook.out"
  mkdir -p "$repo_dir/.git/hooks"
  printf '#!/usr/bin/env bash\necho ran >> "%s"\n' "$out" \
    > "$repo_dir/.git/hooks/fork-post-create"
  chmod +x "$repo_dir/.git/hooks/fork-post-create"

  cd "$repo_dir"
  run git-fork
  [ "$status" -eq 0 ]
  [ -f "$out" ]
  grep -q "ran" "$out"
}

# ── pre-delete ───────────────────────────────────────────────────────────────

@test "fork-pre-delete: fires for -d (clean merged fork)" {
  make_repo myrepo
  local repo_dir="$REAL_TMPDIR/src/myrepo"
  make_fork myrepo myseed
  # fork HEAD == main HEAD so merged check passes

  local out="$REAL_TMPDIR/hook.out"
  _install_env_hook "$repo_dir/.git" pre-delete "$out"

  cd "$GIT_WORKTREE_BASE/myrepo/myseed"
  run git-fork -d
  [ "$status" -eq 0 ]
  [ -f "$out" ]
  grep -qF "SEED=myseed" "$out"
}

@test "fork-pre-delete: fires for -D (skips merged check)" {
  make_repo myrepo
  local repo_dir="$REAL_TMPDIR/src/myrepo"
  make_fork myrepo myseed

  local out="$REAL_TMPDIR/hook.out"
  _install_env_hook "$repo_dir/.git" pre-delete "$out"

  cd "$GIT_WORKTREE_BASE/myrepo/myseed"
  run git-fork -D
  [ "$status" -eq 0 ]
  [ -f "$out" ]
  grep -qF "SEED=myseed" "$out"
}

@test "fork-pre-delete: does NOT fire for --delete-and-skip-checks" {
  make_repo myrepo
  local repo_dir="$REAL_TMPDIR/src/myrepo"
  make_fork myrepo myseed

  local out="$REAL_TMPDIR/hook.out"
  _install_env_hook "$repo_dir/.git" pre-delete "$out"

  cd "$GIT_WORKTREE_BASE/myrepo/myseed"
  run git-fork --delete-and-skip-checks
  [ "$status" -eq 0 ]
  [ ! -f "$out" ]
}

@test "fork-pre-delete: cwd is fork worktree and worktree still present during hook" {
  make_repo myrepo
  local repo_dir="$REAL_TMPDIR/src/myrepo"
  make_fork myrepo myseed

  local out="$REAL_TMPDIR/hook.out"
  mkdir -p "$repo_dir/.git/hooks"
  cat > "$repo_dir/.git/hooks/fork-pre-delete" << HOOK
#!/usr/bin/env bash
pwd -P                                                  >> "$out"
[ -d "\$GIT_FORK_WORKTREE" ] && echo "worktree_present" >> "$out"
HOOK
  chmod +x "$repo_dir/.git/hooks/fork-pre-delete"

  cd "$GIT_WORKTREE_BASE/myrepo/myseed"
  run git-fork -D
  [ "$status" -eq 0 ]
  [ -f "$out" ]
  grep -qF "$GIT_WORKTREE_BASE/myrepo/myseed" "$out"
  grep -q "worktree_present" "$out"
}

# ── post-merge ───────────────────────────────────────────────────────────────

@test "fork-post-merge: fires on successful merge with correct cwd and env" {
  make_repo myrepo
  local repo_dir="$REAL_TMPDIR/src/myrepo"
  make_fork myrepo myseed

  # Add a commit to the fork so the merge is non-trivial
  local fork_dir="$GIT_WORKTREE_BASE/myrepo/myseed"
  command git -C "$fork_dir" config user.email "test@example.com"
  command git -C "$fork_dir" config user.name "Test User"
  command git -C "$fork_dir" commit --allow-empty -q -m "fork commit"
  local fork_sha
  fork_sha=$(command git -C "$fork_dir" rev-parse HEAD)

  local out="$REAL_TMPDIR/hook.out"
  _install_env_hook "$repo_dir/.git" post-merge "$out"

  cd "$fork_dir"
  run git-fork -m
  [ "$status" -eq 0 ]
  [ -f "$out" ]

  grep -qF "SEED=myseed"       "$out"
  grep -qF "MAIN=$repo_dir"    "$out"
  grep -qF "SHA=$fork_sha"     "$out"

  # cwd during hook == main repo root
  local last_line
  last_line=$(tail -1 "$out")
  [ "$last_line" = "$repo_dir" ]
}

@test "fork-post-merge: does NOT fire when merge has conflicts" {
  make_repo myrepo
  local repo_dir="$REAL_TMPDIR/src/myrepo"
  command git -C "$repo_dir" config user.email "test@example.com"
  command git -C "$repo_dir" config user.name "Test User"

  # Both branches will modify conflict.txt differently
  echo "main line" > "$repo_dir/conflict.txt"
  command git -C "$repo_dir" add conflict.txt
  command git -C "$repo_dir" commit -q -m "main: add conflict.txt"

  make_fork myrepo myseed
  local fork_dir="$GIT_WORKTREE_BASE/myrepo/myseed"

  # Main advances further (different change to same file)
  echo "updated main" > "$repo_dir/conflict.txt"
  command git -C "$repo_dir" add conflict.txt
  command git -C "$repo_dir" commit -q -m "main: update conflict.txt"

  # Fork adds conflicting change
  command git -C "$fork_dir" config user.email "test@example.com"
  command git -C "$fork_dir" config user.name "Test User"
  echo "fork line" > "$fork_dir/conflict.txt"
  command git -C "$fork_dir" add conflict.txt
  command git -C "$fork_dir" commit -q -m "fork: conflicting conflict.txt"

  local out="$REAL_TMPDIR/hook.out"
  _install_env_hook "$repo_dir/.git" post-merge "$out"

  cd "$fork_dir"
  run --separate-stderr git-fork -m
  [ "$status" -ne 0 ]
  [ ! -f "$out" ]
  # Worktree still intact
  [ -d "$fork_dir" ]
}

# ── core.hooksPath ───────────────────────────────────────────────────────────

@test "core.hooksPath: hook at custom path fires for post-create" {
  make_repo myrepo
  local repo_dir="$REAL_TMPDIR/src/myrepo"
  local custom_hooks="$REAL_TMPDIR/custom_hooks"
  mkdir -p "$custom_hooks"

  command git -C "$repo_dir" config core.hooksPath "$custom_hooks"

  local out="$REAL_TMPDIR/hook.out"
  cat > "$custom_hooks/fork-post-create" << HOOK
#!/usr/bin/env bash
echo "custom_hook_ran" >> "$out"
HOOK
  chmod +x "$custom_hooks/fork-post-create"

  cd "$repo_dir"
  run git-fork
  [ "$status" -eq 0 ]
  [ -f "$out" ]
  grep -q "custom_hook_ran" "$out"
}

@test "core.hooksPath: relative path (.hooks) resolved against main repo root" {
  make_repo myrepo
  local repo_dir="$REAL_TMPDIR/src/myrepo"
  local custom_hooks="$repo_dir/.hooks"
  mkdir -p "$custom_hooks"

  command git -C "$repo_dir" config core.hooksPath ".hooks"

  local out="$REAL_TMPDIR/hook.out"
  cat > "$custom_hooks/fork-post-create" << HOOK
#!/usr/bin/env bash
echo "relative_hook_ran" >> "$out"
HOOK
  chmod +x "$custom_hooks/fork-post-create"

  cd "$repo_dir"
  run git-fork
  [ "$status" -eq 0 ]
  [ -f "$out" ]
  grep -q "relative_hook_ran" "$out"
}
