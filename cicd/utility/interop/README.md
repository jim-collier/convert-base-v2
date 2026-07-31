# Interop suite

Four of the bases in convert-base-v2 are somebody else's design, not ours: qntm's base2048, base32768 and base65536, and LLFourn's separate base2048. For those, matching the spec is not the goal. Matching the implementation is, because the implementation is what anyone else will be decoding with.

This directory holds those implementations and the glue that runs our output against them. `cicd/test.bash` drives it; there is nothing to run by hand during normal work.

## What is checked

For each of the four bases, randomized byte strings go through both sides and three comparisons:

- our encoding equals theirs, byte for byte
- we read back what they encoded
- they read back what we encoded

Encode alone would not be enough. Two implementations can share a misreading of the tail rules and agree with each other while disagreeing with everyone else, and only crossing the outputs catches that.

Sample lengths start at zero and count up before turning random. Every disagreement these bases have ever had was about the last partial chunk, and the chunk widths are 11, 15 and 16 bits, so the byte-boundary cycle closes inside the first sixteen samples.

## Layout

- `thirdparty/` - the reference implementations, unpacked verbatim from their published releases. **Not our code, and not to be edited.** Each keeps its own license file.
- `drivers/` - ours. Thin batch adapters that give each reference a line-oriented command interface, since three of them are libraries with no runnable form. They read one sample per line and write one result per line, so a whole run costs one process instead of one per sample.
- `pins.env` - the pinned version, download URL and archive hash for each package.
- `manifest.sha256` - hash of every vendored file.
- `fetch.bash` - `--verify` (offline, the default) re-hashes everything against the manifest; `--refresh` re-downloads from the pins.
- `build/` - cargo output for the Rust adapter. Not committed: it is a compiled artifact for one architecture, and it rebuilds offline from the vendored source in a few seconds.

## Why the copies are verified

A reference that has been edited is worse than no reference at all, because the suite would go green against something nobody published. So an edited or missing file under `thirdparty/` fails the test run outright, rather than skipping. A missing toolchain is different and only warns: node or cargo being absent means the checks did not run, not that they failed.

## Pinned versions

| Base in convert-base-v2 | Reference | Version |
| --- | --- | --- |
| `2048qntm` | [qntm/base2048](https://github.com/qntm/base2048) (npm) | 3.0.0 |
| `32768qntm` | [qntm/base32768](https://github.com/qntm/base32768) (npm) | 5.0.1 |
| `65536qntm` | [qntm/base65536](https://github.com/qntm/base65536) (npm) | 5.0.0 |
| `2048llfourn` | [LLFourn/rust-base2048](https://github.com/LLFourn/rust-base2048) (crates.io) | 2.0.2 |

## Updating a reference

Bump the version, the URL and the hash in `pins.env`, run `./fetch.bash --refresh`, and commit the new `thirdparty/` tree, the pins and the regenerated manifest together. Then run the harness: a version bump that changes an alphabet is exactly the thing this suite exists to catch, and it should be a deliberate decision either way.
