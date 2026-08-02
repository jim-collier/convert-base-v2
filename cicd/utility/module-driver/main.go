//	Copyright © 2023-2026 Jim Collier (CryptogID: ѳ6ᴚ℈𐀘𐇦ɛ𐊁¥Mﾏb϶Δ𐌞)
//	Licensed under the GPL, Version 2 or later. Full text in ../../../license.md, or:
//		https://spdx.org/licenses/GPL-2.0-or-later.html
//	SPDX-License-Identifier: GPL-2.0-or-later

// Batch driver over the convertbase package itself, so the harness can hold
// the Go module to the command's answers with no CLI in between. One request
// per stdin line: FROM <tab> TO <tab> PRECISION <tab> HEX(VALUE). One reply
// per line: "ok" <tab> HEX(RESULT), or "err". Values ride as hex so digits
// carrying tabs, newlines, or any unicode survive the line protocol - same
// convention as the interop drivers. A malformed request is a harness bug and
// kills the run; a conversion error is data and answers "err".
package main

import (
	"bufio"
	"encoding/hex"
	"fmt"
	"os"
	"strconv"
	"strings"

	"github.com/jim-collier/convert-base-v2/lib/convertbase"
)

func main() {
	reg, err := convertbase.NewRegistry()
	if err != nil {
		fatal("registry: %v", err)
	}
	in := bufio.NewScanner(os.Stdin)
	in.Buffer(make([]byte, 0, 1<<20), 1<<20)
	out := bufio.NewWriter(os.Stdout)
	for in.Scan() {
		line := in.Text()
		if line == "" {
			continue
		}
		f := strings.Split(line, "\t")
		if len(f) != 4 {
			fatal("bad request line: %q", line)
		}
		prec, err := strconv.Atoi(f[2])
		if err != nil {
			fatal("bad precision %q: %v", f[2], err)
		}
		value, err := hex.DecodeString(f[3])
		if err != nil {
			fatal("bad value hex %q: %v", f[3], err)
		}
		res, cerr := oneShot(reg, f[0], f[1], string(value), prec)
		if cerr != nil {
			fmt.Fprintln(out, "err")
		} else {
			fmt.Fprintf(out, "ok\t%s\n", hex.EncodeToString([]byte(res)))
		}
	}
	if err := in.Err(); err != nil {
		fatal("stdin: %v", err)
	}
	if err := out.Flush(); err != nil {
		fatal("stdout: %v", err)
	}
}

func oneShot(reg *convertbase.Registry, fromName, toName, value string, prec int) (string, error) {
	from, err := convertbase.ResolveBase(reg, fromName, "", nil)
	if err != nil {
		return "", err
	}
	to, err := convertbase.ResolveBase(reg, toName, "", nil)
	if err != nil {
		return "", err
	}
	return convertbase.Convert(value, from, to, prec)
}

func fatal(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "module-driver: FAIL: "+format+"\n", args...)
	os.Exit(1)
}
