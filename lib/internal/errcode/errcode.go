//	Copyright © 2023-2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
//	Licensed under the Apache License, Version 2.0. Full text in
//	../../convertbase/LICENSE, or:
//		https://spdx.org/licenses/Apache-2.0.html
//	SPDX-License-Identifier: Apache-2.0

// Package errcode holds the numeric error codes the reactor and the browser
// module both report, so a page and a host get the same number for the same
// failure. Internal rather than in convertbase, since the numbers belong to
// those two frontends, not to the library's Go API.
package errcode

import (
	"errors"

	"github.com/jim-collier/convert-base-v2/lib/convertbase"
)

// Published in lib/reactor/README.md. Add at the end only, never renumber.
const (
	None          = 0
	UnknownBase   = 1 // base name or alias resolves to nothing
	MissingMarker = 2 // output base lacks a sign or decimal marker the value needs
	MarkerDefault = 3 // default marker collides with a digit
	RetiredToken  = 4 // symbol spec had a retired neg=/dec=/pad= token
	BadInput      = 5 // any other conversion or parse failure
	BadArg        = 6 // bad pointer, length, size, precision or argument from the caller
	Internal      = 7 // registry failed to initialize
)

// Of maps one of the library's errors to its code. Untyped errors are BadInput.
func Of(err error) int32 {
	var ub *convertbase.UnknownBaseError
	var mm *convertbase.MissingMarkerError
	var md *convertbase.MarkerDefaultError
	var rt *convertbase.RetiredTokenError
	switch {
	case err == nil:
		return None
	case errors.As(err, &ub):
		return UnknownBase
	case errors.As(err, &mm):
		return MissingMarker
	case errors.As(err, &md):
		return MarkerDefault
	case errors.As(err, &rt):
		return RetiredToken
	}
	return BadInput
}
