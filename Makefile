# Needs: kyverno, go (test); plus docker, kind, kubectl, helm, jq (demo); vhs (gif).
SHELL := bash
.SHELLFLAGS := -euo pipefail -c

KIND_CLUSTER ?= exec-allowlist
export KIND_CLUSTER

.PHONY: help test kyverno-test go-test lint demo demo-setup demo-run gif kind-up kind-down

help: ## Show targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-14s %s\n", $$1, $$2}'

test: kyverno-test go-test ## Run all offline tests

kyverno-test: ## Kyverno CLI tests against good/bad sample workloads
	kyverno test policies/kyverno/tests --detailed-results

go-test: ## Renderer unit + golden-file tests
	cd controller && go vet ./... && go test ./...

lint: ## gofmt check
	@out=$$(cd controller && gofmt -l .); if [ -n "$$out" ]; then echo "gofmt needed:"; echo "$$out"; exit 1; fi

demo: demo-setup demo-run ## kind + Tetragon + Kyverno, then watch an exec get killed

demo-setup: ## Create the cluster and deploy everything (idempotent)
	demo/setup.sh

demo-run: ## Run the demo steps against an existing cluster
	demo/demo.sh

gif: ## Record docs/demo.gif with vhs (run demo-setup first)
	vhs demo/demo.tape

kind-up: ## Create the kind cluster only
	kind get clusters | grep -qx $(KIND_CLUSTER) || kind create cluster --name $(KIND_CLUSTER) --config demo/kind-config.yaml

kind-down: ## Delete the kind cluster
	kind delete cluster --name $(KIND_CLUSTER)
