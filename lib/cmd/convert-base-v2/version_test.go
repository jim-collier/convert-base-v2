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
)

// Test ID: ErlL5bp
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

// Test ID: ErlL5cK
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

// One line either way, so a script reading --version still gets one line.
// Test ID: ErlL5cs
func TestVersionText(t *testing.T) {
	savedEpoch, savedVersion := buildEpoch, version
	defer func() { buildEpoch, version = savedEpoch, savedVersion }()
	version = "v3.0.0"

	buildEpoch = ""
	if got := versionText(); got != "v3.0.0" {
		t.Errorf("unstamped: got %q, want v3.0.0", got)
	}
	buildEpoch = "1787000000"
	if got := versionText(); got != "v3.0.0 build dbd05" {
		t.Errorf("stamped: got %q, want %q", got, "v3.0.0 build dbd05")
	}
	var about strings.Builder
	printAbout(&about)
	if first, _, _ := strings.Cut(about.String(), "\n"); first != "convert-base-v2 v3.0.0 build dbd05" {
		t.Errorf("--about opens with %q", first)
	}
}

// Like the version, the build stamp only works while it is a var the linker
// can patch.
// Test ID: ErlL5dO
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
	out, err := exec.Command(exe, "--version").Output()
	if err != nil {
		t.Fatal(err)
	}
	if got := string(out); got != "v9.8.7-stamped build dbd05\n" {
		t.Errorf("--version = %q, want one line, v9.8.7-stamped build dbd05", got)
	}
}
