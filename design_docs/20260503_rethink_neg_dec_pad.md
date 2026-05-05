<!-- markdownlint-disable MD007 -- Unordered list indentation -->
<!-- markdownlint-disable MD010 -- No hard tabs -->
<!-- markdownlint-disable MD033 -- No inline html -->
<!-- markdownlint-disable MD055 -- Table pipe style [Expected: leading_and_trailing; Actual: leading_only; Missing trailing pipe] -->
<!-- markdownlint-disable MD041 -- First line in a file should be a top-level heading -->

<!-- TOC ignore:true -->
# Design 20260503: Rethink decimal, negative, and padding symbols definition

<!-- TOC ignore:true -->
## Table of contents

<!-- TOC -->

- [Introduction](#introduction)
- [Related to Issues, PRs](#related-to-issues-prs)
- [Requirements](#requirements)
- [Constraints](#constraints)
- [High-level solution](#high-level-solution)
	- [Pros and cons of idiomatic approaches in Go](#pros-and-cons-of-idiomatic-approaches-in-go)
	- [Example usage comparisons](#example-usage-comparisons)
		- [functional options](#functional-options)
		- [structs](#structs)
- [Detailed solution](#detailed-solution)

<!-- /TOC -->

## Introduction

Currently, the symbols representing 'negative' and 'decimal' are included in the base definion string, like this:

~~~go
mkSpec(base_62hex+" - _ neg=~", "64h", "64hex", "64hexurl", "64hu"),
~~~

Problems:

- Going to get unweildly when adding high-base padding symbols.
- Compound problem with ability to use space as a delimiter.
- It's a little janky.

This is a universal (if minor) problem class - basically how to best break out paremeters you rarely want to specify and that sometimes have magic meaning - solved a million times in a million ways, in different idiomatic ways in different languages.

## Related to Issues, PRs

- Issues: [#6](https://github.com/jim-collier/convert-base-v2/issues/6)

## Requirements

- Those things need to be completely separate from the base symbols string.
- Need to default to standard symbols if not specified.
- Need to be able to positively specify "_no_ negative and/or decimal allowed".

## Constraints

- As far as just modifying the inputs to `mkSpec()` goes, Go has no support for named parameters.
	- The idiomatic workaround is to use `structs` or `functional options` as input to `mkSpec()`.
		- Either can get verbose.
- Neither `structs` nor `functional options` can represent "absence". But we need to be able to tell the function, for example, "for this base we don't allow negative" - vs "I'm not going to specify anything so just use the default symbol that represents 'negative'."

## High-level solution

Either use a struct, or functional options. Struct is the simplest.

### Pros and cons of idiomatic approaches in Go

| Option | Pros | Cons | Idiomatic? | Consider? | Comments
| ---    | ---  | ---  | :--:       | :--:      | ---
| `structs` with string pointers instead of strings | If member not defined, it's `nil`, exactly what we want (which would mean "use the default symbol"). | • Can't pass pointers to string literals, e.g. `&"~"`, only to variables, e.g. `&neg`.<br />• The code is not obvious about our intended meaning of empty and nil. | yes | yes | Can use a helper function e.g. `ptr("~")`, still some jank.
| `functional options` with default values set to "-", ".", and "" for `neg`, `dec`, and `padSymbols`. | • The behavior we originally wanted.<br />• Moves some validation closer to where it logically belongs. | • Inflates the simple codebase slightly just to gain this behavior.<br />• The code is not obvious about our intended meaning of empty and nil.<br />• Could spread validation out. | yes | yes | When keeping things lean, even small functions add up.
| `structs` but using a sentinel value for "don't allow". | The simplest of all | The jankiest of all | NO | NO
| `structs` with added boolean fields `disallowNeg` and `disallowDec`. | More explicit about what we want, a huge plus. | With `false` as the non-overridable default in not specified, we'd have to use `true` for _negation_, which makes reasoning through logic more difficult. | if you squint hard enough | yes
| `functional options` with added boolean fields `allowNeg` and `allowDec` that both default to `true` | The explicitness of the previous option, _and_ without the jank of `true`ing a negative. | • The "extra code" drawback.<br />• Now it's possible to have conflicting fields; need extra validation. | yes | yes

Points to consider:

- In practical use, `mkSpec()` is called with defaults for `neg` and `dec` most of the time. (And same will be true for `padSymbols`.)

- For `neg`, for example, it definitionally can't be defined, _and_ set to disallow; so if going the string and boolean route, the options should never be used at the same time (without triggering an explicit error), so usage won't be any more complex, just the function code.

### Example usage comparisons

- Override the default for `neg`,
- not specify `dec` and let it use the default, and
- disallow padding (just as an example even though the latter wouldn't be done for this base).

#### `functional options`

~~~go
//
mkSpec(
	WithSymbols(base_62hex+" - _"),
	WithAliases("64h", "64hex"),
	WithNegSymbol("~"),
	AllowPadding(false),
),
~~~

#### `structs`

~~~go
mkSpec(SpecOpts{
	BaseSymbols:   base_62hex + " - _ ",
	Aliases:       []string{"64h", "64hex"},
	NegSymbol:     "~",
	DisallowPads:  true,
}),
~~~

## Detailed solution

Decision: Use structs for the simplicity, with the understood and accepted tradeoff being the double-negative in `Disallow`* fields.

1. Define the struct:

	~~~go
	type SpecOpts struct {
		BaseSymbols    string
		Aliases      []string
		NegSymbol      string
		DecSymbol      string
		PadSymbols   []string
		DisallowNeg    bool
		DisallowDec    bool
		DisallowPad    bool
	}
	~~~

1. Add validation logic to `mkSpec()`. Error if, for example, `NegSymbol` is specified and not "", but `DisallowNeg` is set to `true`.

1. Invoke it in `bases.go` as illustrated in the previous section.

1. Update the existing base definitions to use this idiom.