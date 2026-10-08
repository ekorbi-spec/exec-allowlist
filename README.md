# exec-allowlist

[![ci](https://github.com/ekorbi-spec/exec-allowlist/actions/workflows/ci.yaml/badge.svg)](https://github.com/ekorbi-spec/exec-allowlist/actions/workflows/ci.yaml)

Declare which binaries a workload may run at admission time (Kyverno), then enforce
it in the kernel at runtime (Tetragon).

![Kyverno rejects a shell at admission; Tetragon SIGKILLs a non-allowlisted exec](docs/demo.gif)

```yaml
spec:
  template:
    metadata:
      annotations:
        exec-allowlist.io/binaries: /usr/local/bin/app,/usr/bin/curl
```

## Status

| Piece | State |
|---|---|
| Kyverno policy + `kyverno test` suite (good/bad Pods and Deployments) | Done, runs in CI |
| TracingPolicy template + renderer (`controller/cmd/render`), golden tests | Done, runs in CI |
| `make demo` on kind: Kyverno rejects, Tetragon kills, assertions in CI | Done, runs in CI (`e2e` job) |
| Controller reconcile loop (watch, render, garbage-collect) | **Planned**: until then, `demo/apply-policy.sh` renders and applies a policy by hand |
| Controller deployment manifests (`deploy/controller/`) | **Planned** |
| Workload kinds other than Deployment (StatefulSet, DaemonSet, …) | **Planned**: the renderer only reads Deployments |
| `selector.matchExpressions` | **Planned**: the renderer refuses them instead of rendering a broader selector |
| Kyverno `ValidatingPolicy` (CEL) version | **Planned**: Kyverno 1.19 warns that `ClusterPolicy` is deprecated |
| Learning mode (suggest the annotation from observed execs) | **Planned** |
| OPA/Gatekeeper version of the admission policy | **Planned** |
| `docs/how-it-works.md`, `docs/limitations.md` | **Planned**: see the sections below for now |

## Try it

Needs Docker, kind, kubectl, Helm, Go and jq on Linux (Tetragon needs a
BTF-enabled kernel; CI uses GitHub's `ubuntu-24.04` runners).

```sh
make test        # kyverno test + go test, no cluster needed
make demo        # kind + Tetragon + Kyverno, then the steps in the GIF
make kind-down
```

`make demo` is also the end-to-end test: [demo/demo.sh](demo/demo.sh) exits
non-zero unless Kyverno rejects the bad Deployment, the allowed exec succeeds,
the others exit 137, the app keeps running, and Tetragon reports both kills.
To re-record the GIF, run the `demo-gif` workflow (or `make demo-setup gif`).

## How it fits together

1. A namespace opts in with the label `exec-allowlist.io/mode: audit|enforce`.
2. Kyverno rejects Pods (and, through autogen, Deployments, StatefulSets, etc.)
   in opted-in namespaces unless the pod template carries a valid
   `exec-allowlist.io/binaries` annotation: a comma-separated list of absolute
   paths with no whitespace, empty entries or wildcards. In namespaces also
   labeled `exec-allowlist.io/env: prod`, shells are rejected too.
3. The renderer turns the Deployment's pod-template annotation into one
   `TracingPolicyNamespaced` (from
   [tracingpolicy.yaml.tmpl](controller/internal/render/tracingpolicy.yaml.tmpl)),
   owned by the Deployment so it is deleted with it. It parses the annotation
   with the same regex as the Kyverno rule, so admission and runtime agree.
   *(Planned: the controller does this automatically.)*
4. Tetragon hooks `security_bprm_check` and kills (enforce) or reports (audit)
   any exec whose resolved path is not on the list.

## Repo layout

```
├── Makefile                      # make test | demo | demo-setup | demo-run | gif | kind-down
├── policies/kyverno/
│   ├── require-exec-allowlist.yaml
│   └── tests/                    # kyverno test: kyverno-test.yaml, resources.yaml, values.yaml
├── controller/
│   ├── cmd/render/main.go        # Deployment JSON -> TracingPolicyNamespaced YAML
│   └── internal/render/          # parser, template, golden-file tests
├── deploy/tetragon-values.yaml   # Helm values (policy filter on, kind /proc path)
├── demo/
│   ├── setup.sh                  # cluster, Tetragon, Kyverno, sample app, policy
│   ├── demo.sh                   # the recorded steps, with assertions
│   ├── apply-policy.sh           # render + apply one policy (stand-in for the controller)
│   ├── demo.tape                 # VHS script for docs/demo.gif
│   └── kind-config.yaml, namespace.yaml, sample-app.yaml, bad-app.yaml
├── docs/demo.gif
└── .github/workflows/            # ci.yaml (kyverno test, go test, e2e), demo-gif.yaml
```

## Known limitations

- **Symlinks:** the kernel reports the resolved path, so `/bin/sh` shows up as
  `/usr/bin/dash` on Debian and `/bin/busybox` on Alpine. A declared path that
  is a symlink never matches; declare the target. This fails closed: the exec is
  killed, not allowed. Start each namespace in `audit` mode to see real paths.
- **Multi-call binaries:** every busybox/toybox applet resolves to the one
  binary, so allowing `/bin/busybox` allows all applets, shells included. The
  prod shell blocklist rejects it for that reason.
- **Interpreters:** `#!/bin/sh` scripts trigger a second exec check for the
  interpreter, so interpreters must be on the list.
- **Path-based matching:** a writable allowlisted path can be overwritten.
  Pair this with a read-only root filesystem (a good second Kyverno rule).
- **Entrypoint and everything else in the pod:** the policy covers every
  container the pod selector matches: the entrypoint, `exec` liveness/readiness
  probes, sidecars and `kubectl debug` containers. All of them must be on the
  list, or they die in enforce mode.
- **Rollouts:** one policy per Deployment, so during a rollout old pods get the
  new list. Per-ReplicaSet policies (keyed on `pod-template-hash`) would fix it.
- **Mutable pod annotations:** a live pod's annotation can be edited after
  admission. The renderer reads the pod template only, never the pod.
- **Scale:** each policy loads its own BPF program on `security_bprm_check`,
  which runs on every exec on the node. Fine per demo, worth measuring with
  hundreds of workloads.
- **Large allowlists:** Tetragon documents per-selector limits on match
  values. CI only exercises short lists; check long ones against your version.
- **Kernel support:** Sigkill uses `bpf_send_signal` (Linux 5.3+) and Tetragon
  needs BTF. Fall back to `audit` mode where enforcement isn't available.

Tested with Kyverno 1.19.1 (chart 3.9.1), Tetragon 1.7.1 and kind 0.33.0.
