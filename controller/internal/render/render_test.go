package render

import (
	"flag"
	"os"
	"path/filepath"
	"reflect"
	"testing"
)

var update = flag.Bool("update", false, "rewrite golden files in testdata/")

// The same good/bad values as policies/kyverno/tests/resources.yaml, so the
// controller and the admission policy are held to one grammar.
func TestParseBinaries(t *testing.T) {
	good := map[string][]string{
		"/usr/local/bin/app":                    {"/usr/local/bin/app"},
		"/usr/local/bin/app,/usr/bin/curl":      {"/usr/local/bin/app", "/usr/bin/curl"},
		"/usr/bin/sleep,/usr/bin/sleep":         {"/usr/bin/sleep"},
		"/opt/app-1.2/bin/run_server,/bin/true": {"/opt/app-1.2/bin/run_server", "/bin/true"},
	}
	for in, want := range good {
		got, err := ParseBinaries(in)
		if err != nil {
			t.Errorf("ParseBinaries(%q) error: %v", in, err)
			continue
		}
		if !reflect.DeepEqual(got, want) {
			t.Errorf("ParseBinaries(%q) = %q, want %q", in, got, want)
		}
	}

	bad := []string{
		"",
		"app,/usr/bin/curl",
		"/usr/bin/*",
		"/usr/bin/?ash",
		"/usr/local/bin/app, /bin/sh",
		" /usr/local/bin/app",
		"/usr/local/bin/app,\t/usr/bin/curl",
		"/usr/local/bin/app\n",
		"/usr/local/bin/app,",
		"/usr/local/bin/app,,/usr/bin/curl",
		",/usr/local/bin/app",
	}
	for _, in := range bad {
		if got, err := ParseBinaries(in); err == nil {
			t.Errorf("ParseBinaries(%q) = %q, want error", in, got)
		}
	}
}

func TestParseMode(t *testing.T) {
	if e, err := ParseMode("enforce"); err != nil || !e {
		t.Errorf("enforce: got %v, %v", e, err)
	}
	if e, err := ParseMode("audit"); err != nil || e {
		t.Errorf("audit: got %v, %v", e, err)
	}
	if _, err := ParseMode("Enforce"); err == nil {
		t.Error("Enforce: want error")
	}
}

func TestRenderGolden(t *testing.T) {
	base := Workload{
		Name:      "checkout",
		Namespace: "shop",
		UID:       "6f1c1d2e-0000-4000-8000-000000000001",
		OwnerKind: "Deployment",
		OwnerAPI:  "apps/v1",
		Selector:  map[string]string{"app.kubernetes.io/name": "checkout", "tier": "web"},
		Binaries:  []string{"/usr/local/bin/checkout", "/usr/bin/curl"},
	}
	enforce := base
	enforce.Enforce = true

	for name, w := range map[string]Workload{"audit": base, "enforce": enforce} {
		t.Run(name, func(t *testing.T) {
			got, err := Render(w)
			if err != nil {
				t.Fatal(err)
			}
			golden := filepath.Join("testdata", name+".golden.yaml")
			if *update {
				if err := os.WriteFile(golden, got, 0o644); err != nil {
					t.Fatal(err)
				}
			}
			want, err := os.ReadFile(golden)
			if err != nil {
				t.Fatalf("%v (run go test ./... -update to create it)", err)
			}
			if string(got) != string(want) {
				t.Errorf("render mismatch for %s\n--- got\n%s\n--- want\n%s", golden, got, want)
			}
		})
	}
}

func TestRenderRejects(t *testing.T) {
	ok := Workload{Name: "a", Namespace: "b", UID: "c", OwnerKind: "Deployment", OwnerAPI: "apps/v1",
		Selector: map[string]string{"app": "a"}, Binaries: []string{"/bin/true"}}

	noSel := ok
	noSel.Selector = nil
	noBins := ok
	noBins.Binaries = nil
	noUID := ok
	noUID.UID = ""

	for name, w := range map[string]Workload{"empty selector": noSel, "empty allowlist": noBins, "missing uid": noUID} {
		if _, err := Render(w); err == nil {
			t.Errorf("%s: want error", name)
		}
	}
}

func TestFromDeploymentJSON(t *testing.T) {
	const good = `{
	  "apiVersion": "apps/v1", "kind": "Deployment",
	  "metadata": {"name": "sample-app", "namespace": "demo", "uid": "u-1"},
	  "spec": {
	    "selector": {"matchLabels": {"app": "sample-app"}},
	    "template": {"metadata": {"annotations": {"exec-allowlist.io/binaries": "/usr/bin/sleep"}}}
	  }
	}`
	w, err := FromDeploymentJSON([]byte(good), true)
	if err != nil {
		t.Fatal(err)
	}
	want := Workload{Name: "sample-app", Namespace: "demo", UID: "u-1", OwnerKind: "Deployment", OwnerAPI: "apps/v1",
		Selector: map[string]string{"app": "sample-app"}, Binaries: []string{"/usr/bin/sleep"}, Enforce: true}
	if !reflect.DeepEqual(w, want) {
		t.Errorf("got %+v\nwant %+v", w, want)
	}

	bad := map[string]string{
		"not a deployment":  `{"kind": "Pod"}`,
		"no annotation":     `{"apiVersion": "apps/v1", "kind": "Deployment", "spec": {"selector": {"matchLabels": {"a": "b"}}}}`,
		"match expressions": `{"apiVersion": "apps/v1", "kind": "Deployment", "spec": {"selector": {"matchExpressions": [{"key": "a", "operator": "Exists"}]}}}`,
		"bad annotation":    `{"apiVersion": "apps/v1", "kind": "Deployment", "spec": {"template": {"metadata": {"annotations": {"exec-allowlist.io/binaries": "/a, /b"}}}}}`,
	}
	for name, in := range bad {
		if _, err := FromDeploymentJSON([]byte(in), false); err == nil {
			t.Errorf("%s: want error", name)
		}
	}
}
