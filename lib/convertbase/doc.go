//	Copyright © 2023-2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
//	Licensed under the Apache License, Version 2.0. Full text in ./LICENSE, or:
//		https://spdx.org/licenses/Apache-2.0.html
//	SPDX-License-Identifier: Apache-2.0

// Package convertbase converts numbers between arbitrary bases, and encodes and
// decodes raw bytes to and from any base that can carry them.
//
// It is the conversion core of the convert-base-v2 command, which is a thin
// command-line layer over this package. Anything that only makes sense at a
// prompt lives with the command, not here: this package writes nothing to
// standard error, and creates no files of its own.
//
// # Licensing
//
// This package is Apache-2.0, so it can be linked into anything. The command
// around it stays GPL-2.0-or-later. Both licenses ship in the repository.
//
// # Bases
//
// A [Registry] holds the known bases. NewRegistry returns one carrying the
// built-in set; LoadConfig adds bases from an SHCL file. Look a base up by name
// or alias with Lookup, or build one from a symbol spec with [ResolveBase].
//
//	reg, err := convertbase.NewRegistry()
//	ten, err := reg.Lookup("10")
//	hex, err := reg.Lookup("hex")
//	out, err := convertbase.Convert("255", ten, hex, -1)  // "FF"
//
// A precision of -1 sizes the output fraction to the input's; a value of 0 or
// more fixes the digit count.
//
// Each built-in base is built the first time Lookup or OrderedBases reaches
// it, so a new registry is cheap. Lookup and OrderedBases are safe to call from
// several goroutines; Register and LoadConfig are not.
//
// [Options] carries per-base overrides for the negative marker, the decimal
// marker, binary padding, and the tail repertoire a big base needs to stream.
// Each field is a tri-state: nil leaves the base alone, a pointer to an empty
// string disables, and a value sets it.
//
// # Streaming
//
// [ConvertStream] encodes or decodes raw bytes between a reader and a writer,
// or re-encodes the bytes behind one text base's digits in another. The
// power-of-2 bases run in constant memory, whatever the input size. A pair
// that can't stream, such as a codec, is read whole and converted once.
//
//	b64, err := reg.Lookup("64")
//	raw, err := reg.Lookup("bytes")
//	err = convertbase.ConvertStream(os.Stdin, os.Stdout, raw, b64, false)
package convertbase
