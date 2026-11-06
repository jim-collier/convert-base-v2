//	Copyright © 2023-2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
//	Licensed under the GPL, Version 2 or later. Full text in ../../../../license.md, or:
//		https://spdx.org/licenses/GPL-2.0-or-later.html
//	SPDX-License-Identifier: GPL-2.0-or-later

// Package rec is what each old SHCL binding's adapter hands back: the raw reads
// v3.0.0's loader made, before it turned them into a base.
package rec

var FieldNames = []string{"aliases", "symbols", "tail", "negative", "decimal", "pad", "pademit"}

type Field struct {
	Str    string
	StrSt  string
	Arr    []string
	ArrSt  string
	Bool   bool
	BoolSt string
}

type Raw struct {
	ParseErr    string
	Count       int
	Name        string
	Fields      map[string]Field
	Children    []string
	HasChildren bool
	Nested      bool
}
