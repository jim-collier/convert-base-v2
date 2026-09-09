//	Copyright © 2023-2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
//	Licensed under the Apache License, Version 2.0. Full text in ./LICENSE, or:
//		https://spdx.org/licenses/Apache-2.0.html
//	SPDX-License-Identifier: Apache-2.0

package convertbase

import (
	"errors"
	"fmt"
	"io"
	"sort"
	"strconv"
	"strings"
	"unicode/utf8"
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
	// If a nil (=default) marker collides with a digit symbol, Finalize()
	// errors out rather than silently disabling the feature. To disable it
	// on purpose, point the field at an empty string.
	Negative *string
	Decimal  *string

	// Binary, if true, marks this base as the raw-binary mode: each of the
	// 256 digits is one literal byte value. Convert() uses bit-packing (O(N),
	// no big.Int) for roundtrips between binary and any other power-of-2
	// base (2, 4, 8, 16, 32, 64, 128, 256), which preserves leading zero bytes
	// bit-perfectly. Conversions between binary and a non-power-of-2 base are
	// rejected UNLESS that base is a defined binary-to-text codec (BinaryScheme
	// set to base45/ascii85/z85/base91), which carries bytes per its own spec.
	// Sign and decimal are nonsensical here and are always disabled.
	Binary bool

	// Source describes where this Base was defined (e.g. "built-in", a
	// config file path, or "command-line flag"). Set at registration time
	// and used by the --help output. Doesn't affect behavior.
	Source string

	// Compat marks a base that exists only to reproduce convert-base-v1 or
	// convert-base-v1b output. It converts like any other base; it is just kept
	// out of --list (--list-compat shows those instead) so the everyday listing
	// isn't half legacy. Compat bases also sort after all the others, which
	// keeps both listings contiguous in --by-index order.
	Compat bool

	// TailSymbols is a secondary, smaller repertoire used only by the native
	// binary schemes (base 2048/32768/65536) to encode a final partial chunk.
	// Empty means no native scheme: binary conversion falls back to the
	// generic length-prefixed packing. BinaryScheme selects which layout.
	TailSymbols []string
	// BinaryScheme names a non-default raw-binary layout. Power-of-2 big bases
	// use "qntm"/"qntm65536"/"rust2048" (with TailSymbols). Non-power-of-2
	// binary-to-text codecs use "base45"/"ascii85"/"z85"/"base91", implemented
	// per their official specs in convert.go.
	BinaryScheme string

	// PadSymbol is the RFC-style padding character (e.g. "=") for base32/base64.
	// When set, binary decode strips a trailing run of it (lenient input). When
	// PadEmit is also true, binary encode pads its output up to the encoding's
	// group boundary. Set only on the strict RFC variants that require padding;
	// the URL/hex variants accept it but don't emit it.
	PadSymbol string
	PadEmit   bool

	// DecodeAliases maps extra input-only symbols to an existing digit symbol,
	// for asymmetric codecs. Crockford base32 is the case: it emits the strict
	// alphabet but reads O as 0 and I/L as 1. These aliases affect decoding only;
	// they are never emitted. For single-case bases the case-flipped form is
	// added too, so "o"/"i"/"l" work as well.
	DecodeAliases map[string]string

	// derived
	tailValue  map[string]int // tail symbol -> index (native binary decode)
	value      map[string]int // symbol -> digit value (plus case-flipped ASCII letters for input leniency)
	allOneByte bool           // every symbol has len(sym)==1 -> byte-iteration fast path
	byteValue  [256]int       // populated when allOneByte; -1 means not a digit
	allOneRune bool           // every symbol is exactly one rune -> wide streaming path
	runeValue  map[rune]int   // populated when allOneRune; the wide path's decode table
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

// RawCodec reports whether this base can carry a raw binary stream (--from/--to
// binary): every power-of-2 base via bit-packing, plus the defined binary-to-text
// codecs (base45/ascii85/z85/base91) via their own schemes. Any other base has no
// byte-exact mapping and errors in binary mode.
func (b *Base) RawCodec() bool {
	return PowerOfTwoBits(len(b.Symbols)) != 0 || b.BinaryScheme != ""
}

// isTailScheme reports whether a BinaryScheme is one of the tail layouts, as
// opposed to a binary-to-text codec. Both live in the same field, so clearing a
// tail must not take a codec down with it.
func isTailScheme(scheme string) bool {
	switch scheme {
	case "qntm", "qntm65536", "rust2048":
		return true
	}
	return false
}

// NegSym returns the effective negative marker (empty string if disabled).
func (b *Base) NegSym() string { return b.negative }

// DecSym returns the effective decimal marker (empty string if disabled).
func (b *Base) DecSym() string { return b.decimal }

// HasByteDigit reports whether c is a digit of this base in its own right.
// False for any base whose symbols are not all single bytes, since there a byte
// is only ever part of a digit. Callers use it to tell data from framing: a
// trailing newline is a terminator everywhere except a base that spells one.
func (b *Base) HasByteDigit(c byte) bool {
	return b.allOneByte && b.byteValue[c] >= 0
}

// Finalize builds the derived lookup tables and resolves Negative/Decimal.
// Call after Symbols/Aliases/Negative/Decimal are set.
func (b *Base) Finalize() error {
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

	// Decode-only aliases for asymmetric codecs (Crockford: O->0, I/L->1). Input
	// leniency only, never emitted. Applies the same case-flip as digits for
	// single-case bases, so "o"/"i"/"l" resolve too. Won't clobber a real digit.
	for alias, target := range b.DecodeAliases {
		tv, ok := b.value[target]
		if !ok {
			return fmt.Errorf("base %q: decode alias %q targets %q, which is not a digit", b.Name(), alias, target)
		}
		forms := []string{alias}
		if !bothCase && len(alias) == 1 {
			c := alias[0]
			var flipped byte
			switch {
			case c >= 'A' && c <= 'Z':
				flipped = c + 32
			case c >= 'a' && c <= 'z':
				flipped = c - 32
			}
			if flipped != 0 {
				forms = append(forms, string(flipped))
			}
		}
		for _, f := range forms {
			if _, exists := b.value[f]; exists {
				continue // never override a genuine digit
			}
			b.value[f] = tv
			if b.allOneByte && len(f) == 1 {
				b.byteValue[f[0]] = tv
			}
		}
	}

	// Prefix-free check (only possible with multi-byte symbols; single-byte
	// symbol sets are trivially prefix-free). Tokenizing is greedy longest-match,
	// which decodes correctly iff no symbol is a prefix of another - otherwise a
	// string like "10" (digits "1","0") is misread as a single digit "10".
	if !b.allOneByte {
		symSet := make(map[string]struct{}, len(b.Symbols))
		for _, s := range b.Symbols {
			symSet[s] = struct{}{}
		}
		for _, s := range b.Symbols {
			for l := 1; l < len(s); l++ {
				if _, ok := symSet[s[:l]]; ok {
					return fmt.Errorf("base %q: symbol %q begins with another symbol %q, so a run of digits can't be split unambiguously; make the symbol set prefix-free", b.Name(), s, s[:l])
				}
			}
		}
	}

	// Resolve effective negative/decimal markers.
	//
	//   nil         -> use global default; collision with a digit is an error
	//                 (to force-disable, point the field at "")
	//   &""         -> explicitly disabled
	//   &"X"        -> use X; collision is an error
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

	// A marker that appears *inside* a digit symbol breaks parsing: Convert scans
	// the raw string for the marker before tokenizing, so a symbol like "a.b" or
	// "a-b" gets split at the marker and its value silently changes. Reject it.
	for _, mk := range []struct{ kind, mark string }{{"negative", b.negative}, {"decimal", b.decimal}} {
		if mk.mark == "" {
			continue
		}
		for _, s := range b.Symbols {
			if s != mk.mark && strings.Contains(s, mk.mark) {
				return fmt.Errorf("base %q: %s marker %q appears inside digit symbol %q; pick a marker that is not part of any digit", b.Name(), mk.kind, mk.mark, s)
			}
		}
	}

	// A padding symbol must not also be a digit: binary decode strips a trailing
	// run of it, so a pad that doubled as a digit would eat real trailing data.
	if b.PadSymbol != "" {
		if _, collides := b.value[b.PadSymbol]; collides {
			return fmt.Errorf("base %q: padding symbol %q is also a digit", b.Name(), b.PadSymbol)
		}
		// Padding is counted in characters: encode appends one per position left
		// before the group boundary, decode strips a trailing run. A multi-character
		// pad overshoots the boundary on encode and only strips by accident.
		if utf8.RuneCountInString(b.PadSymbol) > 1 {
			return fmt.Errorf("base %q: padding symbol %q must be a single character", b.Name(), b.PadSymbol)
		}
		// Padding is only ever applied on the bit-packed binary path, which needs a
		// power-of-2 base of at most 8 bits per digit. Set anywhere else it would be
		// accepted and then silently do nothing, so reject it where it is defined.
		if k := PowerOfTwoBits(len(b.Symbols)); k == 0 || k > 8 {
			return fmt.Errorf("base %q: padding applies only to power-of-2 bases of at most 256 symbols; this base has %d", b.Name(), len(b.Symbols))
		}
	}

	// Native binary tail repertoire lookup, if this base defines one.
	if len(b.TailSymbols) > 0 {
		b.tailValue = make(map[string]int, len(b.TailSymbols))
		for i, s := range b.TailSymbols {
			if s == "" {
				return fmt.Errorf("base %q: empty tail symbol at index %d", b.Name(), i)
			}
			if _, dup := b.tailValue[s]; dup {
				return fmt.Errorf("base %q: duplicate tail symbol %q", b.Name(), s)
			}
			// Decode looks a symbol up in the primary repertoire first, so a tail
			// symbol that is also a digit could never be reached as a tail.
			if _, isDigit := b.value[s]; isDigit {
				return fmt.Errorf("base %q: tail symbol %q is also a digit", b.Name(), s)
			}
			b.tailValue[s] = i
		}
		if err := b.checkTailWidth(); err != nil {
			return err
		}
	}

	// Rune lookup for the wide streaming path. Checking b.value rather than
	// b.Symbols covers the decode aliases too, so the streaming decoder accepts
	// exactly what the buffered one does or the base doesn't qualify at all.
	b.allOneRune = true
	for sym := range b.value {
		if utf8.RuneCountInString(sym) != 1 {
			b.allOneRune = false
			break
		}
	}
	if b.allOneRune {
		b.runeValue = make(map[rune]int, len(b.value))
		for sym, v := range b.value {
			r, _ := utf8.DecodeRuneInString(sym)
			b.runeValue[r] = v
		}
	} else {
		b.runeValue = nil
	}

	return nil
}

// checkTailWidth validates a native-binary tail repertoire against the primary.
// The tail exists to absorb the final partial chunk of a byte stream: leftovers
// of 1..k-1 bits, where padding a leftover of k-8 bits or fewer up to a whole
// primary digit would invent a spare byte the decoder can't distinguish from
// data. So the tail must be wide enough to cover those (2^(k-8) symbols) and
// narrow enough that its own padding stays under a byte (2^8).
func (b *Base) checkTailWidth() error {
	kPrimary := PowerOfTwoBits(len(b.Symbols))
	if kPrimary <= 8 {
		return fmt.Errorf("base %q: a tail repertoire only applies to a power-of-2 base above 256 symbols; this base has %d", b.Name(), len(b.Symbols))
	}
	kTail := PowerOfTwoBits(len(b.TailSymbols))
	if kTail == 0 {
		return fmt.Errorf("base %q: tail repertoire has %d symbols; it must be a power of 2, at least 2", b.Name(), len(b.TailSymbols))
	}
	if kTail < kPrimary-8 || kTail > 8 {
		return fmt.Errorf("base %q: tail repertoire has %d symbols (%d bits); for a %d-bit base it must be between %d and 256", b.Name(), len(b.TailSymbols), kTail, kPrimary, 1<<(kPrimary-8))
	}
	return nil
}

// resolveMarker applies the nil/empty/explicit rules to a *string marker field.
// Name is e.g. "negative" - used only in error messages.
func resolveMarker(kind string, raw *string, def string, digits map[string]int, baseName string) (string, error) {
	switch {
	case raw == nil:
		if _, collides := digits[def]; collides {
			return "", &MarkerDefaultError{Base: baseName, Marker: kind, Symbol: def}
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
	LoadedConfigs []string // paths of config files actually loaded, in load order
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
	if err := b.Finalize(); err != nil {
		return err
	}
	// Sanity: every pure-integer alias must equal the symbol count. Check the
	// normalized form (so "b99" is caught too, not just "99") and every alias,
	// not only the first - otherwise ["3","99"] would register "99" as a working
	// name for a 3-symbol base.
	for _, a := range b.Aliases {
		if n, err := strconv.Atoi(normalizeBaseName(a)); err == nil && n != len(b.Symbols) {
			return fmt.Errorf("base %q: alias %q implies size %d but has %d symbols",
				b.Name(), a, n, len(b.Symbols))
		}
	}
	seen := make(map[string]bool)
	for _, a := range b.Aliases {
		// The base-prefix strip applies here too, not just at Lookup: an alias
		// spelled "base91" registers under the key "91", so bare 91 and b91
		// resolve. The 91hk base leans on this.
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
// As a fallback, a leading "base" plus one optional "-", "_" or space is
// stripped and retried, so "base-hex", "base_62hex", "base 16" resolve too.
func (r *Registry) Lookup(name string) (*Base, error) {
	k := normalizeBaseName(name)
	if k == "" {
		return nil, errors.New("empty base name")
	}
	if b, ok := r.byAlias[k]; ok {
		return b, nil
	}
	// Exact match above wins, so this can't shadow a real name.
	if rest, ok := stripBasePrefix(k); ok {
		if b, ok := r.byAlias[normalizeBaseName(rest)]; ok {
			return b, nil
		}
	}
	// Offer near matches when we have any. With 60+ bases behind non-obvious
	// naming rules, a bare "unknown base" is unhelpful. Typed, so the command
	// can add its --list pointer without the library knowing flags exist.
	q := k
	if rest, ok := stripBasePrefix(k); ok {
		q = normalizeBaseName(rest)
	}
	return nil, &UnknownBaseError{Name: name, Suggestions: r.suggestBases(q)}
}

// suggestBases returns up to four base aliases near the normalized query k:
// aliases that start with k (a partial like "2048" -> the 2048* names), else the
// closest by edit distance for a small typo. It reports the alias the user nearly
// typed (so "hexx" suggests "hex", not the canonical "16"), and keeps only the
// closest tier so a good match isn't buried under weaker ones. Empty when nothing
// is close.
func (r *Registry) suggestBases(k string) []string {
	if k == "" {
		return nil
	}
	type best struct {
		alias string
		d     int
	}
	bb := make(map[*Base]best)
	for a, b := range r.byAlias {
		d := levenshtein(a, k)
		if len(k) >= 2 && strings.HasPrefix(a, k) {
			d = 0
		}
		// Deterministic pick: at equal distance keep the lexically smaller alias,
		// so the suggestion doesn't shift with map iteration order.
		if cur, ok := bb[b]; !ok || d < cur.d || (d == cur.d && a < cur.alias) {
			bb[b] = best{a, d}
		}
	}
	minD := 1 << 30
	for _, v := range bb {
		if (v.d == 0 || (v.d <= 2 && v.d < len(k))) && v.d < minD {
			minD = v.d
		}
	}
	if minD == 1<<30 {
		return nil
	}
	var out []string
	for _, v := range bb {
		if v.d == minD {
			out = append(out, v.alias)
		}
	}
	sort.Strings(out)
	if len(out) > 4 {
		out = out[:4]
	}
	return out
}

// levenshtein is the plain edit distance between two short strings, used only for
// "did you mean" base suggestions.
func levenshtein(a, b string) int {
	if a == b {
		return 0
	}
	la, lb := len(a), len(b)
	if la == 0 {
		return lb
	}
	if lb == 0 {
		return la
	}
	prev := make([]int, lb+1)
	cur := make([]int, lb+1)
	for j := 0; j <= lb; j++ {
		prev[j] = j
	}
	for i := 1; i <= la; i++ {
		cur[0] = i
		for j := 1; j <= lb; j++ {
			cost := 1
			if a[i-1] == b[j-1] {
				cost = 0
			}
			cur[j] = min3(prev[j]+1, cur[j-1]+1, prev[j-1]+cost)
		}
		prev, cur = cur, prev
	}
	return prev[lb]
}

func min3(a, b, c int) int {
	if b < a {
		a = b
	}
	if c < a {
		a = c
	}
	return a
}

// stripBasePrefix removes a leading "base" plus one optional separator
// (-, _ or space), returning the remainder. Reports false if there is no
// such prefix or nothing is left after it. Input is already lowercased.
func stripBasePrefix(s string) (string, bool) {
	if !strings.HasPrefix(s, "base") {
		return "", false
	}
	rest := s[4:]
	if rest != "" && (rest[0] == '-' || rest[0] == '_' || rest[0] == ' ') {
		rest = rest[1:]
	}
	if rest == "" {
		return "", false
	}
	return rest, true
}

// liveAliases returns the aliases of b that still resolve to b - i.e. those a
// later-registered base (a config override) hasn't taken over. A base whose
// aliases were all stolen is fully shadowed and returns nothing.
func (r *Registry) liveAliases(b *Base) []string {
	var live []string
	for _, a := range b.Aliases {
		k := normalizeBaseName(a)
		if k != "" && r.byAlias[k] == b {
			live = append(live, a)
		}
	}
	return live
}

// OrderedBases returns all registered bases sorted by radix (stable), with the
// v1/v1b compatibility bases after all the others. This is the canonical index
// order: the same order --list then --list-compat print, so --by-index=N
// addresses the same base as the N-th listed row and neither listing has gaps.
// Fully-shadowed bases (every alias overridden by a later config base) are
// dropped, so the count and the index don't include a base no name can reach.
func (r *Registry) OrderedBases() []*Base {
	bases := make([]*Base, 0, len(r.ordered))
	for _, b := range r.ordered {
		if len(r.liveAliases(b)) > 0 {
			bases = append(bases, b)
		}
	}
	sort.SliceStable(bases, func(i, j int) bool {
		if bases[i].Compat != bases[j].Compat {
			return !bases[i].Compat
		}
		return len(bases[i].Symbols) < len(bases[j].Symbols)
	})
	return bases
}

// Print writes a human-readable listing to w. compatOnly picks which half of
// OrderedBases() to show: the everyday bases, or the v1/v1b compatibility ones.
func (r *Registry) Print(w io.Writer, compatOnly bool) {
	bases := r.OrderedBases()
	// The leading INDEX is the value --by-index takes (position in this order).
	fmt.Fprintf(w, "%-5s  %-16s  %-6s  %-5s  %-5s  %-5s  %s\n", "INDEX", "NAME", "SIZE", "NEG", "DEC", "RAW", "ALIASES")
	for i, b := range bases {
		if b.Compat != compatOnly {
			continue
		}
		neg := b.negative
		if neg == "" {
			neg = "(off)"
		}
		dec := b.decimal
		if dec == "" {
			dec = "(off)"
		}
		// RAW: can this base carry a raw binary stream (--from/--to binary)?
		raw := "-"
		if b.RawCodec() {
			raw = "yes"
		}
		// Show only aliases that still resolve to this base (a config override
		// may have taken some), and use the first live one as the display name so
		// a stolen canonical name isn't advertised here.
		live := r.liveAliases(b)
		name := b.Name()
		otherAliases := ""
		if len(live) > 0 {
			name = live[0]
			otherAliases = strings.Join(live[1:], ", ")
		}
		fmt.Fprintf(w, "%-5d  %-16s  %-6d  %-5s  %-5s  %-5s  %s\n",
			i, name, len(b.Symbols), neg, dec, raw, otherAliases)
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
