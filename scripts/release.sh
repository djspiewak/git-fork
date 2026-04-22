#!/usr/bin/env bash
set -euo pipefail

# Usage: release.sh [--dry-run] [--tap-dir <path>] <version>
#
# Cuts a git-fork release: tags, publishes a GitHub release, downloads the
# tarball, computes sha256, and patches the tap formula. Does NOT push the tap
# — the user does that after reviewing the printed diff.

DRY_RUN=0
TAP_DIR="${GIT_FORK_TAP_DIR:-$HOME/Development/homebrew-tap}"
VERSION=""
TARBALL_TMPDIR=""
trap '[ -n "${TARBALL_TMPDIR:-}" ] && rm -rf "$TARBALL_TMPDIR"' EXIT

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)   DRY_RUN=1 ;;
    --tap-dir)   shift; TAP_DIR="$1" ;;
    -*)          echo "release.sh: unknown flag: $1" >&2; exit 1 ;;
    *)           VERSION="$1" ;;
  esac
  shift
done

if [[ -z "$VERSION" ]]; then
  echo "usage: release.sh [--dry-run] [--tap-dir <path>] <version>" >&2
  exit 1
fi

TAG="v${VERSION}"
REPO="djspiewak/git-fork"
TARBALL_URL="https://github.com/${REPO}/archive/refs/tags/${TAG}.tar.gz"
FORMULA="${TAP_DIR}/Formula/git-fork.rb"

die() { echo "release.sh: $*" >&2; exit 1; }
info() { echo "==> $*"; }
dry() { echo "[dry-run] $*"; }

# --- Step 1: Preconditions ---

info "Checking preconditions..."

# Clean working tree
if ! git diff --quiet HEAD 2>/dev/null; then
  die "working tree is not clean; commit or stash changes first"
fi
if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
  die "working tree has untracked or staged changes; clean up first"
fi

# On main branch
CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
if [[ "$CURRENT_BRANCH" != "main" ]]; then
  die "must be on 'main' branch (currently on '${CURRENT_BRANCH}')"
fi

# main up-to-date with origin
git fetch origin main --quiet 2>/dev/null || echo "release.sh: warning: could not fetch from origin (proceeding with local state)" >&2
LOCAL_SHA="$(git rev-parse HEAD)"
REMOTE_SHA="$(git rev-parse origin/main 2>/dev/null)" || die "cannot resolve origin/main"
if [[ "$LOCAL_SHA" != "$REMOTE_SHA" ]]; then
  die "local main (${LOCAL_SHA:0:7}) differs from origin/main (${REMOTE_SHA:0:7}); push or pull first"
fi

# gh authenticated
gh auth status --hostname github.com > /dev/null 2>&1 || die "gh is not authenticated; run 'gh auth login'"

# CI green on main
info "Checking CI status on main..."
CI_STATUS="$(gh run list --workflow ci.yml --branch main --status completed --limit 1 --json conclusion --jq '.[0].conclusion' 2>/dev/null || echo "unknown")"
if [[ "$CI_STATUS" != "success" ]]; then
  die "CI is not green on main (most recent completed run: '${CI_STATUS}'). Fix CI before releasing."
fi

# --- Step 2: Tag check ---

info "Checking tag ${TAG}..."

TAG_EXISTS_LOCAL=0
TAG_EXISTS_REMOTE=0
git rev-parse "$TAG" > /dev/null 2>&1 && TAG_EXISTS_LOCAL=1
gh release view "$TAG" --repo "$REPO" > /dev/null 2>&1 && TAG_EXISTS_REMOTE=1

if [[ $TAG_EXISTS_LOCAL -eq 1 && $TAG_EXISTS_REMOTE -eq 1 ]]; then
  # Check if formula already has this version — if so, nothing to do
  if grep -qE "/tags/${TAG}\\.tar\\.gz" "$FORMULA" 2>/dev/null; then
    info "Tag, release, and formula already at ${TAG} — nothing to do."
    exit 0
  fi
  info "Tag and release exist; skipping to formula update."
elif [[ $TAG_EXISTS_LOCAL -eq 1 && $TAG_EXISTS_REMOTE -eq 0 ]]; then
  info "Local tag ${TAG} exists; will create GitHub release."
elif [[ $TAG_EXISTS_LOCAL -eq 0 && $TAG_EXISTS_REMOTE -eq 1 ]]; then
  die "Remote release ${TAG} exists but local tag is missing. Something is inconsistent."
fi

# --- Step 3: Tag ---

if [[ $TAG_EXISTS_LOCAL -eq 0 ]]; then
  if [[ $DRY_RUN -eq 1 ]]; then
    dry "git tag ${TAG}"
    dry "git push origin ${TAG}"
  else
    info "Creating tag ${TAG}..."
    git tag "$TAG"
    git push origin "$TAG"
  fi
fi

# --- Step 4: GitHub release ---

if [[ $TAG_EXISTS_REMOTE -eq 0 ]]; then
  if [[ $DRY_RUN -eq 1 ]]; then
    dry "gh release create ${TAG} --generate-notes"
    dry "release-url=https://github.com/${REPO}/releases/tag/${TAG}"
  else
    info "Creating GitHub release ${TAG}..."
    gh release create "$TAG" --generate-notes --repo "$REPO"
    info "Release created: https://github.com/${REPO}/releases/tag/${TAG}"
  fi
fi

# --- Steps 5 & 6: Download tarball, verify contents, compute sha256 ---

TARBALL_TMPDIR="$(mktemp -d)"
TARBALL_TMP="${TARBALL_TMPDIR}/tarball.tar.gz"

if [[ $DRY_RUN -eq 1 ]]; then
  dry "curl -fsSL ${TARBALL_URL} -o <tmpfile>"
  dry "tar -tzf <tmpfile>  # verify git-fork.sh and test/ present"
  dry "sha256=<computed from tarball>"
  SHA256="<placeholder-sha256>"
else
  info "Downloading tarball from ${TARBALL_URL}..."
  curl -fsSL "$TARBALL_URL" -o "$TARBALL_TMP"

  # Sanity-check: tarball must contain git-fork.sh and test/
  if ! tar -tzf "$TARBALL_TMP" | grep -q "git-fork.sh"; then
    die "tarball does not contain git-fork.sh — aborting"
  fi
  if ! tar -tzf "$TARBALL_TMP" | grep -q "test/"; then
    die "tarball does not contain test/ — aborting"
  fi

  # Compute sha256
  if command -v sha256sum > /dev/null 2>&1; then
    SHA256="$(sha256sum "$TARBALL_TMP" | awk '{print $1}')"
  elif command -v shasum > /dev/null 2>&1; then
    SHA256="$(shasum -a 256 "$TARBALL_TMP" | awk '{print $1}')"
  else
    die "no sha256sum or shasum found"
  fi
  info "sha256=${SHA256}"
fi

# --- Step 7: Patch formula ---

info "Patching formula at ${FORMULA}..."

if [[ ! -f "$FORMULA" ]]; then
  die "formula not found at ${FORMULA}"
fi

FORMULA_BEFORE="$(cat "$FORMULA")"

NEW_URL="https://github.com/${REPO}/archive/refs/tags/${TAG}.tar.gz"

if [[ $DRY_RUN -eq 1 ]]; then
  dry "formula url -> ${NEW_URL}"
  dry "formula sha256 -> ${SHA256}"
else
  awk -v new_url="$NEW_URL" -v new_sha="$SHA256" '
    /^[[:space:]]*url / { sub(/"[^"]*"/, "\"" new_url "\""); print; next }
    /^[[:space:]]*sha256 / { sub(/"[^"]*"/, "\"" new_sha "\""); print; next }
    { print }
  ' "$FORMULA" > "${FORMULA}.tmp" && mv "${FORMULA}.tmp" "$FORMULA"
fi

FORMULA_AFTER="$(cat "$FORMULA")"

# --- Step 8: Print diff and next steps ---

echo ""
echo "=== Formula diff ==="
if [[ $DRY_RUN -eq 1 ]]; then
  echo "(dry-run: showing what formula would look like)"
  echo "  url change: ${NEW_URL}"
  echo "  sha256 change: ${SHA256}"
else
  diff <(echo "$FORMULA_BEFORE") <(echo "$FORMULA_AFTER") || true
fi

echo ""
echo "=== Next steps: push the tap ==="
echo ""
echo "  cd ${TAP_DIR}"
echo "  git add Formula/git-fork.rb"
echo "  git commit -m 'git-fork ${TAG}'"
echo "  git push origin main"
echo ""
echo "Then verify with:"
echo "  brew tap djspiewak/tap"
echo "  brew install djspiewak/tap/git-fork"
echo "  brew test git-fork"
