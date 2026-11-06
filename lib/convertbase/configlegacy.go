//	Copyright © 2023-2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
//	Licensed under the Apache License, Version 2.0. Full text in ./LICENSE, or:
//		https://spdx.org/licenses/Apache-2.0.html
//	SPDX-License-Identifier: Apache-2.0

package convertbase

import (
	"errors"
	"fmt"
	"strings"

	shcl12 "github.com/jim-collier/convert-base-v2/lib/shcl/old12"
)

// The config loader as v3.0.0 had it, over the SHCL 1.2.0 it shipped with. It
// is how a file with no Format line is read: exactly the way the last release
// before Format 3 read it, errors included. Keep it as it is. A change here
// changes what an old file means.

// legacyFields reads every base in an old config the way v3.0.0 did, and
// checks each as v3.0.0's Register did.
func legacyFields(text string) ([]configFields, error) {
	doc := shcl12.Parse(text)
	var lines []string
	for _, d := range doc.Diagnostics() {
		if d.Severity == shcl12.SeverityError {
			lines = append(lines, fmt.Sprintf("line %d: %s", d.Line, d.Message))
		}
	}
	if len(lines) > 3 {
		lines = append(lines[:3], fmt.Sprintf("(and %d more)", len(lines)-3))
	}
	if len(lines) > 0 {
		return nil, errors.New(strings.Join(lines, "; "))
	}
	if err := legacyCheckFields(doc); err != nil {
		return nil, err
	}
	var out []configFields
	for i := 0; i < doc.Count("base"); i++ {
		sel := fmt.Sprintf("base[#%d]", i)
		f, err := legacyBase(doc, sel)
		if err != nil {
			return nil, err
		}
		if err := legacyListInOneValue(doc, sel, f.name); err != nil {
			return nil, err
		}
		if err := f.base().check(); err != nil {
			return nil, fmt.Errorf("%s%w", legacyCite(doc, sel), err)
		}
		out = append(out, f)
	}
	return out, nil
}

// legacyListInOneValue refuses a one-value field written as a comma list. The
// SHCL releases before 3.0 joined one into text differently: 1.0.0-beta1 with
// the quotes dropped, 1.x adding them where needed, and 2.0.0 keeping them as
// typed. Nothing says which one wrote the file. This check is not v3.0.0's.
func legacyListInOneValue(doc *shcl12.Document, sel, name string) error {
	for _, field := range []string{"", "negative", "decimal", "pad"} {
		path, what := sel, "the name"
		if field != "" {
			path, what = sel+"."+field, field
		}
		if r := doc.ReadStringArray(path); r.Status == shcl12.Good && len(r.Value) > 1 {
			return fmt.Errorf("%sbase %q: %s is a comma list, which SHCL read differently from version to version; quote it",
				legacyCite(doc, path), name, what)
		}
	}
	return nil
}

func legacyCite(doc *shcl12.Document, path string) string {
	for _, n := range doc.Lines(path) {
		if n > 0 {
			return fmt.Sprintf("line %d: ", n)
		}
	}
	return ""
}

func legacyRepeated(doc *shcl12.Document, path, base, field string) error {
	msg := fmt.Sprintf("base %q: %s is given more than once", base, field)
	lines := doc.Lines(path)
	if len(lines) < 2 || lines[0] < 1 || lines[1] < 1 {
		return errors.New(msg)
	}
	return fmt.Errorf("line %d: %s (first at line %d)", lines[1], msg, lines[0])
}

func legacyCheckFields(doc *shcl12.Document) error {
	for _, name := range doc.Children("") {
		if !strings.EqualFold(name, "base") {
			return fmt.Errorf("%sunknown setting %q (this file holds \"base:\" blocks only)",
				legacyCite(doc, shcl12.QuoteSegment(name)), name)
		}
	}
	for i := 0; i < doc.Count("base"); i++ {
		sel := fmt.Sprintf("base[#%d]", i)
		name := strings.TrimSpace(doc.ReadString(sel).Value)
		seen := make(map[string]bool)
		for _, field := range doc.Children(sel) {
			key := strings.ToLower(field)
			path := sel + "." + shcl12.QuoteSegment(field)
			if !configBaseFields[key] {
				return fmt.Errorf("%sbase %q: unknown field %q", legacyCite(doc, path), name, field)
			}
			if seen[key] {
				return legacyRepeated(doc, path, name, field)
			}
			seen[key] = true
		}
	}
	return nil
}

func legacyBase(doc *shcl12.Document, sel string) (configFields, error) {
	f := configFields{name: strings.TrimSpace(doc.ReadString(sel).Value)}
	if f.name == "" {
		return f, fmt.Errorf(`%sa "base:" line has no name`, legacyCite(doc, sel))
	}
	f.aliases = doc.GetStringArrayOr(sel+".aliases", nil)
	var err error
	if f.symbols, err = legacySymbols(doc, sel+".symbols", f.name, "symbols"); err != nil {
		return f, err
	}
	if len(f.symbols.digits) == 0 {
		return f, fmt.Errorf("%sbase %q: missing 'symbols'", legacyCite(doc, sel), f.name)
	}
	if f.tail, err = legacySymbols(doc, sel+".tail", f.name, "tail"); err != nil {
		return f, err
	}
	f.negative = legacyMarker(doc, sel+".negative")
	f.decimal = legacyMarker(doc, sel+".decimal")
	f.pad = legacyMarker(doc, sel+".pad")
	switch r := doc.ReadBool(sel + ".pademit"); r.Status {
	case shcl12.Good:
		v := r.Value
		f.pademit = &v
	case shcl12.BadType:
		return f, fmt.Errorf("%sbase %q: pademit must be true or false",
			legacyCite(doc, sel+".pademit"), f.name)
	}
	return f, nil
}

func legacySymbols(doc *shcl12.Document, path, baseName, field string) (symbolField, error) {
	read := doc.ReadStringArray(path)
	switch read.Status {
	case shcl12.NotFound, shcl12.Empty:
		return symbolField{}, nil
	case shcl12.Multiple:
		return symbolField{}, legacyRepeated(doc, path, baseName, field)
	}
	if len(read.Value) == 1 {
		symbols, err := ParseSymbolSpec(read.Value[0])
		if err != nil {
			return symbolField{}, fmt.Errorf("%sbase %q: %s: %w", legacyCite(doc, path), baseName, field, err)
		}
		spec := read.Value[0]
		return symbolField{spec: &spec, digits: symbols}, nil
	}
	return symbolField{digits: read.Value}, nil
}

func legacyMarker(doc *shcl12.Document, path string) *string {
	r := doc.ReadString(path)
	switch r.Status {
	case shcl12.Good:
		v := r.Value
		return &v
	case shcl12.Empty:
		return strPtr("")
	}
	return nil
}
