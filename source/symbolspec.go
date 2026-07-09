//	Copyright © 2026 Jim Collier (ID: 1cv◂‡Vᛦ)
//	Licensed under the GNU General Public License v2.0 or later. Full text at:
//		https://spdx.org/licenses/GPL-2.0-or-later.html
//	SPDX-License-Identifier: GPL-2.0-or-later

package main

import (
	"fmt"
	"strings"
)

// SymbolSpec is a parsed form of a base's symbol definition.
//
// Negative / Decimal mirror Base.Negative / Base.Decimal:
//
//	nil   - not set by this spec (caller falls back to defaults)
//	&""   - explicitly disabled  (spec token was a bare "neg=" or "dec=")
//	&"X"  - explicit marker X    (spec token was "neg=X" or "dec=X")
//
// Pad is the optional RFC-style padding character for binary output:
//
//	nil   - no padding (the default)
//	&"X"  - pad binary output up to the group boundary with X, and strip a
//	        trailing run of X on decode. Only meaningful for power-of-2 bases.
//	        A bare "pad=" (empty) is treated the same as nil.
type SymbolSpec struct {
	Symbols  []string
	Negative *string
	Decimal  *string
	Pad      *string
}

// Internal placeholders standing in for whitespace characters that were escaped
// in a spec, so they survive strings.Fields and are restored afterward. They are
// Unicode noncharacters, never legal in real text; a raw spec that already
// contains one is rejected up front (see ParseSymbolSpec).
const (
	phSpace   = '\uFFFE'
	phTab     = '\uFFFF'
	phNewline = '\uFDD0'
)

// ParseSymbolSpec parses a whitespace-delimited spec string.
//
//	Rules:
//	  - Tokens of the form "neg=X" and "dec=Y" set the respective marker.
//	    (X and Y are everything after the '='; they may be multi-char, or empty
//	    to explicitly disable that feature for this base.)
//	  - A "pad=X" token turns on RFC-style padding for binary output (see
//	    SymbolSpec.Pad). A bare "pad=" means no padding.
//	  - All other tokens are digit symbols, in order.
//	  - If there is exactly one digit token, it is further split:
//	      * if it contains commas, split on commas (each piece is a symbol);
//	      * otherwise, split per Unicode rune.
//	    This makes "ABCD" and "A,B,C,D" and "A B C D" equivalent.
//	  - If there are multiple digit tokens, each token is one symbol
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
func ParseSymbolSpec(s string) (SymbolSpec, error) {
	if strings.ContainsAny(s, string([]rune{phSpace, phTab, phNewline})) {
		return SymbolSpec{}, fmt.Errorf("symbol spec contains a reserved noncharacter (U+FFFE/U+FFFF/U+FDD0)")
	}
	s = unescapeSpec(s)

	var out SymbolSpec
	tokens := strings.Fields(s)
	var digitTokens []string
	for _, t := range tokens {
		t = restorePlaceholders(t)
		switch {
		case strings.HasPrefix(t, "neg="):
			v := t[len("neg="):]
			out.Negative = &v
		case strings.HasPrefix(t, "dec="):
			v := t[len("dec="):]
			out.Decimal = &v
		case strings.HasPrefix(t, "pad="):
			v := t[len("pad="):]
			out.Pad = &v
		default:
			digitTokens = append(digitTokens, t)
		}
	}
	if len(digitTokens) == 0 {
		return out, fmt.Errorf("symbol spec has no digit symbols")
	}
	if len(digitTokens) == 1 {
		t := digitTokens[0]
		if strings.Contains(t, ",") {
			out.Symbols = splitCommas(t)
		} else {
			for _, r := range t {
				out.Symbols = append(out.Symbols, string(r))
			}
		}
	} else {
		// Multiple tokens: each is one symbol, but a token may still carry a
		// comma-delimited group (the doc's "0,1 2 3" -> four digits). Only split
		// when it yields two or more symbols, so a bare "," token stays the
		// literal comma digit - some builtin alphabets (e.g. 85ps) rely on that.
		for _, t := range digitTokens {
			if parts := splitCommas(t); strings.Contains(t, ",") && len(parts) >= 2 {
				out.Symbols = append(out.Symbols, parts...)
			} else {
				out.Symbols = append(out.Symbols, t)
			}
		}
	}
	return out, nil
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
