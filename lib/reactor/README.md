# Reactor module ABI

A WebAssembly library module. Any host with a wasm runtime loads it, calls `_initialize` once, then calls the exports below as many times as it wants. Built from `lib/` with `make reactor`, which writes `dist/convert-base-reactor.wasm` and needs a Go 1.24 or newer toolchain. Apache-2.0, like the library it wraps.

Design and background: `project/design_docs/20260801_wasm_reactor.md`. A working host that calls every export on this page is in `cicd/utility/reactor-host/`.

## Calling convention

Only numbers cross the boundary, so strings travel through the module's exported linear `memory`:

- Call `alloc(size)` to get a region, write your bytes into it through `memory`, and pass the offset and length as a pair of `u32` arguments. An input pointer must lie inside a region you allocated. Anything else is refused with `BadArg` rather than read blind.

- String results come back as one `u64` packed as `(pointer << 32) | length`. On a zero return, check `last_error_code`: a nonzero code means the call failed, and 0 means a legitimately empty result. That rule is the contract for every string-returning export. Region-returning exports happen to give even an empty result a real address today, so their zero does mean failure. Check the code anyway; the address behavior is not promised.

- Results from `convert`, `convert_fit`, `base_zero`, `symbol_slice`, and `fit` are regions you own: read them out, then pass the pointer to `free`. The strings from `last_error_text` and `version` are module-owned: never free them, and copy the error text out before the next call overwrites it.

- Signed returns (`base_radix`, `symbol_count`, `lookup`, `free`) carry the answer when non-negative and the error as a code (negated where the answer itself is a number).

- A base name is anything the command accepts: canonical names, aliases, `b16`/`base16` prefix forms, any case. An unknown name's error text carries the same near-match suggestions the command prints.

## Exports

| Export | Signature | Returns |
|---|---|---|
| `alloc` | `(size: u32) -> u32` | Region pointer, or 0 on failure. Size must be positive. |
| `free` | `(ptr: u32) -> i32` | 0, or `BadArg` for a pointer that is not an allocated region (this is how a double free reports). |
| `convert` | `(from_ptr, from_len, to_ptr, to_len, value_ptr, value_len: u32, precision: i32) -> u64` | Packed result string, host-freed. Zero on error. Negative precision means automatic, same as the command's default; the cap is 100000. |
| `lookup` | `(name_ptr, name_len: u32) -> i32` | 0 when the name resolves, else the error code. |
| `base_radix` | `(name_ptr, name_len: u32) -> i64` | The base's symbol count, or the negated error code. |
| `base_zero` | `(name_ptr, name_len: u32) -> u64` | The base's first symbol, packed, host-freed. This is the padding symbol for fixed-width output. The word-safe base 32 starts at `2`, so assuming `0` pads wrongly. |
| `symbol_count` | `(name_ptr, name_len, str_ptr, str_len: u32) -> i64` | How many of the base's digit symbols make up the string, or the negated error code. Counts symbols, not bytes. Digits only; a sign or decimal marker in the string is an error. |
| `symbol_slice` | `(name_ptr, name_len, str_ptr, str_len: u32, start, count: i32) -> u64` | The part of the string covering symbols `[start, start+count)`, counting symbols rather than bytes. Negative start counts from the right end (-3 = the last three symbols); count < 0 means through the end; both clamp to what the string holds instead of erroring. Packed, host-freed. Digits only, like `symbol_count`; the result comes back in canonical symbol form. |
| `fit` | `(name_ptr, name_len, str_ptr, str_len, width: u32) -> u64` | The string right-aligned to exactly `width` symbols: left-filled with the base's zero symbol (`base_zero`) when short, cut to the rightmost `width` symbols when long. Packed, host-freed. Digits only. One place for the pad-or-truncate policy, so every caller applies it the same way. Note again that the word-safe base 32 pads with `2`. |
| `convert_fit` | `(from_ptr, from_len, to_ptr, to_len, value_ptr, value_len, width: u32) -> u64` | `convert` at automatic precision, then `fit` to `width` in the destination base, one call and one region. Packed, host-freed. The fit half is digits-only, so a conversion whose result carries a sign or decimal marker errors here; use the two-step path for those. |
| `last_error_code` | `() -> i32` | Code of the most recent call's error, 0 if it succeeded. |
| `last_error_text` | `() -> u64` | Packed message, module-owned. Zero when there is no error. |
| `version` | `() -> u64` | Packed library version (`convertbase.Version`), module-owned. |
| `region_count` | `() -> u32` | Outstanding allocated regions, so a host can assert it freed everything. |
| `stream_new` | `(from_ptr, from_len, to_ptr, to_len: u32) -> i64` | Stream handle (positive), or the negated error code. See Streaming below. |
| `stream_write` | `(handle, ptr, len: u32) -> u64` | Pushes input bytes, returns the packed output produced so far. Module-owned per stream: copy it out before the next call on this stream. Zero length is a legal drain-only call. |
| `stream_finish` | `(handle: u32) -> u64` | Ends the input and returns the packed tail of the output. The handle stays valid until `stream_free`. |
| `stream_free` | `(handle: u32) -> i32` | Releases a stream in any state, finished or not. 0, or `BadArg` for a handle that is not open. |
| `stream_count` | `() -> u32` | Open streams, the `region_count` twin for handles. |

## Streaming

A stream is the reactor's form of the command's piped binary mode: raw bytes on one side and a raw-capable base on the other (any power-of-2 base, or one of the defined binary-to-text codecs), or two such text bases routed through `bytes`. A pair that cannot carry raw bytes at all, base 10 for instance, is refused at `stream_new`. Nothing else about the ABI changes. Input travels through allocated regions, and errors are reported through `last_error_code` and `last_error_text`.

The shape is push-style, like zlib: open, write as many times as you like, finish, free. Each `stream_write` and the `stream_finish` return a packed output chunk. A zero return with `last_error_code` 0 is an empty chunk, not an error. Output can trail input by a partial group, and the tail may be empty. A zero return with a code set means the stream failed. It then refuses further writes, and only `stream_free` still applies. Freeing without finishing abandons the stream, which is allowed.

Output chunks are module-owned and reused per stream, the same contract as `last_error_text`: copy a chunk out before the next call on the same stream. Streams never touch the region allocator, so `region_count` stays the host's own ledger.

Pairs the library streams natively, which is the power-of-two bases including the large ones, run in constant memory at any input size. The four codecs (base45, ascii85, z85, base91) buffer internally and emit everything at `stream_finish`, exactly as the command does for the same conversions. The answers are identical either way; only the memory use differs. The z85 rule that the whole input must be a multiple of four bytes is applied at finish.

## Error codes

Stable and part of the contract: new codes may be added at the end, existing ones never renumber.

| Code | Name | Meaning |
|---|---|---|
| 0 | `None` | Success. |
| 1 | `UnknownBase` | Base name or alias resolves to nothing. The text carries near-match suggestions. |
| 2 | `MissingMarker` | The output base has no sign or decimal marker for a value that needs one. |
| 3 | `MarkerDefault` | A default marker collides with one of the base's digits. |
| 4 | `RetiredToken` | A symbol spec carried a retired `neg=`/`dec=`/`pad=` token. |
| 5 | `BadInput` | Any other conversion or parse failure (a digit not in the base, empty input, and so on). |
| 6 | `BadArg` | A bad pointer, length, size, or precision from the host. |
| 7 | `Internal` | The registry failed to initialize. |

## Which one to use

- `convert` handles whole values held in memory, numbers included.

- Streams handle raw byte re-encoding of input with no size limit.

- A host that only pipes data through may prefer the WASI build of the command (`make wasm`) instead. It gets real standard input and output, and needs no memory protocol at all.
