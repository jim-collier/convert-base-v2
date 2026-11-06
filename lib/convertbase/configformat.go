//	Copyright © 2023-2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
//	Licensed under the Apache License, Version 2.0. Full text in ./LICENSE, or:
//		https://spdx.org/licenses/Apache-2.0.html
//	SPDX-License-Identifier: Apache-2.0

package convertbase

import (
	"errors"
	"fmt"

	"github.com/jim-collier/convert-base-v2/lib/shcl"
)

// unstampedFormat is the SHCL format of a config file with no Format line.
// Every release before that line existed read its config with SHCL 1.x.
const unstampedFormat = 1

// ConfigUpgrade is a config file written for an older SHCL format, converted
// so the current parser reads it the way the old one did.
type ConfigUpgrade struct {
	// FromFormat is the SHCL format the file was written for. A file that
	// names none is taken as format 1.
	FromFormat int
	// Text is the converted file. It ends with the current Format line, so
	// converting it again changes nothing.
	Text string
	// Respelled is true when some value had to be written differently to keep
	// its meaning. When false, the file reads the same under both formats and
	// only gained the Format line.
	Respelled bool
}

// UpgradeConfig converts the text of a config file written for an older SHCL
// format, so that it loads to the same bases it did then. It returns nil when
// the text already names the current format. A file that names no format is
// an old one, read the way v3.0.0 read it.
//
// It refuses rather than guess. When the old loader refused the file, or a
// value cannot be written so it reads the same, the error says why, and
// nothing should be loaded from the file: a different alphabet with no error
// is worse than none.
func UpgradeConfig(text string) (*ConfigUpgrade, error) {
	from, stamped := shcl.FormatVersion(text)
	if stamped && from >= shcl.FormatMajor {
		return nil, nil
	}
	if !stamped {
		from = unstampedFormat
	}
	refuse := func(err error) (*ConfigUpgrade, error) {
		return nil, fmt.Errorf("written for SHCL format %d, and can't be converted to format %d as it is: %w",
			from, shcl.FormatMajor, err)
	}
	want, err := legacyFields(text)
	if err != nil {
		return refuse(err)
	}
	m := shcl.Migrate(text, true)
	// Workaround for shcl's Migrate: a file ending inside an unclosed raw block
	// comes back unchanged and unstamped, with nothing to say why. Unstamped,
	// it would be taken for an old file again on every load.
	if v, ok := shcl.FormatVersion(m.Text); !ok || v < shcl.FormatMajor {
		return refuse(errors.New("the conversion didn't finish; check for a raw block with no closing fence"))
	}
	// Workaround for shcl's Migrate, which reads some old lines differently
	// than the old parser did, such as an apostrophe before a comma or a '#'
	// in a bare value. Each field that reads differently is written again.
	out, err := rewriteToMatch(m.Text, want)
	if err != nil {
		return refuse(err)
	}
	// Registering checks nothing against the bases already there, so an empty
	// registry finds every fault a real load would, without building the
	// built-in set again.
	scratch := &Registry{byAlias: make(map[string]*Base)}
	if err := scratch.loadConfigText("", out); err != nil {
		return refuse(err)
	}
	return &ConfigUpgrade{FromFormat: from, Text: out, Respelled: !readsAs(text, want)}, nil
}

// readsAs reports whether text reads as want under the current rules.
func readsAs(text string, want []configFields) bool {
	doc := shcl.Parse(text)
	if doc.ErrorCount() > 0 || doc.Count("base") != len(want) {
		return false
	}
	for i, w := range want {
		got, err := readBaseBlock(doc, fmt.Sprintf("base(%d)", i))
		if err != nil || !sameFields(got, w) {
			return false
		}
	}
	return true
}

// rewriteToMatch writes again each field of text that does not read as want,
// keeping every other line as it is. A parse error is checked only after,
// since writing a field again can fix one Migrate left.
func rewriteToMatch(text string, want []configFields) (string, error) {
	doc, _ := shcl.ParseKeepLines(text, shcl.Standard)
	if doc.Count("base") != len(want) {
		return "", fmt.Errorf("it reads as %d bases, not %d", doc.Count("base"), len(want))
	}
	for i, w := range want {
		sel := fmt.Sprintf("base(%d)", i)
		got, err := readBaseBlock(doc, sel)
		if err == nil && sameFields(got, w) {
			continue
		}
		whole := err != nil
		for _, fix := range fieldWrites(sel, w) {
			if !whole && fix.same(got, w) {
				continue
			}
			if st := fix.write(doc); st != shcl.SetOk {
				return "", fmt.Errorf("%sbase %q: %s can't be written so it reads the same (%v)",
					citeLine(doc, fix.path), w.name, fix.field, st)
			}
		}
	}
	out, _ := doc.ToTextKeepLines()
	check := shcl.Parse(out)
	if err := configParseError(check); err != nil {
		return "", err
	}
	for i, w := range want {
		sel := fmt.Sprintf("base(%d)", i)
		if got, err := readBaseBlock(check, sel); err != nil || !sameFields(got, w) {
			return "", fmt.Errorf("%sbase %q doesn't read the same once converted", citeLine(check, sel), w.name)
		}
	}
	return out, nil
}

type fieldWrite struct {
	field, path string
	same        func(a, b configFields) bool
	write       func(doc *shcl.Document) shcl.SetStatus
}

func fieldWrites(sel string, w configFields) []fieldWrite {
	at := func(f string) string { return sel + "." + f }
	return []fieldWrite{
		{"the name", sel, func(a, b configFields) bool { return a.name == b.name },
			func(doc *shcl.Document) shcl.SetStatus { return doc.SetString(sel, w.name) }},
		{"aliases", at("aliases"), func(a, b configFields) bool { return sameStrings(a.aliases, b.aliases) },
			func(doc *shcl.Document) shcl.SetStatus { return writeList(doc, at("aliases"), w.aliases) }},
		{"symbols", at("symbols"), func(a, b configFields) bool { return sameStrings(a.symbols.digits, b.symbols.digits) },
			func(doc *shcl.Document) shcl.SetStatus { return writeSymbols(doc, at("symbols"), w.symbols) }},
		{"tail", at("tail"), func(a, b configFields) bool { return sameStrings(a.tail.digits, b.tail.digits) },
			func(doc *shcl.Document) shcl.SetStatus { return writeSymbols(doc, at("tail"), w.tail) }},
		{"negative", at("negative"), func(a, b configFields) bool { return samePtr(a.negative, b.negative) },
			func(doc *shcl.Document) shcl.SetStatus { return writeMarker(doc, at("negative"), w.negative) }},
		{"decimal", at("decimal"), func(a, b configFields) bool { return samePtr(a.decimal, b.decimal) },
			func(doc *shcl.Document) shcl.SetStatus { return writeMarker(doc, at("decimal"), w.decimal) }},
		{"pad", at("pad"), func(a, b configFields) bool { return samePtr(a.pad, b.pad) },
			func(doc *shcl.Document) shcl.SetStatus { return writeMarker(doc, at("pad"), w.pad) }},
		{"pademit", at("pademit"), func(a, b configFields) bool { return samePtr(a.pademit, b.pademit) },
			func(doc *shcl.Document) shcl.SetStatus {
				if w.pademit == nil {
					doc.Remove(at("pademit"))
					return shcl.SetOk
				}
				return doc.SetBool(at("pademit"), *w.pademit)
			}},
	}
}

func writeList(doc *shcl.Document, path string, v []string) shcl.SetStatus {
	switch len(v) {
	case 0:
		doc.Remove(path)
		return shcl.SetOk
	case 1:
		return doc.SetString(path, v[0])
	}
	return doc.SetStringArray(path, v)
}

func writeSymbols(doc *shcl.Document, path string, f symbolField) shcl.SetStatus {
	switch {
	case f.spec != nil:
		return doc.SetString(path, *f.spec)
	case len(f.digits) == 0:
		doc.Remove(path)
		return shcl.SetOk
	}
	return doc.SetStringArray(path, f.digits)
}

func writeMarker(doc *shcl.Document, path string, v *string) shcl.SetStatus {
	switch {
	case v == nil:
		doc.Remove(path)
		return shcl.SetOk
	case *v == "":
		return doc.SetEmpty(path)
	}
	return doc.SetString(path, *v)
}

func sameFields(a, b configFields) bool {
	return a.name == b.name && sameStrings(a.aliases, b.aliases) &&
		sameStrings(a.symbols.digits, b.symbols.digits) && sameStrings(a.tail.digits, b.tail.digits) &&
		samePtr(a.negative, b.negative) && samePtr(a.decimal, b.decimal) && samePtr(a.pad, b.pad) &&
		samePtr(a.pademit, b.pademit)
}

func sameStrings(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}

func samePtr[T comparable](a, b *T) bool {
	if a == nil || b == nil {
		return a == b
	}
	return *a == *b
}
