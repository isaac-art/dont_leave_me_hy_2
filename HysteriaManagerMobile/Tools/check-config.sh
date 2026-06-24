#!/usr/bin/env bash
#
# Validate a sing-box config against the real v1.13.13 schema.
#   ./check-config.sh path/to/config.json
#
# Builds a pinned sing-box once into ~/.cache/hy2-singbox (needs Go), or uses an
# existing `sing-box` on PATH. Catches the kind of config errors that make the
# tunnel "connect" but never route.
#
set -euo pipefail
cfg="${1:?usage: check-config.sh <config.json>}"

SB="${SINGBOX_BIN:-}"
if [[ -z "$SB" ]]; then
  if command -v sing-box >/dev/null 2>&1; then
    SB="$(command -v sing-box)"
  else
    command -v go >/dev/null || { echo "need Go (brew install go) or a sing-box on PATH" >&2; exit 1; }
    GOBIN="$HOME/.cache/hy2-singbox/bin"; mkdir -p "$GOBIN"
    SB="$GOBIN/sing-box"
    if [[ ! -x "$SB" ]]; then
      echo "==> building sing-box v1.13.13 (one-time)…"
      GOBIN="$GOBIN" GOPROXY="${GOPROXY:-https://goproxy.cn,direct}" GOSUMDB="${GOSUMDB:-sum.golang.google.cn}" \
        go install -tags "with_quic,with_gvisor,with_utls" github.com/sagernet/sing-box/cmd/sing-box@v1.13.13
    fi
  fi
fi

echo "==> $("$SB" version | head -1)"
echo "==> checking $cfg"
if "$SB" check -c "$cfg"; then
  echo "✅ config is valid"
else
  echo "❌ config is INVALID — fix the errors above"; exit 1
fi
