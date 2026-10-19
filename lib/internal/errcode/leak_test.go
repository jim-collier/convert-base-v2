//	Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
//	Licensed under the Apache License, Version 2.0. Full text in
//	../../convertbase/LICENSE, or:
//		https://spdx.org/licenses/Apache-2.0.html
//	SPDX-License-Identifier: Apache-2.0

package errcode

import (
	"testing"

	"go.uber.org/goleak"
)

// A goroutine still running once the tests are done fails the run, whoever
// started it.
func TestMain(m *testing.M) {
	goleak.VerifyTestMain(m)
}
