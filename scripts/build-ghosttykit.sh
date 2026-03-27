#!/bin/bash
#
# build-ghosttykit.sh
#
# Builds GhosttyKit.xcframework from the ghostty git submodule and places it
# where GhosttyEmbed/Package.swift expects it.
#
# Run this once after cloning the repo (with --recursive) and again whenever
# you want to pick up a new Ghostty version:
#
#   git submodule update --remote ghostty   # advance to latest
#   ./scripts/build-ghosttykit.sh           # rebuild the framework
#
# Requirements:
#   - Zig toolchain: https://ziglang.org/download/
#     (version must match ghostty/build.zig.zon — check .zig-version if present)
#   - Xcode Command Line Tools
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GHOSTTY_DIR="$REPO_ROOT/ghostty"
XCFRAMEWORK_DEST="$GHOSTTY_DIR/macos/GhosttyKit.xcframework"

if [ ! -d "$GHOSTTY_DIR/.git" ] && [ ! -f "$GHOSTTY_DIR/.git" ]; then
  echo "error: ghostty submodule not initialised. Run:" >&2
  echo "  git submodule update --init --recursive" >&2
  exit 1
fi

if ! command -v zig &>/dev/null; then
  echo "error: zig not found in PATH." >&2
  echo "Install from https://ziglang.org/download/ or via:" >&2
  echo "  brew install zig" >&2
  exit 1
fi

echo "==> Building GhosttyKit.xcframework (this takes a few minutes)…"
cd "$GHOSTTY_DIR"
zig build \
  -Demit-xcframework=true \
  -Doptimize=ReleaseFast \
  --prefix "$GHOSTTY_DIR/macos"

if [ ! -d "$XCFRAMEWORK_DEST" ]; then
  echo "error: build finished but $XCFRAMEWORK_DEST was not created." >&2
  exit 1
fi

echo "==> Done. GhosttyKit.xcframework is at:"
echo "    $XCFRAMEWORK_DEST"
echo ""
echo "    GhosttyEmbed symlink: GhosttyEmbed/GhosttyKit.xcframework -> ../ghostty/macos/GhosttyKit.xcframework"
