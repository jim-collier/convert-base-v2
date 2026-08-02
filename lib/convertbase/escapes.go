//	Copyright © 2023-2026 Jim Collier (CryptogID: ѳ6ᴚ℈𐀘𐇦ɛ𐊁¥Mﾏb϶Δ𐌞)
//	Licensed under the Apache License, Version 2.0. Full text in ./LICENSE, or:
//		https://spdx.org/licenses/Apache-2.0.html
//	SPDX-License-Identifier: Apache-2.0

package convertbase

import (
	"fmt"
	"strings"
)

// A base can carry control characters as digits - the 98-symbol keyboard base
// holds tab, newline and return so that any ordinary text file is valid input.
// Those digits are impossible to type at a prompt and invisible (or actively
// destructive) on a terminal, so they can also be written as a name.
//
// The marker is deliberately outside the printable-ASCII range that such a base
// draws its digits from. That is what makes the notation escape-free: the marker
// can never itself be a digit, so there is no "how do I write a literal marker"
// recursion to solve. A base that really does use the marker as a digit keeps
// it, and escape expansion is skipped there entirely.
const EscapeMarker = "⊳"

// C0 control abbreviations, per ISO/IEC 6429, indexed by code point. These are
// the canonical names: the ones EscapeControls writes.
var c0Names = [32]string{
	"NUL", "SOH", "STX", "ETX", "EOT", "ENQ", "ACK", "BEL",
	"BS", "HT", "LF", "VT", "FF", "CR", "SO", "SI",
	"DLE", "DC1", "DC2", "DC3", "DC4", "NAK", "SYN", "ETB",
	"CAN", "EM", "SUB", "ESC", "FS", "GS", "RS", "US",
}

// Accepted on input, never written. Everyday words for the three controls that
// people actually mean, plus the printables that are a nuisance to quote on a
// command line.
var escapeAliases = map[string]rune{
	"TAB":       '\t',
	"NEWLINE":   '\n',
	"RETURN":    '\r',
	"SP":        ' ',
	"DQUOTE":    '"',
	"SQUOTE":    '\'',
	"BACKSLASH": '\\',
}

var (
	escapeByName     map[string]rune
	maxEscapeNameLen int
)

func init() {
	escapeByName = make(map[string]rune, len(c0Names)+len(escapeAliases)+1)
	for code, name := range c0Names {
		escapeByName[name] = rune(code)
	}
	escapeByName["DEL"] = 0x7F
	for name, r := range escapeAliases {
		escapeByName[name] = r
	}
	for name := range escapeByName {
		if len(name) > maxEscapeNameLen {
			maxEscapeNameLen = len(name)
		}
	}
}

// escapeName returns the canonical written name for a control character.
func escapeName(c byte) (string, bool) {
	switch {
	case c < 0x20:
		return c0Names[c], true
	case c == 0x7F:
		return "DEL", true
	}
	return "", false
}

func isEscapableControl(c byte) bool { return c < 0x20 || c == 0x7F }

func isHexDigit(c byte) bool {
	return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')
}

func hexValue(c byte) byte {
	switch {
	case c <= '9':
		return c - '0'
	case c <= 'F':
		return c - 'A' + 10
	}
	return c - 'a' + 10
}

// matchEscape reads one escape body off the front of s - that is, the text
// immediately after the marker - and returns the character it names and how
// many bytes it consumed.
//
// Names are matched longest-first and case-insensitively. One of them is a
// proper prefix of another (SO of SOH), so a name alone cannot always be
// written; the fixed-width hex form covers that and anything else, since "x"
// plus exactly two hex digits ends where it ends no matter what follows.
func matchEscape(s string) (rune, int, bool) {
	if len(s) >= 3 && (s[0] == 'x' || s[0] == 'X') && isHexDigit(s[1]) && isHexDigit(s[2]) {
		return rune(hexValue(s[1])<<4 | hexValue(s[2])), 3, true
	}
	for l := maxEscapeNameLen; l > 0; l-- {
		if l > len(s) {
			continue
		}
		if r, ok := escapeByName[asciiUpper(s[:l])]; ok {
			return r, l, true
		}
	}
	return 0, 0, false
}

// asciiUpper folds case for name matching. Deliberately ASCII-only: every name
// is ASCII, and Unicode case folding would let look-alikes such as U+017F match
// as an "s".
func asciiUpper(s string) string {
	var b []byte
	for i := 0; i < len(s); i++ {
		c := s[i]
		if c >= 'a' && c <= 'z' {
			if b == nil {
				b = []byte(s)
			}
			b[i] = c - 32
		}
	}
	if b == nil {
		return s
	}
	return string(b)
}

// usesEscapeMarker reports whether the marker is part of this base's own
// alphabet, in which case it is a digit here and must be left alone.
func (b *Base) usesEscapeMarker() bool {
	for _, s := range b.Symbols {
		if strings.Contains(s, EscapeMarker) {
			return true
		}
	}
	return false
}

// ExpandEscapes replaces every escape in s with the character it names, so the
// rest of the conversion sees an ordinary run of digits. Raw and escaped forms
// mix freely: the marker is not a digit, so there is nothing to disambiguate.
//
// Whether the character it produces is actually a digit of b is not checked
// here - an escape naming something the base does not carry fails the same way
// the raw character would, as an unrecognized digit.
func ExpandEscapes(s string, b *Base) (string, error) {
	if !strings.Contains(s, EscapeMarker) {
		return s, nil
	}
	if b != nil && b.usesEscapeMarker() {
		return s, nil
	}
	var sb strings.Builder
	sb.Grow(len(s))
	for {
		i := strings.Index(s, EscapeMarker)
		if i < 0 {
			sb.WriteString(s)
			return sb.String(), nil
		}
		sb.WriteString(s[:i])
		body := s[i+len(EscapeMarker):]
		r, n, ok := matchEscape(body)
		if !ok {
			return "", fmt.Errorf("unrecognized escape %q; expected a control name (%sLF, %sTAB, %sCR, ...) or the hex form %sx0A",
				EscapeMarker+escapeSnippet(body), EscapeMarker, EscapeMarker, EscapeMarker, EscapeMarker)
		}
		sb.WriteRune(r)
		s = body[n:]
	}
}

// escapeSnippet trims the offending text down to something readable in an error
// message, cutting at the next marker so two bad escapes don't run together.
func escapeSnippet(s string) string {
	if i := strings.Index(s, EscapeMarker); i >= 0 {
		s = s[:i]
	}
	const max = 8
	if len(s) > max {
		return s[:max] + "..."
	}
	return s
}

// EscapeControls rewrites the control characters in s as named escapes, so a
// value in a base that carries them can be read, copied and pasted back. Every
// other character is left exactly as it is.
//
// It is the inverse of ExpandEscapes over the same base, which is why b is
// wanted: a base owning the marker as a digit reads escapes as ordinary digits,
// so writing them there would produce something it could not read back. A nil
// base escapes unconditionally.
//
// Control bytes never occur inside a multi-byte UTF-8 sequence, so this is safe
// to do a byte at a time whatever the rest of the alphabet looks like.
func EscapeControls(s string, b *Base) string {
	if b != nil && b.usesEscapeMarker() {
		return s
	}
	found := false
	for i := 0; i < len(s); i++ {
		if isEscapableControl(s[i]) {
			found = true
			break
		}
	}
	if !found {
		return s
	}
	var sb strings.Builder
	sb.Grow(len(s) + 8)
	for i := 0; i < len(s); i++ {
		c := s[i]
		if !isEscapableControl(c) {
			sb.WriteByte(c)
			continue
		}
		sb.WriteString(EscapeMarker)
		// Use the name only when reading it back against what follows still
		// gives this character. Where it doesn't, the trailing text would
		// extend it into a longer name (SO followed by an H reads as SOH), so
		// the fixed-width hex form is written instead.
		name, _ := escapeName(c)
		if r, n, ok := matchEscape(name + s[i+1:]); ok && r == rune(c) && n == len(name) {
			sb.WriteString(name)
		} else {
			fmt.Fprintf(&sb, "x%02X", c)
		}
	}
	return sb.String()
}
