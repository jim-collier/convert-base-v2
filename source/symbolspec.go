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
type SymbolSpec struct {
	Symbols  []string
	Negative *string
	Decimal  *string
}

// ParseSymbolSpec parses a whitespace-delimited spec string.
//
//	Rules:
//	  - Tokens of the form "neg=X" and "dec=Y" set the respective marker.
//	    (X and Y are everything after the '='; they may be multi-char, or empty
//	    to explicitly disable that feature for this base.)
//	  - All other tokens are digit symbols, in order.
//	  - If there is exactly one digit token, it is further split:
//	      * if it contains commas, split on commas (each piece is a symbol);
//	      * otherwise, split per Unicode rune.
//	    This makes "ABCD" and "A,B,C,D" and "A B C D" equivalent.
//	  - If there are multiple digit tokens, each token is one symbol
//	    (with optional comma-split within a token, e.g. "0,1 2 3").
//
// Because symbols are whitespace-delimited in this format, space can never
// itself be a digit symbol. To use a space symbol, construct the Base in code
// or via a YAML array-form "symbols" field.
func ParseSymbolSpec(s string) (SymbolSpec, error) {
	var out SymbolSpec
	tokens := strings.Fields(s)
	var digitTokens []string
	for _, t := range tokens {
		switch {
		case strings.HasPrefix(t, "neg="):
			v := t[len("neg="):]
			out.Negative = &v
		case strings.HasPrefix(t, "dec="):
			v := t[len("dec="):]
			out.Decimal = &v
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
		for _, t := range digitTokens {
			out.Symbols = append(out.Symbols, t)
		}
	}
	return out, nil
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
