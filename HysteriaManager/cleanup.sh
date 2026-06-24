#!/usr/bin/env bash
#
# HysteriaManager fix-it (macOS). Run when things feel flaky:
#   ./cleanup.sh              # kill orphaned hysteria, free ports, reset system proxy
#   ./cleanup.sh --quit-app   # also quit the HysteriaManager app
#
# Safe to run anytime. Resetting the system proxy needs admin (sudo will prompt once,
# or run silently if you've enabled passwordless switching in the app).
#
set -uo pipefail   # intentionally not -e: keep going through individual failures

echo "==> Killing leftover hysteria processes…"
if pkill -f 'hysteria client' 2>/dev/null; then echo "   killed hysteria"; else echo "   none running"; fi

echo "==> Freeing local proxy ports (1080, 8080)…"
for p in 1080 8080; do
  pids="$(lsof -nP -iTCP:"$p" -sTCP:LISTEN -t 2>/dev/null || true)"
  if [[ -n "$pids" ]]; then
    echo "   port $p held by PID(s): $pids → killing"
    kill $pids 2>/dev/null || true
    sleep 1
    pids2="$(lsof -nP -iTCP:"$p" -sTCP:LISTEN -t 2>/dev/null || true)"
    [[ -n "$pids2" ]] && { echo "   still up, force-killing $pids2"; kill -9 $pids2 2>/dev/null || true; }
  else
    echo "   port $p free"
  fi
done

echo "==> Turning the system proxy OFF on all network services (needs admin)…"
# Skip the header line and any disabled (*) services.
networksetup -listallnetworkservices 2>/dev/null | tail -n +2 | while IFS= read -r svc; do
  [[ -z "$svc" || "$svc" == \** ]] && continue
  sudo networksetup -setsocksfirewallproxystate "$svc" off  2>/dev/null
  sudo networksetup -setwebproxystate         "$svc" off  2>/dev/null
  sudo networksetup -setsecurewebproxystate   "$svc" off  2>/dev/null
  echo "   reset: $svc"
done

if [[ "${1:-}" == "--quit-app" ]]; then
  echo "==> Quitting HysteriaManager…"
  osascript -e 'quit app "HysteriaManager"' 2>/dev/null || pkill -f 'HysteriaManager.app' 2>/dev/null || true
fi

echo ""
echo "✅ Cleanup done. Relaunch / reconnect HysteriaManager."
