//	Copyright © 2026 Jim Collier (ID: 1cv◂‡Vᛦ)
//	Licensed under the GNU General Public License v2.0 or later. Full text at:
//		https://spdx.org/licenses/GPL-2.0-or-later.html
//	SPDX-License-Identifier: GPL-2.0-or-later

package main

import (
	_ "embed"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/jim-collier/convert-base-v2/shcl"
)

// defaultConfig is written verbatim to the user config path on first run, so
// the documented example and the file people actually edit can't drift apart.
//
//go:embed default-config.shcl
var defaultConfig string

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
func (r *Registry) LoadConfig(path string) error {
	if path == "" {
		return nil
	}
	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return nil
		}
		return err
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

// checkConfigFields rejects anything the loader would not read. Paths() is the
// union of every path in the file, so one pass covers all the base blocks.
func checkConfigFields(doc *shcl.Document) error {
	for _, p := range doc.Paths() {
		name, field, nested := strings.Cut(strings.ToLower(p), ".")
		if name != "base" {
			return fmt.Errorf("unknown setting %q (this file holds \"base:\" blocks only)", p)
		}
		if nested && !configBaseFields[field] {
			return fmt.Errorf("unknown base field %q", field)
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
		// finalize() rejects a tail the base can't use.
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

// ensureUserConfig writes the shipped default the first time the program runs,
// so the path in the help text points at a real file to read and edit instead
// of at nothing. Reports whether it created one.
//
// Failure is deliberately silent: the config is optional, every built-in base
// still works without it, and a read-only home shouldn't make every run noisy.
func ensureUserConfig(path string) bool {
	if path == "" {
		return false
	}
	if _, err := os.Stat(path); err == nil || !os.IsNotExist(err) {
		return false
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return false
	}
	return os.WriteFile(path, []byte(defaultConfig), 0o644) == nil
}

// legacyConfigPath is the pre-SHCL name of a config file. Nothing reads one any
// more, so the only thing left to do about it is say so once, when its
// replacement is created.
func legacyConfigPath(path string) string {
	return strings.TrimSuffix(path, ".shcl") + ".conf"
}
