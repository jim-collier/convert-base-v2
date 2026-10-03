//	Copyright © 2023-2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
//	Licensed under the GNU General Public License v2.0 or later. Full text at:
//		https://spdx.org/licenses/GPL-2.0-or-later.html
//	SPDX-License-Identifier: GPL-2.0-or-later

package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/jim-collier/convert-base-v2/lib/convertbase"
	"github.com/jim-collier/convert-base-v2/lib/shcl"
)

// The written file has to name its format, or a later version cannot tell it
// from one written under older rules. It also has to load cleanly and define
// the worked example.
func TestUserConfigIsStamped(t *testing.T) {
	path := filepath.Join(t.TempDir(), "sub", "convert-base-v2.shcl")
	if !ensureUserConfig(path) {
		t.Fatal("ensureUserConfig did not create the file")
	}
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	text := string(data)
	if v, ok := shcl.FormatVersion(text); !ok || v != shcl.FormatMajor {
		t.Fatalf("FormatVersion = %d, %v; want %d, true", v, ok, shcl.FormatMajor)
	}
	if m := shcl.Migrate(text, false); !m.Current {
		t.Fatal("Migrate does not see the written file as current")
	}
	if _, ok := shcl.FormatVersion(defaultConfig); ok {
		t.Fatal("the embedded file names a format of its own; the stamp should come only from shcl.GenBanner")
	}
	doc := shcl.Parse(text)
	for _, d := range doc.Diagnostics() {
		t.Errorf("line %d: %s %s", d.Line, d.Code, d.Message)
	}
	// The block has to be the one shcl recognizes, so a library rewrite
	// replaces it rather than adding a second.
	if n := doc.SetBanner(true); n != 1 {
		t.Fatalf("SetBanner found %d old info blocks, want 1", n)
	}

	reg, err := convertbase.NewRegistry()
	if err != nil {
		t.Fatal(err)
	}
	if err := reg.LoadConfig(path); err != nil {
		t.Fatalf("written config does not load: %v", err)
	}
	b, err := convertbase.ResolveBase(reg, "emoji10", "", nil)
	if err != nil {
		t.Fatal(err)
	}
	if got := strings.Join(b.Symbols, " "); got != "😀 😑 😔 😘 😜 😠 😬 😮 🙄 🤔" {
		t.Fatalf("10emoji symbols = %q", got)
	}
	if ensureUserConfig(path) {
		t.Fatal("ensureUserConfig rewrote an existing file")
	}
}
