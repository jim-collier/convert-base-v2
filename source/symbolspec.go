//	Copyright © 2026 Jim Collier (ID: 1cv◂‡Vᛦ)
//	Licensed under the GNU General Public License v2.0 or later. Full text at:
//		https://spdx.org/licenses/GPL-2.0-or-later.html
//	SPDX-License-Identifier: GPL-2.0-or-later

package main

import (
	"fmt"
	"strings"
)

// Internal placeholders standing in for whitespace characters that were escaped
// in a spec, so they survive strings.Fields and are restored afterward. They are
// Unicode noncharacters, never legal in real text; a raw spec that already
// contains one is rejected up front (see ParseSymbolSpec).
const (
	phSpace   = '\uFFFE'
	phTab     = '\uFFFF'
	phNewline = '\uFDD0'
)

// ParseSymbolSpec parses a whitespace-delimited spec string into digit symbols.
//
// A spec is symbols and nothing else. Negative, decimal, and padding markers are
// set alongside it - by the --from-*/--to-* flags on the command line, by the
// negative/decimal/pad fields in a config file, or by SpecOpts in bases.go.
//
//	Rules:
//	  - Every token is a digit symbol, in order.
//	  - If there is exactly one token, it is further split:
//	      * if it contains commas, split on commas (each piece is a symbol);
//	      * otherwise, split per Unicode rune.
//	    This makes "ABCD" and "A,B,C,D" and "A B C D" equivalent.
//	  - If there are multiple tokens, each token is one symbol
//	    (with optional comma-split within a token, e.g. "0,1 2 3").
//
// Escape sequences allow characters that would otherwise conflict with the
// whitespace-delimited format to be used as digit symbols:
//
//	\<space>  -> literal space
//	\\        -> literal backslash
//	\t        -> tab
//	\n        -> newline
//	\"        -> double quote
func ParseSymbolSpec(s string) ([]string, error) {
	if strings.ContainsAny(s, string([]rune{phSpace, phTab, phNewline})) {
		return nil, fmt.Errorf("symbol spec contains a reserved noncharacter (U+FFFE/U+FFFF/U+FDD0)")
	}
	s = unescapeSpec(s)

	var symbols []string
	var digitTokens []string
	for _, t := range strings.Fields(s) {
		t = restorePlaceholders(t)
		if err := checkRetiredToken(t); err != nil {
			return nil, err
		}
		digitTokens = append(digitTokens, t)
	}
	if len(digitTokens) == 0 {
		return nil, fmt.Errorf("symbol spec has no digit symbols")
	}
	if len(digitTokens) == 1 {
		t := digitTokens[0]
		if strings.Contains(t, ",") {
			symbols = splitCommas(t)
		} else {
			for _, r := range t {
				symbols = append(symbols, string(r))
			}
		}
	} else {
		// Multiple tokens: each is one symbol, but a token may still carry a
		// comma-delimited group (the doc's "0,1 2 3" -> four digits). Only split
		// when it yields two or more symbols, so a bare "," token stays the
		// literal comma digit - some builtin alphabets (e.g. 85ps) rely on that.
		for _, t := range digitTokens {
			if parts := splitCommas(t); strings.Contains(t, ",") && len(parts) >= 2 {
				symbols = append(symbols, parts...)
			} else {
				symbols = append(symbols, t)
			}
		}
	}
	return symbols, nil
}

// checkRetiredToken rejects the marker tokens that specs used to carry. Without
// this they would silently become digit symbols, so a stale "0 1 2 3 neg=~" would
// quietly turn into a base 5 whose last digit is the text "neg=~". The check is
// permanent, not transitional: the cost is that these three exact strings can't
// be digits (a config file can still express them via the list form), and the
// alternative is a corrupted alphabet that looks like it worked.
func checkRetiredToken(token string) error {
	for _, m := range []struct{ prefix, flag, field string }{
		{"neg=", "--from-neg/--to-neg", "negative:"},
		{"dec=", "--from-dec/--to-dec", "decimal:"},
		{"pad=", "--from-pad/--to-pad", "pad:"},
	} {
		if strings.HasPrefix(token, m.prefix) {
			return fmt.Errorf("symbol spec: %q is no longer part of the symbol spec; use %s on the command line, or the %q field in a config file", token, m.flag, m.field)
		}
	}
	return nil
}

// unescapeSpec processes escape sequences in a spec string. Escaped whitespace
// (space, tab, newline) is replaced with a Unicode noncharacter placeholder so
// it survives the subsequent strings.Fields split, then restored to the real
// character in the resulting tokens. Without this, an escaped tab/newline would
// be split on by Fields and the symbol would silently vanish.
func unescapeSpec(s string) string {
	if !strings.Contains(s, `\`) {
		return s
	}
	var b strings.Builder
	b.Grow(len(s))
	for i := 0; i < len(s); i++ {
		if s[i] == '\\' && i+1 < len(s) {
			switch s[i+1] {
			case ' ':
				b.WriteRune(phSpace)
				i++
			case '\\':
				b.WriteByte('\\')
				i++
			case 't':
				b.WriteRune(phTab)
				i++
			case 'n':
				b.WriteRune(phNewline)
				i++
			case '"':
				b.WriteByte('"')
				i++
			default:
				b.WriteByte(s[i]) // unrecognized escape, keep as-is
			}
		} else {
			b.WriteByte(s[i])
		}
	}
	return b.String()
}

// restorePlaceholders rewrites the noncharacter placeholders (inserted by
// unescapeSpec for escaped whitespace) back to the real characters, after the
// whitespace split is done.
func restorePlaceholders(s string) string {
	if !strings.ContainsAny(s, string([]rune{phSpace, phTab, phNewline})) {
		return s
	}
	r := strings.NewReplacer(
		string(phSpace), " ",
		string(phTab), "\t",
		string(phNewline), "\n",
	)
	return r.Replace(s)
}

func splitCommas(s string) []string {
	parts := strings.Split(s, ",")
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		// Don't trim - commas are an explicit delimiter, and symbols with
		// surrounding whitespace would have been caught by the whitespace split.
		if p != "" {
			out = append(out, p)
		}
	}
	return out
}
