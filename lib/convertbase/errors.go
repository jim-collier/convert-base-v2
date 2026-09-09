//	Copyright © 2023-2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
//	Licensed under the Apache License, Version 2.0. Full text in ./LICENSE, or:
//		https://spdx.org/licenses/Apache-2.0.html
//	SPDX-License-Identifier: Apache-2.0

package convertbase

import (
	"fmt"
	"strings"
)

// Typed errors for the conditions a caller may want to explain in its own
// words. The library's text stays neutral - no flag names, nothing that
// assumes a command line - and a caller that has a better pointer (a flag, a
// config field, a UI element) can detect the condition with errors.As and
// append its own hint.

// UnknownBaseError reports a base name or alias that resolves to nothing.
// Suggestions carries near matches (closest tier only), possibly empty.
type UnknownBaseError struct {
	Name        string
	Suggestions []string
}

func (e *UnknownBaseError) Error() string {
	if len(e.Suggestions) == 0 {
		return fmt.Sprintf("unknown base %q", e.Name)
	}
	quoted := make([]string, len(e.Suggestions))
	for i, s := range e.Suggestions {
		quoted[i] = fmt.Sprintf("%q", s)
	}
	return fmt.Sprintf("unknown base %q; did you mean %s?", e.Name, strings.Join(quoted, ", "))
}

// MissingMarkerError reports that the output base carries no marker for
// something the value needs - a sign, or a fractional part.
type MissingMarkerError struct {
	Base   string
	Marker string // "negative" or "decimal"
}

func (e *MissingMarkerError) Error() string {
	return fmt.Sprintf("output base %q has no %s marker", e.Base, e.Marker)
}

// MarkerDefaultError reports that the global default marker is also one of the
// base's digits, so the base cannot finalize until the marker is set to
// something else or disabled.
type MarkerDefaultError struct {
	Base   string
	Marker string // "negative" or "decimal"
	Symbol string // the colliding default
}

func (e *MarkerDefaultError) Error() string {
	return fmt.Sprintf("base %q: default %s marker %q collides with a digit; set the marker to something else, or to an empty string to disable it",
		e.Base, e.Marker, e.Symbol)
}

// RetiredTokenError reports a symbol spec carrying one of the retired in-spec
// marker tokens (neg= / dec= / pad=). Markers are set separately now.
type RetiredTokenError struct {
	Token  string // the offending token, e.g. "neg=~"
	Marker string // "negative", "decimal", or "pad"
}

func (e *RetiredTokenError) Error() string {
	return fmt.Sprintf("symbol spec: %q is no longer part of the symbol spec", e.Token)
}
