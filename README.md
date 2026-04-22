# git-fork

Bash functions that add `git fork` and `git unfork` as first-class git subcommands, plus a dispatch shim that routes them through the `git` alias.

## Install

Add one line to `~/.profile` (or `~/.bashrc`):

```bash
source ~/Development/git-fork/git-fork.sh
```

## Usage

```
git fork [--list [-a|--all]] [--jump|-j <seed>] [commitish]
```

Creates a detached worktree under `$GIT_WORKTREE_BASE` (default: `~/Development/.worktrees`), at `<repo-name>/<6-char-seed>`. Without a commitish, forks from HEAD.

```
git unfork [--merge [<git-merge-flags>...]]
```

Run from inside a fork. Returns you to the main repo root and removes the worktree. `--merge` fast-forwards the base branch to the fork's HEAD; additional flags (e.g. `--no-ff`) are forwarded to `git merge`.

### Listing worktrees

```bash
git fork --list          # worktrees for the current repo
git fork --list --all    # worktrees for all repos in $GIT_WORKTREE_BASE
```

### Jumping to a worktree

```bash
git fork --jump <seed>   # cd to the named fork
git fork -j <seed>
```

Looks first in the current repo's directory; falls back to a `find` across all repos if not found there. Exits 1 if ambiguous or not found.

## Notes

**macOS only.** The timestamp formatting in `git-fork-show-worktrees` uses `stat -f "%Sm"` (BSD syntax). It will not work on Linux without modification.

**Alias override.** Sourcing this file sets `alias git="__git__"`. This overrides any pre-existing `git` alias (e.g. from `hub` or `gh`). If you rely on another git wrapper, source this file first and alias-chain as needed.

## Running tests

```bash
brew install bats-core   # if not already installed
bin/test
```

Tests are fully isolated: each test creates its own temp repos under `$BATS_TEST_TMPDIR` and never touches `~/Development/` or `~/.worktrees`.
