//	Copyright © 2023-2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
//	Licensed under the Apache License, Version 2.0. Full text in ./LICENSE, or:
//		https://spdx.org/licenses/Apache-2.0.html
//	SPDX-License-Identifier: Apache-2.0

package convertbase

import (
	"errors"
	"fmt"
)

// Options carries per-base overrides: the three markers and the binary tail
// repertoire. Each field keeps the tri-state the Base fields use - nil leaves
// the base alone, empty disables, and a value sets it.
//
// Label prefixes the override names in error messages ("--from", "--to" from
// the command-line tool); left empty, the messages name the bare override.
// Source describes where a custom alphabet came from, and shows up in
// --show-symbols output.
type Options struct {
	Negative, Decimal, Pad, Tail *string
	Label                        string
	Source                       string
}

func (o *Options) any() bool {
	return o != nil && (o.Negative != nil || o.Decimal != nil || o.Pad != nil || o.Tail != nil)
}

// flag names one override in an error message: "--from-tail" from the command,
// plain "tail" from a caller that set no Label.
func (o *Options) flag(name string) string {
	if o.Label == "" {
		return name
	}
	return o.Label + "-" + name
}

// apply writes the overrides onto a base that has not been finalized yet. Order
// matters: a custom alphabet that uses "-" or "." as digits only survives
// Finalize() once its replacement markers are in place. Unexported on purpose:
// mutating is only safe on a base nobody else holds, so the public surface is
// ApplyOptions, which copies.
func (o *Options) apply(b *Base) error {
	if o == nil {
		return nil
	}
	if o.Negative != nil {
		b.Negative = strPtr(*o.Negative)
	}
	if o.Decimal != nil {
		b.Decimal = strPtr(*o.Decimal)
	}
	if o.Pad != nil {
		b.PadSymbol = *o.Pad
		b.PadEmit = *o.Pad != ""
	}
	if o.Tail != nil {
		if *o.Tail == "" {
			b.TailSymbols = nil
			// Only drop a tail layout. A codec name lives in the same field,
			// and clearing that would quietly stop the base doing binary at all.
			if isTailScheme(b.BinaryScheme) {
				b.BinaryScheme = ""
			}
			return nil
		}
		tail, err := ParseSymbolSpec(*o.Tail)
		if err != nil {
			return fmt.Errorf("%s: %w", o.flag("tail"), err)
		}
		b.TailSymbols = tail
		// Same choice the config makes: a hand-declared tail gets the qntm
		// layout, the one that streams both directions.
		b.BinaryScheme = "qntm"
	}
	return nil
}

// ApplyOptions returns a copy of an already-finalized base with the overrides
// applied, or base itself when nothing was set. It copies because registry
// bases are shared pointers. Finalize() rebuilds every derived table from
// scratch, so re-running it on the copy is safe and re-validates the new markers
// (collision with a digit, marker inside a digit, negative equal to decimal,
// pad that is also a digit).
func ApplyOptions(base *Base, o *Options) (*Base, error) {
	if !o.any() {
		return base, nil
	}
	// Sign and fractions are meaningless for raw bytes, and every byte value is
	// already a digit, so there is nothing a marker could be set to.
	if base.Binary {
		return nil, fmt.Errorf("base %q carries raw bytes; %s do not apply to it", base.Name(), o.flag("neg/-dec/-pad/-tail"))
	}
	overridden := *base
	if err := o.apply(&overridden); err != nil {
		return nil, err
	}
	if o.Label == "" {
		overridden.Source = base.Source + " (with overrides)"
	} else {
		overridden.Source = base.Source + fmt.Sprintf(" (overridden by %s-* flags)", o.Label)
	}
	if err := overridden.Finalize(); err != nil {
		return nil, err
	}
	return &overridden, nil
}

// ResolveBase returns a Base either from the registry (by name) or from a custom
// symbols spec (which, if provided, takes precedence over the name), with any
// overrides applied. A nil opts argument means none.
func ResolveBase(reg *Registry, name, customSpec string, opts *Options) (*Base, error) {
	if customSpec != "" {
		symbols, err := ParseSymbolSpec(customSpec)
		if err != nil {
			return nil, err
		}
		source := "custom symbols"
		if opts != nil && opts.Source != "" {
			source = opts.Source
		}
		b := &Base{
			Aliases: []string{fmt.Sprintf("custom(%d)", len(symbols))},
			Symbols: symbols,
			Source:  source,
		}
		// Set before Finalize, not after: the markers are part of the definition
		// here, and the defaults may well collide with this alphabet's digits.
		if err := opts.apply(b); err != nil {
			return nil, err
		}
		if err := b.Finalize(); err != nil {
			return nil, err
		}
		return b, nil
	}
	if name == "" {
		return nil, errors.New("no base specified")
	}
	b, err := reg.Lookup(name)
	if err != nil {
		return nil, err
	}
	return ApplyOptions(b, opts)
}
