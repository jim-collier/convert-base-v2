<!-- markdownlint-disable MD007 -- Unordered list indentation -->
<!-- markdownlint-disable MD010 -- No hard tabs -->
<!-- markdownlint-disable MD033 -- No inline html -->
<!-- markdownlint-disable MD055 -- Table pipe style [Expected: leading_and_trailing; Actual: leading_only; Missing trailing pipe] -->
<!-- markdownlint-disable MD041 -- First line in a file should be a top-level heading -->

<!-- TOC ignore:true -->
# Design 20260725: Streaming encode and decode for wide-symbol bases

<!-- TOC ignore:true -->
## Table of contents

<!-- TOC -->

- [Introduction](#introduction)
- [Requirements](#requirements)
- [Constraints](#constraints)
- [Measurements](#measurements)
- [High-level solution](#high-level-solution)
	- [Why symbol width is the right axis](#why-symbol-width-is-the-right-axis)
	- [Why the new path also takes the big bases](#why-the-new-path-also-takes-the-big-bases)
	- [The one base that cannot stream both ways](#the-one-base-that-cannot-stream-both-ways)
- [Detailed solution](#detailed-solution)
	- [1. A new gate on Base](#1-a-new-gate-on-base)
	- [2. Wide encode](#2-wide-encode)
	- [3. Wide decode](#3-wide-decode)
	- [4. Tails for the big bases](#4-tails-for-the-big-bases)
	- [5. Byte-route legs](#5-byte-route-legs)
- [Touch points](#touch-points)
- [Testing](#testing)
- [Compatibility](#compatibility)
- [Outcome](#outcome)

<!-- /TOC -->

## Status

Done, on branch `wide`. The three tt bases above eight bits got tail repertoires, so every base that can carry raw bytes now streams in both directions. See [Outcome](#outcome) for measured results.

## Introduction

Binary encode and decode stream today only when the text base has one byte per digit and at most eight bits per digit. That covers base 16, 32, and 64 and their variants, which is what the system encoders do and what the throughput work targeted.

Every other power-of-2 base buffers the whole input and the whole output. That is all of the custom bases: the jc, tt, wordsafe, emoji, and v1compat families, plus the four published big bases. Those bases are the reason this tool exists, and they are the ones that cannot handle a large file.

This design adds a second streaming path for them. The existing single-byte path is not touched.

## Requirements

- Every power-of-2 base that can carry raw bytes should encode and decode a stream in constant memory.
- The tuned single-byte path keeps its current code and its current speed.
- Output stays byte-for-byte identical to the buffered path, in both directions, at every input length.
- A base the new path cannot serve still falls back to buffered, silently and correctly, as it does now.

## Constraints

- The big bases have published formats that must keep interoperating with their reference implementations.
- The bit-packing rules, RFC padding, and the trailing-bits guard are already settled and must not change.
- A conversion that streams must decide so before reading any input, because the caller commits to a path up front.

## Measurements

Peak resident memory, encoding a 48 MB blob from `bytes`:

| Bases | Peak | Time
|---|---|---
| 16, 32, 32c, 32z, 32bip, 64, 64u, 64h | 16 MB | 0.10 s
| 64jc1, 64tt, 128tt | 256 - 337 MB | 0.46 - 0.51 s
| 128jc1, 128v1compat, 128w, 256jc1, 256tt | 446 - 526 MB | 0.57 - 0.69 s
| 64w, 64v1compat, 512tt | 533 - 594 MB | 0.61 - 0.80 s
| emoji64 | 1183 MB | 0.85 s
| 2048twitter, 2048rust, 32768qntm, 65536qntm | 352 - 418 MB | 0.37 - 0.53 s

Decoding is worse. Recovering a 12 MB payload:

| Base | Encoded size | Peak | Time
|---|---|---|---
| 64 | 16 MB | 15 MB | 0.05 s
| 128tt | 21 MB | 753 MB | 1.42 s
| 256tt | 24 MB | 557 MB | 1.32 s
| 2048twitter | 22 MB | 113 MB | 0.58 s
| 65536qntm | 21 MB | 113 MB | 0.53 s

The worst case in the project is decoding a wide base of eight bits or fewer, at about sixty times the payload size. That is `Tokenize` building one string header per digit before any bits are unpacked. The big bases avoid it by walking runes directly, which is why they cost a third as much.

## High-level solution

Add `streamEncodeWide` and `streamDecodeWide` alongside the existing pair. `streamConvert` tries the single-byte cases first, exactly as now, and only offers the conversion to the wide pair when they decline.

### Why symbol width is the right axis

The single-byte path is a byte-table design from end to end. Encode builds `table[i] = to.Symbols[i][0]`, one byte per digit, and the unrolled group loops write at fixed strides. Decode indexes a `[256]int` array with the raw input byte. Neither structure can represent a symbol longer than one byte, so the current gate is protecting correctness, not just speed. Widening those functions in place would mean variable-width writes and a map lookup in the loops that were written to avoid exactly that.

A separate path keeps the tuned one intact and lets the wide one stay plain: the general group loop, no unrolled widths, no pretense that it will match base64.

### Why the new path also takes the big bases

A base above eight bits per digit has more than 256 symbols, so it cannot be single-byte. Wide symbols and big bases are therefore not two problems, they are one. Every base above eight bits is already wide, so the new path gets them for the cost of a tail-handling branch at end of input.

### The bases that had no tail scheme

`512tt`, `1024tt` and `2048tt` wrote the byte count as a leading varint, which cannot stream: the length has to be known before the first digit is emitted. The fix is to give them what the four published big bases already have, a tail repertoire, which is decided at end of input and so streams fine.

The tail width follows from the packing. Encoding N bytes into k-bit digits leaves r = 8N mod k bits over. Padding those out to a whole digit adds a spare byte the decoder cannot tell from data whenever the padding reaches eight bits, which is exactly when r is k-8 or less. A tail repertoire of 2^(k-8) symbols covers precisely those cases, and everything above them pads to a primary digit with fewer than eight bits left over.

That rule matches all four published bases, which is a good sign it is the real one rather than a coincidence of one implementation:

| Base | Bits per digit | Tail symbols | 2^(k-8)
|---|---|---|---
| 2048twitter | 11 | 8 | 8
| 2048rust | 11 | 8 | 8
| 32768qntm | 15 | 128 | 128
| 65536qntm | 16 | 256 | 256

So the three tt bases need 2, 4 and 8 tail symbols. One shared block of eight covers all three, and because they use the qntm layout they reuse `encodeBigBaseNative` and `decodeBigBaseNative` unchanged. No new scheme code.

The eight symbols have to sit outside `base_2048tt`, which holds exactly 2048 with no spares, so they are genuinely new: U+2E00 to U+2E07, supplemental punctuation. Punctuation reads as a terminator against a primary repertoire of letters, digits and CJK, which is the same instinct behind qntm using ASCII 0-7 against a Latin primary.

A user-defined base above eight bits can declare its own tail, through a `tail:` config field or the `--from-tail` / `--to-tail` flags, in the same string-or-list form as the symbols. Declaring one moves the base onto the tail scheme and it streams like any built-in. Leaving it out keeps the varint packing, which still round-trips but has to buffer the encode, so nothing that worked before changed.

A hand-declared tail always gets the qntm layout. It is the scheme that streams cleanly in both directions, and choosing it here means a config never has to name one. The width rule above is enforced at load time rather than at conversion time, so a tail that could never be used is an error where it is written.

## Detailed solution

### 1. A new gate on Base

Add `allOneRune bool` and `runeValue map[rune]int`, filled in by `finalize()` next to the existing `allOneByte` and `byteValue`. A base qualifies when every symbol is exactly one UTF-8 rune.

All sixteen currently-buffered power-of-2 bases qualify, verified against the binary. Only a custom symbol set with a multi-rune symbol falls outside, and those keep the buffered path they have now.

One rune per symbol is what makes the decoder cheap. The general greedy longest-match tokenizer is not needed, and neither is a trie, which would be unaffordable for a 65536-symbol base anyway.

The symbol set is already guaranteed prefix-free by `finalize()`, so nothing new has to be proven about splitting a run of digits.

### 2. Wide encode

Same group loop as the general branch of `streamEncode`. Two differences:

- The lookup table holds symbols, not bytes. Flat byte blob plus offsets, so the table is one allocation rather than 65536 strings.
- The output buffer is sized by the longest symbol, and digits are copied in rather than stored.

Padding, where the base defines it, works unchanged. It only applies at eight bits or fewer, which is already enforced at definition time.

### 3. Wide decode

Read a chunk, walk it with `utf8.DecodeRune`, look each rune up in `runeValue`, feed the value into the same bit accumulator the buffered path uses.

The two things the byte decoder does not have to worry about:

- A rune can straddle a chunk boundary. Carry the incomplete tail forward, and distinguish an incomplete rune from an invalid one so a truncated stream is an error rather than silent garbage.
- Line breaks and a trailing pad run still have to be tolerated, matching the byte decoder so wrapped input reads the same.

### 4. Tails for the big bases

Above eight bits the last chunk is the only interesting part, and the schemes already exist in `encodeBigBaseNative` and `decodeBigBaseNative`. Encoding needs nothing new, because the tail is only decided at end of input.

Decoding needs one symbol of lookahead, since a tail symbol is legal only in the final position. `2048rust` additionally sizes its final symbol from the total symbol count, which a running counter provides by the time the held-back symbol is emitted.

### 5. Byte-route legs

`--binary` between two text bases joins two stages through a pipe. Each stage already picks its own path, so a wide base on one side and a single-byte base on the other should compose without special handling. The leg predicate that currently gates the route needs to admit wide bases.

## Touch points

- `bases.go` - tail repertoires on the three tt bases.
- `registry.go` - two fields and their setup in `finalize()`, plus validation that a tail repertoire is disjoint from the digits and wide enough for the base. The `tail:` config field and the shared string-or-list decoder it uses with `symbols:`.
- `main.go` - the `--from-tail` / `--to-tail` flags, on the same per-side override group as the markers.
- `convert.go` - the two new functions, the dispatch in `streamConvert`, the leg predicate, and line-break tolerance on the buffered multi-byte decode.
- `conversions_test.go`, `fuzz_test.go`, `cicd/test.bash` - wider targets, the wrapped-input case, the peak-memory ceiling, and both tail-declaring surfaces.

## Testing

The equivalence test already compares streamed against buffered output for any base the streaming path accepts, and skips the rest. Its target list includes `128jc1` and `256jc1`, which are skipped today and start being compared the moment the wide path accepts them. The list should grow to all sixteen bases, and the length list should keep its awkward values so tails and chunk boundaries stay covered.

The fuzz target should get a wide base as well as its current single-byte one, since chunk-boundary rune splitting is the kind of bug that only shows up on odd lengths.

## Compatibility

The binary layout of `512tt`, `1024tt` and `2048tt` changed, from the varint length prefix to the tail scheme. None of the three has ever appeared in a release, so nothing can have encoded data in the old layout. The two layouts cannot be told apart reliably anyway, so a decoder could not have accepted both.

Nothing else changed. Every other conversion produces exactly what it produced before, at less memory. One behavior did get more permissive: binary decoding of a multi-byte base now tolerates line breaks, matching what the single-byte bases already did, so wrapped output reads back. Input that was valid before is still valid and still means the same thing.

## Outcome

Every base that can carry raw bytes now streams both ways, at about 20 MB of peak memory regardless of input size. That includes a base of your own once it declares a tail: a 24 MB encode through a custom 512-symbol base falls from 244 MB to 21 MB, and decoding it holds at 21 MB.

Encoding 48 MB, before and after:

| Base | Before | After
|---|---|---
| emoji64 | 1183 MB, 0.85 s | 20 MB, 0.36 s
| 64w | 533 MB, 0.78 s | 21 MB, 0.61 s
| 512tt | 594 MB, 0.61 s | 20 MB, 0.49 s
| 256tt | 445 MB, 0.57 s | 21 MB, 0.44 s
| 65536qntm | 411 MB, 0.52 s | 20 MB, 0.45 s

Decoding a 12 MB payload, before and after:

| Base | Before | After
|---|---|---
| 128tt | 753 MB, 1.42 s | 21 MB, 0.41 s
| 256tt | 557 MB, 1.32 s | 20 MB, 0.40 s
| 2048twitter | 113 MB, 0.58 s | 20 MB, 0.35 s

Decoding gained the most, because the buffered path built one string header per digit before unpacking a single bit.

Verification: 625 streamed-against-buffered comparisons across 25 bases and 25 lengths, 121000 fuzz round-trips across the six streaming shapes, and the harness at 252 checks including the published reference vectors and the v1 cross-checks. The harness also asserts a peak-memory ceiling per base, which is the only check that catches a base silently falling back to buffered, since output stays correct either way.
