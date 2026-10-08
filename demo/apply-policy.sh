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

# The container runtime's execs (runc init, OCI hooks) are exempt by mount
# namespace. On a real node that's the host's ("host_ns"); on kind, runc runs
# inside the node container, so use that container's mount namespace.
runtime_ns=${RUNTIME_MNT_NS:-}
if [ -z "$runtime_ns" ]; then
  ctx=$(kubectl config current-context)
  if [[ $ctx == kind-* ]]; then
    node="${ctx#kind-}-control-plane"
    runtime_ns=$(docker exec "$node" readlink /proc/1/ns/mnt | tr -dc 0-9)
  else
    runtime_ns=host_ns
  fi
fi

kubectl -n "$ns" get deploy "$deploy" -o json \
  | (cd "$root/controller" && go run ./cmd/render --mode "$mode" --runtime-mnt-ns "$runtime_ns") \
  | kubectl apply -f -
