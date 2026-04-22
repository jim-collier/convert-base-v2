//	Copyright © 2026 Jim Collier (ID: 1cv◂‡Vᛦ)
//	Licensed under the GNU General Public License v2.0 or later. Full text at:
//		https://spdx.org/licenses/GPL-2.0-or-later.html
//	SPDX-License-Identifier: GPL-2.0-or-later

package main

import (
	"fmt"
	"io"
	"os"
	"sort"
	"strconv"
	"strings"

	"gopkg.in/yaml.v3"
)

// Base describes a numeric base: an ordered list of symbols (each one "digit"),
// plus optional negative and decimal markers for textual representation.
type Base struct {
	Aliases []string // first element is the canonical display name
	Symbols []string // len(Symbols) is the base radix

	// Negative and Decimal are the textual markers used for sign and the
	// fractional separator, respectively.
	//
	//   nil          - use the global default ("-" / ".")
	//   &""          - explicitly disabled (base doesn't support sign / decimal)
	//   &"X"         - explicit marker X
	//
	// If a nil (=default) marker collides with a digit symbol, finalize()
	// errors out rather than silently disabling the feature. To disable it
	// on purpose, point the field at an empty string.
	Negative *string
	Decimal  *string

	// Binary, if true, marks this base as the raw-binary mode: each of the
	// 256 digits is one literal byte value. Convert() uses bit-packing (O(N),
	// no big.Int) for roundtrips between binary and any other power-of-2
	// base (2, 4, 8, 16, 32, 64, 128, 256). That scheme preserves leading
	// zero bytes bit-perfectly. Conversions between binary and a non-power-
	// of-2 base are rejected. Sign and decimal are nonsensical here and are
	// always disabled.
	Binary bool

	// Source describes where this Base was defined (e.g. "built-in", a
	// config file path, or "command-line flag"). Set at registration time
	// and used by the --help output. Doesn't affect behavior.
	Source string

	// derived
	value      map[string]int // symbol -> digit value (plus case-flipped ASCII letters for input leniency)
	allOneByte bool           // every symbol has len(sym)==1 → byte-iteration fast path
	byteValue  [256]int       // populated when allOneByte; -1 means not a digit
	negative   string         // effective negative marker ("" if disabled)
	decimal    string         // effective decimal marker ("" if disabled)
	maxByteLen int            // longest symbol in bytes (for slow-path tokenizing)
}

// Built-in defaults if a base doesn't override.
const (
	DefaultNegative = "-"
	DefaultDecimal  = "."
)

// Name returns the canonical display name (first alias), or "base(N)".
func (b *Base) Name() string {
	if len(b.Aliases) > 0 {
		return b.Aliases[0]
	}
	return fmt.Sprintf("base(%d)", len(b.Symbols))
}

// NegSym returns the effective negative marker (empty string if disabled).
func (b *Base) NegSym() string { return b.negative }

// DecSym returns the effective decimal marker (empty string if disabled).
func (b *Base) DecSym() string { return b.decimal }

// finalize builds the derived lookup tables and resolves Negative/Decimal.
// Call after Symbols/Aliases/Negative/Decimal are set.
func (b *Base) finalize() error {
	if len(b.Symbols) < 2 {
		return fmt.Errorf("base %q: need at least 2 symbols, have %d", b.Name(), len(b.Symbols))
	}

	b.value = make(map[string]int, len(b.Symbols))
	b.allOneByte = true
	for i := range b.byteValue {
		b.byteValue[i] = -1
	}
	b.maxByteLen = 0

	for i, s := range b.Symbols {
		if s == "" {
			return fmt.Errorf("base %q: empty symbol at index %d", b.Name(), i)
		}
		if _, dup := b.value[s]; dup {
			return fmt.Errorf("base %q: duplicate symbol %q", b.Name(), s)
		}
		b.value[s] = i
		if len(s) > b.maxByteLen {
			b.maxByteLen = len(s)
		}
		if len(s) == 1 {
			b.byteValue[s[0]] = i
		} else {
			b.allOneByte = false
		}
	}

	// Accept case-flipped ASCII letters as *input* aliases (doesn't affect
	// output), but only for effectively single-case bases. Skip this behavior
	// entirely for mixed-case bases (e.g., base32w, base52, base64r) where
	// upper and lower are distinct digits.
	bothCase := false
	for sym := range b.value {
		if len(sym) != 1 {
			continue
		}
		c := sym[0]
		var flipped byte
		switch {
		case c >= 'A' && c <= 'Z':
			flipped = c + 32
		case c >= 'a' && c <= 'z':
			flipped = c - 32
		default:
			continue
		}
		if _, exists := b.value[string(flipped)]; exists {
			bothCase = true
			break
		}
	}
	if !bothCase {
		type extra struct {
			s string
			b byte
			v int
		}
		var adds []extra
		for sym, v := range b.value {
			if len(sym) != 1 {
				continue
			}
			c := sym[0]
			var flipped byte
			switch {
			case c >= 'A' && c <= 'Z':
				flipped = c + 32
			case c >= 'a' && c <= 'z':
				flipped = c - 32
			default:
				continue
			}
			fs := string(flipped)
			if _, exists := b.value[fs]; !exists {
				adds = append(adds, extra{fs, flipped, v})
			}
		}
		for _, e := range adds {
			b.value[e.s] = e.v
			if b.allOneByte {
				b.byteValue[e.b] = e.v
			}
		}
	}

	// Resolve effective negative/decimal markers.
	//
	//   nil         → use global default; collision with a digit is an error
	//                 (to force-disable, point the field at "")
	//   &""         → explicitly disabled
	//   &"X"        → use X; collision is an error
	var err error
	b.negative, err = resolveMarker("negative", b.Negative, DefaultNegative, b.value, b.Name())
	if err != nil {
		return err
	}
	b.decimal, err = resolveMarker("decimal", b.Decimal, DefaultDecimal, b.value, b.Name())
	if err != nil {
		return err
	}
	if b.negative != "" && b.decimal != "" && b.negative == b.decimal {
		return fmt.Errorf("base %q: negative and decimal markers are both %q", b.Name(), b.negative)
	}

	return nil
}

// resolveMarker applies the nil/empty/explicit rules to a *string marker field.
// Name is e.g. "negative" - used only in error messages.
func resolveMarker(kind string, raw *string, def string, digits map[string]int, baseName string) (string, error) {
	switch {
	case raw == nil:
		if _, collides := digits[def]; collides {
			return "", fmt.Errorf(
				"base %q: default %s marker %q collides with a digit; set %s marker explicitly (e.g. \"%s=X\"), or disable with bare \"%s=\"",
				baseName, kind, def, kind, kind[:3], kind[:3])
		}
		return def, nil
	case *raw == "":
		return "", nil // explicitly disabled
	default:
		if _, collides := digits[*raw]; collides {
			return "", fmt.Errorf("base %q: %s marker %q is also a digit symbol", baseName, kind, *raw)
		}
		return *raw, nil
	}
}

// Tokenize splits s into a sequence of this base's symbols (canonical form).
// Returns an error for any unrecognized byte/rune. s must NOT contain the
// negative or decimal markers - the caller is expected to strip those first.
func (b *Base) Tokenize(s string) ([]string, error) {
	if s == "" {
		return nil, nil
	}
	if b.allOneByte {
		out := make([]string, 0, len(s))
		for i := 0; i < len(s); i++ {
			v := b.byteValue[s[i]]
			if v < 0 {
				return nil, fmt.Errorf("byte %#02x (%q) not in base %q", s[i], string(s[i]), b.Name())
			}
			out = append(out, b.Symbols[v])
		}
		return out, nil
	}
	// Greedy longest-match for bases with multi-byte symbols.
	var out []string
	for len(s) > 0 {
		matched := ""
		for l := b.maxByteLen; l > 0; l-- {
			if l > len(s) {
				continue
			}
			if _, ok := b.value[s[:l]]; ok {
				matched = s[:l]
				break
			}
		}
		if matched == "" {
			return nil, fmt.Errorf("cannot tokenize %q in base %q", s, b.Name())
		}
		out = append(out, b.Symbols[b.value[matched]])
		s = s[len(matched):]
	}
	return out, nil
}

// Registry holds all known bases, keyed by normalized alias.
type Registry struct {
	byAlias       map[string]*Base
	ordered       []*Base  // registration order preserved
	LoadedConfigs []string // paths of config files actually loaded (for --help)
}

// NewRegistry builds a registry pre-populated with the predefined bases.
func NewRegistry() (*Registry, error) {
	r := &Registry{byAlias: make(map[string]*Base)}
	for _, b := range predefinedBases() {
		b.Source = "built-in"
		if err := r.Register(b); err != nil {
			return nil, fmt.Errorf("predefined %q: %w", b.Name(), err)
		}
	}
	return r, nil
}

// Register adds b to the registry. Later registrations with the same (normalized)
// alias override earlier ones - this is how config-file entries override built-ins.
func (r *Registry) Register(b *Base) error {
	if err := b.finalize(); err != nil {
		return err
	}
	// Sanity: if any alias is a pure integer, it must equal the symbol count.
	for _, a := range b.Aliases {
		if n, err := strconv.Atoi(a); err == nil {
			if n != len(b.Symbols) {
				return fmt.Errorf("base %q: alias %q implies size %d but has %d symbols",
					b.Name(), a, n, len(b.Symbols))
			}
			break
		}
	}
	seen := make(map[string]bool)
	for _, a := range b.Aliases {
		k := normalizeBaseName(a)
		if k == "" || seen[k] {
			continue
		}
		seen[k] = true
		r.byAlias[k] = b
	}
	r.ordered = append(r.ordered, b)
	return nil
}

// Lookup resolves a base name or alias. Case-insensitive; accepts an optional
// "base" or "b" prefix before a digit ("16", "b16", "Base16", "Hex" all work).
func (r *Registry) Lookup(name string) (*Base, error) {
	k := normalizeBaseName(name)
	if k == "" {
		return nil, fmt.Errorf("empty base name")
	}
	if b, ok := r.byAlias[k]; ok {
		return b, nil
	}
	return nil, fmt.Errorf("unknown base %q", name)
}

// Print writes a human-readable listing to w.
func (r *Registry) Print(w io.Writer) {
	bases := make([]*Base, len(r.ordered))
	copy(bases, r.ordered)
	sort.SliceStable(bases, func(i, j int) bool {
		return len(bases[i].Symbols) < len(bases[j].Symbols)
	})
	fmt.Fprintf(w, "%-16s  %-6s  %-5s  %-5s  %s\n", "NAME", "SIZE", "NEG", "DEC", "ALIASES")
	for _, b := range bases {
		neg := b.negative
		if neg == "" {
			neg = "(off)"
		}
		dec := b.decimal
		if dec == "" {
			dec = "(off)"
		}
		fmt.Fprintf(w, "%-16s  %-6d  %-5s  %-5s  %s\n",
			b.Name(), len(b.Symbols), neg, dec, strings.Join(b.Aliases, ", "))
	}
}

// normalizeBaseName lowercases and strips an optional "base" or "b" prefix
// that precedes a digit.
func normalizeBaseName(s string) string {
	s = strings.TrimSpace(strings.ToLower(s))
	if s == "" {
		return ""
	}
	switch {
	case strings.HasPrefix(s, "base") && len(s) > 4 && isDigitByte(s[4]):
		s = s[4:]
	case strings.HasPrefix(s, "b") && len(s) > 1 && isDigitByte(s[1]):
		s = s[1:]
	}
	return s
}

func isDigitByte(b byte) bool { return b >= '0' && b <= '9' }

// strPtr is a short helper for Base.Negative / Base.Decimal struct literals
// where you need a *string value (e.g. strPtr("") to mean "explicitly disabled").
func strPtr(s string) *string { return &s }

// --- YAML config loading ----------------------------------------------------

// configBase is the YAML shape of one base entry. The top-level config file
// is a YAML list of these.
//
//	`symbols` may be either:
//	   * a string - parsed via ParseSymbolSpec (whitespace-delimited, with
//	     optional "neg=X" / "dec=Y" trailer tokens); or
//	   * a YAML list of strings - each list entry is one literal digit
//	     symbol (convenient for symbols containing "=" or similar).
//	`negative` and `decimal`, if present, override any values set via the
//	in-string trailer.
type configBase struct {
	Aliases  []string  `yaml:"aliases"`
	Symbols  yaml.Node `yaml:"symbols"`
	Negative *string   `yaml:"negative,omitempty"`
	Decimal  *string   `yaml:"decimal,omitempty"`
}

// LoadConfig reads the YAML config at path and registers each base it defines.
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
	var cfg []configBase
	if err := yaml.Unmarshal(data, &cfg); err != nil {
		return fmt.Errorf("parsing %s: %w", path, err)
	}
	for i, cb := range cfg {
		b, err := cb.toBase()
		if err != nil {
			return fmt.Errorf("%s[%d]: %w", path, i, err)
		}
		b.Source = path
		if err := r.Register(b); err != nil {
			return fmt.Errorf("%s[%d]: %w", path, i, err)
		}
	}
	r.LoadedConfigs = append(r.LoadedConfigs, path)
	return nil
}

func (cb configBase) toBase() (*Base, error) {
	if len(cb.Aliases) == 0 {
		return nil, fmt.Errorf("config base has no aliases")
	}
	b := &Base{Aliases: cb.Aliases}
	switch cb.Symbols.Kind {
	case yaml.ScalarNode:
		spec, err := ParseSymbolSpec(cb.Symbols.Value)
		if err != nil {
			return nil, fmt.Errorf("base %q: %w", cb.Aliases[0], err)
		}
		b.Symbols = spec.Symbols
		b.Negative = spec.Negative
		b.Decimal = spec.Decimal
	case yaml.SequenceNode:
		var arr []string
		if err := cb.Symbols.Decode(&arr); err != nil {
			return nil, fmt.Errorf("base %q: symbols list: %w", cb.Aliases[0], err)
		}
		b.Symbols = arr
	case 0:
		return nil, fmt.Errorf("base %q: missing 'symbols' field", cb.Aliases[0])
	default:
		return nil, fmt.Errorf("base %q: 'symbols' must be a string or list of strings", cb.Aliases[0])
	}
	// Explicit YAML fields override any trailer in the symbols string.
	if cb.Negative != nil {
		b.Negative = cb.Negative
	}
	if cb.Decimal != nil {
		b.Decimal = cb.Decimal
	}
	return b, nil
}
