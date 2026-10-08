// Command render prints the TracingPolicyNamespaced for one Deployment.
//
//	kubectl get deploy sample-app -n demo -o json \
//	  | go run ./cmd/render --mode enforce \
//	  | kubectl apply -f -
//
// It is the render step of the planned controller, usable on its own until
// the reconcile loop (watch, render, garbage-collect) exists.
package main

import (
	"flag"
	"fmt"
	"io"
	"os"

	"github.com/ekorbi-spec/exec-allowlist/controller/internal/render"
)

func main() {
	mode := flag.String("mode", "audit", "namespace mode: audit or enforce")
	flag.Parse()

	if err := run(*mode, os.Stdin, os.Stdout); err != nil {
		fmt.Fprintln(os.Stderr, "render:", err)
		os.Exit(1)
	}
}

func run(mode string, in io.Reader, out io.Writer) error {
	enforce, err := render.ParseMode(mode)
	if err != nil {
		return err
	}
	data, err := io.ReadAll(in)
	if err != nil {
		return err
	}
	w, err := render.FromDeploymentJSON(data, enforce)
	if err != nil {
		return err
	}
	y, err := render.Render(w)
	if err != nil {
		return err
	}
	_, err = out.Write(y)
	return err
}
