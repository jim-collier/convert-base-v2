//	Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
//	Licensed under the GNU General Public License v2.0 or later. Full text at:
//		https://spdx.org/licenses/GPL-2.0-or-later.html
//	SPDX-License-Identifier: GPL-2.0-or-later

package main

import (
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// Test ID: ddgds
func TestCrockfordBase32(t *testing.T) {
	cases := []struct {
		n    int64
		want string
	}{
		{0, "0"},
		{9, "9"},
		{10, "a"},
		{17, "h"},
		{18, "j"}, // no i
		{20, "m"}, // no l
		{22, "p"}, // no o
		{27, "v"}, // no u
		{31, "z"},
		{32, "10"},
		{14018084, "dbsh4"},
		{33554431, "zzzzz"},  // the last five-character number, in 2063
		{52596000, "1j5390"}, // 2100
	}
	for _, c := range cases {
		if got := crockfordBase32(c.n); got != c.want {
			t.Errorf("crockfordBase32(%d) = %q, want %q", c.n, got, c.want)
		}
	}
}

// Test ID: ddgdt
func TestBuildNumber(t *testing.T) {
	cases := []struct {
		stamp string
		want  string
	}{
		{"", ""},
		{"not a number", ""},
		{"946684800", "0"},
		{"946684859", "0"},
		{"946684860", "1"},
		{"0", ""},
		{"-1", ""},
		{"1787000000", "dbd05"},
		{"99999999999999999999", ""},
	}
	saved := buildEpoch
	defer func() { buildEpoch = saved }()
	for _, c := range cases {
		buildEpoch = c.stamp
		if got := buildNumber(); got != c.want {
			t.Errorf("buildNumber() with stamp %q = %q, want %q", c.stamp, got, c.want)
		}
	}
}

// One line either way, so a script reading the first line of --version gets
// all of it.
// Test ID: ddgdv
func TestVersionText(t *testing.T) {
	savedEpoch, savedVersion := buildEpoch, version
	defer func() { buildEpoch, version = savedEpoch, savedVersion }()
	version = "v3.0.0"

	buildEpoch = ""
	if got := versionText(); got != "convert-base-v2 v3.0.0" {
		t.Errorf("unstamped: got %q, want convert-base-v2 v3.0.0", got)
	}
	buildEpoch = "1787000000"
	if got := versionText(); got != "convert-base-v2 v3.0.0 build dbd05" {
		t.Errorf("stamped: got %q, want %q", got, "convert-base-v2 v3.0.0 build dbd05")
	}
	var about strings.Builder
	printAbout(&about)
	if first, _, _ := strings.Cut(about.String(), "\n"); first != "convert-base-v2 v3.0.0 build dbd05" {
		t.Errorf("--about opens with %q", first)
	}
}

// Test ID: debg1
func TestIsRelease(t *testing.T) {
	cases := map[string]bool{
		"v3.0.0":                  true,
		"v3.0.1-beta1":            true,
		"v1.0.0-rc3":              true,
		"v2.0.0-alpha":            true,
		"v3.0.1-beta1-3-g07d536e": false,
		"v3.0.0-dirty":            false,
		"v3.0.1-beta1-dirty":      false,
		"07d536e":                 false,
		"dev":                     false,
		"":                        false,
		"3.0.0":                   false,
		"v3.0":                    false,
		"v3..0":                   false,
		"v3.0.x":                  false,
		"v9.8.7-stamped":          false,
	}
	for v, want := range cases {
		if got := isRelease(v); got != want {
			t.Errorf("isRelease(%q) = %v, want %v", v, got, want)
		}
	}
}

// The date is the viewer's, so the same build reads a day apart across zones.
// Test ID: debg2
func TestVersionTextDate(t *testing.T) {
	savedEpoch, savedVersion, savedLocal := buildEpoch, version, time.Local
	defer func() { buildEpoch, version, time.Local = savedEpoch, savedVersion, savedLocal }()
	buildEpoch = "1792720800" // 2026-10-23 02:00 UTC
	cases := []struct {
		version string
		zone    *time.Location
		want    string
	}{
		{"v3.0.1-beta1-3-g07d536e", time.UTC, "convert-base-v2 v3.0.1-beta1-3-g07d536e build dea3r (2026-10-23)"},
		{"v3.0.1-beta1-3-g07d536e", time.FixedZone("CDT", -5*3600), "convert-base-v2 v3.0.1-beta1-3-g07d536e build dea3r (2026-10-22)"},
		{"dev", time.UTC, "convert-base-v2 dev build dea3r (2026-10-23)"},
		{"v3.0.1-beta1", time.UTC, "convert-base-v2 v3.0.1-beta1 build dea3r"},
		{"v3.0.0", time.FixedZone("CDT", -5*3600), "convert-base-v2 v3.0.0 build dea3r"},
	}
	for _, c := range cases {
		version, time.Local = c.version, c.zone
		if got := versionText(); got != c.want {
			t.Errorf("%s in %s: got %q, want %q", c.version, c.zone, got, c.want)
		}
	}
	// unstamped has no date to give
	buildEpoch, version = "", "dev"
	if got := versionText(); got != "convert-base-v2 dev" {
		t.Errorf("unstamped dev: got %q", got)
	}
}

// Like the version, the build stamp only works while it is a var the linker
// can patch.
// Test ID: ddgdw
func TestBuildEpochIsPatchable(t *testing.T) {
	gobin, err := exec.LookPath("go")
	if err != nil {
		t.Skip("no go tool on PATH")
	}
	exe := filepath.Join(t.TempDir(), "convert-base-v2")
	build := exec.Command(gobin, "build", "-ldflags", "-X main.version=v9.8.7-stamped -X main.buildEpoch=1787000000", "-o", exe, ".")
	if out, err := build.CombinedOutput(); err != nil {
		t.Fatalf("build: %v\n%s", err, out)
	}
	run := exec.Command(exe, "--version")
	run.Env = append(run.Environ(), "TZ=UTC")
	out, err := run.Output()
	if err != nil {
		t.Fatal(err)
	}
	want := "convert-base-v2 v9.8.7-stamped build dbd05 (2026-08-17)\n" + copyrightLine() + "\n"
	if got := string(out); got != want {
		t.Errorf("--version = %q, want %q", got, want)
	}
}
