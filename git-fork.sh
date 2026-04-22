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
            ts=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M" "$cur_path" 2>/dev/null || echo "unknown")
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
  local base_dir="${GIT_WORKTREE_BASE:-$HOME/Development/.worktrees}"

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
    local default_base="$HOME/Development/.worktrees"
    if [[ "$base_dir" != "$default_base" && -d "$default_base" ]]; then
      scan_dirs+=("$default_base")
    fi

    local first=1
    local -A seen
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

        if [[ -n "${seen[$dedup_key]+x}" ]]; then
          [[ -n "$main_repo" ]] && command git -C "$main_repo" worktree list --porcelain 2>/dev/null \
            | git-fork-show-worktrees "$cand"
          continue
        fi
        seen["$dedup_key"]=1

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

git-fork() {
  local list=0 list_all=0 jump_seed=""
  local positional=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help)
        echo 'usage: git fork [--list [-a|--all]] [--jump|-j <seed>] [commitish]'
        echo
        echo "Creates a new detached worktree under ${GIT_WORKTREE_BASE:-$HOME/Development/.worktrees}, pointing to commitish or HEAD if unspecified"
        echo
        echo 'Options:'
        echo '  --list, -l        List worktrees for the current repository'
        echo '  --all, -a         With --list: list worktrees for all repositories'
        echo '  --jump, -j <seed> cd to the worktree identified by seed (first column of --list)'
        return 1
        ;;
      --list|-l) list=1 ;;
      --all|-a)  list_all=1 ;;
      --jump|-j) shift; jump_seed="$1" ;;
      *)         positional+=("$1") ;;
    esac
    shift
  done

  [[ $list_all -eq 1 ]] && list=1

  if [[ -n "$jump_seed" ]]; then
    local base_dir="${GIT_WORKTREE_BASE:-$HOME/Development/.worktrees}"
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
    cd "$jump_dir"
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

  cd "$(command git rev-parse --git-common-dir)/.."

  local base="$(basename "$PWD")"
  local seed=$(LC_ALL=C tr -dc 'a-zA-Z' < /dev/urandom | head -c 6; echo)
  local dir="${GIT_WORKTREE_BASE:-$HOME/Development/.worktrees}/$base/$seed"
  mkdir -p "$dir"

  command git worktree add --detach "$dir" "$sha"
  cd "$dir"
  (command git submodule init && command git submodule update) || :
}

git-unfork() {
  if [[ "$1" == --help ]]; then
    echo 'usage: git unfork [--merge]'
    echo
    echo 'Run from a forked worktree. Returns to the base directory and removes the worktree. Merges if --merge is specified'
    return 1
  fi

  local fork_base="$(command git rev-parse --show-toplevel)"
  local sha=$(command git rev-parse HEAD)

  if [[ -f "$fork_base/.git" ]]; then
    cd "$(command git rev-parse --git-common-dir)/.."

    command git worktree remove -f "$fork_base"

    if [[ "$1" == --merge ]]; then
      shift
      command git merge "$@" "$sha"
    fi
  else
    echo "Not in worktree"
    return 1
  fi
}

# we're doing this just so I can add git commands myself
__git__() {
  if [[ "$1" == fork ]]; then
    shift
    git-fork "$@"
  elif [[ "$1" == unfork ]]; then
    shift
    git-unfork "$@"
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
