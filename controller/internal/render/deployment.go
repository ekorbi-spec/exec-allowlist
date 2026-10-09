package render

import (
	"encoding/json"
	"errors"
	"fmt"
)

// deployment is the subset of apps/v1 Deployment that the renderer needs.
// Decoding into it keeps this package free of client-go.
type deployment struct {
	APIVersion string `json:"apiVersion"`
	Kind       string `json:"kind"`
	Metadata   struct {
		Name      string `json:"name"`
		Namespace string `json:"namespace"`
		UID       string `json:"uid"`
	} `json:"metadata"`
	Spec struct {
		Selector struct {
			MatchLabels      map[string]string `json:"matchLabels"`
			MatchExpressions []json.RawMessage `json:"matchExpressions"`
		} `json:"selector"`
		Template struct {
			Metadata struct {
				Annotations map[string]string `json:"annotations"`
			} `json:"metadata"`
		} `json:"template"`
	} `json:"spec"`
}

// FromDeploymentJSON builds a Workload from `kubectl get deploy -o json`
// output. The allowlist comes from the pod template, which is what admission
// validated; live pod annotations are mutable and are deliberately ignored.
func FromDeploymentJSON(data []byte, enforce bool) (Workload, error) {
	var d deployment
	if err := json.Unmarshal(data, &d); err != nil {
		return Workload{}, fmt.Errorf("decode deployment: %w", err)
	}
	if d.Kind != "Deployment" {
		return Workload{}, fmt.Errorf("want kind Deployment, got %q", d.Kind)
	}
	if len(d.Spec.Selector.MatchExpressions) > 0 {
		// Tetragon's podSelector would need the same expressions; until that's
		// supported here, refuse rather than render a broader selector.
		return Workload{}, errors.New("selector.matchExpressions is not supported yet")
	}
	ann, ok := d.Spec.Template.Metadata.Annotations[Annotation]
	if !ok {
		return Workload{}, fmt.Errorf("pod template has no %s annotation", Annotation)
	}
	bins, err := ParseBinaries(ann)
	if err != nil {
		return Workload{}, err
	}
	return Workload{
		Name:      d.Metadata.Name,
		Namespace: d.Metadata.Namespace,
		UID:       d.Metadata.UID,
		OwnerKind: d.Kind,
		OwnerAPI:  d.APIVersion,
		Selector:  d.Spec.Selector.MatchLabels,
		Binaries:  bins,
		Enforce:   enforce,
	}, nil
}
