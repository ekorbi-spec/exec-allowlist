Idea: exec-allowlist: declare at admission, enforce at runtime

This is a small project that connects Kyverno and Tetragon. A pod declares which binaries it’s allowed to run, and that declaration is enforced in the kernel.

How it works

A developer adds an annotation to their Deployment:
yaml
   exec-allowlist.io/binaries: "/usr/local/bin/app,/bin/sh"
A Kyverno policy rejects pods in labeled namespaces that are missing the annotation. It also blocks obviously bad entries, like wildcards or /bin/bash in prod namespaces.
A small controller (Go, or Python with kopf) watches pods and generates a namespaced Tetragon TracingPolicy for each workload. The policy hooks process exec and sends SIGKILL (or only logs, in audit mode) when the workload runs anything outside its list.
A demo script sets up a kind cluster, deploys a sample app, then kubectl execs into it and runs curl. The process gets killed, and the Tetragon event appears in the logs.

Why it makes a good portfolio piece

It covers both halves of the problem: admission-time policy (shift-left) and runtime enforcement (eBPF). Most demos show only one.
It’s small. The MVP is roughly a Kyverno policy, a ~300-line controller, and a Makefile.
The value is easy to see. A 30-second GIF of a shell getting killed is the README hero image.
It shows you understand the limits, like the gap between what’s declared and what actually runs, and the TOCTOU problem with path-based matching. Writing those up honestly in the README impresses reviewers.

MVP scope (about a weekend or two)

Kyverno ClusterPolicy plus Kyverno CLI tests (kyverno test) running in GitHub Actions
Controller that generates and garbage-collects TracingPolicies
An audit / enforce mode, set by a namespace label
make demo on kind, with Tetragon installed via Helm

Stretch goals

A “learning mode” that watches Tetragon exec events for N minutes and suggests the annotation value
A Chainsaw or e2e test that asserts the kill actually happens
An OPA/Gatekeeper version of the admission policy for comparison

Practical notes

Tetragon’s enforcement actions depend on kernel support, so mention the kernel requirements in the README and fall back to audit mode where enforcement isn’t available.
Check the current Tetragon docs for exact TracingPolicy fields, since the CRD has evolved over versions.
Two lighter alternatives
Falco rules pack + test harness: a handful of custom Falco rules, such as detecting reads of service account tokens by non-allowlisted processes, plus a CI pipeline that replays scenarios and asserts each rule fires. The real contribution is the “unit tests for detection rules” angle.
Kyverno policy-as-code library with a coverage report: 10–15 policies mapped to CIS or Pod Security Standards controls, with tests and a generated table showing which controls are covered. It’s less flashy, but very practical and easy to keep growing.

I’ve drafted three starter files for the project.

README.md has the full repo layout, how the pieces fit together, and a “known limitations” section.
require-exec-allowlist.yaml is the Kyverno policy, with three rules:
The annotation must be present.
Every entry must be an absolute path with no wildcards.
No shells are allowed in namespaces labeled exec-allowlist.io/env: prod.
It only applies to namespaces labeled exec-allowlist.io/mode. Kyverno’s autogen extends it to Deployments, so mistakes are caught before any pods exist.
tracingpolicy.yaml.tmpl is the Go template the controller renders for each workload.
It hooks security_bprm_check, which runs on every exec, and matches the path of the binary about to run against the allowlist.
Enforce mode kills the process; audit mode only logs it.
The ownerReferences delete the policy automatically when the workload goes away.

Things to verify:

Check the exact Kyverno and Tetragon field names and operator meanings against the versions you install. Both projects have changed their schemas recently, and I’ve noted the specific spots in comments.
Turn on Tetragon’s policy filter, or podSelector won’t work.
The kernel reports resolved file paths, so /bin/sh may show up as /usr/bin/dash. Start each namespace in audit mode first to see the real paths.

A good next step is the demo/ folder (kind config, sample app, and demo.sh), since that’s what produces the README GIF.