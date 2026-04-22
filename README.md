# git-fork

Bash functions that add `git fork` as a first-class git subcommand, plus a dispatch shim that routes it through the `git` alias.

## Install

Add one line to `~/.profile` (or `~/.bashrc`):

```bash
source ~/Development/git-fork/git-fork.sh
```

## Usage

### Creating a fork

```
git fork [commitish]
```

Creates a detached worktree under `$GIT_WORKTREE_BASE` (default: `~/Development/.worktrees`), at `<repo-name>/<6-char-seed>`. Without a commitish, forks from HEAD.

### Listing worktrees

```bash
git fork --list          # worktrees for the current repo  (-l)
git fork --list --all    # worktrees for all repos          (-la)
```

Short-flag clusters work: `-la` is identical to `--list --all`.

### Jumping to a worktree

```bash
git fork --jump <seed>   # cd to the named fork
git fork -j <seed>
git fork -lj <seed>      # jump (value-taking -j must be last in cluster)
```

Looks first in the current repo's directory; falls back to a `find` across all repos if not found there. Exits 1 if ambiguous or not found.

### Removing a fork (from inside the fork)

| Command | Dirty check | Merged check | Effect |
|---|---|---|---|
| `git fork -d` / `--delete` | fail | fail | `git worktree remove` |
| `git fork -D` / `--delete-unmerged` | fail | skipped | `git worktree remove` |
| `git fork --delete-and-skip-checks` | skipped | skipped | `git worktree remove -f` |

`-d` and `-D` refuse to remove a worktree that has uncommitted changes; the error message names `--delete-and-skip-checks` as the escape hatch. `-d` also refuses if the fork's HEAD has not been merged into the main branch; use `-D` to delete without merging.

`--delete-and-skip-checks` has no short form deliberately — it is the nuclear option.

### Merging a fork (from inside the fork)

```bash
git fork -m [<git-merge-flags>...]
git fork --merge [<git-merge-flags>...]
```

Merges the fork's HEAD into the main branch then removes the worktree. Additional flags are forwarded to `git merge` (e.g. `--no-ff`). On merge conflict the worktree is left intact and the main repo is left in the mid-merge state for you to resolve.

Refuses to run if the worktree is dirty; commit or stash your changes first.

### Hooks

`git fork` looks for executable scripts in `.git/hooks/` and runs them at key points in the lifecycle. If a hook exits non-zero the operation continues and a warning is printed to stderr.

| Hook | When | cwd |
|---|---|---|
| `fork-post-create` | after `git worktree add` and built-in submodule init | new worktree |
| `fork-pre-delete` | after safety checks pass, before `git worktree remove` (`-d` and `-D` only) | fork worktree |
| `fork-post-merge` | after a successful `git merge`, before `git worktree remove` | main repo root |

`--delete-and-skip-checks` skips `fork-pre-delete` by design — it is the nuclear option.

Note: `fork-pre-delete` fires before the removal is attempted; if `git worktree remove` subsequently fails, the hook has already run.

#### Environment variables

Every hook receives:

| Variable | Value |
|---|---|
| `GIT_FORK_WORKTREE` | absolute path of the fork worktree |
| `GIT_FORK_MAIN` | absolute path of the main repo root |
| `GIT_FORK_SEED` | the 6-char seed (basename of the worktree) |
| `GIT_FORK_SHA` | HEAD SHA at the moment of the hook (for `fork-post-merge`: the fork's pre-merge HEAD, i.e. the SHA merged in) |

#### `core.hooksPath`

`git fork` resolves hook paths with `git rev-parse --git-path`, so `core.hooksPath` is respected automatically. Repos that want versioned hooks can set:

```bash
git config core.hooksPath .hooks
```

and check the scripts into the tree. In a linked worktree the hook resolves through the common dir, so the file lives once in the main repo.

#### Example

```bash
cat > .git/hooks/fork-post-create << 'EOF'
#!/usr/bin/env bash
npm install
cp .env.example .env
EOF
chmod +x .git/hooks/fork-post-create
```

#### Built-in submodule init

`git fork` always runs `git submodule init && git submodule update` immediately before `fork-post-create`. A failure is tolerated (same `|| :` semantics as before). The hook can rely on submodule directories already being present.

### Short-flag cluster rule

A cluster is a single token starting with `-` where the second character is not `-` and the token is at least 3 characters long (e.g. `-la`). Value-taking flags (`-j`) must appear last in a cluster; `-jl` is a parse error.

Valid: `-la`, `-lj <seed>`  
Invalid: `-jl <seed>` (parse error)

### Mutual exclusion

Delete/merge flags (`-d`, `-D`, `--delete-and-skip-checks`, `-m`) are mutually exclusive with each other and with listing/jumping flags (`-l`, `-a`, `-j`).

## Notes

**macOS and Linux.** The timestamp formatting in `git-fork-show-worktrees` uses `__git_fork_mtime`, which tries BSD `stat -f "%Sm"` first (macOS) then falls back to GNU `stat -c "%y"` (Linux). If both fail it prints `unknown`.

**Alias override.** Sourcing this file sets `alias git="__git__"`. This overrides any pre-existing `git` alias (e.g. from `hub` or `gh`). If you rely on another git wrapper, source this file first and alias-chain as needed.

**`git unfork` is gone.** The `git-unfork` command has been removed; its functionality is now under `git fork -d`, `-D`, `--delete-and-skip-checks`, and `-m`. Running `git unfork` falls through to real git, which prints an "unknown command" error.

## License

Apache-2.0

## Running tests

```bash
brew install bats-core   # if not already installed
bin/test
```

Tests are fully isolated: each test creates its own temp repos under `$BATS_TEST_TMPDIR` and never touches `~/Development/` or `~/.worktrees`.
