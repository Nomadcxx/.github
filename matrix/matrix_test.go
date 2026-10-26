package matrix

import (
	"reflect"
	"sort"
	"strings"
	"testing"
)

func TestMatrixCoversEveryRepository(t *testing.T) {
	rows, err := ReadFile("../MATRIX.md")
	if err != nil {
		t.Fatal(err)
	}

	want := []string{
		"sysc-shell", "sysc", "sysc-launch", "sysc-wayland", "sysc-metrics",
		"sysc-notify", "sysc-tray", "sysc-clipboard", "sysc-plugins", "sysc-terminal",
		"sysclet", "sysc-compositor", "sysc-greet", "sysc-walls", "gSlapper", "sysc-lock",
		"sysc-Go", "sysc/aur", "void-packages",
	}
	got := make([]string, 0, len(rows))
	for _, row := range rows {
		got = append(got, row.Cells["Project"])
	}
	sort.Strings(got)
	sort.Strings(want)
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("matrix projects = %v, want %v", got, want)
	}
}

func TestMatrixColumnsAreComplete(t *testing.T) {
	rows, err := ReadFile("../MATRIX.md")
	if err != nil {
		t.Fatal(err)
	}
	for _, row := range rows {
		for _, column := range requiredColumns {
			if row.Cells[column] == "" {
				t.Errorf("%s has an empty %q cell", row.Cells["Project"], column)
			}
		}
	}
}

func TestMatrixBranchesMatchFixtures(t *testing.T) {
	rows, err := ReadFile("../MATRIX.md")
	if err != nil {
		t.Fatal(err)
	}
	want := map[string]string{
		"sysc-shell": "main", "sysc": "main", "sysc-launch": "main", "sysc-wayland": "main",
		"sysc-metrics": "main", "sysc-notify": "main", "sysc-tray": "main", "sysc-clipboard": "main",
		"sysc-plugins": "main", "sysc-terminal": "main", "sysclet": "main", "sysc-compositor": "main",
		"sysc-greet": "master", "sysc-walls": "master", "gSlapper": "master", "sysc-lock": "master",
		"sysc-Go": "master", "sysc/aur": "main", "void-packages": "master",
	}
	for _, row := range rows {
		project := row.Cells["Project"]
		if row.Cells["Default branch"] != want[project] {
			t.Errorf("%s default branch = %q, want %q", project, row.Cells["Default branch"], want[project])
		}
	}
}

func TestDEBRPMAllowlist(t *testing.T) {
	rows, err := ReadFile("../MATRIX.md")
	if err != nil {
		t.Fatal(err)
	}
	allowed := map[string]bool{"sysc-greet": true, "gSlapper": true, "sysc-Go": true}
	for _, row := range rows {
		project := row.Cells["Project"]
		artifacts := strings.ToLower(row.Cells["DEB/RPM artifacts"])
		switch {
		case allowed[project]:
			if artifacts == "none" || strings.HasPrefix(artifacts, "none ") {
				t.Errorf("%s is in the DEB/RPM allowlist but has no recorded artifacts", project)
			}
		case project == "sysc-walls":
			if !strings.Contains(artifacts, "historical") || !strings.Contains(artifacts, "no future") {
				t.Errorf("sysc-walls must retain historical assets and stop future DEB/RPM output; got %q", artifacts)
			}
		default:
			if !strings.HasPrefix(artifacts, "none") {
				t.Errorf("%s is outside the DEB/RPM allowlist but records %q", project, artifacts)
			}
		}
	}
}

func TestSyscGreetSourceLicenseAndMetadataSurfaces(t *testing.T) {
	rows, err := ReadFile("../MATRIX.md")
	if err != nil {
		t.Fatal(err)
	}
	for _, row := range rows {
		if row.Cells["Project"] != "sysc-greet" {
			continue
		}
		if !strings.Contains(row.Cells["Licence file SPDX"], "GPL-3.0-only") {
			t.Errorf("sysc-greet project licence = %q, want GPL-3.0-only", row.Cells["Licence file SPDX"])
		}
		surfaces := strings.ToLower(row.Cells["Licence metadata surfaces"])
		for _, surface := range []string{"nfpm", "flake.nix", "aur", "void", "third-party notices"} {
			if !strings.Contains(surfaces, surface) {
				t.Errorf("sysc-greet metadata surfaces %q omit %q", surfaces, surface)
			}
		}
		return
	}
	t.Fatal("sysc-greet row missing")
}
