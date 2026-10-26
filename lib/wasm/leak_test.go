//	Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
//	Licensed under the Apache License, Version 2.0. Full text in
//	../convertbase/LICENSE, or:
//		https://spdx.org/licenses/Apache-2.0.html
//	SPDX-License-Identifier: Apache-2.0

//go:build js && wasm && !noleakcheck

package main

import (
	"testing"

	"go.uber.org/goleak"
)

// A goroutine still running once the tests are done fails the run, whoever
// started it. The one parked in runtime.handleEvent is the js runtime's own,
// waiting to hand control back to node.
func TestMain(m *testing.M) {
	goleak.VerifyTestMain(m, goleak.IgnoreAnyFunction("runtime.handleEvent"))
}
