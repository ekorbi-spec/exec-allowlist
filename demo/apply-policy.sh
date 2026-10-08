#!/usr/bin/env bash
# Render one Deployment's TracingPolicyNamespaced and apply it.
# This is the job of the planned controller; until it exists, run this
# after creating or changing an annotated Deployment.
#
#   demo/apply-policy.sh <namespace> <deployment>
set -euo pipefail

ns=$1
deploy=$2
root=$(cd "$(dirname "$0")/.." && pwd)

mode=$(kubectl get ns "$ns" -o jsonpath='{.metadata.labels.exec-allowlist\.io/mode}')
if [ -z "$mode" ]; then
  echo "namespace $ns has no exec-allowlist.io/mode label; nothing to do" >&2
  exit 1
fi

kubectl -n "$ns" get deploy "$deploy" -o json \
  | (cd "$root/controller" && go run ./cmd/render --mode "$mode") \
  | kubectl apply -f -
