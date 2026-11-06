//	Copyright © 2023-2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
//	Licensed under the Apache License, Version 2.0. Full text in ./LICENSE, or:
//		https://spdx.org/licenses/Apache-2.0.html
//	SPDX-License-Identifier: Apache-2.0

package convertbase

import (
	"bufio"
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"strings"
	"testing"
)

// record must match the one in cicd/utility/legacy-config-corpus/main.go.
func corpusRecord(b *Base) string {
	ptr := func(p *string) string {
		if p == nil {
			return "-"
		}
		return fmt.Sprintf("%q", *p)
	}
	r := fmt.Sprintf("%q|%q|%q|%q|%s|%s|%q|%t", b.Aliases, b.Symbols, b.TailSymbols, b.BinaryScheme,
		ptr(b.Negative), ptr(b.Decimal), b.PadSymbol, b.PadEmit)
	sum := sha256.Sum256([]byte(r))
	return "L" + hex.EncodeToString(sum[:8])
}

const corpusBigMark = "<<512 digits>>"

func corpusBigAlphabet() string {
	big := make([]rune, 512)
	for i := range big {
		big[i] = rune(0x4e00 + i)
	}
	return string(big)
}

// A config with no Format line could have been written for any SHCL release
// before 3.0, prereleases included. The corpus holds how each of them read a
// set of texts, built by cicd/utility/legacy-config-corpus/gen.bash from the
// releases themselves. A text may be refused now, but one that loads has to
// load the base 1.2.0 did, which is what v3.0.0 shipped with, and no release
// may have loaded it differently. Each text also has to come out the way it
// did when the corpus was built.
// Test ID: deysc
func TestLegacyConfigCorpus(t *testing.T) {
	data, err := os.ReadFile("testdata/legacy-config-corpus.jsonl")
	if err != nil {
		t.Fatal(err)
	}
	sc := bufio.NewScanner(bytes.NewReader(data))
	sc.Buffer(make([]byte, 1<<20), 1<<20)
	var head struct {
		Versions []string `json:"versions"`
		Shipped  int      `json:"shipped"`
	}
	if !sc.Scan() || json.Unmarshal(sc.Bytes(), &head) != nil || head.Shipped >= len(head.Versions) {
		t.Fatal("corpus has no header")
	}
	big := corpusBigAlphabet()
	n, loads := 0, 0
	for sc.Scan() {
		var e struct {
			Text string   `json:"t"`
			Old  []string `json:"o"`
			Want string   `json:"w"`
		}
		if err := json.Unmarshal(sc.Bytes(), &e); err != nil {
			t.Fatalf("line %d: %v", n+2, err)
		}
		n++
		text := strings.ReplaceAll(e.Text, corpusBigMark, big)
		got := "R"
		if up, err := UpgradeConfig(text); err == nil {
			if up != nil {
				text = up.Text
			}
			scratch := &Registry{byAlias: make(map[string]*Base)}
			if scratch.loadConfigText("", text) == nil && len(scratch.ordered) == 1 {
				got = corpusRecord(scratch.ordered[0])
			}
		}
		if got != "R" {
			loads++
			for i, o := range e.Old {
				if o != "R" && o != got {
					t.Errorf("%q: loads, but %s read it differently", e.Text, head.Versions[i])
				}
			}
			if e.Old[head.Shipped] != got {
				t.Errorf("%q: loads, but %s did not load it this way", e.Text, head.Versions[head.Shipped])
			}
		}
		if got != e.Want {
			t.Errorf("%q: got %s, corpus says %s", e.Text, got, e.Want)
		}
	}
	if err := sc.Err(); err != nil {
		t.Fatal(err)
	}
	// A corpus that lost its texts, or that every text is refused from, would
	// pass the checks above on nothing.
	if n < 1000 || loads < n/4 {
		t.Fatalf("%d texts, %d loading; the corpus is too thin to say anything", n, loads)
	}
}
