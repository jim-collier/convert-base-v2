//	Copyright © 2023-2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
//	Licensed under the GPL, Version 2 or later. Full text in ../../../license.md, or:
//		https://spdx.org/licenses/GPL-2.0-or-later.html
//	SPDX-License-Identifier: GPL-2.0-or-later

// Builds lib/convertbase/testdata/legacy-config-corpus.jsonl, the config texts
// TestLegacyConfigCorpus walks. Run it through gen.bash, which fetches every
// SHCL release before 3.0 into old/ beside this file; it does not build here.
//
// Each text is read by each old release the way v3.0.0's loader read it,
// written again here rather than taken from the library, and by the current
// loader. The current one may refuse a text, but when it loads one it has to
// load the base 1.2.0 did, and no release may have loaded a different one. A
// run that finds otherwise fails and writes nothing.
package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"flag"
	"fmt"
	"math/rand"
	"os"
	"path/filepath"
	"strings"

	cb "github.com/jim-collier/convert-base-v2/lib/convertbase"

	"legacycorpus/rec"

	o100 "legacycorpus/old/v1_0_0"
	o100b1 "legacycorpus/old/v1_0_0_beta1"
	o100b2 "legacycorpus/old/v1_0_0_beta2"
	o100rc1 "legacycorpus/old/v1_0_0_rc1"
	o110 "legacycorpus/old/v1_1_0"
	o120 "legacycorpus/old/v1_2_0"
	o200 "legacycorpus/old/v2_0_0"
)

type version struct {
	name string
	read func(string) rec.Raw
}

var versions = []version{
	{"1.0.0-beta1", o100b1.ReadRec},
	{"1.0.0-beta2", o100b2.ReadRec},
	{"1.0.0-rc1", o100rc1.ReadRec},
	{"1.0.0", o100.ReadRec},
	{"1.1.0", o110.ReadRec},
	{"1.2.0", o120.ReadRec},
	{"2.0.0", o200.ReadRec},
}

const shipped = 5 // 1.2.0, the SHCL v3.0.0 read its config with

var known = map[string]bool{"aliases": true, "symbols": true, "negative": true, "decimal": true, "pad": true, "pademit": true, "tail": true}

// record must match the one in lib/convertbase/legacycorpus_test.go.
func record(b *cb.Base) string {
	ptr := func(p *string) string {
		if p == nil {
			return "-"
		}
		return fmt.Sprintf("%q", *p)
	}
	r := fmt.Sprintf("%q|%q|%q|%q|%s|%s|%q|%t", b.Aliases, b.Symbols, b.TailSymbols, b.BinaryScheme,
		ptr(b.Negative), ptr(b.Decimal), b.PadSymbol, b.PadEmit)
	sum := sha256.Sum256([]byte(r))
	return "L" + hex.EncodeToString(sum[:8])
}

func symbols(f rec.Field) ([]string, bool) {
	switch f.ArrSt {
	case "NotFound", "Empty":
		return nil, true
	case "Multiple":
		return nil, false
	}
	if len(f.Arr) == 1 {
		s, err := cb.ParseSymbolSpec(f.Arr[0])
		return s, err == nil
	}
	return f.Arr, true
}

func marker(f rec.Field) *string {
	switch f.StrSt {
	case "Good":
		v := f.Str
		return &v
	case "Empty":
		v := ""
		return &v
	}
	return nil
}

// oldOutcome is v3.0.0's loader over one release's reads, then its Register.
func oldOutcome(r rec.Raw) (string, string) {
	if r.ParseErr != "" || r.Count != 1 || r.Name == "" {
		return "R", ""
	}
	if r.HasChildren {
		seen := map[string]bool{}
		for _, c := range r.Children {
			k := strings.ToLower(c)
			if !known[k] || seen[k] {
				return "R", ""
			}
			seen[k] = true
		}
	}
	b := &cb.Base{Aliases: []string{r.Name}}
	if f := r.Fields["aliases"]; f.ArrSt == "Good" {
		b.Aliases = append(b.Aliases, f.Arr...)
	}
	syms, ok := symbols(r.Fields["symbols"])
	if !ok || len(syms) == 0 {
		return "R", ""
	}
	b.Symbols = syms
	tail, ok := symbols(r.Fields["tail"])
	if !ok {
		return "R", ""
	}
	if len(tail) > 0 {
		b.TailSymbols = tail
		b.BinaryScheme = "qntm"
	}
	b.Negative = marker(r.Fields["negative"])
	b.Decimal = marker(r.Fields["decimal"])
	if p := marker(r.Fields["pad"]); p != nil {
		b.PadSymbol = *p
		b.PadEmit = *p != ""
	}
	switch pe := r.Fields["pademit"]; pe.BoolSt {
	case "Good":
		b.PadEmit = pe.Bool
	case "BadType":
		return "R", ""
	}
	reg, err := cb.NewRegistry()
	if err != nil {
		panic(err)
	}
	if err := reg.Register(b); err != nil {
		return "R", ""
	}
	return record(b), r.Name
}

var tmpDir string

func newOutcome(text string, names []string) string {
	p := filepath.Join(tmpDir, "convert-base-v2.shcl")
	if err := os.WriteFile(p, []byte(text), 0o600); err != nil {
		panic(err)
	}
	reg, err := cb.NewRegistry()
	if err != nil {
		panic(err)
	}
	if err := reg.LoadConfig(p); err != nil {
		return "R"
	}
	for _, n := range append(names, "bt") {
		if b, err := reg.Lookup(n); err == nil && b.Source == p {
			return record(b)
		}
	}
	return "L?"
}

var pieces = []string{
	"a", "b", "z", "0", "1", "9", "x", "é", "😀", "AB",
	" ", "  ", "\t", ",", ", ", ",,", "\"", "'", "`", "\\", "\\\\",
	"\\t", "\\n", "\\r", "\\ ", "\\,", "\\#", "\\'", "\\\"", "\\u00e9", "\\u0041", "\\x41", "\\0", "\\a",
	"#", " #", " # c", ":", ": ", "[", "]", "[#0]", "{", "}", "(", ")", "-", "- ", "* ", "*", "=", ";",
	"C:\\temp", "C:\\new", "\\\\server\\share", "~", "~~", "@", "$", "%", "&", "!", "?", "/", "|", "<", ">",
	"true", "false", "yes", "no", "null", "1,000", "1_000", "0x10", "1.5", "-3", "+", ".",
	"◉", "◉TAB◉", "◉NEWLINE◉", "◉U+00E9◉", "\u00a0", "\u200b",
}

func randValue(rng *rand.Rand) string {
	n := 1 + rng.Intn(5)
	var sb strings.Builder
	for i := 0; i < n; i++ {
		sb.WriteString(pieces[rng.Intn(len(pieces))])
	}
	v := sb.String()
	switch rng.Intn(6) {
	case 0:
		v = `"` + v + `"`
	case 1:
		v = `'` + v + `'`
	case 2:
		v = "[" + v + "]"
	}
	return v
}

var hand = []string{
	``, `0123`, `01`, `0 1 2 3`, `"0 1 2 3"`, `'0 1 2 3'`, `0,1,2,3`, `0, 1, 2, 3`, `"0, 1", 2`, `a b, c`,
	`[ab]`, `[a, b]`, `[a,b]`, `"[ab]"`, `a\ b c`, `"a\ b c"`, `"a\\ b c"`, `'a\ b c'`, `x\ty`, `"x\ty"`, `'x\ty'`,
	`\\ x`, `"\\\\ x"`, `"\u00e9 x"`, `a\, b`, `a\#b c`, `"a\ b"`, `a\'b c`, `C:\temp x`, `C:\new x`, `"C:\temp x"`,
	`'C:\new x'`, `a#b`, `a #b`, `"a#b"`, `a:b`, `a: b`, `"a: b"`, `- a`, `* a`, `a"b`, `a'b`, `it's`, `'it''s'`,
	`"a\"b"`, `'a"b'`, "`ab`", `😀 😑 😔`, `"😀 😑 😔 😘"`, `🥕`, `"🥕"`, `-`, `.`, `""`, `''`, `"" x`, `x ""`,
	`true`, `false`, `yes`, `0`, `1`, `"true"`, `a  b`, ` a`, `a `, `a,`, `,a`, `a,,b`, `"a",b`, `"a", "b"`,
	`'a', 'b'`, `a, "b c"`, `[a, "b c"]`, `[]`, `[ ]`, `[[a]]`, `a[b]`, `a]`, `x◉TAB◉y`, `"x◉TAB◉y"`, `◉`,
	`\`, `"\"`, `'\'`, `"\`, `a\`, `\u00e9`, `\n`, `"\n"`, `"\r"`, `"\0"`, `"\x41"`, `"\a"`, `"\/"`, `"\'"`, `'\''`,
	`,`, `","`, `','`, `, `, `;`, `,,`, `1,000`, `"1,000"`, `0x41`, `1e5`, `@null`, `"@null"`, `~~~`, `a ~~~`,
	`"a" # c`, `a # c`, "a\t# c", `o'clock, oc`, `jim's # mine`, `x, it's`, `'  # minus`, `~ # tilde`,
}

var shapes = []string{
	"base: bt\r\n\tsymbols: 0123\r\n",
	"\ufeffbase: bt\n\tsymbols: 0123\n",
	"base: bt\n    symbols: 0123\n",
	"base: bt\n  symbols: 0123\n  aliases: q, r\n",
	"BASE: bt\n\tSymbols: 0123\n",
	"# c\nbase: bt # c\n\tsymbols: 0123 # c\n\n# end\n",
	"base: bt\n\tsymbols: 0123\n\tsymbols: 01\n",
	"base: bt\n\tsymbols: 0123\n\tnegative:\n\tdecimal:\n",
	"base: bt\n\tsymbols:\n\t\t0123\n",
	"base: bt\n\tsymbols: 0123\n\t\tx: y\n",
	"base:\n\tsymbols: 0123\n",
	"base: \"b t\"\n\tsymbols: 0123\n",
	"base: bt\n\taliases: \"q, r\"\n\tsymbols: 0123\n",
	"base: bt\n\tsymbols: 0123\n\taliases:\n\t\t~~~\n\t\tq\n\t\t~~~\n",
	"base: bt\n\tsymbols: 01\n\ttail:\n\t\t~~~\n\t\tab\n",
}

// A tail needs a base of more than 256 digits. The corpus names that alphabet
// with bigMark rather than spelling it out each time, and the test expands it.
// bigAlphabet and bigMark must match the test's.
const bigMark = "<<512 digits>>"

func bigAlphabet() string {
	big := make([]rune, 512)
	for i := range big {
		big[i] = rune(0x4e00 + i)
	}
	return string(big)
}

type entry struct {
	Text string   `json:"t"`
	Old  []string `json:"o"`
	Want string   `json:"w"`
}

func main() {
	out := flag.String("out", "", "corpus file to write")
	full := flag.Int("full", 3000, "random values per field checked")
	keep := flag.Int("keep", 120, "random values per field written")
	flag.Parse()
	var err error
	if tmpDir, err = os.MkdirTemp(os.Getenv("TMPDIR"), "corpus"); err != nil {
		panic(err)
	}
	defer os.RemoveAll(tmpDir)

	big := bigAlphabet()
	build := func(field, v string) string {
		switch field {
		case "name":
			return "base: " + v + "\n\tsymbols: 0123\n"
		case "symbols":
			return "base: bt\n\tsymbols: " + v + "\n"
		case "tail":
			return "base: bt\n\tsymbols: " + big + "\n\ttail: " + v + "\n"
		}
		return "base: bt\n\tsymbols: 0123\n\t" + field + ": " + v + "\n"
	}
	type tc struct {
		text  string
		write bool
	}
	var cases []tc
	rng := rand.New(rand.NewSource(1))
	for _, f := range []string{"name", "symbols", "aliases", "negative", "decimal", "pad", "tail", "pademit"} {
		for _, v := range hand {
			cases = append(cases, tc{build(f, v), true})
		}
		for i := 0; i < *full; i++ {
			cases = append(cases, tc{build(f, randValue(rng)), i < *keep})
		}
	}
	for _, s := range shapes {
		cases = append(cases, tc{s, true})
	}

	var written []entry
	seen := map[string]bool{}
	bad, loads, refusals := 0, 0, 0
	for _, c := range cases {
		e := entry{Text: c.text}
		var names []string
		for _, v := range versions {
			o, name := oldOutcome(v.read(c.text))
			e.Old = append(e.Old, o)
			if name != "" {
				names = append(names, name)
			}
		}
		e.Want = newOutcome(c.text, names)
		if e.Want == "R" {
			refusals++
		} else {
			loads++
			ok := e.Want == e.Old[shipped]
			for _, o := range e.Old {
				ok = ok && (o == "R" || o == e.Want)
			}
			if !ok {
				bad++
				if bad <= 20 {
					fmt.Fprintf(os.Stderr, "loads differently: %q\n  old %v\n  new %s\n", c.text, e.Old, e.Want)
				}
			}
		}
		if c.write && !seen[c.text] {
			seen[c.text] = true
			e.Text = strings.ReplaceAll(e.Text, big, bigMark)
			written = append(written, e)
		}
	}
	fmt.Printf("%d texts: %d load as they did, %d refused, %d load differently\n", len(cases), loads-bad, refusals, bad)
	if bad > 0 {
		os.Exit(1)
	}
	if *out == "" {
		return
	}
	var sb strings.Builder
	head, _ := json.Marshal(map[string]any{"versions": func() []string {
		var n []string
		for _, v := range versions {
			n = append(n, v.name)
		}
		return n
	}(), "shipped": shipped})
	sb.Write(head)
	sb.WriteByte('\n')
	for _, e := range written {
		line, err := json.Marshal(e)
		if err != nil {
			panic(err)
		}
		sb.Write(line)
		sb.WriteByte('\n')
	}
	if err := os.WriteFile(*out, []byte(sb.String()), 0o644); err != nil {
		panic(err)
	}
	fmt.Printf("wrote %d texts to %s\n", len(written), *out)
}
