#!/usr/bin/env bash
# Bring up kind + Tetragon + Kyverno, deploy the sample app, render its
# TracingPolicy, and wait until enforcement is live. Idempotent.
set -euo pipefail

cd "$(dirname "$0")/.."

CLUSTER=${KIND_CLUSTER:-exec-allowlist}
TETRAGON_CHART_VERSION=${TETRAGON_CHART_VERSION:-1.7.1}
KYVERNO_CHART_VERSION=${KYVERNO_CHART_VERSION:-3.9.1}

step() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }

step "kind cluster '$CLUSTER'"
if ! kind get clusters | grep -qx "$CLUSTER"; then
  kind create cluster --name "$CLUSTER" --config demo/kind-config.yaml --wait 120s
fi
kubectl config use-context "kind-$CLUSTER" >/dev/null

step "Helm repos"
helm repo add cilium https://helm.cilium.io >/dev/null 2>&1 || true
helm repo add kyverno https://kyverno.github.io/kyverno >/dev/null 2>&1 || true
helm repo update cilium kyverno >/dev/null

step "Tetragon $TETRAGON_CHART_VERSION"
helm upgrade --install tetragon cilium/tetragon --version "$TETRAGON_CHART_VERSION" \
  -n kube-system -f deploy/tetragon-values.yaml --wait --timeout 5m
kubectl -n kube-system rollout status ds/tetragon --timeout 300s

step "Kyverno chart $KYVERNO_CHART_VERSION"
helm upgrade --install kyverno kyverno/kyverno --version "$KYVERNO_CHART_VERSION" \
  -n kyverno --create-namespace --wait --timeout 5m

step "Admission policy"
# helm --wait can return before Kyverno's webhook Service has endpoints, and
# applying a policy goes through that webhook. Retry for up to ~2 minutes.
for i in $(seq 1 24); do
  kubectl apply -f policies/kyverno/require-exec-allowlist.yaml && break
  [ "$i" -eq 24 ] && exit 1
  echo "Kyverno webhook not ready yet, retrying in 5s..."
  sleep 5
done
kubectl wait --for=condition=Ready clusterpolicy/require-exec-allowlist --timeout 120s

step "Namespace and sample app"
kubectl apply -f demo/namespace.yaml
kubectl apply -f demo/sample-app.yaml
kubectl -n demo rollout status deploy/sample-app --timeout 180s

step "Render and apply the TracingPolicy"
demo/apply-policy.sh demo sample-app

step "Waiting for Tetragon to enforce"
# /usr/bin/true is not on the allowlist, so once the policy is loaded the
# exec gets SIGKILLed (exit 137). Until then it exits 0.
last=""
for i in $(seq 1 60); do
  rc=0
  err=$(kubectl -n demo exec deploy/sample-app -- /usr/bin/true 2>&1 >/dev/null) || rc=$?
  sig=$(printf "%s" "$err" | sed -E "s/[0-9a-f]{64}/<id>/g")
  if [ "rc=$rc $sig" != "$last" ]; then
    echo "probe $i: exit $rc ${err:+($err)}"
    last="rc=$rc $sig"
  fi
  if [ "$rc" -eq 137 ]; then
    echo "enforcing after ~$((i * 2))s"
    exit 0
  fi
  sleep 2
done
echo "Tetragon never started enforcing (last exit code: $rc)" >&2
kubectl -n kube-system logs ds/tetragon -c export-stdout --tail 400 \
  | jq -c 'select(.process_kprobe) | .process_kprobe | {action, policy_name, args, bin: .process.binary, pod: .process.pod.name}' >&2 || true
kubectl get tracingpolicynamespaced -A -o yaml >&2 || true
kubectl -n kube-system logs ds/tetragon -c tetragon --tail 100 >&2 || true
exit 1
