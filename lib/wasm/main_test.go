//	Copyright © 2023-2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
//	Licensed under the Apache License, Version 2.0. Full text in
//	../convertbase/LICENSE, or:
//		https://spdx.org/licenses/Apache-2.0.html
//	SPDX-License-Identifier: Apache-2.0

//go:build js && wasm

package main

import (
	"math"
	"strings"
	"syscall/js"
	"testing"

	"github.com/jim-collier/convert-base-v2/lib/convertbase"
	"github.com/jim-collier/convert-base-v2/lib/internal/errcode"
)

func call(t *testing.T, opts map[string]any) map[string]any {
	t.Helper()
	reg, err := convertbase.NewRegistry()
	if err != nil {
		t.Fatal(err)
	}
	res, ok := convert(reg)(js.Undefined(), []js.Value{js.ValueOf(opts)}).(map[string]any)
	if !ok {
		t.Fatal("convert() did not answer with an object")
	}
	return res
}

// NaN and the infinities format as words, which used to come back as an
// unrecognized digit. They are refused as what they are.
// Test ID: ErkSf4h
func TestConvertRefusesNonFinite(t *testing.T) {
	for _, v := range []float64{math.NaN(), math.Inf(1), math.Inf(-1)} {
		res := call(t, map[string]any{"value": v, "from": "10", "to": "16"})
		if res["ok"] != false || !strings.Contains(res["error"].(string), "finite") {
			t.Errorf("value %v: got %v", v, res)
		}
	}
	res := call(t, map[string]any{"value": "1", "from": "10", "to": "16", "precision": math.NaN()})
	if res["ok"] != false {
		t.Errorf("NaN precision: got %v", res)
	}
}

// The cap matches the command's, so a page and a prompt refuse the same values.
// Test ID: Ern7YZg
func TestPrecisionBound(t *testing.T) {
	res := call(t, map[string]any{"value": "1", "from": "10", "to": "16", "precision": 100000})
	if res["ok"] != true {
		t.Errorf("precision at the bound: got %v", res)
	}
	res = call(t, map[string]any{"value": "1", "from": "10", "to": "16", "precision": 100001})
	if res["ok"] != false || !strings.Contains(res["error"].(string), "0 to 100000") {
		t.Errorf("precision past the bound: got %v", res)
	}
}

// A number is the natural way to pass a value from a page, so it is read.
// Test ID: ErkSf4i
func TestConvertReadsNumbers(t *testing.T) {
	res := call(t, map[string]any{"value": 255.5, "from": "10", "to": "16"})
	if res["ok"] != true || res["value"] != "FF.8" {
		t.Errorf("255.5 -> 16: got %v", res)
	}
}

// Every way convert() can fail answers with the reactor's code beside the
// text. The harness's Frontend parity section checks the cases the reactor can
// also be given against the reactor itself.
// Test ID: Ert2MSr
func TestFailuresHaveCodes(t *testing.T) {
	reg, err := convertbase.NewRegistry()
	if err != nil {
		t.Fatal(err)
	}
	for _, c := range []struct {
		name string
		args []js.Value
		want int32
	}{
		{"no argument", nil, errcode.BadArg},
		{"not an object", []js.Value{js.ValueOf("255")}, errcode.BadArg},
		{"unknown from", []js.Value{js.ValueOf(map[string]any{"value": "1", "from": "hexx", "to": "16"})}, errcode.UnknownBase},
		{"unknown to", []js.Value{js.ValueOf(map[string]any{"value": "1", "from": "10", "to": "hexx"})}, errcode.UnknownBase},
		{"missing marker", []js.Value{js.ValueOf(map[string]any{"value": "-5", "from": "10", "to": "38hostname"})}, errcode.MissingMarker},
		{"default marker collides", []js.Value{js.ValueOf(map[string]any{"value": "1", "fromSymbols": "0 1 - 3", "to": "16"})}, errcode.MarkerDefault},
		{"retired token", []js.Value{js.ValueOf(map[string]any{"value": "1", "from": "10", "toSymbols": "0123456789 neg=~"})}, errcode.RetiredToken},
		{"digit not in base", []js.Value{js.ValueOf(map[string]any{"value": "12z", "from": "10", "to": "16"})}, errcode.BadInput},
		{"empty input", []js.Value{js.ValueOf(map[string]any{"value": "", "from": "10", "to": "16"})}, errcode.BadInput},
		{"precision past the bound", []js.Value{js.ValueOf(map[string]any{"value": "1", "from": "10", "to": "16", "precision": 100001})}, errcode.BadArg},
		{"negative precision", []js.Value{js.ValueOf(map[string]any{"value": "1", "from": "10", "to": "16", "precision": -1})}, errcode.BadArg},
		{"NaN value", []js.Value{js.ValueOf(map[string]any{"value": math.NaN(), "from": "10", "to": "16"})}, errcode.BadArg},
	} {
		res, ok := convert(reg)(js.Undefined(), c.args).(map[string]any)
		if !ok || res["ok"] != false {
			t.Errorf("%s: did not fail: %v", c.name, res)
			continue
		}
		if msg, _ := res["error"].(string); msg == "" {
			t.Errorf("%s: no error text: %v", c.name, res)
		}
		if code, _ := res["code"].(int); code != int(c.want) {
			t.Errorf("%s: code %v, want %d (%v)", c.name, res["code"], c.want, res["error"])
		}
	}
	if res := call(t, map[string]any{"value": "255", "from": "10", "to": "16"}); res["ok"] != true {
		t.Errorf("a good conversion failed: %v", res)
	}
}
