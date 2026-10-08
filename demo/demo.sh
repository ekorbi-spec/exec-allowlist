#!/usr/bin/env bash
# The part of the demo worth watching. Run demo/setup.sh first (make demo
# does both). Every step checks its outcome, so this doubles as the e2e
# test: it exits non-zero if admission or the kill doesn't happen.
#
# DEMO_PAUSE=1.5 slows it down for recording (see demo/demo.tape).
set -uo pipefail

cd "$(dirname "$0")/.."

PAUSE=${DEMO_PAUSE:-0}
POLICY=exec-allowlist-sample-app
START=$(date -u +%Y-%m-%dT%H:%M:%SZ)
failures=0

say()  { printf '\n\033[1;36m# %s\033[0m\n' "$*"; sleep "$PAUSE"; }
ok()   { printf '\033[32m  ✓ %s\033[0m\n' "$*"; }
bad()  { printf '\033[31m  ✗ %s\033[0m\n' "$*"; failures=$((failures + 1)); }

# run <expected-exit> <command string>: echo it, run it, check the exit code.
# "nonzero" accepts any failure.
run() {
  local want=$1 cmd=$2 rc=0
  printf '\033[1;32m$\033[0m %s\n' "$cmd"
  sleep "$PAUSE"
  eval "$cmd" || rc=$?
  case $want in
    nonzero) [ "$rc" -ne 0 ] && ok "rejected (exit $rc)" || bad "expected a failure, got exit 0" ;;
    *)       [ "$rc" -eq "$want" ] && ok "exit $rc" || bad "expected exit $want, got $rc" ;;
  esac
  sleep "$PAUSE"
}

say "Admission (Kyverno): a shell hidden behind a space is rejected"
run nonzero "kubectl apply -f demo/bad-app.yaml"
kubectl -n demo delete deploy bad-app --ignore-not-found >/dev/null 2>&1

say "The sample app declares the one binary it may run"
run 0 "kubectl -n demo get deploy sample-app -o jsonpath='{.spec.template.metadata.annotations.exec-allowlist\.io/binaries}{\"\\n\"}'"
run 0 "kubectl -n demo get tracingpolicynamespaced"

say "Runtime (Tetragon): an allowed exec works"
run 0 "kubectl -n demo exec deploy/sample-app -- /usr/bin/sleep 1"

say "Anything else is SIGKILLed in the kernel (137 = 128 + SIGKILL)"
run 137 "kubectl -n demo exec deploy/sample-app -- cat /var/run/secrets/kubernetes.io/serviceaccount/token"
run 137 "kubectl -n demo exec deploy/sample-app -- sh -c 'echo pwned'"

say "The app itself keeps running"
run 0 "kubectl -n demo get pods -l app=sample-app"
restarts=$(kubectl -n demo get pods -l app=sample-app -o jsonpath='{.items[0].status.containerStatuses[0].restartCount}')
[ "$restarts" = 0 ] && ok "0 restarts" || bad "app restarted $restarts times"

say "What Tetragon reported"
sleep 2 # let the export sidecar flush
events=$(kubectl -n kube-system logs ds/tetragon -c export-stdout --since-time="$START" \
  | jq -c --arg p "$POLICY" 'select(.process_kprobe.policy_name == $p) | .process_kprobe')
printf '\033[1;32m$\033[0m %s\n' "kubectl -n kube-system logs ds/tetragon -c export-stdout | jq ..."
sleep "$PAUSE"
printf '%s\n' "$events" | jq -r 'select(. != null)
  | "\(.action)  \(.args[0].linux_binprm_arg.path)  pod=\(.process.pod.namespace)/\(.process.pod.name)"'
for bin in /usr/bin/cat /usr/bin/dash; do
  if printf '%s\n' "$events" | jq -e --arg b "$bin" \
      'select(.action == "KPROBE_ACTION_SIGKILL" and .args[0].linux_binprm_arg.path == $b)' >/dev/null 2>&1; then
    ok "SIGKILL event for $bin"
  else
    bad "no SIGKILL event for $bin"
  fi
done
if [ "$failures" -gt 0 ] && [ -z "${DEMO_QUIET:-}" ]; then
  echo "--- raw events for $POLICY since $START:" >&2
  printf '%s\n' "$events" >&2
fi

echo
if [ "$failures" -eq 0 ]; then
  printf '\033[1;32mAll checks passed.\033[0m\n'
else
  printf '\033[1;31m%d check(s) failed.\033[0m\n' "$failures"
  exit 1
fi
