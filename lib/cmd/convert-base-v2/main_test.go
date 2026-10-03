//	Copyright © 2023-2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
//	Licensed under the GNU General Public License v2.0 or later. Full text at:
//		https://spdx.org/licenses/GPL-2.0-or-later.html
//	SPDX-License-Identifier: GPL-2.0-or-later

package main

import (
	"flag"
	"io"
	"reflect"
	"strings"
	"testing"
)

func parseInfo(t *testing.T, args ...string) infoAsks {
	t.Helper()
	var asked infoAsks
	fs := flag.NewFlagSet("test", flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	fs.String("from", "", "")
	fs.Var(asked.flag("help"), "help", "")
	fs.Var(asked.flag("help"), "h", "")
	fs.Var(asked.flag("version"), "version", "")
	fs.Var(asked.flag("about"), "about", "")
	fs.Var(asked.flag("donate"), "donate", "")
	fs.Var(asked.flag("examples"), "examples", "")
	if err := fs.Parse(args); err != nil {
		t.Fatalf("parse %q: %v", args, err)
	}
	return asked
}

func TestInfoFlagOrder(t *testing.T) {
	cases := []struct {
		args []string
		want infoAsks
	}{
		{[]string{"--donate", "--version"}, infoAsks{"donate", "version"}},
		{[]string{"--version", "--donate"}, infoAsks{"version", "donate"}},
		{[]string{"-h", "--about", "--help"}, infoAsks{"help", "about"}},
		{[]string{"--help", "--help=false", "--examples"}, infoAsks{"examples"}},
		{[]string{"--from", "16"}, nil},
	}
	for _, c := range cases {
		got := parseInfo(t, c.args...)
		if len(got) == 0 && len(c.want) == 0 {
			continue
		}
		if !reflect.DeepEqual(got, c.want) {
			t.Errorf("%q: got %q, want %q", c.args, got, c.want)
		}
	}
}

func TestPrintInfoLoneIsUnchanged(t *testing.T) {
	var got, want strings.Builder
	if err := printInfo(&got, parseInfo(t, "--version"), nil); err != nil {
		t.Fatal(err)
	}
	if got.String() != version+"\n" {
		t.Errorf("--version: got %q", got.String())
	}

	got.Reset()
	if err := printInfo(&got, parseInfo(t, "--donate"), nil); err != nil {
		t.Fatal(err)
	}
	printDonate(&want)
	if got.String() != want.String() {
		t.Errorf("--donate alone differs from printDonate")
	}
}

// One blank line between outputs, whether or not the first one already ends
// in a blank line (the help does, the others do not).
func TestPrintInfoSeparation(t *testing.T) {
	help := func(w io.Writer) { io.WriteString(w, "HELP\n\n") }

	var got strings.Builder
	if err := printInfo(&got, parseInfo(t, "--version", "--help", "--donate"), help); err != nil {
		t.Fatal(err)
	}
	var donate strings.Builder
	printDonate(&donate)
	want := version + "\n\nHELP\n\n" + donate.String()
	if got.String() != want {
		t.Errorf("got %q\nwant %q", got.String(), want)
	}
	if strings.Contains(got.String(), "\n\n\n") {
		t.Errorf("more than one blank line between outputs: %q", got.String())
	}
}

func TestAboutAndDonateContent(t *testing.T) {
	var about, donate strings.Builder
	printAbout(&about)
	printDonate(&donate)
	for _, s := range []string{version, "Copyright ©", "GPL-2.0-or-later", "https://github.com/jim-collier/convert-base-v2"} {
		if !strings.Contains(about.String(), s) {
			t.Errorf("--about is missing %q", s)
		}
	}
	for _, s := range []string{"https://github.com/sponsors/jim-collier", "https://ko-fi.com/jimcollier"} {
		if !strings.Contains(donate.String(), s) {
			t.Errorf("--donate is missing %q", s)
		}
	}
}
