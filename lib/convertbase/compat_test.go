//	Copyright © 2023-2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
//	Licensed under the Apache License, Version 2.0. Full text in ./LICENSE, or:
//		https://spdx.org/licenses/Apache-2.0.html
//	SPDX-License-Identifier: Apache-2.0

package convertbase

import (
	"os"
	"regexp"
	"strings"
	"testing"
)

// bases.go carries a comment per alias that the older tools depend on, saying
// which tool needs it and not to delete it. Those comments are the record of
// what convert-base-v1 and convert-base-v1b scripts can still call, so a rename
// that ignores one breaks the older tools silently: nothing else reads them, and
// the base itself keeps working under its new name.
//
// This walks the file, collects the names those comments quote, and checks each
// one against the alias list of the base the comment sits on.

var (
	reCompatNote  = regexp.MustCompile(`(?i)backward|backwards`)
	reQuotedName  = regexp.MustCompile(`"([^"]+)"`)
	reAliasesLine = regexp.MustCompile(`^\s*Aliases:\s*\[\]string\{(.*)\}`)
)

func TestLegacyAliasesArePreserved(t *testing.T) {
	src, err := os.ReadFile("bases.go")
	if err != nil {
		t.Fatalf("read bases.go: %v", err)
	}
	reg := newReg(t)

	var pending []string // names claimed by comments not yet matched to a base
	checked := 0
	for lineNo, line := range strings.Split(string(src), "\n") {
		trimmed := strings.TrimSpace(line)

		if strings.HasPrefix(trimmed, "//") {
			// Only a comment naming something in quotes is a claim. The section
			// headers say "backwards-compatibility" with no name and mean nothing
			// here; so does prose about a standard being backwards.
			if !reCompatNote.MatchString(trimmed) || !strings.Contains(trimmed, "convert-base-v1") {
				continue
			}
			for _, m := range reQuotedName.FindAllStringSubmatch(trimmed, -1) {
				pending = append(pending, m[1])
			}
			continue
		}

		m := reAliasesLine.FindStringSubmatch(line)
		if m == nil {
			continue
		}
		if len(pending) == 0 {
			continue
		}
		var aliases []string
		for _, a := range reQuotedName.FindAllStringSubmatch(m[1], -1) {
			aliases = append(aliases, a[1])
		}
		for _, want := range pending {
			if !containsString(aliases, want) {
				t.Errorf("bases.go:%d: alias %q is documented as required by the older tools, but the base's aliases are %v", lineNo+1, want, aliases)
				continue
			}
			// The alias list can carry a name the registry then rejects (a
			// duplicate loses to a later base), so resolve it too.
			b, err := reg.Lookup(want)
			if err != nil {
				t.Errorf("bases.go:%d: alias %q does not resolve: %v", lineNo+1, want, err)
				continue
			}
			if !containsString(b.Aliases, want) {
				t.Errorf("bases.go:%d: alias %q resolves to %q, which does not carry it", lineNo+1, want, b.Name())
			}
			checked++
		}
		pending = nil
	}

	if len(pending) != 0 {
		t.Errorf("bases.go: %v named as required by the older tools, but no base follows the comment", pending)
	}
	// A rewrite that drops the comment convention would otherwise leave this
	// test passing with nothing to check.
	if checked < 15 {
		t.Errorf("only %d legacy aliases checked; the comment convention in bases.go changed", checked)
	}
}

func containsString(haystack []string, needle string) bool {
	for _, s := range haystack {
		if s == needle {
			return true
		}
	}
	return false
}
