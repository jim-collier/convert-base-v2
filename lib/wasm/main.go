//	Copyright © 2023-2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
//	Licensed under the Apache License, Version 2.0. Full text in
//	../convertbase/LICENSE, or:
//		https://spdx.org/licenses/Apache-2.0.html
//	SPDX-License-Identifier: Apache-2.0

//go:build js && wasm

// Browser entry point. This is a build target of the same library the command
// uses, not a second implementation, so the two cannot disagree about what a
// base means. Nothing here touches a file or an environment variable, which is
// the whole reason config loading lives with the command and not the library.
//
// Apache-2.0 rather than the command's GPL, deliberately: this compiles into
// somebody else's page, so it has to be as free to embed as the library it
// wraps. The wasip1 build is a different matter - that one is the command.
package main

import (
	"math"
	"strconv"
	"syscall/js"

	"github.com/jim-collier/convert-base-v2/lib/convertbase"
)

func main() {
	reg, err := convertbase.NewRegistry()
	if err != nil {
		// Only a bad built-in alphabet reaches here, which is a build-time bug.
		js.Global().Get("console").Call("error", "convertBase: "+err.Error())
		return
	}

	api := js.Global().Get("Object").New()
	api.Set("convert", js.FuncOf(convert(reg)))
	api.Set("bases", js.FuncOf(bases(reg)))
	api.Set("version", convertbase.Version)
	js.Global().Set("convertBase", api)

	// Callbacks are torn down when main returns, so it must not.
	select {}
}

// convert takes one options object and always answers with one, rather than
// throwing: a bad base name is ordinary user input here, not an exception.
func convert(reg *convertbase.Registry) func(js.Value, []js.Value) any {
	return func(_ js.Value, args []js.Value) any {
		if len(args) != 1 || args[0].Type() != js.TypeObject {
			return fail("convert() takes one options object")
		}
		opt := args[0]

		from, err := convertbase.ResolveBase(reg, str(opt, "from"), str(opt, "fromSymbols"), nil)
		if err != nil {
			return fail(err.Error())
		}
		to, err := convertbase.ResolveBase(reg, str(opt, "to"), str(opt, "toSymbols"), nil)
		if err != nil {
			return fail(err.Error())
		}

		precision := -1 // negative means auto, same default the command uses
		if p := opt.Get("precision"); p.Type() == js.TypeNumber {
			// Bounded here because this runs synchronously on the page's main
			// thread: fractional digits cost quadratic time, and a browser tab
			// has no Ctrl-C. The check also catches NaN and infinities.
			f := p.Float()
			if f != math.Trunc(f) || f < 0 || f > 100000 {
				return fail("precision must be a whole number from 0 to 100000")
			}
			precision = int(f)
		}

		value := str(opt, "value")
		if v := opt.Get("value"); v.Type() == js.TypeNumber {
			// A number is the natural JS spelling of a value; read it rather
			// than answering "empty input" for something the caller did pass.
			// NaN and the infinities format as words, which would otherwise be
			// reported as an unrecognized digit.
			f := v.Float()
			if math.IsNaN(f) || math.IsInf(f, 0) {
				return fail("value must be a finite number, or a string")
			}
			value = strconv.FormatFloat(f, 'f', -1, 64)
		}

		out, err := convertbase.Convert(value, from, to, precision)
		if err != nil {
			return fail(err.Error())
		}
		return map[string]any{"ok": true, "value": out}
	}
}

// bases lists what a picker should offer. Compatibility bases are left out for
// the same reason --list drops them: they exist to reproduce v1 output.
func bases(reg *convertbase.Registry) func(js.Value, []js.Value) any {
	return func(js.Value, []js.Value) any {
		ordered := reg.OrderedBases()
		out := make([]any, 0, len(ordered))
		for _, b := range ordered {
			if b.Compat {
				continue
			}
			entry := map[string]any{
				"name":   b.Name(),
				"digits": len(b.Symbols),
				"raw":    b.RawCodec(),
			}
			if len(b.Aliases) > 1 {
				entry["alias"] = b.Aliases[1]
			}
			out = append(out, entry)
		}
		return out
	}
}

func str(o js.Value, key string) string {
	if v := o.Get(key); v.Type() == js.TypeString {
		return v.String()
	}
	return ""
}

func fail(msg string) any { return map[string]any{"ok": false, "error": msg} }
