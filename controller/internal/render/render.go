// Package render turns a workload's exec-allowlist annotation into a Tetragon
// TracingPolicyNamespaced.
package render

import (
	"bytes"
	_ "embed"
	"errors"
	"fmt"
	"regexp"
	"strings"
	"text/template"
)

// Annotation is the pod-template annotation that declares the allowlist.
const Annotation = "exec-allowlist.io/binaries"

// ModeLabel is the namespace label that opts a namespace in.
const ModeLabel = "exec-allowlist.io/mode"

// allowlistRE is the same grammar the Kyverno rule entries-well-formed
// enforces at admission (policies/kyverno/require-exec-allowlist.yaml).
// Keep the two in sync: if admission accepts a value, this must parse it
// identically, or what's declared and what's enforced drift apart.
var allowlistRE = regexp.MustCompile(`^/[^,*?[:space:]]+(,/[^,*?[:space:]]+)*$`)

//go:embed tracingpolicy.yaml.tmpl
var tmplText string

var tmpl = template.Must(template.New("tracingpolicy").Parse(tmplText))

// HostMntNS is Tetragon's keyword for the host's mount namespace, where the
// container runtime runs on a normal node.
const HostMntNS = "host_ns"

var mntNSRE = regexp.MustCompile(`^(host_ns|[0-9]+)$`)

// Workload is the template data for one TracingPolicyNamespaced.
type Workload struct {
	Name      string            // workload name, e.g. "checkout"
	Namespace string            // workload namespace
	UID       string            // owner UID, for ownerReferences / cleanup
	OwnerKind string            // e.g. "Deployment"
	OwnerAPI  string            // e.g. "apps/v1"
	Selector  map[string]string // the workload's pod selector labels
	Binaries  []string          // parsed from the annotation
	Enforce   bool              // namespace label is mode=enforce

	// RuntimeMntNS is the mount namespace the container runtime runs in:
	// HostMntNS, or an inode number (e.g. a kind node's, which isn't the
	// host's). Execs in it (runc init, OCI hooks) are not policed.
	// Empty means HostMntNS.
	RuntimeMntNS string
}

// ParseBinaries splits an annotation value into absolute paths. It rejects
// anything the admission policy would reject, and drops duplicates.
func ParseBinaries(v string) ([]string, error) {
	if !allowlistRE.MatchString(v) {
		return nil, fmt.Errorf("%s: %q is not a comma-separated list of absolute paths without spaces, empty entries or wildcards", Annotation, v)
	}
	var out []string
	seen := map[string]bool{}
	for _, p := range strings.Split(v, ",") {
		if !seen[p] {
			seen[p] = true
			out = append(out, p)
		}
	}
	return out, nil
}

// ParseMode maps the namespace mode label to Workload.Enforce.
func ParseMode(m string) (enforce bool, err error) {
	switch m {
	case "enforce":
		return true, nil
	case "audit":
		return false, nil
	}
	return false, fmt.Errorf("%s: want audit or enforce, got %q", ModeLabel, m)
}

// Render produces the TracingPolicyNamespaced YAML for w.
func Render(w Workload) ([]byte, error) {
	switch {
	case w.Name == "", w.Namespace == "", w.UID == "", w.OwnerKind == "", w.OwnerAPI == "":
		return nil, errors.New("render: name, namespace, uid, owner kind and owner API are required")
	case len(w.Selector) == 0:
		// An empty podSelector would match every pod in the namespace.
		return nil, errors.New("render: refusing an empty pod selector")
	case len(w.Binaries) == 0:
		return nil, errors.New("render: allowlist is empty")
	}
	if w.RuntimeMntNS == "" {
		w.RuntimeMntNS = HostMntNS
	}
	if !mntNSRE.MatchString(w.RuntimeMntNS) {
		return nil, fmt.Errorf("render: runtime mount namespace must be %q or an inode number, got %q", HostMntNS, w.RuntimeMntNS)
	}
	var buf bytes.Buffer
	if err := tmpl.Execute(&buf, w); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}
