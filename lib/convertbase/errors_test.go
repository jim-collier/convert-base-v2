//	Copyright © 2023-2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
//	Licensed under the Apache License, Version 2.0. Full text in ./LICENSE, or:
//		https://spdx.org/licenses/Apache-2.0.html
//	SPDX-License-Identifier: Apache-2.0

package convertbase

import (
	"errors"
	"strings"
	"testing"
)

// A Go program or a web page calling the library has no flags, so its error
// text must not point at any. The command adds its own pointers on the way out.
// Test ID: ErkSf4a
func TestLibraryErrorsNameNoFlags(t *testing.T) {
	reg := newReg(t)
	dec10 := base(t, reg, "10")

	_, unknown := reg.Lookup("hexx")
	_, missing := Convert("-5", dec10, markerBase(t, reg, "0123456789", "", "."), 50)
	_, collide := ResolveBase(reg, "", "0 1 - 3", nil)
	_, retired := ParseSymbolSpec("0123456789 neg=~")

	var e1 *UnknownBaseError
	var e2 *MissingMarkerError
	var e3 *MarkerDefaultError
	var e4 *RetiredTokenError
	for _, c := range []struct {
		name string
		err  error
		ok   bool
	}{
		{"unknown base", unknown, errors.As(unknown, &e1)},
		{"missing marker", missing, errors.As(missing, &e2)},
		{"default marker collides", collide, errors.As(collide, &e3)},
		{"retired token", retired, errors.As(retired, &e4)},
	} {
		if !c.ok {
			t.Errorf("%s: got %v, not its own error type", c.name, c.err)
			continue
		}
		if strings.Contains(c.err.Error(), "--") {
			t.Errorf("%s names a flag: %q", c.name, c.err)
		}
	}
}
