//	Copyright © 2023-2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
//	Licensed under the GNU General Public License v2.0 or later. Full text at:
//		https://spdx.org/licenses/GPL-2.0-or-later.html
//	SPDX-License-Identifier: GPL-2.0-or-later

package main

import (
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"regexp"
	"slices"
	"strings"
	"testing"
	"unicode/utf8"

	"github.com/jim-collier/convert-base-v2/lib/convertbase"
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
	fs.Var(asked.flag("version"), "v", "")
	fs.Var(asked.flag("version"), "V", "")
	fs.Var(asked.flag("about"), "about", "")
	fs.Var(asked.flag("donate"), "donate", "")
	fs.Var(asked.flag("examples"), "examples", "")
	if err := fs.Parse(args); err != nil {
		t.Fatalf("parse %q: %v", args, err)
	}
	return asked
}

// Test ID: Erfqe2I
func TestInfoFlagOrder(t *testing.T) {
	cases := []struct {
		args []string
		want infoAsks
	}{
		{[]string{"--donate", "--version"}, infoAsks{"donate", "version"}},
		{[]string{"--version", "--donate"}, infoAsks{"version", "donate"}},
		{[]string{"-h", "--about", "--help"}, infoAsks{"help", "about"}},
		{[]string{"-v", "--donate", "-V"}, infoAsks{"version", "donate"}},
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

// Test ID: Erfqe2J
func TestPrintInfoLoneIsUnchanged(t *testing.T) {
	var got, want strings.Builder
	if err := printInfo(&got, parseInfo(t, "--version"), nil); err != nil {
		t.Fatal(err)
	}
	if got.String() != versionText()+"\n" {
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
// Test ID: Erfqe2K
func TestPrintInfoSeparation(t *testing.T) {
	help := func(w io.Writer) { fmt.Fprint(w, "HELP\n\n") }

	var got strings.Builder
	if err := printInfo(&got, parseInfo(t, "--version", "--help", "--donate"), help); err != nil {
		t.Fatal(err)
	}
	var donate strings.Builder
	printDonate(&donate)
	want := versionText() + "\n\nHELP\n\n" + donate.String()
	if got.String() != want {
		t.Errorf("got %q\nwant %q", got.String(), want)
	}
	if strings.Contains(got.String(), "\n\n\n") {
		t.Errorf("more than one blank line between outputs: %q", got.String())
	}
}

// Test ID: Erfqe2L
func TestAboutAndDonateContent(t *testing.T) {
	var about, donate strings.Builder
	printAbout(&about)
	printDonate(&donate)
	for _, s := range []string{versionText(), "Copyright ©", "GPL-2.0-or-later", "https://github.com/jim-collier/convert-base-v2"} {
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

// Release builds stamp the version with -X main.version, and the linker can
// only patch a variable. A const once made the stamp a silent no-op.
// Test ID: ErkSf4g
func TestVersionIsPatchable(t *testing.T) {
	gobin, err := exec.LookPath("go")
	if err != nil {
		t.Skip("no go tool on PATH")
	}
	exe := filepath.Join(t.TempDir(), "convert-base-v2")
	build := exec.Command(gobin, "build", "-ldflags", "-X main.version=v9.8.7-stamped", "-o", exe, ".")
	if out, err := build.CombinedOutput(); err != nil {
		t.Fatalf("build: %v\n%s", err, out)
	}
	out, err := exec.Command(exe, "--version").Output()
	if err != nil {
		t.Fatal(err)
	}
	if got := strings.TrimSpace(string(out)); got != "v9.8.7-stamped" {
		t.Errorf("--version = %q, want the stamped v9.8.7-stamped", got)
	}
}

// Each alias sets its flag's one value, so the last spelling given wins, as
// with -h and --help.
// Test ID: ErqCOGX
func TestFlagAliasesShareOneValue(t *testing.T) {
	type field func(*cliFlags) bool
	binary := func(f *cliFlags) bool { return f.binary }
	number := func(f *cliFlags) bool { return f.number }
	noNewline := func(f *cliFlags) bool { return f.noNewline }
	cases := []struct {
		args []string
		get  field
		want bool
	}{
		{[]string{"--binary"}, binary, true},
		{[]string{"--bin"}, binary, true},
		{[]string{"-b"}, binary, true},
		{[]string{"--number"}, number, true},
		{[]string{"--num"}, number, true},
		{[]string{"-N"}, number, true},
		{[]string{"--no-newline"}, noNewline, true},
		{[]string{"-n"}, noNewline, true},
		{[]string{"--binary", "--bin=false"}, binary, false},
		{[]string{"-b=false", "--binary"}, binary, true},
		{[]string{"--num", "-N=false"}, number, false},
		{[]string{"-n", "--no-newline=false"}, noNewline, false},
		{[]string{"--from", "16"}, binary, false},
	}
	for _, c := range cases {
		f, err := parseFlags(c.args)
		if err != nil {
			t.Fatalf("%q: %v", c.args, err)
		}
		if got := c.get(f); got != c.want {
			t.Errorf("%q: got %v, want %v", c.args, got, c.want)
		}
	}
}

// Pad and tail symbols pass through the case flags untouched, on either side of
// a chunk split, and everything else recases as before.
// Test ID: ErsqAaO
func TestRecaseWriterKeepsPadAndTail(t *testing.T) {
	keep := []rune{'P', 'ω', 'x', '�'}
	samples := []string{
		"c4PPPPPP",
		"deadPbeefP",
		"αβγωωΩω",
		"仂侉伛X乆x",
		"ab\xffP�q",
		"ПpPΩωxX",
	}
	for _, upper := range []bool{false, true} {
		for _, s := range samples {
			var want strings.Builder
			for i, w := 0, 0; i < len(s); i += w {
				r, size := utf8.DecodeRuneInString(s[i:])
				w = size
				if slices.Contains(keep, r) && (r != utf8.RuneError || size > 1) {
					want.WriteString(s[i : i+size])
				} else if upper {
					want.WriteString(strings.ToUpper(s[i : i+size]))
				} else {
					want.WriteString(strings.ToLower(s[i : i+size]))
				}
			}
			for size := 1; size <= len(s)+1; size++ {
				var got strings.Builder
				rw := newRecaseWriter(&got, upper, keep...)
				for i := 0; i < len(s); i += size {
					if _, err := rw.Write([]byte(s[i:min(i+size, len(s))])); err != nil {
						t.Fatal(err)
					}
				}
				if err := rw.flush(); err != nil {
					t.Fatal(err)
				}
				if got.String() != want.String() {
					t.Errorf("upper=%v %q in chunks of %d: got %q, want %q", upper, s, size, got.String(), want.String())
				}
			}
		}
	}
}

// A stream can split a multi-byte digit across two writes. Every split of every
// sample has to give the same bytes as recasing the whole thing at once.
// Test ID: Ersmg4k
func TestRecaseWriterMatchesWholeRecase(t *testing.T) {
	samples := []string{
		"DEADbeef0123=",
		"ΑΒΓΔαβγδ",
		"ЖжЯя日本Ééİıẞßǅ",
		"x\U0001F600Y\U00010400\U00010428",
		"ab\xc3",
		"\xe2\x82Ab\xffC",
		"",
	}
	for _, upper := range []bool{false, true} {
		recase := strings.ToLower
		if upper {
			recase = strings.ToUpper
		}
		for _, s := range samples {
			want := recase(s)
			for size := 1; size <= len(s)+1; size++ {
				var got strings.Builder
				rw := newRecaseWriter(&got, upper)
				for i := 0; i < len(s); i += size {
					chunk := []byte(s[i:min(i+size, len(s))])
					if n, err := rw.Write(chunk); err != nil || n != len(chunk) {
						t.Fatalf("Write(%q) = %d, %v", chunk, n, err)
					}
				}
				if err := rw.flush(); err != nil {
					t.Fatal(err)
				}
				if got.String() != want {
					t.Errorf("upper=%v %q in chunks of %d: got %q, want %q", upper, s, size, got.String(), want)
				}
			}
		}
	}
}

// Wherever a case flag is allowed, every digit of the base, recased and run
// together, reads back as the same digits through that base, on the number
// path and the byte path. Built-ins, plus custom ones where only one-letter
// ASCII digits or uncased ones are allowed.
// Test ID: Ervq3zH
func TestCaseFlagOutputReadsBack(t *testing.T) {
	reg, err := convertbase.NewRegistry()
	if err != nil {
		t.Fatal(err)
	}
	type refusal struct{ lower, upper bool }
	want := map[*convertbase.Base]refusal{}
	bases := reg.OrderedBases()
	for _, cb := range []struct {
		spec string
		refusal
	}{
		{"Ab Cd Ef Gh", refusal{true, true}},
		{"α β γ δ", refusal{false, true}},
		{"s ſ", refusal{false, true}},
		{"ab cd \u212a", refusal{true, true}},
		{"a b 一 二", refusal{false, false}},
		{"0! 1! 2! 3!", refusal{false, false}},
	} {
		b, err := convertbase.ResolveBase(reg, "", cb.spec, nil)
		if err != nil {
			t.Fatalf("%q: %v", cb.spec, err)
		}
		want[b] = cb.refusal
		bases = append(bases, b)
	}
	for _, b := range bases {
		for _, upper := range []bool{false, true} {
			c := &conversion{f: &cliFlags{lower: !upper, upper: upper}, to: b}
			err := c.checkOutputFlags()
			if w, custom := want[b]; custom && (err != nil) != (upper && w.upper || !upper && w.lower) {
				t.Errorf("%q upper=%v: got %v, want refused=%v", b.Symbols, upper, err, upper && w.upper || !upper && w.lower)
			}
			if err != nil {
				continue
			}
			all := strings.Join(b.Symbols, "")
			for path, out := range map[string]string{"number": recaseDigits(all, b, upper), "byte": recaseBytePath(all, b, upper)} {
				back, err := b.Tokenize(out)
				if err != nil || !slices.Equal(back, b.Symbols) {
					t.Errorf("%s upper=%v %s path: allowed, but %q doesn't read back (%v)", b.Name(), upper, path, out, err)
				}
			}
		}
	}
}

// The help names every flag the parser takes, and the query flags that pick a
// base show it as an argument.
// Test ID: ErsskKE
func TestHelpListsEveryFlag(t *testing.T) {
	f, err := parseFlags(nil)
	if err != nil {
		t.Fatal(err)
	}
	reg, err := convertbase.NewRegistry()
	if err != nil {
		t.Fatal(err)
	}
	var help strings.Builder
	printHelp(&help, reg, nil, etcConfigPath, "", "", "", "", "")
	text := help.String()
	f.fs.VisitAll(func(fl *flag.Flag) {
		name := "--" + fl.Name
		if len(fl.Name) == 1 {
			name = "-" + fl.Name
		}
		if !regexp.MustCompile(`(^|[\s,])` + regexp.QuoteMeta(name) + `([\s,]|$)`).MatchString(text) {
			t.Errorf("help does not list %s", name)
		}
	})
	for _, q := range []string{"--get-base-name", "--show-symbols", "--show-symbols-0"} {
		if !strings.Contains(text, "\n  "+q+" BASE") {
			t.Errorf("help lists %s without its BASE argument", q)
		}
	}
}

// A positional after the NUMBER that looks like a flag gets the flags-first
// hint, so no built-in base may look like one.
// Test ID: ErsskKs
func TestNoBuiltinBaseLooksLikeFlag(t *testing.T) {
	reg, err := convertbase.NewRegistry()
	if err != nil {
		t.Fatal(err)
	}
	for _, b := range reg.OrderedBases() {
		for _, a := range b.Aliases {
			if looksLikeFlag(a) {
				t.Errorf("base %q alias %q looks like a flag", b.Name(), a)
			}
		}
	}
	for _, s := range []string{"-5", "-123", "-.5", "-", "5"} {
		if looksLikeFlag(s) {
			t.Errorf("%q reads as a flag", s)
		}
	}
	for _, s := range []string{"--lower", "--", "-x", "-N", "--5"} {
		if !looksLikeFlag(s) {
			t.Errorf("%q does not read as a flag", s)
		}
	}
}

// What each flag does in each mode, as the "Flags by mode" table in design.md
// has it. Every flag the parser takes is covered in every mode it can be given
// in, so a new flag can't skip the rule.
// Test ID: ErsveFb
func TestIdleFlagNotes(t *testing.T) {
	reg, err := convertbase.NewRegistry()
	if err != nil {
		t.Fatal(err)
	}
	tz, err := reg.Lookup("2048tz")
	if err != nil {
		t.Fatal(err)
	}
	tzDigit := tz.Symbols[1]
	const dashDot = "0 1 2 3 4 5 6 7 8 9 a b c d - ."
	type want int
	const (
		used want = iota
		noted
		usage // refused, exit 2
		base  // refused, exit 1: the base can't take it
	)
	cases := []struct {
		mode, flag string
		want       want
		args       []string
	}{
		{"number", "from", used, []string{"--from", "10", "255"}},
		{"number", "to", used, []string{"--to", "16", "255"}},
		{"number", "from-symbols", used, []string{"--from-symbols", "0 1 2 3 4 5 6 7 8 9", "255"}},
		{"number", "to-symbols", used, []string{"--to-symbols", "0 1", "255"}},
		{"number", "from-neg", used, []string{"--from-neg", "~", "255"}},
		{"number", "from-dec", used, []string{"--from-dec", ",", "255"}},
		{"number", "to-neg", used, []string{"--to-neg", "~", "255"}},
		{"number", "to-dec", used, []string{"--to-dec", ",", "255"}},
		{"number", "from-pad", noted, []string{"--from", "16", "--from-pad", "=", "FF"}},
		{"number", "to-pad", noted, []string{"--to", "64", "--to-pad", "=", "255"}},
		{"number", "from-tail", noted, []string{"--from", "2048tz", "--from-tail=", tzDigit}},
		{"number", "to-tail", noted, []string{"--to", "2048tz", "--to-tail=", "255"}},
		{"number", "precision", used, []string{"--precision", "3", "1.5"}},
		{"number", "lower", used, []string{"--lower", "--to", "16", "255"}},
		{"number", "upper", used, []string{"--upper", "--to", "16", "255"}},
		{"number", "lower", base, []string{"--lower", "--to", "62", "255"}},
		{"number", "lower", usage, []string{"--lower", "--upper", "255"}},
		{"number", "escape-controls", used, []string{"--escape-controls", "--to", "keyboard", "255"}},
		{"number", "no-newline", used, []string{"-n", "255"}},
		{"number", "number", used, []string{"--number", "--from", "16", "--to", "64", "FF"}},
		{"number", "by-index", noted, []string{"--by-index", "3", "255"}},
		{"number", "config", used, []string{"--config", "/nonexistent", "255"}},
		{"number", "precision", usage, []string{"--precision", "foo", "255"}},

		{"byte", "from", used, []string{"--binary", "--from", "16", "dead"}},
		{"byte", "to", used, []string{"--binary", "--to", "64", "-"}},
		{"byte", "from-symbols", used, []string{"--binary", "--from-symbols", "0 1", "--to", "16", "0101"}},
		{"byte", "to-symbols", used, []string{"--from", "bytes", "--to-symbols", "0 1", "-"}},
		{"byte", "from-neg", noted, []string{"--binary", "--from", "16", "--from-neg", "~", "--to", "64", "dead"}},
		{"byte", "from-dec", noted, []string{"--binary", "--from", "16", "--from-dec", ",", "--to", "64", "dead"}},
		{"byte", "to-neg", noted, []string{"--binary", "--from", "16", "--to", "64", "--to-neg", "~", "dead"}},
		{"byte", "to-dec", noted, []string{"--binary", "--from", "16", "--to", "64", "--to-dec=", "dead"}},
		{"byte", "from-neg", used, []string{"--binary", "--from-symbols", dashDot, "--from-neg=", "--from-dec=", "--to", "64", "dead"}},
		{"byte", "from-dec", used, []string{"--binary", "--from-symbols", dashDot, "--from-neg=", "--from-dec", "~", "--to", "64", "dead"}},
		{"byte", "to-neg", used, []string{"--from", "bytes", "--to-symbols", dashDot, "--to-neg", "~", "--to-dec=", "-"}},
		{"byte", "to-dec", used, []string{"--from", "bytes", "--to-symbols", dashDot, "--to-neg=", "--to-dec=", "-"}},
		{"byte", "from-neg", base, []string{"--from", "bytes", "--from-neg", "~", "--to", "64", "-"}},
		{"byte", "from-pad", used, []string{"--binary", "--from", "16", "--from-pad", "=", "--to", "64", "dead"}},
		{"byte", "to-pad", used, []string{"--binary", "--from", "16", "--to", "64", "--to-pad", "=", "dead"}},
		{"byte", "from-tail", used, []string{"--from", "2048tz", "--from-tail=", "--to", "bytes", "-"}},
		{"byte", "to-tail", used, []string{"--from", "bytes", "--to", "2048tz", "--to-tail=", "-"}},
		{"byte", "precision", noted, []string{"--binary", "--precision", "3", "--from", "16", "--to", "64", "dead"}},
		{"byte", "precision", usage, []string{"--binary", "--precision", "-1", "--from", "16", "--to", "64", "dead"}},
		{"byte", "lower", used, []string{"--binary", "--lower", "--from", "16", "--to", "32", "dead"}},
		{"byte", "upper", used, []string{"--binary", "--upper", "--from", "16", "--to", "32", "dead"}},
		{"byte", "escape-controls", usage, []string{"--escape-controls", "--binary", "--from", "16", "--to", "64", "dead"}},
		{"byte", "escape-controls", usage, []string{"--escape-controls", "--from", "keyboard", "--to", "bytes", "-"}},
		{"byte", "no-newline", used, []string{"-n", "--binary", "--from", "16", "--to", "64", "dead"}},
		{"byte", "no-newline", noted, []string{"--no-newline", "--from", "16", "--to", "bytes", "dead"}},
		{"byte", "binary", used, []string{"--binary", "--from", "16", "--to", "64", "dead"}},
		{"byte", "binary", used, []string{"-b", "--from", "bytes", "--to", "64", "-"}},
		{"byte", "number", noted, []string{"--number", "--from", "bytes", "--to", "64", "-"}},
		{"byte", "number", usage, []string{"--binary", "-N", "--from", "16", "--to", "64", "dead"}},
		{"byte", "by-index", noted, []string{"--binary", "--by-index", "3", "--from", "16", "--to", "64", "dead"}},
		{"byte", "config", used, []string{"--binary", "--config", "/nonexistent", "--from", "16", "--to", "64", "dead"}},

		{"query", "from", noted, []string{"--from", "16", "--show-symbols", "hex"}},
		{"query", "to", noted, []string{"--to", "16", "--show-symbols", "hex"}},
		{"query", "from-symbols", noted, []string{"--from-symbols", "0 1", "--get-base-name", "hex"}},
		{"query", "to-symbols", noted, []string{"--to-symbols", "0 1", "--get-base-name", "hex"}},
		{"query", "from-neg", noted, []string{"--from-neg", "~", "--list"}},
		{"query", "from-dec", noted, []string{"--from-dec", "~", "--list"}},
		{"query", "from-pad", noted, []string{"--from-pad", "=", "--list"}},
		{"query", "from-tail", noted, []string{"--from-tail=", "--list"}},
		{"query", "to-neg", noted, []string{"--to-neg", "~", "--list"}},
		{"query", "to-dec", noted, []string{"--to-dec", "~", "--list"}},
		{"query", "to-pad", noted, []string{"--to-pad", "=", "--list"}},
		{"query", "to-tail", noted, []string{"--to-tail=", "--list"}},
		{"query", "precision", noted, []string{"--precision", "3", "--get-index-count"}},
		{"query", "lower", noted, []string{"--lower", "--show-symbols", "hex"}},
		{"query", "upper", noted, []string{"--upper", "--show-symbols", "hex"}},
		{"query", "escape-controls", used, []string{"--escape-controls", "--show-symbols", "keyboard"}},
		{"query", "escape-controls", noted, []string{"--escape-controls", "--show-symbols-0", "keyboard"}},
		{"query", "no-newline", noted, []string{"-n", "--show-symbols", "hex"}},
		{"query", "binary", used, []string{"--binary", "--show-symbols", "hex"}},
		{"query", "number", used, []string{"--num", "--list"}},
		{"query", "list", used, []string{"--list"}},
		{"query", "list-compat", used, []string{"--list-compat"}},
		{"query", "list-compat", used, []string{"--list", "--list-compat"}},
		{"query", "get-index-count", used, []string{"--get-index-count"}},
		{"query", "get-index-count", noted, []string{"--list-compat", "--get-index-count"}},
		{"query", "get-base-name", used, []string{"--get-base-name", "hex"}},
		{"query", "get-base-name", noted, []string{"--get-index-count", "--get-base-name"}},
		{"query", "show-symbols", used, []string{"--show-symbols", "hex"}},
		{"query", "show-symbols", noted, []string{"--get-base-name", "--show-symbols", "hex"}},
		{"query", "show-symbols-0", used, []string{"--show-symbols-0", "hex"}},
		{"query", "show-symbols", noted, []string{"--show-symbols-0", "--show-symbols", "hex"}},
		{"query", "by-index", used, []string{"--by-index", "3", "--show-symbols"}},
		{"query", "by-index", noted, []string{"--by-index", "3", "--list"}},
		{"query", "config", used, []string{"--config", "/nonexistent", "--list"}},
		{"query", "show-symbols", usage, []string{"--show-symbols", "hex", "--lower"}},
		{"query", "show-symbols", usage, []string{"--by-index", "3", "--show-symbols", "hex"}},
		{"query", "list", usage, []string{"--list", "foo"}},
	}

	covered := map[string]bool{}
	for _, c := range cases {
		covered[c.mode+" "+c.flag] = true
		f, err := parseFlags(c.args)
		if err != nil {
			t.Fatalf("%q: %v", c.args, err)
		}
		var notes []string
		if q := f.query(); q != "" {
			if c.mode != "query" {
				t.Fatalf("%q: ran as query %s", c.args, q)
			}
			if err = checkQueryArgs(f, q); err == nil {
				notes = idleNotes(f, func(name string) string { return queryIdle(q, name) })
			}
		} else {
			var conv *conversion
			if conv, err = planConversion(reg, f); err == nil {
				notes = conv.notes
				if got := conv.byteMode(); got != (c.mode == "byte") {
					t.Errorf("%q: byte mode is %v", c.args, got)
				}
			}
		}
		var isUsage usageError
		switch {
		case c.want == usage || c.want == base:
			if err == nil || errors.As(err, &isUsage) != (c.want == usage) {
				t.Errorf("%q: want refused with exit %d, got %v", c.args, map[want]int{usage: 2, base: 1}[c.want], err)
			}
			continue
		case err != nil:
			t.Errorf("%q: %v", c.args, err)
			continue
		}
		prefix := "note: --" + c.flag + " does nothing "
		hit := slices.ContainsFunc(notes, func(n string) bool { return strings.HasPrefix(n, prefix) })
		if hit != (c.want == noted) {
			t.Errorf("%q: --%s noted is %v, want %v; notes %q", c.args, c.flag, hit, c.want == noted, notes)
		}
		for _, n := range notes {
			if strings.Contains(n, "does nothing") && !strings.HasPrefix(n, prefix) {
				t.Errorf("%q: unexpected %q", c.args, n)
			}
		}
	}

	f, err := parseFlags(nil)
	if err != nil {
		t.Fatal(err)
	}
	f.fs.VisitAll(func(fl *flag.Flag) {
		name := longFlagName(fl.Name)
		if programInfo[name] {
			return
		}
		for _, mode := range []string{"number", "byte", "query"} {
			if mode != "query" && (strings.HasPrefix(name, "list") || strings.HasPrefix(name, "get-") || strings.HasPrefix(name, "show-")) {
				continue // a query flag makes it a query
			}
			if mode == "number" && name == "binary" {
				continue // --binary makes it byte mode
			}
			if !covered[mode+" "+name] {
				t.Errorf("no %s mode case for --%s", mode, fl.Name)
			}
		}
	})
}

// programInfo are the program info flags, which print and exit before any other
// flag is looked at.
var programInfo = map[string]bool{"help": true, "version": true, "about": true, "donate": true, "examples": true}

func longFlagName(name string) string {
	if long, ok := map[string]string{"n": "no-newline", "b": "binary", "bin": "binary", "N": "number", "num": "number", "h": "help", "v": "version", "V": "version"}[name]; ok {
		return long
	}
	return name
}

// design.md's "Flags by mode" table has a row for every flag the parser takes.
// Test ID: ErsveGF
func TestDesignTableListsEveryFlag(t *testing.T) {
	raw, err := os.ReadFile(filepath.Join("..", "..", "..", "project", "design.md"))
	if err != nil {
		t.Fatal(err)
	}
	_, table, found := strings.Cut(string(raw), "\n#### Flags by mode\n")
	if !found {
		t.Fatal(`design.md has no "Flags by mode" section`)
	}
	table, _, _ = strings.Cut(table, "\n#")
	rows := map[string]bool{}
	for _, line := range strings.Split(table, "\n") {
		if !strings.HasPrefix(line, "| `-") {
			continue
		}
		first, _, _ := strings.Cut(line[1:], "|")
		for _, m := range regexp.MustCompile("`(-[^`]+)`").FindAllStringSubmatch(first, -1) {
			rows[m[1]] = true
		}
	}
	f, err := parseFlags(nil)
	if err != nil {
		t.Fatal(err)
	}
	f.fs.VisitAll(func(fl *flag.Flag) {
		name := "--" + fl.Name
		if len(fl.Name) == 1 {
			name = "-" + fl.Name
		}
		if !rows[name] {
			t.Errorf("design.md's flag table has no row for %s", name)
		}
	})
}
