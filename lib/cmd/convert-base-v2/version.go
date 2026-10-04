//	Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
//	Licensed under the GNU General Public License v2.0 or later. Full text at:
//		https://spdx.org/licenses/GPL-2.0-or-later.html
//	SPDX-License-Identifier: GPL-2.0-or-later

package main

import "strconv"

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

// buildNumber is the minutes from 2000 to the stamped time, in lower-case
// Crockford base32: five characters until 2063. A missing, unreadable or pre-2000
// stamp gives "", meaning no build number, never zero.
func buildNumber() string {
	if buildEpoch == "" {
		return ""
	}
	secs, err := strconv.ParseInt(buildEpoch, 10, 64)
	if err != nil || secs < epoch2000 {
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

// versionText is the version line, "v3.0.0 build dbrk8", or the version alone
// when nothing stamped a build.
func versionText() string {
	if b := buildNumber(); b != "" {
		return version + " build " + b
	}
	return version
}
