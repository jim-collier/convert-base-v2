//	Copyright © 2023-2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
//	Licensed under the Apache License, Version 2.0. Full text in
//	../../convertbase/LICENSE, or:
//		https://spdx.org/licenses/Apache-2.0.html
//	SPDX-License-Identifier: Apache-2.0

package errcode

import (
	"fmt"
	"os"
	"regexp"
	"strconv"
	"testing"

	"github.com/jim-collier/convert-base-v2/lib/convertbase"
)

// Each code comes from a real library failure, not a hand-built error value,
// so a library change that swaps an error's type shows up here. The numbers
// are checked against the table hosts read in the reactor README.
// Test ID: Ert2MSA
func TestCodesMatchLibraryAndReadme(t *testing.T) {
	reg, err := convertbase.NewRegistry()
	if err != nil {
		t.Fatal(err)
	}
	dec10, err := convertbase.ResolveBase(reg, "10", "", nil)
	if err != nil {
		t.Fatal(err)
	}
	host, err := convertbase.ResolveBase(reg, "38hostname", "", nil)
	if err != nil {
		t.Fatal(err)
	}
	_, unknown := convertbase.ResolveBase(reg, "hexx", "", nil)
	_, missing := convertbase.Convert("-5", dec10, host, -1)
	_, collide := convertbase.ResolveBase(reg, "", "0 1 - 3", nil)
	_, retired := convertbase.ResolveBase(reg, "", "0123456789 neg=~", nil)
	_, badDigit := convertbase.Convert("12z", dec10, dec10, -1)
	_, empty := convertbase.Convert("", dec10, dec10, -1)

	for _, c := range []struct {
		name string
		err  error
		want int32
	}{
		{"success", nil, None},
		{"unknown base", unknown, UnknownBase},
		{"missing marker", missing, MissingMarker},
		{"default marker collides", collide, MarkerDefault},
		{"retired token", retired, RetiredToken},
		{"digit not in base", badDigit, BadInput},
		{"empty input", empty, BadInput},
		{"wrapped unknown base", fmt.Errorf("from: %w", unknown), UnknownBase},
	} {
		if c.want != None && c.err == nil {
			t.Errorf("%s: the library did not fail", c.name)
			continue
		}
		if got := Of(c.err); got != c.want {
			t.Errorf("%s: code %d, want %d (%v)", c.name, got, c.want, c.err)
		}
	}

	readme, err := os.ReadFile("../../reactor/README.md")
	if err != nil {
		t.Fatal(err)
	}
	want := map[string]int{"None": None, "UnknownBase": UnknownBase, "MissingMarker": MissingMarker,
		"MarkerDefault": MarkerDefault, "RetiredToken": RetiredToken, "BadInput": BadInput,
		"BadArg": BadArg, "Internal": Internal}
	rows := regexp.MustCompile("(?m)^\\| (\\d+) \\| `(\\w+)` \\|").FindAllSubmatch(readme, -1)
	if len(rows) != len(want) {
		t.Errorf("README lists %d codes, the package has %d", len(rows), len(want))
	}
	for _, r := range rows {
		n, _ := strconv.Atoi(string(r[1])) // the pattern only matches digits
		if code, ok := want[string(r[2])]; !ok || code != n {
			t.Errorf("README row %s %s does not match the package", r[1], r[2])
		}
	}
}
