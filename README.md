# exec-allowlist

Declare which binaries a workload may run at admission time (Kyverno), then enforce
it in the kernel at runtime (Tetragon).

## Repo layout

```
exec-allowlist/
├── README.md
├── Makefile                      # make demo | test | lint | kind-up | kind-down
├── policies/
│   └── kyverno/
│       ├── require-exec-allowlist.yaml
│       └── tests/                # kyverno CLI tests (run in CI)
│           ├── kyverno-test.yaml
│           ├── resources.yaml    # good + bad Pods/Deployments
│           └── values.yaml       # namespace labels for the CLI
├── controller/
│   ├── go.mod
│   ├── cmd/main.go               # controller-runtime manager setup
│   └── internal/
│       ├── reconcile/pod.go      # watch Pods -> owning workload -> policy
│       └── render/
│           ├── render.go         # annotation -> template data
│           ├── render_test.go    # golden-file tests
│           └── tracingpolicy.yaml.tmpl
├── deploy/
│   ├── controller/               # kustomize: Deployment, RBAC, ServiceAccount
│   └── tetragon-values.yaml      # Helm values (policy filter enabled)
├── demo/
│   ├── kind-config.yaml
│   ├── namespace.yaml            # labeled exec-allowlist.io/mode=enforce
│   ├── sample-app.yaml           # annotated Deployment
│   └── demo.sh                   # exec curl -> killed -> show Tetragon event
├── docs/
│   ├── how-it-works.md
│   └── limitations.md            # symlinks, interpreters, TOCTOU, etc.
└── .github/workflows/
    └── ci.yaml                   # kyverno test, go test, e2e on kind
```

## How it fits together

1. A namespace opts in with the label `exec-allowlist.io/mode: audit|enforce`.
2. Kyverno rejects Pods (and, through autogen, Deployments/StatefulSets/etc.)
   in opted-in namespaces unless they carry a valid
   `exec-allowlist.io/binaries` annotation.
3. The controller renders one `TracingPolicyNamespaced` per workload from
   `tracingpolicy.yaml.tmpl` and deletes it when the workload goes away.
4. Tetragon kills (enforce) or reports (audit) any exec outside the list.

## Known limitations (write these up in docs/limitations.md)

- **Symlinks:** the kernel reports the resolved path. `/bin/sh` may show up as
  `/usr/bin/dash`. The controller should either document this or resolve paths
  by inspecting the image.
- **Interpreters:** `#!/bin/sh` scripts trigger a second exec check for the
  interpreter, so interpreters must be on the list.
- **Path-based matching:** a writable allowlisted path can be overwritten.
  Pair this with a read-only root filesystem (a good second Kyverno rule).
- **Entrypoint:** the container's own entrypoint must be on the list, or the
  pod dies at startup in enforce mode. Start every namespace in `audit` mode.
- **Kernel support:** Sigkill uses `bpf_send_signal`. Check Tetragon's docs for
  kernel requirements, and fall back to audit mode where it's missing.
