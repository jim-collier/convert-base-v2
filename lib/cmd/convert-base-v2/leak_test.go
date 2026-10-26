//	Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
//	Licensed under the GNU General Public License v2.0 or later. Full text at:
//		https://spdx.org/licenses/GPL-2.0-or-later.html
//	SPDX-License-Identifier: GPL-2.0-or-later

//go:build !noleakcheck

package main

import (
	"testing"

	"go.uber.org/goleak"
)

// A goroutine still running once the tests are done fails the run, whoever
// started it.
func TestMain(m *testing.M) {
	goleak.VerifyTestMain(m)
}
