//	Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
//	Licensed under the GNU General Public License v2.0 or later. Full text at:
//		https://spdx.org/licenses/GPL-2.0-or-later.html
//	SPDX-License-Identifier: GPL-2.0-or-later

package main

import (
	"strconv"
	"strings"
	"time"
)

// buildEpoch is the source commit's time in unix seconds, set at build time with
// -ldflags "-X main.buildEpoch=...". It must stay a var, like version. Empty on a
// plain 'go build' or 'go install', which then prints no build number rather than
// one made up from the clock.
var buildEpoch = ""

// 2000-01-01T00:00:00Z as unix seconds.
const epoch2000 = 946684800

// Crockford's alphabet has no I, L, O or U, so a build number read aloud or
// retyped comes back the same.
const crockford32 = "0123456789abcdefghjkmnpqrstvwxyz"

// stampSecs is the stamp as unix seconds, or false when missing, unreadable or
// before 2000.
func stampSecs() (int64, bool) {
	if buildEpoch == "" {
		return 0, false
	}
	secs, err := strconv.ParseInt(buildEpoch, 10, 64)
	if err != nil || secs < epoch2000 {
		return 0, false
	}
	return secs, true
}

// buildNumber is the minutes from 2000 to the stamped time, in lower-case
// Crockford base32: five characters until 2063. A missing, unreadable or pre-2000
// stamp gives "", meaning no build number, never zero.
func buildNumber() string {
	secs, ok := stampSecs()
	if !ok {
		return ""
	}
	return crockfordBase32((secs - epoch2000) / 60)
}

func crockfordBase32(n int64) string {
	if n == 0 {
		return "0"
	}
	var digits []byte
	for n > 0 {
		digits = append(digits, crockford32[n%32])
		n /= 32
	}
	for i, j := 0, len(digits)-1; i < j; i, j = i+1, j-1 {
		digits[i], digits[j] = digits[j], digits[i]
	}
	return string(digits)
}

// isRelease says whether v is a bare tag like v3.0.0 or v3.0.1-beta1. Anything
// describe adds after one (-3-gabc1234, -dirty), a bare hash, or "dev" is not.
// No regexp, since nothing else links it in.
func isRelease(v string) bool {
	core, pre, _ := strings.Cut(strings.TrimPrefix(v, "v"), "-")
	if len(core) == len(v) || strings.Count(core, ".") != 2 {
		return false
	}
	for _, part := range strings.Split(core, ".") {
		if part == "" || strings.Trim(part, "0123456789") != "" {
			return false
		}
	}
	if pre == "" {
		return true
	}
	for _, tag := range []string{"alpha", "beta", "rc"} {
		if n, ok := strings.CutPrefix(pre, tag); ok {
			return strings.Trim(n, "0123456789") == ""
		}
	}
	return false
}

// versionText is the version line, "convert-base-v2 v3.0.0 build dbrk8", minus
// the build part when nothing stamped one. A non-release build adds the commit
// date, in the viewer's own time zone: "... build dbrk8 (2026-10-23)".
func versionText() string {
	b := buildNumber()
	if b == "" {
		return "convert-base-v2 " + version
	}
	line := "convert-base-v2 " + version + " build " + b
	if !isRelease(version) {
		secs, _ := stampSecs()
		line += " (" + time.Unix(secs, 0).Local().Format("2006-01-02") + ")"
	}
	return line
}
