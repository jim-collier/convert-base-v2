//	Copyright © 2023-2026 Jim Collier (CryptogID: ѳ6ᴚ℈𐀘𐇦ɛ𐊁¥Mﾏb϶Δ𐌞)
//	Licensed under the Apache License, Version 2.0. Full text in ./LICENSE, or:
//		https://spdx.org/licenses/Apache-2.0.html
//	SPDX-License-Identifier: Apache-2.0

package convertbase

import (
	"errors"
	"fmt"
	"os"
	"strings"

	"github.com/jim-collier/convert-base-v2/lib/shcl"
)

// unreadableConfig marks a config file that could not be read at all, as
// opposed to one that was read and would not parse. Its message is the
// underlying error's, so marking costs nothing in the text anyone sees.
type unreadableConfig struct{ err error }

func (e unreadableConfig) Error() string { return e.err.Error() }
func (e unreadableConfig) Unwrap() error { return e.err }

// IsConfigUnreadable reports whether err means a config file could not be read
// at all. Callers decide what that is worth: a path nobody typed is optional
// and this means there is no config, while an explicitly named file that will
// not open is a typo worth refusing, since dropping it silently would convert
// with the wrong set of bases.
func IsConfigUnreadable(err error) bool {
	var u unreadableConfig
	return errors.As(err, &u)
}

// Fields a "base:" block may carry. An unrecognized one is a typo, and a typo
// that silently drops a marker is worse than a refused load.
var configBaseFields = map[string]bool{
	"aliases":  true,
	"symbols":  true,
	"negative": true,
	"decimal":  true,
	"pad":      true,
	"pademit":  true,
	"tail":     true,
}

// LoadConfig reads the SHCL config at path and registers each base it defines.
// A missing file is not an error. Each base's Source is set to the full path.
// Any other read failure comes back marked, for IsConfigUnreadable to sort out.
func (r *Registry) LoadConfig(path string) error {
	if path == "" {
		return nil
	}
	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return nil
		}
		// "Not there" does not always arrive as ErrNotExist. A sandbox with no
		// preopened directory reports EBADF, and a path whose parent is a file
		// reports ENOTDIR, so neither can be treated as a real failure here.
		return unreadableConfig{err}
	}
	// Both callers already name the file, so nothing below repeats the path.
	doc := shcl.Parse(string(data))
	if err := configParseError(doc); err != nil {
		return err
	}
	if err := checkConfigFields(doc); err != nil {
		return err
	}
	for i := 0; i < doc.Count("base"); i++ {
		b, err := configBase(doc, fmt.Sprintf("base[#%d]", i))
		if err != nil {
			return err
		}
		b.Source = path
		if err := r.Register(b); err != nil {
			return err
		}
	}
	r.LoadedConfigs = append(r.LoadedConfigs, path)
	return nil
}

// configParseError collects SHCL's per-line diagnostics into one error. The
// parser keeps going after a bad line, which is right for a log or a dashboard
// but not for a file that defines alphabets - there a dropped line is a base
// with the wrong digits, which nothing downstream can notice.
func configParseError(doc *shcl.Document) error {
	var lines []string
	for _, d := range doc.Diagnostics() {
		if d.Severity != shcl.SeverityError {
			continue
		}
		lines = append(lines, fmt.Sprintf("line %d: %s", d.Line, d.Message))
	}
	if len(lines) == 0 {
		return nil
	}
	if len(lines) > 3 {
		lines = append(lines[:3], fmt.Sprintf("(and %d more)", len(lines)-3))
	}
	return fmt.Errorf("%s", strings.Join(lines, "; "))
}

// checkConfigFields rejects anything the loader would not read, and anything it
// would read only once. Children() gives the names as written, in file order,
// with repeats kept, which is what both halves need: a repeat is how a field
// silently loses its value (the read comes back Multiple and the loader falls
// back to a default), and a name needing quotes is invisible to Paths().
func checkConfigFields(doc *shcl.Document) error {
	// A repeated "base" is how the file defines a second base, so only the
	// names are checked at the top level.
	for _, name := range doc.Children("") {
		if !strings.EqualFold(name, "base") {
			return fmt.Errorf("unknown setting %q (this file holds \"base:\" blocks only)", name)
		}
	}
	for i := 0; i < doc.Count("base"); i++ {
		sel := fmt.Sprintf("base[#%d]", i)
		name := strings.TrimSpace(doc.ReadString(sel).Value)
		seen := make(map[string]bool)
		for _, field := range doc.Children(sel) {
			key := strings.ToLower(field)
			if !configBaseFields[key] {
				return fmt.Errorf("base %q: unknown field %q", name, field)
			}
			if seen[key] {
				return fmt.Errorf("base %q: %s is given more than once", name, field)
			}
			seen[key] = true
		}
	}
	return nil
}

// configBase builds one base from the block at sel (a positional selector, so a
// name carrying a comma or a bracket still addresses cleanly).
func configBase(doc *shcl.Document, sel string) (*Base, error) {
	name := strings.TrimSpace(doc.ReadString(sel).Value)
	if name == "" {
		return nil, fmt.Errorf(`a "base:" line has no name`)
	}
	b := &Base{Aliases: append([]string{name}, doc.GetStringArrayOr(sel+".aliases", nil)...)}

	symbols, err := configSymbols(doc, sel+".symbols", name, "symbols")
	if err != nil {
		return nil, err
	}
	if len(symbols) == 0 {
		return nil, fmt.Errorf("base %q: missing 'symbols'", name)
	}
	b.Symbols = symbols

	tail, err := configSymbols(doc, sel+".tail", name, "tail")
	if err != nil {
		return nil, err
	}
	if len(tail) > 0 {
		b.TailSymbols = tail
		// A config tail always gets the qntm layout. It is the scheme that
		// streams cleanly both ways, so the file never has to name one.
		// Finalize() rejects a tail the base can't use.
		b.BinaryScheme = "qntm"
	}

	b.Negative = configMarker(doc, sel+".negative")
	b.Decimal = configMarker(doc, sel+".decimal")
	if pad := configMarker(doc, sel+".pad"); pad != nil {
		b.PadSymbol = *pad
		b.PadEmit = *pad != ""
	}
	// pademit lets a config define a strip-only pad: accepted on decode, never
	// written, like the builtin URL/hex variants.
	switch r := doc.ReadBool(sel + ".pademit"); r.Status {
	case shcl.Good:
		b.PadEmit = r.Value
	case shcl.BadType:
		return nil, fmt.Errorf("base %q: pademit must be true or false", name)
	}
	return b, nil
}

// configSymbols decodes a symbols-shaped field. SHCL splits a value on unquoted
// commas, so one element is the whitespace or comma delimited spelling and
// several are literal digits, one per element - which is how a symbol carrying a
// space or a comma of its own gets written.
func configSymbols(doc *shcl.Document, path, baseName, field string) ([]string, error) {
	read := doc.ReadStringArray(path)
	switch read.Status {
	case shcl.NotFound, shcl.Empty:
		return nil, nil
	case shcl.Multiple:
		return nil, fmt.Errorf("base %q: %s is given more than once", baseName, field)
	}
	if len(read.Value) == 1 {
		symbols, err := ParseSymbolSpec(read.Value[0])
		if err != nil {
			return nil, fmt.Errorf("base %q: %s: %w", baseName, field, err)
		}
		return symbols, nil
	}
	return read.Value, nil
}

// configMarker reads one marker field, keeping the tri-state the Base fields
// use: absent leaves the default alone, empty disables the marker on purpose,
// and a value sets it.
func configMarker(doc *shcl.Document, path string) *string {
	r := doc.ReadString(path)
	switch r.Status {
	case shcl.Good:
		v := r.Value
		return &v
	case shcl.Empty:
		return strPtr("")
	}
	return nil
}
