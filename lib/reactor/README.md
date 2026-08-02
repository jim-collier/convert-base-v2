# Reactor module ABI

A WebAssembly library module. Any host with a wasm runtime loads it, calls `_initialize` once, then calls the exports below as many times as it wants. Built from `lib/` with `make reactor` (needs a Go 1.24+ toolchain; the artifact lands at `dist/convert-base-reactor.wasm`). Apache-2.0, like the library it wraps.

Design and background: `project/design_docs/20260801_wasm_reactor.md`. The exercised reference for everything on this page is `cicd/utility/reactor-host/main.go`.

## Calling convention

Only numbers cross the boundary, so strings travel through the module's exported linear `memory`:

- Call `alloc(size)` to get a region, write your bytes into it through `memory`, and pass the offset and length as a pair of `u32` arguments. Input pointers must lie inside a region you allocated; anything else is refused with `BadArg` rather than read blind.
- String results come back as one `u64` packed as `(pointer << 32) | length`. Zero means failure; ask `last_error_code` and `last_error_text` why.
- Results from `convert` and `base_zero` are regions you own: read them out, then pass the pointer to `free`. The strings from `last_error_text` and `version` are module-owned: never free them, and copy the error text out before the next call overwrites it.
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
| `base_zero` | `(name_ptr, name_len: u32) -> u64` | The base's first symbol, packed, host-freed. This is the padding symbol for fixed-width output: the word-safe base 32 starts at `2`, so assuming `0` pads wrongly. |
| `symbol_count` | `(name_ptr, name_len, str_ptr, str_len: u32) -> i64` | How many of the base's digit symbols make up the string, or the negated error code. Counts symbols, not bytes. Digits only; a sign or decimal marker in the string is an error. |
| `last_error_code` | `() -> i32` | Code of the most recent call's error, 0 if it succeeded. |
| `last_error_text` | `() -> u64` | Packed message, module-owned. Zero when there is no error. |
| `version` | `() -> u64` | Packed library version (`convertbase.Version`), module-owned. |
| `region_count` | `() -> u32` | Outstanding allocated regions, so a host can assert it freed everything. |

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

## Not here yet

Streaming. The one-shot surface covers whole values held in memory; piped raw-binary conversion stays with the WASI command build (`make wasm`), which gets real stdin and stdout. A push-style streaming API (`stream_new`/`stream_write`/`stream_finish`) is the planned addition and will not change anything above.
