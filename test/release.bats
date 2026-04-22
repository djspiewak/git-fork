load 'helpers'

# Fixture: fake git repo with a fake remote and stub gh.
setup_release_fixture() {
  REPO_DIR="$REAL_TMPDIR/release-repo"
  mkdir -p "$REPO_DIR"
  command git -C "$REPO_DIR" init -q
  command git -C "$REPO_DIR" config user.email "test@example.com"
  command git -C "$REPO_DIR" config user.name "Test User"
  command git -C "$REPO_DIR" commit --allow-empty -q -m "initial"
  command git -C "$REPO_DIR" checkout -q -B main

  # Fake remote so "up-to-date with origin" check can be satisfied.
  REMOTE_DIR="$REAL_TMPDIR/release-remote"
  command git init --bare -q "$REMOTE_DIR"
  command git -C "$REPO_DIR" remote add origin "$REMOTE_DIR"
  command git -C "$REPO_DIR" push -q origin main

  # Stub gh: prints predictable output so we can assert on it.
  GH_STUB="$REAL_TMPDIR/bin/gh"
  mkdir -p "$REAL_TMPDIR/bin"
  cat > "$GH_STUB" << 'STUB'
#!/usr/bin/env bash
# Minimal stub: auth status OK, run status always green, release create echoes URL.
case "$1 $2" in
  "auth status")    exit 0 ;;
  "run list")       echo "success" ;;
  "release create") echo "https://github.com/djspiewak/git-fork/releases/tag/$4" ;;
  "release view")   exit 1 ;;
  *)                exit 0 ;;
esac
STUB
  chmod +x "$GH_STUB"

  TAP_DIR="$REAL_TMPDIR/fake-tap"
  mkdir -p "$TAP_DIR/Formula"
  cat > "$TAP_DIR/Formula/git-fork.rb" << 'FORMULA'
class GitFork < Formula
  url "https://github.com/djspiewak/git-fork/archive/refs/tags/v0.0.0.tar.gz"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"
end
FORMULA

  export PATH="$REAL_TMPDIR/bin:$PATH"
}

@test "release.sh --dry-run 0.1.0: mentions tag v0.1.0" {
  setup_release_fixture
  local script="$BATS_TEST_DIRNAME/../scripts/release.sh"
  run bash -c "cd '$REPO_DIR' && '$script' --dry-run --tap-dir '$TAP_DIR' 0.1.0"
  [ "$status" -eq 0 ]
  [[ "$output" == *"v0.1.0"* ]]
}

@test "release.sh --dry-run 0.1.0: mentions release URL shape" {
  setup_release_fixture
  local script="$BATS_TEST_DIRNAME/../scripts/release.sh"
  run bash -c "cd '$REPO_DIR' && '$script' --dry-run --tap-dir '$TAP_DIR' 0.1.0"
  [ "$status" -eq 0 ]
  [[ "$output" == *"github.com/djspiewak/git-fork"* ]]
}

@test "release.sh --dry-run 0.1.0: mentions sha placeholder" {
  setup_release_fixture
  local script="$BATS_TEST_DIRNAME/../scripts/release.sh"
  run bash -c "cd '$REPO_DIR' && '$script' --dry-run --tap-dir '$TAP_DIR' 0.1.0"
  [ "$status" -eq 0 ]
  [[ "$output" == *"sha256"* ]]
}

@test "release.sh --dry-run 0.1.0: mentions formula diff header" {
  setup_release_fixture
  local script="$BATS_TEST_DIRNAME/../scripts/release.sh"
  run bash -c "cd '$REPO_DIR' && '$script' --dry-run --tap-dir '$TAP_DIR' 0.1.0"
  [ "$status" -eq 0 ]
  [[ "$output" == *"formula"* ]] || [[ "$output" == *"Formula"* ]]
}

@test "release.sh without version arg exits 1" {
  setup_release_fixture
  local script="$BATS_TEST_DIRNAME/../scripts/release.sh"
  run bash -c "cd '$REPO_DIR' && '$script' --dry-run --tap-dir '$TAP_DIR'"
  [ "$status" -eq 1 ]
}
