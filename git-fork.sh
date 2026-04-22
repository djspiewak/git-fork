__git_fork_mtime() {
  local ts
  if stat --version > /dev/null 2>&1; then
    ts=$(LC_ALL=C stat -c "%y" "$1" 2>/dev/null | cut -c1-16)
  else
    ts=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M" "$1" 2>/dev/null)
  fi
  echo "${ts:-unknown}"
}

# Read `git worktree list --porcelain` from stdin; print entries under repo_dir.
# Buffers all rows before printing so column widths can be computed dynamically.
git-fork-show-worktrees() {
  local repo_dir="$1"
  local cur_path="" cur_sha="" cur_branch=""
  local -a wt_names wt_slugs wt_times wt_ok
  local max_name=0 max_slug=0

  while IFS= read -r line; do
    case "$line" in
      "worktree "*)  cur_path="${line#worktree }"; cur_sha=""; cur_branch="" ;;
      "HEAD "*)      cur_sha="${line#HEAD }" ;;
      "branch "*)    cur_branch="${line#branch refs/heads/}" ;;
      "")
        if [[ -n "$cur_path" && "$cur_path" == "$repo_dir"/* ]]; then
          local wt_name="${cur_path##*/}"
          wt_names+=("$wt_name")
          [[ ${#wt_name} -gt $max_name ]] && max_name=${#wt_name}
          if [[ ! -d "$cur_path" ]]; then
            wt_slugs+=("") wt_times+=("") wt_ok+=(0)
          else
            local ts slug
            ts=$(__git_fork_mtime "$cur_path")
            [[ -n "$cur_branch" ]] && slug="$cur_branch" || slug="(${cur_sha:0:7}...)"
            wt_slugs+=("$slug") wt_times+=("$ts") wt_ok+=(1)
            [[ ${#slug} -gt $max_slug ]] && max_slug=${#slug}
          fi
        fi
        cur_path=""
        ;;
    esac
  done

  if [[ ${#wt_names[@]} -eq 0 ]]; then
    echo "  (no worktrees)"
    return
  fi

  local i
  for (( i = 0; i < ${#wt_names[@]}; i++ )); do
    local name_col
    printf -v name_col "%-${max_name}s" "${wt_names[$i]}"
    if [[ ${wt_ok[$i]} -eq 0 ]]; then
      printf "  \033[1m%s\033[0m  \033[1;31m[PROBLEM: directory not found]\033[0m\n" "$name_col"
    else
      local slug_col
      printf -v slug_col "%-${max_slug}s" "${wt_slugs[$i]}"
      printf "  \033[1m%s\033[0m  \033[33m%s\033[0m  \033[2m%s\033[0m\n" "$name_col" "$slug_col" "${wt_times[$i]}"
    fi
  done
}

git-fork-list() {
  local list_all="${1:-0}"
  local base_dir="${GIT_WORKTREE_BASE:-$HOME/.worktrees}"

  if [[ ! -d "$base_dir" ]]; then
    echo "git fork: worktrees base directory not found: $base_dir" >&2
    return 1
  fi

  if [[ "$list_all" -eq 0 ]]; then
    # Single-repo mode: use git worktree list directly, no base_dir scan.
    # No repo-name header — there is only ever one repo in this mode.
    local git_common_dir
    git_common_dir=$(command git rev-parse --git-common-dir 2>/dev/null) || {
      echo "git fork --list: not in a git repository (use --all/-a to list all)" >&2
      return 1
    }
    local repo_root
    if [[ "$git_common_dir" == /* ]]; then
      repo_root="${git_common_dir%/*}"
    else
      repo_root="$(command git rev-parse --show-toplevel 2>/dev/null)"
    fi
    local repo_name="${repo_root##*/}"
    command git -C "$repo_root" worktree list --porcelain 2>/dev/null \
      | git-fork-show-worktrees "${base_dir}/${repo_name}"
  else
    # All-repos mode: scan base_dir for non-empty repo-name dirs.
    # Also scan the default base when GIT_WORKTREE_BASE points elsewhere,
    # so forks created outside the current project context are visible.
    # base_dir may contain tens of thousands of empty abandoned seeds;
    # -not -empty skips them without descending into each one.
    local -a scan_dirs
    scan_dirs=("$base_dir")
    local default_base="$HOME/.worktrees"
    if [[ "$base_dir" != "$default_base" && -d "$default_base" ]]; then
      scan_dirs+=("$default_base")
    fi

    local first=1
    local -a _seen_keys=()
    for scan_dir in "${scan_dirs[@]}"; do
      while IFS= read -r cand; do
        local git_file main_repo=""
        git_file=$(command find "$cand" -maxdepth 2 -type f -name ".git" -print -quit 2>/dev/null)
        if [[ -n "$git_file" ]]; then
          local common_dir
          common_dir=$(command git -C "${git_file%/.git}" rev-parse --git-common-dir 2>/dev/null) || true
          [[ "$common_dir" == /* ]] && main_repo="${common_dir%/*}"
        fi

        local dedup_key
        if [[ -n "$main_repo" ]]; then
          dedup_key="$main_repo"
        else
          dedup_key=$(cd "$cand" && pwd -P 2>/dev/null) || dedup_key="$cand"
        fi

        local _found=0 _sk
        for _sk in "${_seen_keys[@]}"; do
          [[ "$_sk" == "$dedup_key" ]] && { _found=1; break; }
        done
        if [[ $_found -eq 1 ]]; then
          [[ -n "$main_repo" ]] && command git -C "$main_repo" worktree list --porcelain 2>/dev/null \
            | git-fork-show-worktrees "$cand"
          continue
        fi
        _seen_keys+=("$dedup_key")

        local repo_name="${cand##*/}"
        [[ $first -eq 0 ]] && echo
        first=0
        echo "$repo_name"

        if [[ -n "$main_repo" ]]; then
          command git -C "$main_repo" worktree list --porcelain 2>/dev/null \
            | git-fork-show-worktrees "$cand"
        else
          echo "  (no active worktrees found)"
        fi
      done < <(command find "$scan_dir" -maxdepth 1 -mindepth 1 -type d -not -empty 2>/dev/null)
    done

    [[ $first -eq 1 ]] && echo "(no repositories with worktrees found)"
    return 0
  fi
}

# Expand a short-flag cluster token like -la into -l -a (one flag per line).
# Value-taking flags (-j) must be last in a cluster; otherwise returns 1.
_git_fork_parse_cluster() {
  local token="$1"
  local stripped="${token#-}"
  if [[ ! "$stripped" =~ ^[a-zA-Z]+$ ]]; then
    echo "git fork: invalid cluster '$token': only letters allowed in short-flag clusters" >&2
    return 1
  fi
  local i=0 len=${#stripped} ch
  local -a out=()
  while (( i < len )); do
    ch="${stripped:i:1}"
    case "$ch" in
      j)
        if (( i != len - 1 )); then
          echo "git fork: flag -$ch takes a value and must be last in a cluster: $token" >&2
          return 1
        fi
        ;;
    esac
    out+=("-$ch")
    (( i++ )) || true
  done
  printf '%s\n' "${out[@]}"
}

# Echoes the worktree root if inside a linked worktree (.git is a file), or returns 1.
_git_fork_worktree_root() {
  local root
  root=$(command git rev-parse --show-toplevel 2>/dev/null) || return 1
  [[ -f "$root/.git" ]] || return 1
  echo "$root"
}

# Echoes the canonical main repo root, or returns 1.
_git_fork_main_repo_root() {
  local common_dir
  common_dir=$(command git rev-parse --git-common-dir 2>/dev/null) || return 1
  (cd "${common_dir}/.." && pwd -P) 2>/dev/null
}

# Returns 0 if the given directory has uncommitted or untracked changes.
_git_fork_is_dirty() {
  local dir="$1"
  local status_out
  status_out=$(command git -C "$dir" status --porcelain 2>/dev/null)
  [[ -n "$status_out" ]]
}

# Returns 0 if fork_sha is an ancestor of HEAD in main_repo_root.
_git_fork_is_merged() {
  local fork_sha="$1"
  local main_repo_root="$2"
  command git -C "$main_repo_root" merge-base --is-ancestor "$fork_sha" HEAD 2>/dev/null
}

# _git_fork_run_hook <phase> <worktree> <main_root> <seed> <sha>
# Looks up hooks/fork-<phase> (honoring core.hooksPath), executes it
# with GIT_FORK_* env vars. Warns on non-zero exit. Always returns 0.
_git_fork_run_hook() {
  local phase="$1" worktree="$2" main_root="$3" seed="$4" sha="$5"
  local hook_path
  hook_path=$(command git -C "$main_root" rev-parse --git-path "hooks/fork-$phase" 2>/dev/null) || return 0
  [[ "$hook_path" != /* ]] && hook_path="$main_root/$hook_path"
  [[ -x "$hook_path" ]] || return 0
  local rc=0
  GIT_FORK_WORKTREE="$worktree" \
  GIT_FORK_MAIN="$main_root" \
  GIT_FORK_SEED="$seed" \
  GIT_FORK_SHA="$sha" \
    "$hook_path" || rc=$?
  if [[ $rc -ne 0 ]]; then
    echo "git fork: hook 'fork-$phase' exited $rc (continuing)" >&2
  fi
  return 0
}

git-fork() {
  local list=0 list_all=0 jump_seed=""
  local delete_mode=""
  local -a merge_passthrough=()
  local -a positional=()

  while [[ $# -gt 0 ]]; do
    # Short-flag cluster expansion: leading -, second char not -, length >= 3
    if [[ "$1" =~ ^-[^-].+ ]]; then
      local cluster_out
      cluster_out=$(_git_fork_parse_cluster "$1") || return 1
      local -a expanded=()
      while IFS= read -r _flag; do expanded+=("$_flag"); done <<< "$cluster_out"
      shift
      set -- "${expanded[@]}" "$@"
      continue
    fi

    case "$1" in
      --help|-h)
        echo 'usage: git fork [--list [-a|--all]] [--jump|-j <seed>] [commitish]'
        echo '       git fork -d|--delete'
        echo '       git fork -D|--delete-unmerged'
        echo '       git fork --delete-and-skip-checks'
        echo '       git fork -m|--merge [merge-args…]'
        echo
        echo "Creates a new detached worktree under ${GIT_WORKTREE_BASE:-$HOME/.worktrees}, pointing to commitish or HEAD if unspecified"
        echo
        echo 'Options:'
        echo '  --list, -l              List worktrees for the current repository'
        echo '  --all, -a               With --list: list worktrees for all repositories'
        echo '  --jump, -j <seed>       cd to the worktree identified by seed (first column of --list)'
        echo '  -d, --delete            Remove this worktree (fails if dirty or unmerged)'
        echo '  -D, --delete-unmerged   Remove this worktree (fails if dirty; skips merged check)'
        echo '  --delete-and-skip-checks  Force-remove worktree (skips all safety checks)'
        echo '  -m, --merge [args…]     Merge fork into main then remove worktree; passes remaining args to git merge'
        echo
        echo 'Short-flag cluster rule: value-taking flags (-j) must be last in a cluster.'
        echo '  Valid: -la, -lj <seed>   Invalid: -jl <seed>'
        echo
        echo 'Delete/merge flags are mutually exclusive with -l/-a/-j and with each other.'
        echo 'Dirty-check failures name --delete-and-skip-checks as the escape hatch.'
        return 0
        ;;
      --list|-l)   list=1 ;;
      --all|-a)    list_all=1 ;;
      --jump|-j)   shift; jump_seed="$1" ;;
      --delete|-d)
        if [[ -n "$delete_mode" ]]; then
          echo "git fork: conflicting delete/merge flags" >&2
          return 1
        fi
        delete_mode="d"
        ;;
      --delete-unmerged|-D)
        if [[ -n "$delete_mode" ]]; then
          echo "git fork: conflicting delete/merge flags" >&2
          return 1
        fi
        delete_mode="D"
        ;;
      --delete-and-skip-checks)
        if [[ -n "$delete_mode" ]]; then
          echo "git fork: conflicting delete/merge flags" >&2
          return 1
        fi
        delete_mode="skip"
        ;;
      --merge|-m)
        if [[ -n "$delete_mode" ]]; then
          echo "git fork: conflicting delete/merge flags" >&2
          return 1
        fi
        delete_mode="m"
        shift
        while [[ $# -gt 0 ]]; do
          merge_passthrough+=("$1")
          shift
        done
        continue
        ;;
      --)
        shift
        while [[ $# -gt 0 ]]; do
          positional+=("$1")
          shift
        done
        continue
        ;;
      -*)
        echo "git fork: unknown flag: $1" >&2
        return 1
        ;;
      *)           positional+=("$1") ;;
    esac
    shift
  done

  [[ $list_all -eq 1 ]] && list=1

  if [[ -n "$delete_mode" ]]; then
    if [[ $list -eq 1 || $list_all -eq 1 || -n "$jump_seed" || ${#positional[@]} -gt 0 ]]; then
      echo "git fork: delete/merge flags cannot be combined with --list, --all, --jump, or positional args" >&2
      return 1
    fi

    local worktree_root main_root fork_sha seed

    worktree_root=$(_git_fork_worktree_root) || {
      echo "git fork: not inside a fork worktree" >&2
      return 1
    }
    main_root=$(_git_fork_main_repo_root) || {
      echo "git fork: could not locate main repo root" >&2
      return 1
    }
    seed="${worktree_root##*/}"

    if [[ "$delete_mode" != "skip" ]]; then
      if _git_fork_is_dirty "$worktree_root"; then
        echo "git fork: uncommitted changes in worktree; commit/stash first, or pass --delete-and-skip-checks to force" >&2
        return 1
      fi
    fi

    case "$delete_mode" in
      d)
        fork_sha=$(command git rev-parse HEAD 2>/dev/null) || {
          echo "git fork: cannot resolve fork HEAD" >&2
          return 1
        }
        if ! _git_fork_is_merged "$fork_sha" "$main_root"; then
          echo "git fork: fork HEAD $fork_sha not merged into main; use -D (--delete-unmerged) to override" >&2
          return 1
        fi
        cd "$worktree_root" || { echo "git fork: cannot cd to fork worktree" >&2; return 1; }
        _git_fork_run_hook pre-delete "$worktree_root" "$main_root" "$seed" "$fork_sha"
        cd "$main_root" || { echo "git fork: cannot cd to main repo root" >&2; return 1; }
        command git worktree remove "$worktree_root"
        ;;
      D)
        fork_sha=$(command git rev-parse HEAD 2>/dev/null) || {
          echo "git fork: cannot resolve fork HEAD" >&2
          return 1
        }
        cd "$worktree_root" || { echo "git fork: cannot cd to fork worktree" >&2; return 1; }
        _git_fork_run_hook pre-delete "$worktree_root" "$main_root" "$seed" "$fork_sha"
        cd "$main_root" || { echo "git fork: cannot cd to main repo root" >&2; return 1; }
        command git worktree remove "$worktree_root"
        ;;
      skip)
        cd "$main_root" || { echo "git fork: cannot cd to main repo root" >&2; return 1; }
        command git worktree remove -f "$worktree_root"
        ;;
      m)
        fork_sha=$(command git rev-parse HEAD 2>/dev/null) || {
          echo "git fork: cannot resolve fork HEAD" >&2
          return 1
        }
        cd "$main_root" || { echo "git fork: cannot cd to main repo root" >&2; return 1; }
        if ! command git merge "${merge_passthrough[@]}" "$fork_sha"; then
          echo "git fork -m: merge failed; worktree left intact" >&2
          return 1
        fi
        _git_fork_run_hook post-merge "$worktree_root" "$main_root" "$seed" "$fork_sha"
        command git worktree remove "$worktree_root"
        ;;
    esac
    return
  fi

  if [[ -n "$jump_seed" ]]; then
    local base_dir="${GIT_WORKTREE_BASE:-$HOME/.worktrees}"
    local jump_dir=""

    local git_common_dir
    git_common_dir=$(command git rev-parse --git-common-dir 2>/dev/null) || true
    if [[ -n "$git_common_dir" ]]; then
      local repo_root
      if [[ "$git_common_dir" == /* ]]; then
        repo_root="${git_common_dir%/*}"
      else
        repo_root="$(command git rev-parse --show-toplevel 2>/dev/null)"
      fi
      local repo_name="${repo_root##*/}"
      local candidate="$base_dir/$repo_name/$jump_seed"
      [[ -d "$candidate" ]] && jump_dir="$candidate"
    fi

    if [[ -z "$jump_dir" ]]; then
      local -a matches=()
      while IFS= read -r d; do
        matches+=("$d")
      done < <(command find "$base_dir" -maxdepth 2 -mindepth 2 -type d -name "$jump_seed" 2>/dev/null)
      if [[ ${#matches[@]} -eq 1 ]]; then
        jump_dir="${matches[0]}"
      elif [[ ${#matches[@]} -gt 1 ]]; then
        echo "git fork --jump: ambiguous seed '$jump_seed' matches multiple worktrees:" >&2
        printf '  %s\n' "${matches[@]}" >&2
        return 1
      fi
    fi

    if [[ -z "$jump_dir" ]]; then
      echo "git fork --jump: worktree not found: $jump_seed" >&2
      return 1
    fi
    cd "$jump_dir" || { echo "git fork --jump: cannot cd to $jump_dir" >&2; return 1; }
    return 0
  fi

  if [[ $list -eq 1 ]]; then
    git-fork-list "$list_all"
    return $?
  fi

  local sha
  if [[ ${#positional[@]} -gt 0 ]]; then
    sha="${positional[0]}"
  else
    sha=$(command git rev-parse --verify HEAD 2>/dev/null) || {
      echo "git fork: cannot fork an unborn repository (no commits yet)" >&2
      return 1
    }
  fi

  local main_root
  main_root=$(_git_fork_main_repo_root) || {
    echo "git fork: could not locate main repo root" >&2
    return 1
  }
  cd "$main_root" || { echo "git fork: cannot cd to main repo root" >&2; return 1; }

  local base
  base=$(basename "$main_root")
  local seed
  seed=$(LC_ALL=C head -c 128 /dev/urandom | LC_ALL=C tr -dc 'a-zA-Z' | head -c 6)
  local dir="${GIT_WORKTREE_BASE:-$HOME/.worktrees}/$base/$seed"
  mkdir -p "$dir"

  command git worktree add --detach "$dir" "$sha" || { rmdir "$dir" "${dir%/*}" 2>/dev/null; return 1; }
  cd "$dir" || { echo "git fork: cannot cd to new worktree" >&2; return 1; }
  local fork_sha
  fork_sha=$(command git rev-parse HEAD 2>/dev/null) || fork_sha=""
  (command git submodule init && command git submodule update) || :
  _git_fork_run_hook post-create "$dir" "$main_root" "$seed" "$fork_sha"
}

# we're doing this just so I can add git commands myself
__git__() {
  if [[ "$1" == fork ]]; then
    shift
    git-fork "$@"
  else
    if [[ $# -gt 0 ]]; then
      $(which git) "$@"
      return $?
    else
      $(which git)
      return $?
    fi
  fi
}

alias git="__git__"
