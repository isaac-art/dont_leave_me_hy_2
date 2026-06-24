#!/usr/bin/env bash
#
# Builds Libbox.xcframework (sing-box for iOS/Apple) and drops it next to this script.
#
# ⚠️  RUN THIS ON macOS. It needs Xcode (xcodebuild / xcrun) and Go. It CANNOT run on
#     Linux — gomobile cross-compiles to arm64-apple-ios and the .xcframework is
#     assembled with Apple-only tooling.
#
# Resumable: clones, module downloads and compiles are all cached, and each network
# step is retried, so a timeout partway through picks up where it left off instead of
# starting over. Just re-run it.
#
# Usage:
#   ./build-libbox.sh                 # sing-box v1.13.13 (matches the Swift glue), iPhone + Simulator
#   LIBBOX_PLATFORM=ios ./build-libbox.sh        # device-only (fastest)
#   SINGBOX_REF=v1.13.14 ./build-libbox.sh       # override the pinned sing-box tag
#
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
work="${LIBBOX_WORKDIR:-$HOME/.cache/hy2-libbox}"
# Pin to the stable sing-box release whose Libbox API matches the Swift glue in
# Tunnel/PlatformInterface.swift + PacketTunnelProvider.swift. Do NOT use the default
# `testing` branch — its API differs and the app won't compile.
ref="${SINGBOX_REF:-v1.13.13}"
platform="${LIBBOX_PLATFORM:-ios,iossimulator}"

# ---- preflight ---------------------------------------------------------------
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "ERROR: must run on macOS (needs Xcode). This host is $(uname -s)." >&2
  exit 1
fi
command -v xcodebuild >/dev/null || { echo "ERROR: Xcode not found (install Xcode + 'xcode-select --install')." >&2; exit 1; }
command -v go >/dev/null         || { echo "ERROR: Go not found. Run: brew install go" >&2; exit 1; }
command -v git >/dev/null        || { echo "ERROR: git not found." >&2; exit 1; }
export PATH="$PATH:$(go env GOPATH)/bin"
# proxy.golang.org / sum.golang.org are Google-hosted and unreachable behind the GFW.
# Default to goproxy.cn (works in China AND globally) + the China-accessible sum mirror.
# Override by exporting GOPROXY / GOSUMDB yourself if you don't need this.
export GOPROXY="${GOPROXY:-https://goproxy.cn,direct}"
export GOSUMDB="${GOSUMDB:-sum.golang.google.cn}"
echo "    GOPROXY=$GOPROXY"

# ---- helpers -----------------------------------------------------------------
# Retry a command up to 6 times with backoff (for flaky network steps).
retry() {
  local n=0 max=6
  until "$@"; do
    n=$((n+1))
    if [[ $n -ge $max ]]; then echo "  ✗ giving up after $max attempts: $*" >&2; return 1; fi
    echo "  …step failed, retry $n/$max in 8s (progress so far is cached)"; sleep 8
  done
}

# Clone only if not already a complete repo; otherwise reuse (resume-friendly).
ensure_repo() {
  local url=$1 dir=$2 shallow=${3:-}
  if git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then
    echo "==> reusing existing clone: $dir"
    return 0
  fi
  rm -rf "$dir"   # remove any half-finished clone
  echo "==> cloning $url"
  if [[ "$shallow" == "shallow" ]]; then
    retry git clone --depth 1 "$url" "$dir"
  else
    retry git clone "$url" "$dir"
  fi
}

mkdir -p "$work"; cd "$work"

# sing-box = the engine. sing-box-for-apple = where build_libbox writes the framework.
ensure_repo https://github.com/SagerNet/sing-box.git sing-box
ensure_repo https://github.com/SagerNet/sing-box-for-apple.git sing-box-for-apple shallow

cd sing-box
if [[ -n "$ref" ]]; then
  echo "==> checking out sing-box $ref"
  retry git fetch --tags --depth 1 origin "$ref" || retry git fetch --tags
  git checkout --quiet "$ref"
fi

echo "==> installing SagerNet's gomobile fork (cached after first run)"
if ! command -v gomobile >/dev/null; then
  retry make lib_install
else
  echo "    gomobile already installed, skipping"
fi

# Pre-download all Go modules first, with retries. This is the part that usually
# times out; once cached in ~/go/pkg/mod it never re-downloads.
echo "==> downloading Go modules (~0.5-1GB once; resumes from cache)"
retry go mod download

echo "==> building Libbox.xcframework for: $platform"
echo "    (compilation is cached in \$GOCACHE — a re-run resumes, it won't recompile everything)"
retry go run ./cmd/internal/build_libbox -target apple -platform "$platform"

out="$work/sing-box-for-apple/Libbox.xcframework"
[[ -d "$out" ]] || { echo "ERROR: build did not produce $out" >&2; exit 1; }

echo "==> installing into $here/Libbox.xcframework"
rm -rf "$here/Libbox.xcframework"
cp -R "$out" "$here/Libbox.xcframework"

echo ""
echo "✅ Done: $here/Libbox.xcframework"
echo "   Open HysteriaManagerMobile.xcodeproj and build."
