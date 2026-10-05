<!-- markdownlint-disable MD007 -- Unordered list indentation -->
<!-- markdownlint-disable MD010 -- No hard tabs -->
<!-- markdownlint-disable MD041 -- First line in a file should be a top-level heading -->

<!-- TOC ignore:true -->
# Project backlog

<!-- TOC ignore:true -->
## Table of contents

<!-- TOC -->

- [Introduction](#introduction)
- [Issues](#issues)
- [Old format](#old-format)
	- [Bugs](#bugs)
	- [Features and enhancements](#features-and-enhancements)
	- [Done](#done)
		- [Done - Bugs](#done---bugs)
		- [Done - Features and enhancements](#done---features-and-enhancements)
	- [Deferred](#deferred)
	- [Canceled](#canceled)
- [Template](#template)

<!-- /TOC -->

## Introduction

Going forward, new issues in the new template at the bottom of this file, will go in the '## New format' section only. No more status emojis. Refer to '## Reference' for sort order. Issues in the old format (with status emojis) won't be refactored, but will continue to be worked until moved to closed, canceled, or deferred sections, and emojis updated. (Eventually this will all be moved to nano-git-db anyway. This new template is an intermediate effort to make issues going forward more structured and importable.)

This is a product backlog just for pre-v1.0.0 release. After that, bugs, features, and enhancements will be managed in Github Issues, and/or [todo.md](../todo.md)

Sub-bullets can be prefaced with a short tag so the note's role is clear at a glance: `Reproduced:`, `Cause:`, `Probable fix:`, `Fixed:`, `Done:`, `Verified:`, or `Note:`.

## Issues

- Several Go functions are hard to read at a glance. (Code review 20261004 item 23)
	- ID: 2026100413480023
	- Type: Enhancement
	- Status: Queued
	- Priority: Low
	- Opened: 20261004-134800
	- Opened by: Code review 20261004
	- Target OS: Any
	- Note: `Finalize` scores 117 on gocognit, and copies its case-flip block three times, one copy already different. `Convert` opens with 70 lines of byte-mode branching before the number path. `run()` is 440 lines with an `os.Exit(2)` inside.
	- Note: alias flags are separate bools ORed at each use. `canLowercase` and `canUppercase` are copies. The `case from.allOneByte` arm in `convertBitPacked` can never be reached.
	- Origin: mostly ad488ce, grown since. Not seen by an earlier round. Confirmed by gocognit and a coverage profile.
	- Progress log:
		- 20261005: split into 3 children, one per file, so each can be done and checked alone. This item closes when they do.

- `Finalize` is hard to follow and copies its case-flip block 3 times. (Code review 20261004 item 23a)
	- ID: 2026100507495201
	- Type: Enhancement
	- Status: Queued
	- Priority: Low
	- Opened: 20261005-074952
	- Opened by: Code review 20261004
	- Parent ID: 2026100413480023
	- Target OS: Any
	- Note: `registry.go` `Finalize` scores 117 on gocognit. One of the 3 case-flip copies already differs from the others.

- `Convert` buries the number path under byte-mode branching, and `convertBitPacked` has a dead arm. (Code review 20261004 item 23b)
	- ID: 2026100507495202
	- Type: Enhancement
	- Status: Queued
	- Priority: Low
	- Opened: 20261005-074952
	- Opened by: Code review 20261004
	- Parent ID: 2026100413480023
	- Target OS: Any
	- Note: `convert.go` `Convert` opens with 70 lines of byte-mode branching. The `case from.allOneByte` arm in `convertBitPacked` can never be reached.

- `run()` is 440 lines, and the command's flag helpers repeat themselves. (Code review 20261004 item 23c)
	- ID: 2026100507495203
	- Type: Enhancement
	- Status: Queued
	- Priority: Low
	- Opened: 20261005-074952
	- Opened by: Code review 20261004
	- Parent ID: 2026100413480023
	- Target OS: Any
	- Note: `main.go` `run()` has an `os.Exit(2)` inside it. Alias flags are separate bools ORed at each use, and `canLowercase` and `canUppercase` are copies.

- The Bash scripts drift from the house Bash style. (Code review 20261004 item 26)
	- ID: 2026100413480026
	- Type: Enhancement
	- Status: Queued
	- Priority: Low
	- Opened: 20261004-134800
	- Opened by: Code review 20261004
	- Target OS: Linux
	- Note: most harness and helper functions are not `fCamelCase`, many variables are snake_case, and private globals take one underscore. About 850 expansions are unbraced.
	- Note: some files lack History or a `## Purpose` header, some have shellcheck disables mid-file, and a few print errors to stdout. `test.bash` groups output with `>>>` rather than the house section rule.
	- Note: fix a file when it is next touched. `gfs-rotate.bash` is a shared copy, so leave it.
	- Progress log:
		- 20261005: left out of the round. It stays a fix-when-touched rule, since a one-pass restyle of every script would be a big diff for little gain.
	- Origin: several commits. Directive gap, filed against the 2026-10-04 directives.

- The first-run config is written in place, so a crash or a second process can leave a broken file. (Code review 20261004 item 2)
	- ID: 2026100413480002
	- Type: Bug
	- Status: Done
	- Needs external testing: none. Hosted CI passed on dev at 971ae42, run 37252643753.
	- Severity: High
	- Opened: 20261004-134800
	- Opened by: Code review 20261004
	- Target OS: Any
	- Steps to reproduce:
		- Leave a truncated copy of the default config where the first run writes it, then run `convert-base-v2 255 16`.
		- Or start 16 first runs at once on an empty config dir.
	- Incorrect behavior: a cut that drops the Format line gets migrated and stamped as current. A cut inside the `10emoji` block makes every run fail, `--help` included, with an error that blames an old format. Parallel first runs both wrote the file in 1 of 30 trials.
	- Expected behavior: the file is either whole or absent, and only one process creates it.
	- Reproduced: 20261004, by the review, in a scratch home.
	- Possible cause: `userconfig.go:51` uses `os.WriteFile`. The migration path already writes atomically.
	- Probable fix: `shcl.WriteFileAtomic`, which creates exclusively through a temp file and a link.
	- Origin: `userconfig.go:51`, last touched by 51f59b6 on 2026-10-03; the in-place write is older. Not seen by an earlier round. Confirmed.
	- Actual cause: `os.WriteFile` creates and truncates in place, so a half-written file is visible, and a second run that passed the existence check writes over the first.
		- `shcl.WriteFileAtomic`, the first fix, checks for the file again itself. A run that finds one by then replaces it and reports success, so the write was atomic but not exclusive.
	- Actual fix: the first run creates the file itself. The text goes to a synced temp file beside it, and a hard link puts it in place. A link fails if anything is at the path, so only one run creates the file and the rest leave it be. The truncated-copy case has the same cause: now a whole file appears or none does. Where links don't work, an exclusive create in place still allows one creator, but a crash there can leave half a file.
	- Note: a new file takes 0666 less the umask, like any newly created file, where it took 0644 less the umask. Under the usual 022 umask both are 0644. A crash mid-write can leave a `.convert-base-v2.shcl.tmp*` file beside the config instead of a broken config.
	- Note: a dangling symlink at the config path is now left alone, and the run goes on without a config. Before, the default was written to wherever the link pointed.
	- Verified: 20261004, go vet, golangci-lint and `go test ./...` clean.
	- Verified: 20261004, second fix: go vet (linux, windows, darwin), golangci-lint and `go test ./...` clean. 30 trials of 16 first-run processes at once each had one creator and no leftover files.
	- Swept: every file create in `lib/` and `cicd/`. The migration backup already links with an exclusive fallback. The config rewrite, `keepBackup` and the macho-fat output mean to replace. wasm and reactor write no files.
	- Branch: exit-fixes, firstrun-excl
	- Commit: e5892c9, 7a01a50
	- Test case: `ErlzPLg` TestUserConfigFirstRunsRace, 20 trials of 16 first runs at once. Each must have one creator, the whole default text and no leftover files. On dev it failed on the first trial in 5 of 5 runs, with 2 to 4 creators. With the fix it passed 10 of 10 runs under the race detector.
		- Second fix: it now runs 60 trials on two threads, since the gap showed on a small CI runner and almost never with many cores. With the first fix it failed 20 of 20 plain runs here, and 46 of 50 at `-count=50 -cpu 2` before the test change. With this fix it passed 20 of 20 plain runs, and 50 of 50 at `-cpu` 1, 2, 4 and 32 and under the race detector.
		- `Ermok4L` TestUserConfigCreateKeepsFile: the create step finds a file already there and leaves it. It failed with the first fix's write in its place.
		- `Ermok4r` TestUserConfigCreateWithoutLinks: with no hard links, one create succeeds, whole, and a second finds the file. It failed with a truncating create in the fallback.
	- Acceptance signoff: closed without it. Tested here and on hosted CI. The dangling symlink case is left alone on purpose, since writing through a link to a missing target is a guess about where the file should live.
	- Closed: 20261004
	- Progress log:
		- 20261004: reopened. `ErlzPLg` fails on hosted CI on every dev push since the merge, 2 runs creating the file. It passes here, so the window is timing.
		- Cause: `ensureUserConfig` checks that the file is missing, then `shcl.WriteFileAtomic` checks again. A run that finds the file there by its second check replaces it, and still reports it created. So the write is atomic but not exclusive.
		- Probable fix: create it in `ensureUserConfig` itself. Write a temp file beside it, then `os.Link` it into place; "exists" means another run made it. Where links don't work, an `O_EXCL` create.
		- 20261004: fixed on firstrun-excl, as the probable fix above. Reproduced here first with `-count=50 -cpu 2`, 46 of 50 runs with 2 to 4 creators.
		- Note: shcl friction, a missing capability. `WriteFileAtomic` has no create-only mode, so a caller can't create a file whole and only if absent. Smallest repro: 16 goroutines each calling it on one new path. Several return nil, where one is wanted.

- A big base with multi-character digits and a tail encodes data it can't decode. (Code review 20261004 item 3)
	- ID: 2026100413480003
	- Type: Bug
	- Status: Done
	- Severity: High
	- Opened: 20261004-134800
	- Opened by: Code review 20261004
	- Target OS: Any
	- Steps to reproduce:
		- Define a 2048-symbol base with two-character digits, an 8-symbol tail and the qntm scheme, then encode bytes to it and decode them back.
	- Incorrect behavior: the encode works, and the decode fails with `symbol "..." is not in the base`.
	- Expected behavior: the base is refused when it is defined, or it round trips.
	- Reproduced: 20261004, by the review, with a throwaway test in package `convertbase`. A config `tail:` field or `--to-tail` reaches it.
	- Possible cause: `Finalize` accepts the tail, and the buffered big-base decoder reads one character at a time. The streaming path already demands one-character digits.
	- Origin: `convert.go:1773` and `registry.go` Finalize, from 2757bd5 "Big-base binary interop" on 2026-07-06. Not seen by an earlier round. Confirmed.
	- Related IDs: 2026100413480020
	- Note: also reproduced 20261004 on the command. Five bytes encoded through `--to-symbols` and `--to-tail`, and decoding them failed both piped and as an argument.
	- Actual cause: both binary decoders of a tail base read one character per digit. The streaming one is kept off such a base by its one-character gate, but the buffered one is not, and `Finalize` accepted the tail.
	- Decisions:
		- A tail now needs every digit and every tail symbol to be one character, checked in `Finalize`. That is the rule the streaming path already had, and a tail's whole point is that the base streams.
		- Supporting longer digits was passed over. The tokenizer would have to tell a tail symbol from the start of a longer digit at the end of the input, for a case no built-in base has.
	- Actual fix: `Finalize` refuses such a tail with an error naming the base and the offending digit or tail symbol. The config comments and the wide-symbols design doc say so. README and design.md don't describe tails.
	- Verified: every built-in base and the default config still load. Every built-in tail base round trips. `go vet`, `golangci-lint`, `go test ./...` and the harness Binary/streaming section pass.
	- Swept: every way a tail is set goes through `Finalize`: the built-ins, the config `tail:` field, `--from-tail`/`--to-tail` through `ApplyOptions`, and library callers. The browser and reactor modules take no tail. `decodeBigBaseNative` has no other caller.
	- Branch: bigbase-tail
	- Commit: 44ed0be
	- Test case: `Erm5wwf` TestTailNeedsOneCharDigits, `Erm5wxB` "tail on two-character digits rejected" and `Erm5wxg` "config tail on two-character digits rejected". All three fail before the fix and pass after.
	- Acceptance signoff: Closed on review: refusing at definition matches the streaming rule, and the error names the base and the digit.
	- Closed: 20261004-182334

- A tail layout with no tail symbols, such as from `--to-tail ','`, decodes bytes wrong at exit 0.
	- ID: 2026100416041479
	- Type: Bug
	- Status: Done
	- Severity: High
	- Note: raised from Low once the command was found to reach it. It blocks release, since the result is wrong bytes at exit 0.
	- Opened: 20261004-160414
	- Opened by: found while working 2026100413480003
	- Target OS: Any
	- Steps to reproduce:
		- In Go, build a `Base` with `BinaryScheme` set to a tail scheme and no tail, then decode bytes from it.
	- Incorrect behavior: fails with `symbol "..." is not in the base`, which doesn't say what is wrong.
	- Expected behavior: `Finalize` refuses a tail scheme without a tail, naming the base.
	- Reproduced: 20261004. The command reaches it too. `--to-tail ','` parses to no tail symbols but still sets the qntm layout, and 3, 7 and 10 bytes then decode to the wrong bytes with exit 0. A config `tail:` can't reach it, since the layout is set only when the tail has symbols.
	- Actual cause: binary mode picks the tail codec from `BinaryScheme` alone, and nothing checked that a tail layout had a tail. A tail spec of only commas parses to an empty list with no error, and `ApplyOptions` set the layout anyway.
	- Actual fix: `Finalize` refuses a tail layout with no tail symbols, naming the base and the layout, beside the one-character tail check. The command reports it the same way.
	- Note: a config `tail:` of only commas is still ignored without a word, for the same parsing reason. `--to-symbols ','` is refused, but as "need at least 2 symbols, have 0".
	- Verified: every built-in base still loads, and clearing a tail with an empty `--to-tail` still works on a tail base and a codec base. `go vet`, `golangci-lint`, `go test ./...` and the full harness in quick mode pass.
	- Swept: every way a scheme is set. Built-ins all have a tail with a tail layout. The config sets one only with a nonempty tail. `ApplyOptions` clears the layout with an empty tail and sets it with a parsed one, which is now checked. The browser and reactor modules take no tail.
	- Branch: digit-values
	- Commit: fbf6380
	- Test case: `ErmULmP` TestTailSchemeNeedsTail, for each tail layout and for a comma-only tail through `ApplyOptions`, and `ErmULmv` "comma-only tail rejected" on the command. Both fail before the fix and pass after.
	- Acceptance signoff: Closed on review: an error in place of wrong bytes at exit 0, naming the base and the layout.
	- Related IDs: 2026100417280514
	- Closed: 20261004-182334

- `package.bash` deletes whatever directory `--out` names before it builds. (Code review 20261004 item 4)
	- ID: 2026100413480004
	- Type: Bug
	- Status: Done
	- Needs local test suite run?: No. The cicd run through stage 6 passed on 20261004, with the harness at 572 of 572. Packaging made all 25 artifacts in a fresh, marked `lib/dist`.
	- Severity: High
	- Opened: 20261004-134800
	- Opened by: Code review 20261004
	- Target OS: Linux
	- Steps to reproduce:
		- `make release DIST=<a dir with other files in it>`
	- Incorrect behavior: the directory is emptied, whatever was in it.
	- Expected behavior: only a directory the script made or marked as its own is cleared. Anything else is refused.
	- Reproduced: 20261004, by the review, with a fake `go` and a scratch dir.
	- Origin: `package.bash:115`, from 9c40e8d "release packaging" on 2026-07-12. Not seen by an earlier round. Confirmed.
	- Sweep: every `rm -rf` on a variable path in `cicd/` and `utility/`. `interop/fetch.bash:93` is one; see item 16.
	- Actual cause: the script cleared `--out` with `rm -rf` before building, whatever it held. `make clean` did the same to `DIST`.
	- Actual fix: a build marks the dir it makes with a hidden file. `package.bash` clears a dir only when it has the mark, takes over an empty one, and refuses anything else with a message. `make wasm` and `make reactor` mark the dir when they create it, and `make clean` follows the same rule. The mark stays out of `checksums.txt`, and the release workflow's `lib/dist/*` upload skips it as a dotfile.
	- Swept: every `rm -r` in `cicd/`, `utility/`, `install.bash` and `lib/Makefile`. The trap removes in `package.bash`, `check-vendor.bash`, `interop/fetch.bash`, `test.bash`, `bench-encoders.bash`, `gen-screenshots.bash` and `install.bash` each take a dir the same script made with `mktemp -d`. `interop/fetch.bash:94` is fixed under item 16. `lib/Makefile` clean was the twin of this one and is fixed here. The other `rm` calls remove single files.
	- Verified: 20261004, the three new checks fail on dev and pass on this branch. The packaging section ran with real builds: two full packages still rebuild to the same checksums, and the prerelease name checks pass. `make wasm` into a new dir marks it, and the next packaging run clears it. Shellcheck finds nothing new.
	- Note: `make release` and `make clean` now stop on an old `lib/dist` with no mark, and say so. Trash it once.
	- Branch: bash-traps
	- Commit: 65ce2be
	- Test case: harness checks `Erm3Sws` (an `--out` with other files is left alone), `Erm3SxT` (a marked dir is cleared and an empty one taken), `Erm3Syv` (`make clean`) and `Erm3SyD` (the mark is not in `checksums.txt`). The first three fail on dev. `Erm3SyD` fails when the mark is left in the checksum list.
	- Acceptance signoff: Closed on review: the refusal says what to do, and a marked folder is the usual way a build tool knows its own output.
	- Closed: 20261004-182334

- A failed write of the result still exits 0. (Code review 20261004 item 1)
	- ID: 2026100413480001
	- Type: Bug
	- Status: Done
	- Needs local test suite run?: No. The full `cicd/test.bash` passed 569 of 569 on 20261004, on a tree with this fix merged.
	- Severity: High
	- Opened: 20261004-134800
	- Opened by: Code review 20261004
	- Target OS: Any
	- Steps to reproduce:
		- `convert-base-v2 255 16 >/dev/full`
	- Incorrect behavior: exit 0 with nothing written. Same for `--list`, `--get-index-count`, `--get-base-name` and a piped `-` input.
	- Expected behavior: an error and a non-zero exit, as `-n 255 16`, `--version` and streaming already do.
	- Reproduced: 20261004, with a stripped build.
	- Possible cause: the result prints go through `fmt.Fprint*` with errcheck turned off for them, and nothing checks a flush. The `.golangci.yml` comment says every write that matters is checked; these are not.
	- Probable fix: one buffered writer over stdout in `run()`, with the flush error returned.
	- Origin: `main.go:509` and its siblings, from the first v1.0.0-rc1 commit ad488ce. Not seen by an earlier round. Confirmed.
	- Sweep: every stdout write in `lib/cmd`, `lib/wasm` and `lib/reactor`.
	- Actual cause: the result prints were unchecked, as the possible cause says. Only `-n` output, `--version`/`--help` and the streams checked their writes.
	- Actual fix: one buffered writer over stdout in `run()`. It keeps the first write error, and the deferred flush returns it, so the run exits 1 with the error. The streams still write stdout directly and check their own writes. The errcheck exclusions in `.golangci.yml` add that writer's `WriteString`, and their comment now says where each kind of write is checked.
	- Swept: every stdout write in `lib/cmd/convert-base-v2`, all in `main.go`: the info flags, `--list` and `--list-compat`, `--get-index-count`, `--get-base-name`, `--show-symbols` and `-0`, the newline after a stream, and the result. `lib/wasm` and `lib/reactor` write nothing to stdout, by `grep -n 'os.Stdout\|fmt.Print'`. The library's `Registry.Print` writes to the writer it is given, so its errors come out at the command's flush.
	- Verified: 20261004, the harness sections from CLI surface through control-character escapes pass, 342 of 342, and so do the reactor, browser module and frontend parity sections. Output of 25 sample commands matched the dev build byte for byte, apart from the version stamp. go vet, golangci-lint, staticcheck and `go test ./...` clean.
	- Branch: exit-fixes
	- Commit: 7eb27c9
	- Test case: harness check `Erm02E7`, 13 ways of writing a result to `/dev/full`. On dev 8 of them exit 0. With the fix all 13 fail with the write error.
	- Acceptance signoff: Self-closed: reproduced, its test failed before the fix and passes after, the Sweep is answered, and the full suite passed.
	- Closed: 20261004-165456

- A field written under another field in a config file is ignored without a word.
	- ID: 2026100314430255
	- Type: Bug
	- Status: Done
	- Severity: High
	- Opened: 20261003-144302
	- Opened by: found while working 2026100313304802
	- Target OS: Any
	- Steps to reproduce:
		- A base block with `negative:` and, indented under it, `decimal: X`.
	- Incorrect behavior: it loads. The negative marker is switched off and the decimal line is never read.
	- Expected behavior: refused, like any other unknown or misplaced field, citing the line.
	- Reproduced: 20261003, with both the old and the new shcl.
		- 20261003: again on dev. With `negative: N` and `decimal: D` under it, 1.5 to that base printed `1.5` at exit 0.
	- Possible cause: the field check looks one level down only.
	- Actual cause: the field check looked at the names directly under each base block and nothing below them. No base field takes fields of its own, so anything under one was dropped unread. A dotted name like `negative.decimal: X` builds the same tree and slipped past the same way.
	- Note: blocks release, since the result is a wrong alphabet at exit 0.
	- Progress log:
		- Done: anything under a base field is refused, at any depth. The error names the base, the stray field and the field it sits under, and cites the stray field's line. That makes nine refusal paths that cite a line.
		- Note: no shcl bug was involved. Two same-named fields that both have fields under them merge into one in shcl, so the repeat check misses them, but the new check still catches the fields under them.
		- Note: found along the way, logged as 2026100315002873: a raw block as a field value drops aliases without a word and reports symbols as missing.
	- Actual fix: the field check now also refuses any field under a base field.
	- Sweep: every place config.go walks children, the top level of the file, fields under list-valued fields, and whether `lib/wasm` and `lib/reactor` load configs.
	- Swept: config.go walks children in two places, the top level and each base block. The top level refuses every name but `base`, so nothing under them is ever read. Each base block's fields are now checked for children. Under `aliases:` and stacked `* x` lists, a field is caught by this check or already refused by shcl as a list mixed with fields. `configBase` only reads fixed paths. `lib/wasm` and `lib/reactor` load no config at all; the only `LoadConfig` callers are the command's two paths in `main.go`, both through `Registry.LoadConfig`.
	- Verified: go vet, golangci-lint and `go test ./...` in lib pass. The new unit test and the new harness check fail on dev and pass on this branch. The full `cicd/test.bash` passed 446 of 446 with the fixed build. Shellcheck finds nothing new in `cicd/test.bash`.
	- Branch: nested-field
	- Commit: 5c64d73
	- Test case: `Erg4X7J` TestConfigRejectsNestedField and the "nested" case in `Em2MFrs` TestConfigErrorsCiteLines; `Erg4X7I` "config nested field rejected" in the harness.
	- Acceptance signoff: Self-closed: reproduced, its tests failed before the fix and pass after, and the Sweep is answered.
	- Closed: 20261003-150028

- Every run builds all hundred or so built-in bases, though a conversion uses two. (Code review 20261004 item 17)
	- ID: 2026100413480017
	- Type: Enhancement
	- Status: Done
	- Priority: High
	- Opened: 20261004-134800
	- Opened by: Code review 20261004
	- Target OS: Any
	- Note: `255 16` takes about 68 ms, against 1 ms for `--version`. `NewRegistry` is about 53 ms of that, and `32768qntm` and `65536qntm` alone are about 48 ms.
	- Note: the test harness makes about 5000 calls, so startup is over five minutes of each run. Scripts that call the command in a loop pay the same.
	- Probable fix: keep built-ins as cheap specs and finalize each on first lookup, or on `--list`. Config bases still validate at load. A unit test that builds every built-in keeps catching bad data. Add a `NewRegistry` benchmark with a threshold.
	- Origin: the registry design from ad488ce. The cost was noted in passing on 2026-08-02 and in G12, never filed. Confirmed by timing and pprof.
	- Related IDs: 2026100413480018
	- Done: each built-in keeps its spec and is parsed and checked the first time `Lookup` or `OrderedBases` reaches it. A lookup builds only the base it finds, and a miss builds none. `--list`, `--get-index-count` and `--by-index` build them all. `leftTokens` stops at the tokens it needs instead of splitting a whole alphabet. `NewRegistry` went from about 38 ms and 29 MB to 0.17 ms and 0.24 MB.
	- Decisions:
		- Config bases are still checked when the file loads, through `Register`, as before. No error compared config bases against built-ins before: a config name or alias that matches a built-in takes it over by design. So there was nothing to keep there, and the config errors and their line citations are unchanged.
		- Library meaning: `NewRegistry` no longer checks the built-ins, so its error is always nil. It stays in the signature. A built-in that fails to build comes back as an error from `Lookup`, and `OrderedBases`, which has no error return, panics, like `mkSpec` already does on bad data. Only a broken `bases.go` can reach either, and `TestEveryBuiltinBuilds` fails on that. The library is already at v0.2.0 for the next release, so no new bump.
		- Concurrency: one `sync.Once` per built-in. `Lookup` and `OrderedBases` are safe from several goroutines. `Register` and `LoadConfig` are not, as before. Both are documented on `Registry` and in the package doc.
	- Verified: release build, 40 runs each, dev against this branch. `255 16` went from 58 ms to 1.5 ms, `--version` stayed at 1.0 ms, and `--list` went from 59 ms to 41 ms.
	- Verified: `--list`, `--list-compat`, both together, `--get-index-count`, `--get-base-name` and `--show-symbols` and `--show-symbols-0` for every index, `--get-base-name` and a conversion for every listed name, and an unknown-name suggestion are byte-identical to dev. So are five config cases: a stolen alias, a shadowed built-in, and three load errors with their line citations. The name, size, raw flag, markers, digits and tail of every base `.bases()` lists match dev too.
	- Verified: go vet, golangci-lint, `go test ./...`, the four new tests under `-race`, and the full `test.bash` with the performance section and packaging rebuilds, 569 of 569.
	- Test case: `ErmQ6z6` TestEveryBuiltinBuilds fails on a duplicate digit put into base 2. `ErmQ6zb` TestLookupBuildsOnlyItsBase and `ErmQ70b` TestNewRegistryCost (at most 2 MiB and 10 ms) fail when `NewRegistry` builds every base. `ErmQ706` TestConcurrentLookup reports a data race under `-race` without the once. `BenchmarkNewRegistry` gives the number.
	- Branch: lazy-bases
	- Commit: f46614b
	- Acceptance signoff: Closed on review: lookups give the same output as before, and a broken built-in can only come from `bases.go`, which a test catches.
	- Closed: 20261004-182334

- One failing check can abort the test harness or lose its failure detail. (Code review 20261004 item 8)
	- ID: 2026100413480008
	- Type: Bug
	- Status: Done
	- Severity: Avg
	- Opened: 20261004-134800
	- Opened by: Code review 20261004
	- Target OS: Linux
	- Incorrect behavior:
		- A conversion that fails inside `x="$(...)"` kills the harness with HARNESS ABORTED, no summary, and the rest unrun.
		- `fFirstDiff` runs `cmp`, which exits 1 on any difference, so a failed interop check prints false abort lines and loses its detail.
		- With Go off the PATH, the reactor section aborts instead of skipping with its warning.
	- Expected behavior: a failure is counted and reported, and the run goes on.
	- Reproduced: 20261004, by the review, with scratch copies of each pattern.
	- Origin: several commits from 4ff92e8 on 2026-07-10 to 36d7ccc on 2026-08-02. Not seen by an earlier round. Confirmed.
	- Sweep: every command substitution in `cicd/test.bash` that runs the program, `cmp`, `diff`, `grep` or `go`. The review listed lines 155, 176, 364, 392, 415, 679, 702, 727, 749-823, 969-971, 1190, 1256, 1296, 1316, 1360, 1389 and 1395.
	- Reproduced: 20261004, against a program that refuses everything. The run ended at the first capture in the CLI surface section.
	- Actual cause: the harness runs under errexit, with an ERR trap that also fires inside `$( )` and `<( )`. A plain capture of a refused conversion ended the run. Inside a substitution the trap cut the output short wherever a non-zero status is the normal answer, as with `cmp` in `fFirstDiff`.
	- Actual fix: the trap no longer ends a subshell, so the status goes to whatever reads it. A single run of the program is captured through `_run` or `_run_in`, which keep the status. A pipeline capture ends in `|| true`, and so do the `go env` lookups and the perf section's bare runs. The two fuzz loops skip an empty base list, since a modulo by its size ended the run.
	- Note: a helper run through `$( )` no longer stops at its first failed command. Each one feeds a check that fails on a wrong result.
	- Note: the self-check adds about 9 seconds to a run.
	- Verified: a full harness run passed 569 of 569. The run against a program that refuses everything, with Go off the PATH, reached its summary with no abort. shellcheck shows no new warnings, and `test-ids.py check` passes.
	- Swept: every capture in `cicd/test.bash` that runs the program, `cmp`, `diff`, `grep` or `go`. That is the CLI surface lists and counts, the `85ps` and config symbol reads, `cvec`, `nvec`, `pipecheck`, the pad, tail and `--binary` captures, the fuzz base count and names, and the reactor and browser `go env` lookups. The trap change covers `fFirstDiff`, the parity `diff` messages, the interop verify message and every `<( )` base listing. The perf section's bare runs were guarded too. A grep for assignments from `$( )` that name those tools and have no `||` or `&&` after leaves only `fFirstDiff` and helpers that make dirs or random input.
	- Branch: harness-abort
	- Commit: 2590437
	- Test case: `ErmGPkH` "every check failing still reaches the summary", `ErmGPkf` "reactor section skips with Go off the PATH" and `ErmGPl4` "failed interop check keeps its detail". They run the harness against a program that refuses everything. All three fail before the fix and pass after. Putting back the old trap, the reactor lookup or one capture alone turns at least two of them red.
	- Acceptance signoff: Self-closed: reproduced, its tests failed before the fix and pass after, and the Sweep is answered.
	- Closed: 20261004-165412

- Any failed fuzz run aborts the whole pipeline, including the deadline case meant to pass. (Code review 20261004 item 5)
	- ID: 2026100413480005
	- Type: Bug
	- Status: Done
	- Severity: Avg
	- Opened: 20261004-134800
	- Opened by: Code review 20261004
	- Target OS: Linux
	- Steps to reproduce:
		- A fuzz target that exits non-zero, such as Go's bare `context deadline exceeded`.
	- Incorrect behavior: the ERR trap fires at the `go test | tee` line and cicd prints CICD ABORTED. The check that tells a deadline from a real find never runs, and the temp log stays in `/tmp`.
	- Expected behavior: the deadline case passes with a note, as G18 says, and a real find fails the stage with its own message.
	- Reproduced: 20261004, with the same trap and pipeline in a scratch script. `set +e` does not stop the ERR trap.
	- Origin: `cicd.bash:303-306`, from 6e3fd63 "Fuzz stage fixes" on 2026-08-01, on top of the trap from a8d50ce. Not seen by an earlier round. Confirmed.
	- Actual cause: the ERR trap fires on a failed pipeline whatever `set +e` says, so the stage aborted before it read the log.
	- Actual fix: the fuzz run is guarded with `||`, so its status reaches the check. The deadline case passes with its note, a real find fails the stage with its own message, and the temp log is removed either way.
	- Swept: no other `set +e` or `PIPESTATUS` in `cicd/`, `utility/` or `install.bash`, outside `legacy/`. The other pipelines in `cicd.bash` already end in `|| fDie`.
	- Verified: 20261004, on dev both cases abort with CICD ABORTED and leave the temp log behind.
	- Branch: cicd-fixes
	- Commit: ffeed2e
	- Test case: `ErmCp2E` "fuzz deadline passes with a note, and its log is removed" and `ErmCp2F` "fuzz find fails the stage with its own message". Both fail before the fix and pass after.
	- Acceptance signoff: Self-closed: reproduced, its tests failed before the fix and pass after.
	- Closed: 20261004-161813

- The constant-memory check never runs in a normal pipeline. (Code review 20261004 item 7)
	- ID: 2026100413480007
	- Type: Bug
	- Status: Done
	- Severity: Avg
	- Opened: 20261004-134800
	- Opened by: Code review 20261004
	- Target OS: Linux
	- Incorrect behavior: the harness's perf section, with the streaming memory guard, runs only with `--long`. Its header still says the engine turns it on unless `--quick`.
	- Expected behavior: it runs on every non-quick pipeline.
	- Reproduced: 20261004. Nothing sets `CICDTEST_DO_PERF` any more.
	- Possible cause: a8d50ce on 2026-07-09 dropped `CICDTEST_DO_PERF` from the harness call in `cicd.bash`.
	- Origin: regression of 8df148a "Run perf stage unless quick" on 2026-07-06. Not seen by an earlier round. Confirmed.
	- Actual cause: as the possible cause says. The harness call lost `CICDTEST_DO_PERF` when the engine was rewritten.
	- Actual fix: the engine sets `CICDTEST_DO_PERF=1` on the harness call unless `--quick`. A long run still turns it on by itself.
	- Swept: the harness reads `CICDTEST_EXE`, `CICDTEST_DO_LONGTEST`, `CICDTEST_DO_PERF`, `CICDTEST_QUICK` and `CICDTEST_FUZZ_ITERS`. The engine sets all but the last, which is a manual override.
	- Verified: 20261004, the perf section alone against the current build passes 36 of 36, the constant-memory check on every power-of-2 base included. It adds about 35 s to a normal run.
	- Branch: cicd-fixes
	- Commit: ffeed2e
	- Test case: `ErmCp2G` "harness perf section asked for", for a full and a `--quick` run. It fails before the fix and passes after.
	- Acceptance signoff: Self-closed: restores 8df148a, and its test failed before the fix and passes after.
	- Closed: 20261004-161813

- `bench-encoders.bash` and `gen-screenshots.bash` use base names and flags that were removed. (Code review 20261004 item 10)
	- ID: 2026100413480010
	- Type: Bug
	- Status: Done
	- Severity: Avg
	- Opened: 20261004-134800
	- Opened by: Code review 20261004
	- Target OS: Linux
	- Incorrect behavior: `bench-encoders.bash` times error exits from `--from binary` and `--raw`, and reports 2,211 MiB/s decode for them. The README says its throughput table can be reproduced with this script. `gen-screenshots.bash` uses `20w` and `binary` and would die at screenshot 4.
	- Expected behavior: both use `bytes` and `20ws`, and the benchmark fails on a non-zero exit.
	- Reproduced: 20261004, by the review, for bench-encoders. gen-screenshots was checked by base lookup only, since it writes into `assets/`.
	- Origin: bench-encoders from d47b533 on 2026-07-06, gen-screenshots from 0c6709c on 2026-07-25; both went stale with later renames. Not seen by an earlier round. Confirmed.
	- Actual cause: both scripts predate the 20260708 renames to `bytes` and `--no-newline`, and `20w` was dropped later. The benchmark threw away each command's errors, so an error exit was timed as a result.
	- Actual fix: both use `bytes` and `20ws`. The benchmark stops on a failed command and prints it with its error. The screenshot script stops before drawing a picture once any of its commands has failed, instead of drawing an empty line.
	- Note: the README throughput table is from 20260706, before the rename, so its numbers came from working commands.
	- Swept: no other `--from binary`, `--to binary`, `--raw` or `20w` in the scripts, README or demo scenario. A comment in `registry.go` said `--to binary` and now says `bytes`. Two dated design docs keep the old names as history.
	- Verified: 20261004, the screenshot script ran every scene against the current build without drawing anything or touching `assets/`. The benchmark ran at 1 MiB against the current build.
	- Branch: cicd-fixes
	- Commit: db57771
	- Test case: `ErmCp2M` "bench-encoders stops on a failed conversion", `ErmCp2N` "bench-encoders runs every convert-base-v2 row", `ErmCp2O` "gen-screenshots: every command in every scene works" and `ErmCp2P` "gen-screenshots draws nothing after a failed command". `ErmCp2M`, `ErmCp2O` and `ErmCp2P` fail on dev. `ErmCp2N` passes on dev, which hid the errors, and fails with one old name put back.
	- Acceptance signoff: Self-closed: the names are mechanical, and the tests failed before the fix and pass after.
	- Closed: 20261004-161813

- `check-release.bash` and `install.bash` exit without their own error messages. (Code review 20261004 item 9)
	- ID: 2026100413480009
	- Type: Bug
	- Status: Done
	- Severity: Avg
	- Opened: 20261004-134800
	- Opened by: Code review 20261004
	- Target OS: Linux, macOS
	- Incorrect behavior: a README with no Lifecycle badge, a checksums file without the asset, or no release tag ends the script at exit 1 with nothing printed.
	- Expected behavior: "no Lifecycle badge found", "No checksum for ..." and "could not determine the release tag" print as written.
	- Reproduced: 20261004, by the review, against scratch inputs.
	- Possible cause: a `grep` that finds nothing inside `x="$(...)"` under `set -e`.
	- Origin: `check-release.bash:61-62` from 9c40e8d on 2026-07-12, `install.bash:119-120,167-168` from 33cdd30 on 2026-08-04. Not seen by an earlier round. Confirmed.
	- Actual cause: as the possible cause says. In `check-release.bash` a missing `main.go`, or a dir that is not a repo, also ended with no message of its own, at the `sed` and at `git tag`.
	- Actual fix: `|| true` inside each lookup's substitution, so its own message prints. `check-release.bash` reads the badge with `grep -m1` and no pipe, and says so when the tags can't be listed.
	- Swept: every `x="$(...)"` in both scripts. In `install.bash` the rest are guarded already, and the hash line reads a file the script just wrote. In `check-release.bash`, all four lookups.
	- Verified: 20261004, both checks fail on dev in all five cases, at exit 1, 2 or 128 with no message of the script's own, and pass on this branch. The badge reads the same from the real README. Shellcheck clean.
	- Branch: bash-traps
	- Commit: 65ce2be
	- Test case: harness checks `Erm3Szg` (`check-release.bash` with no `main.go`, outside a repo, and with no badge) and `Erm3T0M` (`install.bash` with a stand-in curl: no tag, and no checksum line).
	- Acceptance signoff: Self-closed: reproduced, its tests failed before the fix and pass after.
	- Closed: 20261004-154100

- `.` and `-.` convert to `0` at exit 0. (Code review 20261004 item 6)
	- ID: 2026100413480006
	- Type: Bug
	- Status: Done
	- Severity: Avg
	- Opened: 20261004-134800
	- Opened by: Code review 20261004
	- Target OS: Any
	- Steps to reproduce:
		- `convert-base-v2 --from 10 --to 16 -- .`
	- Incorrect behavior: prints `0`, exit 0.
	- Expected behavior: `no digits in input`, as for an empty value.
	- Reproduced: 20261004.
	- Possible cause: the empty integer part is set to the zero digit before the no-digits check runs, so the check never sees an empty value.
	- Origin: `convert.go:372-379`, from the first v1.0.0-rc1 commit ad488ce. Not seen by an earlier round. Confirmed.
	- Sweep: the same check in `lib/wasm` and `lib/reactor`, which call the same `Convert`.
	- Actual cause: the empty integer part became the zero digit before the no-digits check, and that check only caught a fully empty value.
	- Actual fix: the check runs first and fails when both sides of the decimal marker are empty. `.5` and `5.` still read as numbers.
	- Swept: `lib/wasm` and `lib/reactor` have no check of their own. Both call the same `Convert`. The frontend parity section now sends `.` and `-.` through the command, the module and the reactor.
	- Verified: 20261004, `.` and `-.` give `no digits in input` at exit 1. Parity passes over 209 cases on both the module and the reactor.
	- Branch: exit-fixes
	- Commit: 74cf4ea
	- Test case: `Erlz3L2` TestMarkersWithoutDigits and harness check `ErlzAd6`. Both fail on dev and pass with the fix.
	- Acceptance signoff: Self-closed: reproduced, its tests fail before the fix and pass after, and the sweep is answered.
	- Closed: 20261004-152620

- `checksums.txt` names a prerelease `.deb` or `.rpm` with a `~`, but GitHub serves the file with a `.` there.
	- ID: 2026100412472515
	- Type: Bug
	- Status: Done
	- Needs local test suite run?: No. The full `cicd/test.bash` passed 489 of 489 on dev after the merge, and CI passed.
	- Severity: Avg
	- Opened: 20261004-124725
	- Opened by: found while working 2026100409572736
	- Target OS: Linux
	- Steps to reproduce:
		- `make release` on a prerelease version such as v3.1.0-beta1, upload, then `sha256sum -c checksums.txt` beside the downloaded packages.
	- Incorrect behavior: nfpm names the packages `3.1.0~beta1`, `checksums.txt` lists that name, and GitHub serves `3.1.0.beta1`, so the check can't find the files.
	- Expected behavior: the names in `checksums.txt` match the names served.
	- Reproduced: not yet. Read only; no prerelease has shipped packages so far. The next release is a beta.
		- 20261004: packaging v9.9.9-beta1 put four `~` names in `checksums.txt`. With the files under the names GitHub would serve, `sha256sum -c` could not find those four.
	- Possible cause: packaging hashes before GitHub's rename. Rename before hashing.
	- Actual cause: nfpm names the file after the package version, which has a `~` for a prerelease, and nothing changed that name before the checksums were taken.
	- Actual fix: packaging renames any file GitHub would rename to the name GitHub serves, before it writes `checksums.txt`. Two files that would end up with one name stop the run. The version inside the package keeps the `~`.
	- Sweep: everything that builds or reads an asset name.
	- Swept: `release-notes.bash` already links the served name, and now finds the renamed packages with no warning. `install.bash` fetches only the bare binary and `checksums.txt`, and neither name has a `~`. The release workflow uploads `lib/dist/*` as written. `cicd.bash` counts the files by extension. The installer shows the version but its file name has none.
	- Verified: a v9.9.9-beta1 package run names all four packages with a `.`, and `sha256sum -c checksums.txt` passes beside them. `dpkg-deb` and `rpm` read `9.9.9~beta1` from inside them, and dpkg sorts that below 9.9.9. `ErlP6Bg` fails with dev's packaging and passes with the fix. `ErlP6CE` passes on both, and fails when the package version is given a `.` in place of the `~`. Nothing was tagged or published.
	- Branch: pkg-repro
	- Commit: cdd002f
	- Test case: `ErlP6Bg` "prerelease packages named as GitHub serves them" and `ErlP6CE` "prerelease package version keeps its ~" in the harness.
	- Note: check again at the next beta. Download its `.deb` and `.rpm` files beside `checksums.txt` and run `sha256sum -c checksums.txt`.
	- Acceptance signoff: Self-closed: reproduced, its test failed before the fix and passes after, and the full suite passed.
	- Closed: 20261004-131952

- The lint stage checks Go only. Shellcheck and ruff don't run, and nothing configures them. (Code review 20261004 item 22)
	- ID: 2026100413480022
	- Type: Enhancement
	- Status: Done
	- Needs local test suite run?: none. A `cicd/cicd.bash --quick` run on dev passed on 20261004: stage 3 clean with shellcheck on 14 files and ruff on 5, harness 555 of 555.
	- Priority: Avg
	- Opened: 20261004-134800
	- Opened by: Code review 20261004
	- Target OS: Linux
	- Note: shellcheck finds 106 SC2015 notes in `test.bash`, all the harmless `&& _pass || _fail` form, plus a few false positives. Default ruff finds 150, none a real bug, nine of them in the pipeline tools.
	- Probable fix: clear the notes, add `shellcheck -x` and ruff to the lint stage, and add a `pyproject.toml` with tab indent so existing files stay as they are.
	- Origin: the lint stage from a8d50ce on 2026-07-09. Directive gap, filed against the 2026-10-04 directives.
	- Prereq IDs: 2026100413480032
	- Note: item 32 answered. ruff's naming rules stay on, with `flame-report.py` excluded since it came from silkterm.
	- Progress log:
		- Done: stage 3 runs shellcheck on every tracked Bash file, found by `.bash` name or by a shell shebang on an executable, and ruff on the Python tools. Both are probe-gated like golangci-lint. A finding stops the run, and so does an empty file list.
		- Done: `.shellcheckrc` lets shellcheck follow sourced files beside a script. `pyproject.toml` adds ruff's naming rules and sets tab indent for its formatter.
		- Done: `lint-report.bash` now shows shellcheck and ruff findings from a run log. `tool-versions.env` records both versions, and `pin-tools.bash` warns when one differs, since neither is installed by the pipeline.
		- Done: the nine ruff findings in the pipeline tools are fixed. `pprof2flame.py` now uses its `wpx`, and its SVG output is unchanged.
		- Note: hosted CI is unchanged. Its runner has an older shellcheck and no ruff.
	- Decisions:
		- The SC2015 notes in `test.bash`, 134 by now, are cleared with one file-level disable rather than rewritten. All of them are `&& _pass || _fail`, and `_pass` fails only when printing fails, which `_fail` then counts. An if/else on each would add several hundred lines and change nothing.
		- Left out of shellcheck: `legacy/`, the v1 and v1b scripts, the shared `n8git_backup-and-publish` and `gfs-rotate.bash`, and the Unicode research scripts. Left out of ruff: the Unicode research scripts.
		- Naming rules are off for `flame-report.py` for good, and for `pprof2flame.py`, `gen-demo-gif.py` and `gen-bases-table.py` until their snake_case rename.
	- Verified: shellcheck is clean on the 14 files the stage finds, and ruff on 5. The stage fails on a shellcheck finding in `install.bash` and on a ruff finding in `gen-bases-table.py`, and passes again without them. The new harness checks fail on the old engine, `lint-report.bash` and `pin-tools.bash`, and pass on the new ones.
	- Swept: every tracked shell file through shellcheck and every Python file through ruff, the excluded ones included.
	- Branch: lint-sh-py
	- Commit: 294764b
	- Test case: ErmroeI, Ermroeo, ErmrofR, Ermroh4, Ermrofy, ErmrogW (CI engine section), Ermt58H (pin-tools).
	- Closed: 20261004

- The demo gif generator holds every frame uncompressed in memory. (Code review 20261004 item 21)
	- ID: 2026100413480021
	- Type: Enhancement
	- Status: Done
	- Needs local test suite run?: No. The full harness passed 572 of 572 on 20261004, with both new checks in it.
	- Priority: Avg
	- Opened: 20261004-134800
	- Opened by: Code review 20261004
	- Target OS: Linux
	- Note: 3166 frames at 960x540 come to about 1.6 GB before the save, on a box where `/tmp` has failed under memory pressure. Each added frame also copies itself and the previous frame to compare them.
	- Probable fix: keep the last frame's bytes, and store frames compressed until the save.
	- Origin: `gen-demo-gif.py:599-610`, from f4339b4 on 2026-07-11. Not seen by an earlier round. Confirmed by arithmetic on the committed gif.
	- Note: the real peak was twice the estimate, since Pillow's save copied every frame again.
	- Fixed: frames are encoded 32 at a time as they come in. Each batch is saved behind the last frame of the batch before, then that frame and the header are cut off, so the bytes match one save. Only the last frame's bytes are kept for the duplicate check.
	- Verified: the full demo from dev's script and from this one, same scenario and binary, is byte-identical with and without the gifsicle pass, and matches the committed gif. Peak RSS went from 3308324 KB to 185140 KB, about 3.2 GB to 181 MB. Render time is about the same.
	- Test case: `ErmYENq` "demo gif batches match one Pillow save" and `ErmYEP0` "demo gif frames are not all held until the save", in `cicd/test.bash`. They feed made-up frames and take under a second, where a real render takes over a minute. They fail with the cut point off by one byte, and with every frame held until the save (402 MiB against a 99 MiB bound).
	- Branch: gif-memory
	- Commit: ba15b41
	- Acceptance signoff: Self-closed: the output is byte-identical, peak memory is measured before and after, and its checks pass in the full suite.
	- Closed: 20261004-174452

- The number path looks up each digit twice. (Code review 20261004 item 19)
	- ID: 2026100413480019
	- Type: Enhancement
	- Status: Done
	- Priority: Avg
	- Opened: 20261004-134800
	- Opened by: Code review 20261004
	- Target OS: Any
	- Note: `Tokenize` knows each digit's value, turns it back into a string, and `parseLeaf` hashes it again. Passing values instead was 30 to 37 percent faster from 1K to 64K digits, and the suite passed.
	- Note: this leaves the divide and conquer design alone.
	- Origin: `convert.go:148` from a6c8612 on 2026-08-02, and `Tokenize`. Not seen by an earlier round. Confirmed by benchmark.
	- Done: the number path takes digit values straight from the tokenizer, and the divide and conquer parse packs them as they are. The two binary paths that read through `Tokenize` and looked each digit up again do the same. `Tokenize` keeps its signature and errors, and is now built on the same value scan.
	- Decisions:
		- The divide and conquer split, leaf size and format leg are unchanged.
	- Verified: `BenchmarkPositional`, base 10 to 36, went from 40 to 24 us at 1K digits, 184 to 121 us at 4K, 0.98 to 0.73 ms at 16K and 6.8 to 5.4 ms at 64K. `go vet`, `golangci-lint` and `go test ./...` pass, the browser and reactor modules build, and the full harness passes in quick mode, conversions, interop and frontend parity included.
	- Swept: every `Tokenize` caller. The number path and the two binary decoders now use values. `SymbolSlice`, `Fit` and the reactor's symbol count want symbols, so they keep `Tokenize`. No other site looks a digit up by its symbol after tokenizing.
	- Branch: digit-values
	- Commit: 6b7629b
	- Test case: `ErmUk2J` TestNumberPathUsesTokenValues converts with the symbol map removed, so a second lookup reads every digit as zero. `ErmULlt` TestPositionalNearMathBig limits 1K digits to 1.5 times math/big's own conversion. It measured 1.9 before and 1.2 after. Both fail before the change and pass after. `BenchmarkPositional1K` to `64K` give the numbers, and `ElmJ1ea` TestDivideConquerBoundaries, `Elm99Wy` TestDigitChunkBoundaries and `Elm99Wz` TestFractionChunkBoundaries cover correctness.
	- Acceptance signoff: Self-closed: the change does what the item asked, and its tests pass.
	- Closed: 20261004-172702

- `ParseSymbolSpec` splits every token on commas before checking for one, and rebuilds a replacer per token. (Code review 20261004 item 18)
	- ID: 2026100413480018
	- Type: Enhancement
	- Status: Done
	- Priority: Avg
	- Opened: 20261004-134800
	- Opened by: Code review 20261004
	- Target OS: Any
	- Note: the built-in alphabets run to 65536 tokens, so this runs on every start. Checking for a comma first and building the replacer once took `NewRegistry` from 64 ms to 46 ms and from 224k allocations to 4.5k.
	- Origin: `symbolspec.go:79` and `:150-154`. Not seen by an earlier round. Confirmed by benchmark.
	- Related IDs: 2026100413480017
	- Done: a token is split on commas only when it has one, and the placeholder replacer is built once. The token list is reused and the output sized up front. The bare `,` token is still the comma digit, so `85ps` keeps all 85.
	- Verified: `NewRegistry` went from 54 ms and 224k allocations to 38 ms and 3.8k, before 2026100413480017. The `85ps` ascii85 vectors pass, and so do go vet, golangci-lint and `go test ./...`.
	- Test case: `ErmOs7S` TestSpecParserAllocs. A 4096-digit spec took 8270 allocations before and passes at most 40 after. It also pins the comma digit, the escapes and a comma group.
	- Branch: lazy-bases
	- Commit: 83947e6
	- Acceptance signoff: Self-closed: did what the item asked, and its test failed before and passes after.
	- Closed: 20261004-171604

- The buffered big-base decoder allocates for every character. (Code review 20261004 item 20)
	- ID: 2026100413480020
	- Type: Enhancement
	- Status: Done
	- Priority: Avg
	- Opened: 20261004-134800
	- Opened by: Code review 20261004
	- Target OS: Any
	- Note: it makes a string per character and looks that up, though the streaming decoder's per-character table is there. Using it took a 1 MiB `65536qntm` decode from 37 ms and 524k allocations to 15 ms and 3. This path serves typed input, the browser page and the reactor.
	- Origin: `convert.go:1773`, from 2757bd5 on 2026-07-06. Not seen by an earlier round. Confirmed by benchmark.
	- Prereq IDs: 2026100413480003
	- Done: the decoder walks the input by rune and looks each one up in the rune table, which 2026100413480003 now guarantees for every tail base. The output buffer is sized up front.
	- Verified: a 1 MiB `65536qntm` decode went from 33 to 37 ms and 524k allocations to 19 to 22 ms and 2. `2048qntm` went from 46 ms and 763k allocations to 25 ms and 2. `go vet`, `golangci-lint`, `go test ./...` and the harness Binary/streaming, fuzz round-trip, interop, reactor, browser and parity sections pass.
	- Swept: `streamDecodeWide` already used the rune table. `decodeBigBaseNative` is the only other per-character lookup for a tail base.
	- Branch: bigbase-tail
	- Commit: 7a8f56f
	- Test case: `Erm5wyD` TestBigBaseDecodeAllocs, which allows at most 8 allocations to decode 64 KiB through five tail bases. It counted 32k to 58k before and 2 after. `BenchmarkDecode65536` and `BenchmarkDecode2048` give the timings.
	- Acceptance signoff: Self-closed: the change does what the item asked and its test passes.
	- Closed: 20261004-160327

- `--version` also shows the build number: Linux epoch seconds, in lower-case Crockford base 32.
	- ID: 2026100408500169
	- Type: Enhancement
	- Status: Done
	- Needs local test suite run?: No. The full `cicd/test.bash` passed 489 of 489 on dev after the merge, and CI passed.
	- Priority: Avg
	- Opened: 20261004-085001
	- Opened by: JC
	- Target OS: Any
	- Note: release builds are rebuilt to their published checksums, so the seconds should come from the commit date, not the clock.
	- Note: `--version` alone prints one bare line today, and scripts may read it.
	- Progress log:
		- Done: `--version` prints `v3.0.0 build dbrk8` when the build was stamped, and the version alone when not. `--about` and the help open with the same line.
		- Done: `make local`, `make debug`, `make wasm` and `make release` stamp the commit's time. `package.bash` takes `--build-epoch`, and defaults to HEAD's commit time, so the release workflow's build is stamped with no change there.
		- Fixed: `install.bash` compared the whole `--version` line to the release tag, so with a build number on it every run would have reinstalled. It compares the version part now.
		- Note: `lib/wasm` and `lib/reactor` are unchanged. They report `convertbase.Version`, the library's own number, which names a package surface rather than a build.
		- Note: the parity and interop harnesses compare conversion answers only, never the version line, so they are unaffected.
	- Decisions:
		- Match sister projects gitsby and shcl, not the epoch seconds in the title: minutes from 2000-01-01 00:00 UTC to the commit's time, in lower-case Crockford base32, five characters until 2063.
		- Taken from the commit date, never the clock, so release builds still rebuild to their published checksums.
		- Same line, like the sisters: `v3.0.0 build dbrk8`. A build with no stamp, such as `go install`, prints the version alone, as before.
		- It stays a `var` patched by `-X`, beside `version`.
		- `--version` alone stays one line, per 2026100313304797. `--about` still covers it.
	- Swept: every `-X main.version` in the tree (Makefile, `package.bash`), every reader of `--version` (`install.bash`, `cicd.bash` log lines, the harness), the three hosted workflows (`release.yml` builds through `package.bash`, `ci.yml` builds unstamped, `pages.yml` builds only the browser module), and the docs that describe the version output.
	- Verified: go vet, golangci-lint and `go test ./...` in lib pass. The four new Go tests and the two new harness checks fail with the version on two lines, `buildEpoch` as a const, or the Makefile without the stamp, and pass with the change. A plain `go build` prints `v3.0.0` alone. `make release` twice a minute apart gives the same checksums for every bare binary. `test-ids.py check` passes. Shellcheck finds nothing new beyond the harness's usual `A && B || C` notes.
	- Branch: build-num
	- Commit: d8ac98d
	- Test case: `ErlL5bp` TestCrockfordBase32, `ErlL5cK` TestBuildNumber, `ErlL5cs` TestVersionText and `ErlL5dO` TestBuildEpochIsPatchable; `ErlL5dx` "--version is one line, version then build number" and `ErlL5eT` "make stamps every command build with the commit's time" in the harness.
	- Acceptance signoff: Self-closed: the format and placement were the ones asked for, its tests pass, and the full suite passed.
	- Closed: 20261004-131952

- Release notes group the downloads in a table, with CPU architecture in columns and target OS in rows.
	- ID: 2026100409572736
	- Type: Feature
	- Status: Done
	- Needs local test suite run?: No. The full `cicd/test.bash` passed 489 of 489 on dev after the merge, and CI passed.
	- Priority: Avg
	- Opened: 20261004-095727
	- Opened by: JC
	- Target OS: Any
	- Note: the notes are written in `.github/workflows/release.yml`, in its "release notes" step.
	- Progress log:
		- Done: the notes come from the new `cicd/utility/release-notes.bash`: the changelog section, then a downloads table, then a checksums link, then the version line the linux-x86_64 build prints, build number included. It publishes nothing, so it runs by hand against `make release`.
		- Done: the table is made from the files packaging wrote. A row or column with nothing in it is left out, so a `--no-arm` build has no arm64 column. A file it can't place is still linked under the table, with a warning.
		- Done: links use the name GitHub serves an asset under, so a prerelease `.deb` named with `~` links to its `.` name.
		- Done: packaging now also ships the WASI build of the command, `convert-base-v2.wasm`, so WebAssembly has something in its row.
		- Done: the workflow packages and writes the notes before it tags, so a failed build leaves no tag behind.
		- Fixed: the old notes step matched the changelog heading by prefix, so a v3.1.0 release would have taken a v3.1.0-beta1 section. It matches the whole version now.
		- Note: found along the way, logged as 2026100412472515: `checksums.txt` names prerelease packages with `~`, which GitHub renames on upload.
		- Note: found along the way, logged as 2026100412472615: the archives and packages don't rebuild to the same bytes. The binaries do.
	- Decisions:
		- Columns are x86_64, arm64 and Universal. Rows are Linux, macOS, Windows, FreeBSD and WebAssembly (WASI). Best guess, reversible.
		- macOS gets the universal build in the Universal column, beside its per-arch builds.
		- WebAssembly gets a row, with the WASI command in the Universal column, since one file runs on every CPU. The reactor module is not shipped. Best guess, reversible.
		- The notes end with the build's version line, as gitsby's do.
	- Verified: the table was made from a real `make release` output of 25 files and reads right. The three new harness checks fail with the old heading match, without the GitHub name rule, with `.wasm` unplaced, or without the warning, and pass with the change. `make release` twice a minute apart gives the same checksums for every bare binary and the `.wasm`. Shellcheck finds nothing in the new script, and nothing new elsewhere beyond the harness's usual `A && B || C` notes. `test-ids.py check` passes. Nothing was tagged or published.
	- Branch: build-num
	- Commit: 947757f
	- Test case: `ErlN8Nk` "release notes: changelog, downloads table, build line", `ErlN8OJ` "release notes warn of a file they can't place" and `ErlN8Oq` "release notes: only filled columns, no build line for another version" in the harness. The workflow itself only runs on a merge to main.
	- Question: releases now ship `convert-base-v2.wasm`, the WASI build of the command, so the WebAssembly row has something in it. Keep it? Dropping it is one block in `package.bash`, and the row then goes away by itself.
		- Answered: keep shipping it. zuid embeds the reactor module, which its own cicd builds from the pinned `convertbase` source, so nothing downloads this asset yet.
	- Note: check again at the next release. The table renders, every link downloads, and the notes end with the build line.
	- Acceptance signoff: Signed off 20261004.
	- Closed: 20261004-132358

- A symbol spec of only commas parses to no symbols without an error.
	- ID: 2026100417280514
	- Type: Bug
	- Status: Done
	- Severity: Low
	- Opened: 20261004-172805
	- Opened by: found while working 2026100416041479
	- Target OS: Any
	- Steps to reproduce:
		- A config base with `tail: ,` or `tail: , ,`.
	- Incorrect behavior: the base loads with no tail and no word about it. `--to-symbols ','` is refused, but as "need at least 2 symbols, have 0".
	- Expected behavior: "no digit symbols" or similar, naming the field.
	- Reproduced: 20261004. `--to-symbols ','`, `--to-tail ','` and a config `tail: ","` in quotes all parse to no symbols with no error. A bare `tail: ,` never reaches the parser; see Decisions.
	- Probable fix: `ParseSymbolSpec` returns an error when a non-empty spec yields no symbols. Check what an intentionally empty field means first, since an empty `--to-tail` clears a tail on purpose.
	- Related IDs: 2026100416041479
	- Actual cause: in a one-token spec a comma is a separator, so a spec of only commas left nothing, and `ParseSymbolSpec` returned the empty list as fine.
	- Actual fix: `ParseSymbolSpec` refuses it as having only commas. The command names the flag, such as `--to-symbols:` or `--to-tail:`, and a config error names the line, the base and the field.
	- Decisions:
		- An empty value still means none on purpose, and never reaches the parser. An empty `--to-tail` clears a tail, an empty `--to-symbols` falls back to the base name, and an empty config `tail:` sets no tail.
		- SHCL reads a bare `tail: ,` or `tail: , ,` as an empty list, the same as `tail:`. So it stays meaning no tail. Only a quoted `","` reaches the parser.
		- A lone `,` among other tokens is still the comma digit, as `85ps` needs.
	- Against: closed item 2026100416041479. Its checks `ErmULmv` and the comma-only part of `ErmULmP` expected "needs tail symbols", naming the base. The parser now refuses first, naming the flag, so both are commented out with the reason. The layout check itself stands, and the rest of `ErmULmP` still pins it.
	- Verified: 20261004. `go vet`, `golangci-lint`, `go test ./...` and the harness from CLI surface through Config migration pass. Every built-in base still loads.
	- Swept: every `ParseSymbolSpec` caller. `--from-symbols` and `--to-symbols` through `ResolveBase`, both tail flags through `ApplyOptions`, config `symbols` and `tail` through `configSpec`, the built-in specs, and the help's base report, which prints the new error. `lib/wasm` gets the new error with no flag name, like its other errors. `lib/reactor` takes base names only.
	- Branch: help-commas
	- Commit: 27146f0
	- Test case: Go `Ermubbp` TestSpecOnlyCommas, and harness `ErmufVw` (`--to-tail`), `ErmufXE` (`--to-symbols`) and `ErmufYc` (config `tail`). All fail before the fix and pass after.
	- Acceptance signoff: 20261005. The next shcl release should handle a bare comma. Check `tail: ,` again after the re-pin.

- `filter_2_messy.py` crashes on six Arabic ligatures.
	- ID: 2026100419493125
	- Type: Bug
	- Status: Done
	- Severity: Low
	- Opened: 20261004-194931
	- Opened by: found while working 2026100413480015
	- Target OS: Any
	- Steps to reproduce:
		- `filter_2_messy.py` with U+FC5B, U+FC5C, U+FC5D, U+FC63, U+FC90 or U+FCD9 in its input.
	- Incorrect behavior: a `TypeError` from `ord()`, since these are superscript forms whose NFKD form is two characters.
	- Note: `filter_1_junk.py` drops all six as right-to-left, so the full pipeline never reaches it. `unicode_2_messy_alter_xclipboard_contents.bash` runs filter 2 alone, and since 2026100413480015 a crash there leaves the clipboard alone.
	- Related IDs: 2026100413480015
	- Reproduced: 20261004. Exit 1 with the `TypeError` on the six alone, and on every assigned character. These six are the only assigned characters that hit it.
	- Actual cause: the input parser lets super and subscripts skip both decomposition checks, by name. These six are matched by "WITH SUPERSCRIPT ALEF" in their names. They skipped the multi-character check, but the ASCII check after it still ran `ord()` on the decomposed string.
	- Actual fix: super and subscripts now skip both checks together, so `ord()` only sees a one-character decomposition. The six reach the later superscript filter and are dropped there.
	- Verified: 20261004. Before, the six crash; after, they exit 0 with empty output, and `--debug` lists each as SUPERSCRIPT. Plain and `--debug` output over every other assigned character is byte-identical before and after, and the full run matches the run without the six. No ruff findings.
	- Swept: every `ord()` and `normalize()` in the research scripts. In filter 2, the other two decomposition users loop over the result one character at a time. `filter_1_junk.py` calls `ord()` per character of its normalized text and only takes the length of its NFD string. `filter_3_visual.py` does no normalization, and its `ord()` calls take parsed single characters. The spreadsheet, block, sort and `build_csv.py` scripts call `ord()` on single characters only.
	- Test case: none in CI. These are one-off research tools kept out of the CI and lint gates. The fix was run before and after on the six and on every assigned character, as above.
	- Branch: messy-ord
	- Commit: 4b7f563
	- Acceptance signoff: Self-closed: the crash is gone and output is otherwise unchanged.
	- Closed: 20261004-195218

- The Unicode research tools have small bugs and stale headers. (Code review 20261004 item 15)
	- ID: 2026100413480015
	- Type: Bug
	- Status: Done
	- Severity: Low
	- Opened: 20261004-134800
	- Opened by: Code review 20261004
	- Target OS: Linux
	- Incorrect behavior:
		- The three `unicode_*_alter_xclipboard_contents.bash` scripts write an empty clipboard when the Python filter fails, since `local` hides its exit status.
		- `test_filter_all_from_xclipboard_input.bash` prints the python3 message for a missing `eog`, and opens `eog` on the visible display.
		- The ODS writer in `populate_unicode_spreadsheets_with_filtered_results.py` maps every row of a repeated-row group to one row. Plausible, read only.
		- Purpose headers in `filter_1_junk.py`, `blocks.py`, `generate_unicode_all_grouped_by_block.py` and `filter_3_visual.py` describe other files or old names. The `.gitignore` line for the debug image no longer matches its name.
		- `filter_2_messy.py` builds a `kept` set it never reads, and tests membership in lists inside loops.
	- Expected behavior: a failed filter leaves the clipboard alone, and headers describe their own file.
	- Reproduced: the clipboard mechanism with a failing filter in a scratch script, and the `.gitignore` miss with `git check-ignore`.
	- Origin: b3e719f and de93848, 2026-05-06 to 05-08. Not seen by an earlier round. Confirmed, the ODS writer included.
	- Reproduced: 20261004, the ODS writer. Three different values written to a three-row repeated group all read back as the last one. A row added to a sheet saved the usual way, with a large empty group to the end, landed at row 1048577, past the sheet's last row. A value repeated across three columns read as empty in the last two.
	- Actual cause:
		- The clipboard scripts assign the filter's output on a `local` line, which hides the filter's exit status.
		- The `eog` check was copied from the `python3` line, message and all, and the viewer launch had no display check.
		- The ODS reader maps every row of a repeated group to the group's one element, so a write to one of them changed all of them. It stops indexing at the first large group, and a new row was then added after that group. It also kept a repeated cell's value for its first column only.
		- The headers came from the files they were copied from, or from older names.
	- Actual fix:
		- A failed filter stops the clipboard script with an error, and the clipboard is left as it was.
		- The test script no longer needs `eog`. It opens the debug image only when a display is set and `eog` is installed, and says why when it doesn't.
		- The ODS writer splits a row out of its repeated group, or out of the large group at the end, before writing to it. A repeated cell reads the same in every column it covers.
		- The four headers describe their own file. `.gitignore` matches `unicode_visual_debug_*.png`.
		- `filter_2_messy.py` drops the unused set and tests membership in sets. Output is unchanged, and a run over every assigned character went from about 65 seconds to 1.
		- Two spelling fixes in messages: "Warting" and "Scrabled".
	- Note: the viewer still opens by default at a desktop, since showing the image is what the test script is for. Opening it only on request would be an enhancement.
	- Note: left alone: the block generator reads its output name from argv when imported, the test script opens the newest image in the folder rather than the one it just wrote, and rows after a large repeated group in the middle of an ODS sheet are still not indexed.
	- Swept: the `local` line in all three clipboard scripts. The other `local x="$(...)"` lines there and in the test script are checked on the next line already. List membership in every research script: only `_parse_chars` in `filter_3_visual.py` had it, and now uses a set with unchanged output. Every ODS write goes through `set_cell_value`. The gnumeric and xlsx adapters have no repeated rows.
	- Verified: 20261004, each fix before and after. Before, a failing filter emptied the clipboard at exit 0; after, the clipboard is unchanged at exit 1, and a working filter still writes it. Before, a missing `eog` stopped the script with the `python3` message and the viewer opened with no display; after, the filters run and the image is skipped with a note, and it opens when a display is set. All three ODS cases fail before and pass after, and LibreOffice reads the written file back the same. Filter 2 and 3 output is byte-identical before and after. `git check-ignore` misses a current debug image name before and matches it after. No new shellcheck or ruff findings.
	- Test case: none in CI. These are one-off research tools, kept out of the lint gates by item 22, and they need a clipboard, a display, fonts or odfpy. Each fix was run before and after, as above.
	- Related IDs: 2026100419493125
	- Branch: unicode-tools
	- Commit: 4033fb5
	- Acceptance signoff: closed without it. The viewer still opens at a desktop, since that is what the script is for. The ODS writer now writes what it was asked to.
	- Closed: 20261004

- `TestPositionalNearMathBig` fails now and then on a busy machine.
	- ID: 2026100419103794
	- Type: Bug
	- Status: Done
	- Severity: Low
	- Opened: 20261004-191037
	- Opened by: found during the 20261004 evening backlog round
	- Target OS: Any
	- Incorrect behavior: at a load average near 15, `go test ./...` failed once with "took 1.58 times math/big's own conversion, limit 1.5". Three reruns passed.
	- Expected behavior: a timing check that a busy box doesn't trip.
	- Reproduced: 20261004, 1 of 4 runs at load 15. Again at load 27, 3 of 30 runs, and with 16 to 32 extra busy processes, 6 to 16 of 100.
	- Possible cause: best of 15 rounds still isn't enough when both sides get different slices of a loaded CPU.
	- Actual cause: all of our rounds ran first, then all of math/big's, so a change in load between the two halves read as a slowdown. Each round was a batch of 20 calls, long enough that most batches took a preemption, so even the best of 15 was often a loaded one.
	- Actual fix: the two now take turns, one call each, in alternating order, over 1201 rounds. Each side's fastest call is compared. The limit stays 1.5.
	- Note: a box well past its core count still slows our side a bit more than math/big's, even at its fastest. Short calls over a longer span are what find the quiet moments. With 401 rounds it still failed 5 and 6 of 100 runs under 32 extra busy processes, and with 1201 none of 200.
	- Note: the test fails under the race detector, before and after, since that slows our side about twice as much. Nothing here runs it that way.
	- Verified: 20261004, with 32 extra busy processes: 0 failures in 200 runs, where the old test failed 15 of 200. The double-lookup code from before 6b7629b, with the new test, failed 100 of 100 at ratios of 1.9 to 2.5. `go vet`, golangci-lint and `go test ./...` pass.
	- Swept: every timed Go test. The only other is `ErmQ70b` TestNewRegistryCost, which times one side against a fixed limit about ten times what it takes, so it was left alone.
	- Branch: low-bugs
	- Commit: cbdb7a1
	- Test case: `ErmULlt` TestPositionalNearMathBig itself. It still fails on the double-lookup code it was written for, 100 of 100, and no longer fails on a busy box.
	- Acceptance signoff: Self-closed: reproduced, and the test now holds both ways it has to.
	- Closed: 20261004-193613

- `test-ids.py` reads a bash array of linter arguments in `test.bash` as a test call with no ID.
	- ID: 2026100419103799
	- Type: Bug
	- Status: Done
	- Severity: Low
	- Opened: 20261004-191037
	- Opened by: found while working 2026100413480022
	- Target OS: Any
	- Steps to reproduce:
		- Put a line like `RUFF_CMD=(ruff check .)` in `cicd/test.bash` and run `cicd/utility/test-ids.py check`.
	- Incorrect behavior: it reports a check with no ID.
	- Expected behavior: only real test calls count.
	- Reproduced: no. Worked around in 2026100413480022 by copying the linter commands from `config.bash` instead.
	- Possible cause: `SH_CALL` in `test-ids.py` matches the `(` that opens an array.
	- Reproduced: 20261004, with `RUFF_CMD=(ruff check .)`, `x=(check -x)` and `a+=(_fail --quiet)` in a copy of the harness. All three were read as calls with no ID.
	- Actual cause: `RUFF_CMD=(ruff` passed as an env assignment before a command, so `check` read as the command. A `(` after `=` passed as the start of a subshell.
	- Actual fix: an assignment whose value opens with `(` no longer counts as an env prefix, and a `(` right after `=` no longer starts a statement. A call inside a real subshell still counts.
	- Note: the item 22 workaround in the CI engine checks stays as it is.
	- Verified: 20261004, the new regex finds the same 525 calls as the old one in the harness, and `test-ids.py check` passes.
	- Swept: the other two patterns in `test-ids.py` read Go files, not bash.
	- Branch: low-bugs
	- Commit: debca16
	- Test case: `Ermz7B5` runs `test-ids.py check` from a copy against a fixture with three arrays, a plain call and a call in a subshell. It fails before the fix and passes after.
	- Acceptance signoff: Self-closed: reproduced, and its test fails before and passes after.
	- Closed: 20261004-193613

- `flame-report.py` exits 1 on an unreadable flamegraph, where the spec says 2, and misfiles the big-number path. (Code review 20261004 item 14)
	- ID: 2026100413480014
	- Type: Bug
	- Status: Done
	- Severity: Low
	- Opened: 20261004-134800
	- Opened by: Code review 20261004
	- Target OS: Any
	- Incorrect behavior: a non-UTF-8 or mode-000 SVG gives a traceback and exit 1, so the startup `--check` gate shows a crash, not a skip. `dcState.parse`/`format` and their leaf helpers land in "other, app code", which understates the big-int share. Those two are about 36% of inclusive time.
	- Expected behavior: exit 2 on any read or decode failure, and a big-int bucket that has the divide and conquer functions.
	- Reproduced: 20261004, by the review.
	- Origin: `flame-report.py:65` from a8d50ce on 2026-07-09; the buckets predate the divide and conquer change a6c8612 on 2026-08-02. Not seen by an earlier round. Confirmed.
	- Actual cause: the SVG was read with no error handling, and the big-int bucket names only math/big and older function names.
	- Actual fix: a read or decode failure on the SVG, or on the profiling dir, is a skip with exit 2 and a one-line message. The big-int bucket also takes `dcState`, `newDCState`, `parseDigits`, `formatDigits` and `wordChunk`. Names in the script are unchanged.
	- Verified: 20261004, on the newest real flamegraph the big-int share went from 5.0 to 6.4 percent, and "other, app code" from 2.6 to 1.1. ruff is clean.
	- Swept: every file read in `flame-report.py`. The marker read already caught `OSError`, and the marker write already reported one.
	- Branch: low-bugs
	- Commit: d35882b
	- Test case: `Ermz79l` runs it on a non-UTF-8 SVG and on a mode-000 one, where the mode holds, and wants exit 2 with no traceback. `Ermz7AQ` runs it on a made-up flamegraph whose self time is all in the divide and conquer functions, and wants 100 percent big-int. Both failed before the fix and pass after.
	- Acceptance signoff: Self-closed: reproduced, and its tests fail before and pass after.
	- Closed: 20261004-193613

- The frontend parity and macOS universal binary sections of the harness fail when Go is missing, where the reactor section skips.
	- ID: 2026100416545665
	- Type: Bug
	- Status: Done
	- Severity: Low
	- Opened: 20261004-165456
	- Opened by: found while working 2026100413480008
	- Target OS: Linux
	- Incorrect behavior: with no `go` on the PATH, both sections count failures.
	- Expected behavior: they skip with a warning, as the reactor section does.
	- Reproduced: 20261004, in the harness self-check, which runs with a stub `go` that acts as missing. `EloQXv6` and `ErftBA8` failed there. First seen while testing 2026100413480008.
	- Actual cause: neither section checked for Go before building or testing with it.
	- Actual fix: both sections first run `go env GOVERSION`, as the reactor section does. Without Go they skip with a warning that names their checks, the macho-fat Go tests included.
	- Verified: 20261004, with Go present the sections from binary streaming through the macOS universal binary pass, 316 of 316. shellcheck is clean.
	- Swept: every Go call in `test.bash`. The reactor and browser module sections already skip. The config migration check skips when `go` is missing from the PATH, though a stub `go` that fails makes it fail. The packaging rebuild checks run `package.bash`, which needs Go, and they skip under `--quick`. Both left as they are.
	- Branch: low-bugs
	- Commit: 9c26b3e
	- Test case: `ErmzVUR` in the harness self-check wants both skip lines and no failure from either section. It failed before the fix and passes after.
	- Acceptance signoff: Self-closed: the change does what the item asked, and its test fails before and passes after.
	- Closed: 20261004-193613

- The "Config files" part of `--help` can be wrong or missing. (Code review 20261004 item 13)
	- ID: 2026100413480013
	- Type: Bug
	- Status: Done
	- Severity: Low
	- Opened: 20261004-134800
	- Opened by: Code review 20261004
	- Target OS: Any
	- Incorrect behavior: a config at mode 000 shows as `[loaded]`, though the load skipped it. A config that fails to parse stops `--help` from printing at all.
	- Expected behavior: help shows "unreadable" or the parse error in that section, and prints the rest.
	- Reproduced: 20261004, by the review, in a scratch home.
	- Possible cause: `describePath` only checks that `os.Stat` works. The config load runs before the help branch and returns on error.
	- Origin: `main.go:902-912`, from ad488ce. Not seen by an earlier round. Confirmed.
	- Actual cause: the help's status for each config file came from `os.Stat`, not from the load. The loads run before the help branch, and their errors returned first.
	- Actual fix: under `--help`, a failed config load is kept and the run goes on. The config section marks the file `[unreadable]`, or `[not loaded]` with the error on the next line. A typed `--config` that is missing shows as `[not found]` there. Any other run still stops at the error. `LoadConfig` now checks every base in a file before adding any, so a failed file leaves no bases for the help's base report to list.
	- Against: the strict config loader (G12). Only the help goes on past a bad config. A conversion still fails on one.
	- Verified: 20261004. A mode 000 user config, a mode 000 typed config, a file that won't parse and one with a bad second base each show in the help, with exit 0. The same files still fail a conversion. `go vet`, `golangci-lint`, `go test ./...` and the harness from CLI surface through Config migration pass.
	- Swept: both config paths, system and user, and both help callers, `--help` and the no-argument help on stderr. The other `os.Stat` in main is the typed `--config` check, which still refuses outside the help. `lib/wasm` and `lib/reactor` load no config.
	- Branch: help-commas
	- Commit: 27146f0
	- Test case: harness `ErmufTF` (parse error shown, rest printed) and `ErmufUW` (mode 000, default and typed path), and Go `ErmubcQ` TestLoadConfigAllOrNothing. All three fail before the fix and pass after.
	- Acceptance signoff: closed without it. Help is the place a broken config should be visible, so showing it there and going on is the least surprise. A conversion still stops at a bad config.
	- Closed: 20261004

- The dogfood stage reports a failed copy as installed. (Code review 20261004 item 11)
	- ID: 2026100413480011
	- Type: Bug
	- Status: Done
	- Severity: Low
	- Opened: 20261004-134800
	- Opened by: Code review 20261004
	- Target OS: Linux
	- Incorrect behavior: when `cp` fails under `$HOME`, "OK: installed" prints anyway. Outside `$HOME` it runs `sudo` with no guard, which blocks a `-q` run on a password prompt.
	- Expected behavior: a failed copy is an error. `sudo` only with `-n`, and never when unattended.
	- Reproduced: 20261004, by the review, with the block in a scratch script.
	- Origin: `cicd.bash:411-414`, from 9c40e8d on 2026-07-12. Not seen by an earlier round. Confirmed.
	- Actual cause: the `cp` result was tested only together with the `$HOME` check, so under `$HOME` a failure went unseen, and outside it `sudo` could prompt.
	- Actual fix: a failed copy ends the run with an error. Outside `$HOME`, an attended run tries `sudo -n` once, which never prompts. A `-y` or `-q` run doesn't try `sudo` at all.
	- Swept: no other `sudo` in `cicd/`, `utility/` or `install.bash`, outside `legacy/`.
	- Branch: cicd-fixes
	- Commit: ffeed2e
	- Test case: `ErmCp2J` "dogfood: a failed copy under HOME is an error", `ErmCp2K` "dogfood: an unattended run never calls sudo" and `ErmCp2L` "dogfood: an attended run tries only sudo -n". All three fail on dev and pass after.
	- Acceptance signoff: Closed on review: `sudo -n` can't hang a run, and an unattended run never escalates.
	- Closed: 20261004-182334

- In `cicd.bash`, `-q` does the same as `-y`, and `--quick` doesn't reach the harness. (Code review 20261004 item 12)
	- ID: 2026100413480012
	- Type: Bug
	- Status: Done
	- Severity: Low
	- Opened: 20261004-134800
	- Opened by: Code review 20261004
	- Target OS: Linux
	- Incorrect behavior: `quiet` is set and never read, though the help says `-y` is "unattended but not quiet". The harness still runs its two packaging rebuilds, about 6 s each, under `--quick`.
	- Expected behavior: `-q` cuts stage chatter or is merged into `-y`, and `--quick` skips the packaging rebuild check.
	- Reproduced: 20261004, by the review. Shellcheck flags `quiet` as unused once the blanket disables are off.
	- Origin: `cicd.bash:86` from a8d50ce on 2026-07-09. Not seen by an earlier round. Confirmed.
	- Actual cause: nothing read `quiet`, and the harness call had no quick knob.
	- Decisions:
		- `-q` keeps its own meaning, since the help already sets it apart from `-y`. It drops the plan and the progress lines. Stage headers, results, warnings, errors and the output of each stage's tools still print.
	- Actual fix: the plan and progress lines go through a helper that `-q` silences. Under `--quick` the engine passes `CICDTEST_QUICK=1`, and the harness skips the two packaging runs and lists their four checks as skipped.
	- Note: a `-q` run still prints every harness and unit test line. Quieting those too would take a harness knob, and is left alone.
	- Swept: every `fEcho_Clean` in `cicd.bash`. The ones left are spacing, the flamegraph path and hot spots, and the missing-utility notices.
	- Verified: 20261004, the packaging section passes in full without the knob, and shows its four checks skipped with it.
	- Branch: cicd-fixes
	- Commit: ffeed2e
	- Test case: `ErmCp2H` "--quick reaches the harness" and `ErmCp2I` "-q drops the plan and progress lines, not the stage results". Both fail on dev and pass after. The harness side of the skip has no check, since that would run the harness inside itself.
	- Acceptance signoff: Closed on review: `-q` now differs from `-y` the way the help says. Quieting harness lines too can be its own item if wanted.
	- Closed: 20261004-182334

- A few Bash trap patterns are latent in the cicd scripts. (Code review 20261004 item 16)
	- ID: 2026100413480016
	- Type: Bug
	- Status: Done
	- Severity: Low
	- Opened: 20261004-134800
	- Opened by: Code review 20261004
	- Target OS: Linux
	- Incorrect behavior:
		- An early-exiting reader after a writer under pipefail, at `test.bash:215`, `gen-screenshots.bash:59` and `pin-tools.bash:196`.
		- `awk -v` passing the version in `release-notes.bash:49`.
		- `interop/fetch.bash:93` removes a path built from pin data with no check, so an empty name would remove all of `thirdparty/`.
	- Expected behavior: here-strings, `ENVIRON`, and a name check before the remove.
	- Reproduced: no. 0 of 50 and 0 of 30 tries for the two pipes; real version strings don't trip `awk -v`.
	- Origin: several commits. Not seen by an earlier round. Plausible.
	- Progress log:
		- Pinned: `gen-screenshots.bash:59` and `pin-tools.bash` fail when the tool in front writes more than a pipe holds. The probe then says pango is missing, and `pin-tools.bash` exits 141 with no message. The cited line 196 doesn't exist; the pattern is at line 45, `go version -m` into an `awk` that exits.
		- Pinned: `release-notes.bash` misses the changelog section for a version with a backslash in it.
		- Pinned: `interop/fetch.bash --refresh` with an empty pin name removed all of `thirdparty/`.
		- Can't reproduce: `test.bash:215`. The largest alphabet with a `-` digit prints 195 bytes, far under a pipe buffer, and a failed pipe there falls to `|| continue` rather than ending the run. Left as is.
	- Actual fix: the tool's output goes to a variable and then a here-string in front of `grep -q` and `awk ... exit`. `ENVIRON` in place of `awk -v`. The pin name has to be a plain name, checked right before the remove.
	- Swept: every pipe into `head`, `grep -q`, `grep -m` or an exiting `awk` in `cicd/`, `utility/` and `install.bash`. `check-release.bash:62` is fixed under item 9. The rest read a file or a here-string, end in `|| true`, run without pipefail, or get a few lines from `sed -n`, as `bench-encoders.bash:89` does.
	- Verified: 20261004, the four checks fail on dev and pass on this branch, the two pipe ones 10 of 10 runs each way. `fetch.bash --verify` passes, and release notes for v3.0.0 still find the section. Shellcheck clean.
	- Branch: bash-traps
	- Commit: 65ce2be
	- Test case: harness checks `Erm3T0v` (gen-screenshots), `Erm3T1Z` (pin-tools), `Erm3T2D` (release notes) and `Erm3T2q` (interop refresh). None for `test.bash:215`, which can't be made to fail with the current bases.
	- Acceptance signoff: Self-closed: each fix's check failed before and passes after; the one part that could not be reproduced is left alone.
	- Closed: 20261004-154100

- A raw block as a config field value is dropped or misreported.
	- ID: 2026100315002873
	- Type: Bug
	- Status: Done
	- Needs local test suite run?: No. The full `cicd/test.bash` passed 467 of 467 on the cfg-migrate branch, which had this merged.
	- Severity: Low
	- Opened: 20261003-150028
	- Opened by: found while working 2026100314430255
	- Target OS: Any
	- Steps to reproduce:
		- `aliases:` followed by a `~~~` raw block holding a name.
		- `symbols:` followed by a `~~~` raw block holding the digits.
	- Incorrect behavior: the aliases are dropped without a word, so the alias is later an unknown base. The symbols one is refused as "missing 'symbols'", which is wrong about the cause. A `tail` raw block would be dropped the same way.
	- Expected behavior: read the value, or refuse it and say why.
	- Reproduced: 20261003, on the nested-field branch.
	- Possible cause: shcl answers an array read of a raw block with BadType. The aliases read takes that as no value, and the symbols read treats it as empty.
	- Reproduced: also a `tail` block dropped, and a marker or `pad` block taken as the marker, line breaks and all. A two-line `negative:` block loaded with a marker of `x`, newline, `y`. A raw block as the `base:` name was taken as the name. `pademit` was already refused, as not true or false.
	- Actual cause: ours, not shcl's. shcl's spec says an array read of a raw block is BadType and a string read gives its text, and the vendored copy does exactly that. The loader had no arm for BadType.
	- Progress log:
		- 20261003: a raw block suits a long alphabet, so `symbols` and `tail` read one now. Every other field is one short value, so a block there is refused.
		- Question: a block reads like the one-line form, so a line break counts as a space. That keeps one rule for both spellings, but a block of rows with no spaces, such as `ABCD` then `EFGH`, is two digits of four characters each, not eight digits. The docs say to put spaces between digits. Should each line be split per character instead?
			- Answered: neither. It's ambiguous, so a block is refused under `symbols` and `tail` too.
	- Actual fix: every field, and the `base:` name, refuses a raw block, naming the base, the field and the line. Documented in the README, the default config and the changelog.
	- Sweep: every field config.go reads, plus the base name.
	- Swept: `symbols`, `tail`, `aliases`, `negative`, `decimal`, `pad`, `pademit` and the `base:` name refuse it. Two blocks under one field are two instances, already refused as a repeat. A field nested under a block is already refused. The refusal runs in the field check, before anything is read, so no read path can see a block it does not handle.
	- Verified: go vet, golangci-lint and `go test ./...` in lib pass. The new unit tests fail against the old loader and pass on this branch, except the empty-block case, which already said missing symbols. The two new harness checks fail on a dev build and pass on this one; the harness up to the end of its config section passed 116 of 116. The README example converts as shown. Shellcheck finds nothing new in `cicd/test.bash`.
	- Branch: rawblock
	- Commit: 7c91a52
	- Test case: `Erg6SWX` TestConfigRejectsRawBlockValue and the "raw marker" and "raw name" cases in `Em2MFrs` TestConfigErrorsCiteLines; `ErgbjuS` "config raw block symbols rejected" and `Erg6SWW` "config raw block alias rejected" in the harness. TestConfigRawBlockSymbols went when blocks under symbols were refused.
	- Acceptance signoff: Signed off 20261003.
	- Closed: 20261003-180637

- The release archives and packages don't rebuild to the same bytes.
	- ID: 2026100412472615
	- Type: Bug
	- Status: Done
	- Needs local test suite run?: No. The full `cicd/test.bash` passed 489 of 489 on dev after the merge, and CI passed.
	- Severity: Low
	- Opened: 20261004-124726
	- Opened by: found while working 2026100409572736
	- Target OS: Any
	- Steps to reproduce:
		- `make release` twice, a minute apart, on the same commit.
	- Incorrect behavior: every bare binary and the `.wasm` match, but the `.tgz`, `.zip`, `.deb`, `.rpm` and installer checksums differ.
	- Expected behavior: a rebuild of one commit matches the published checksums for every asset.
	- Reproduced: 20261004.
		- 20261004: again on dev. Two v9.9.9-beta1 runs a few seconds apart differed in 15 of 25 files, every archive, package and installer.
	- Possible cause: file times and archive headers taken from the clock. Probably fixed by setting them from the commit's time.
	- Actual cause: each binary went into its archive or installer with the time it was built and a mode from the umask. nfpm stamped the packages with the clock and the rpm with the host name, and took the license file's checkout time and mode. The zip kept local time and owner fields. The Go builds also took a VCS stamp, so a dirty tree or a source tarball built other bytes.
	- Actual fix: every file that goes into an asset gets the commit's time and a fixed mode. The tarballs have fixed owners and no gzip time, the zip is made in UTC without the extra fields, and nfpm takes the commit's time, a fixed build host and a fixed license mode. The Go builds have no VCS stamp or build ID. `checksums.txt` is sorted the same in any locale.
	- Sweep: every file package.bash writes.
	- Swept: all 25 files of a full run, the macOS universal build and the `.wasm` included. `make release` runs package.bash, and no other path builds a release asset.
	- Verified: two package runs a few seconds apart, the second with another umask and time zone, gave the same checksums for all 25 files. So did a run from a dirty tree against one from a clean export of the commit at another path. `ErlP6B8` fails with dev's packaging, naming the 15 files, and passes with the fix. It also fails when the zip loses its fixed time zone. The macho-fat tests pass and the universal build still has both slices.
	- Note: no part was left open. The installer rebuilt the same once its input had a fixed time.
	- Note: matching a published checksum needs the same tool versions. Go and nfpm are pinned. NSIS, tar, gzip and zip come from the OS, and NSIS is the one most likely to differ between a runner and a local box.
	- Branch: pkg-repro
	- Commit: cdd002f
	- Test case: `ErlP6B8` "release assets rebuild to the same bytes" in the harness.
	- Note: check again after the next release. Rebuild its tag with the Go, nfpm and NSIS versions the workflow used, and compare with its `checksums.txt`. NSIS comes from the runner's apt, so its version has to be read from the workflow log.
	- Acceptance signoff: Self-closed: reproduced, its test failed before the fix and passes after, and the full suite passed.
	- Closed: 20261004-131952

- There is no public code style guide or contributing.md. (Code review 20261004 item 28)
	- ID: 2026100413480028
	- Type: Enhancement
	- Status: Done
	- Priority: Low
	- Opened: 20261004-134800
	- Opened by: Code review 20261004
	- Target OS: Any
	- Note: the directives want `project/style-guide_code.md`, a `contributing.md` that links it, and a short README pointer to both. None exist.
	- Origin: directive gap, filed against the 2026-10-04 directives.
	- Progress log:
		- Done: `project/style-guide_code.md` covers Go, Bash and Python as the code is written now, with the reason for each rule. Prose and markdown rules are left out.
		- Done: `contributing.md` covers bug reports, branches, the checks to run with the stage 3 linters, test IDs, adding a base, licensing and support links. It links the style guide.
		- Done: one sentence at the end of the README's development section points to both. No other README text changed.
	- Decisions:
		- Python is documented with tabs, as every Python file here and the ruff formatter setting use, not four spaces.
		- Contributions take the license of the directory they go into. Signed off 20261005.
	- Fixed: `.github/CODEOWNERS` dropped the `DONATE.md` that doesn't exist, and now covers the support links in the README, `contributing.md` and `--donate`.
	- Verified: the relative links and anchors in the new docs and the README pointer resolve. `make vet`, `test-ids.py new`, the bases table command and the profiling example ran clean. The pipeline command was checked against its `--help` only.
	- Branch: style-docs
	- Commit: 7fcc945
	- Test case: none, docs only. The harness has no link check.
	- Acceptance signoff: 20261005.

- The harness repeats calls and forks that one pass could do. (Code review 20261004 item 27)
	- ID: 2026100413480027
	- Type: Enhancement
	- Status: Done
	- Priority: Low
	- Opened: 20261004-134800
	- Opened by: Code review 20261004
	- Target OS: Linux
	- Note: the `IDX_NAME` loop, the README name check and the dash check run the program per base, about 13 s together. One listing would do.
	- Note: `$(cat f)`, a per-symbol `printf` loop and `_rand_int` fork in loops. `$(<f)`, `printf -v` and `$SRANDOM` are near free.
	- Origin: several commits from 4ff92e8 on. Not seen by an earlier round. Confirmed by timing.
	- Related IDs: 2026100413480017
	- Note: 2026100413480017 had already cut most of the 13 s, since a lookup by name no longer builds every base. A lookup by index still does, which is why the `IDX_NAME` loop was the slow one left.
	- Done: `IDX_NAME` comes from one `--list --list-compat`. An index the listing leaves out gets a name no base has, so its round trips fail. An empty name would have read as base 10 and passed.
	- Done: the README check takes names and aliases from one listing, and asks the program only about a name that is in neither, so a prefix or other case still resolves as before.
	- Done: the dash check skips a base whose marker is already `~` or off, and tests the digits in the shell instead of through `grep`. There is no listing of every alphabet, so it still runs the program once for each other base.
	- Done: `_run` and the other simple reads use `$(<f)`. The random helpers use `$SRANDOM`, and `_rand16` is gone. The three code-point loops build their strings with `printf -v`. The harness now stops at the top on a bash older than 5.1.
	- Verified: section timings, median of three, before and after: CLI surface 1.1 s to 0.9 s, binary and streaming 13.8 s to 11.5 s, fuzz 10.5 s to 4.6 s, back-compat 5.7 s to 5.4 s. The full harness went from 147 s to 138 s, 555 of 555 both times. shellcheck is clean and `test-ids.py check` passes.
	- Verified: each rewritten check fails when what it watches is broken, and passes again once restored. A binary with `64url` renamed and a README row with an unknown name fail the README check, while `HEX`, `base-16` and an alias still pass. A listing that shows `64url` with a `-` marker fails the dash check. Swapping two names in the listing, or dropping a row, fails the symbol fuzz. Corrupted base-10 output fails the matrix, fuzz and back-compat round trips. Corrupted 2048 and 65536 output fails the native vectors, and a broken tail round trip fails the tail checks.
	- Verified: the new code-point strings match the old ones byte for byte, for all three loops.
	- Swept: every `$(cat "...")` of a single file, every `_rand16` and `od ... /dev/urandom` random number, and each `printf "\U..."` loop. Left alone: `head -c ... /dev/urandom` where the loop needs random bytes, the per-base `--show-symbols-0 --by-index` load in the symbol fuzz, which also checks that an index and its listed name are the same base, and the per-pair name check in the back-compat suite, which costs about 0.1 s.
	- Test case: none new. These are the harness's own checks. Each one touched was watched to fail and pass, as above. A wall-clock limit on harness sections would flake on a busy machine.
	- Branch: harness-forks
	- Commit: 94bbb66
	- Acceptance signoff: Self-closed: the change does what the item asked, the checks keep their meaning and were each watched to fail.
	- Closed: 20261004-205908

- The Python pipeline tools miss most of the Python style rules. (Code review 20261004 item 25)
	- ID: 2026100413480025
	- Type: Enhancement
	- Status: Done
	- Priority: Low
	- Opened: 20261004-134800
	- Opened by: Code review 20261004
	- Target OS: Any
	- Note: no type hints anywhere, files opened without `with`, lists and tuples used as records, os.path over pathlib. Scope is `flame-report.py`, `pprof2flame.py`, `test-ids.py`, `gen-demo-gif.py` and `gen-bases-table.py`.
	- Note: also unused `wpx` in pprof2flame and `prog` in gen-demo-gif, a private Pillow call, a `find(" ")` of -1 that skips the fast-typing start for a one-word command, and test-ids keying tests by directory basename.
	- Origin: a8d50ce onward. Not seen by an earlier round. Confirmed by mypy and ruff.
	- Prereq IDs: 2026100413480032
	- Note: item 32 answered. `pprof2flame.py`, `gen-demo-gif.py` and `gen-bases-table.py` move to snake_case. `flame-report.py` keeps silkterm's names.
	- Progress log:
		- Done: the three scripts use PEP 8 names, and ruff's naming rules cover them again. `flame-report.py` keeps its names and stays exempt. File names and command lines are unchanged.
		- Done: all five have type hints, named records where bare tuples, lists and dicts stood in for them, pathlib for paths, and `with` or pathlib for every file read and write.
		- Fixed: a one-word command types at the same pace as the first word of a longer one. The missing-glyph check uses public Pillow calls only. The unused `prog` argument is gone.
		- Fixed: test-ids keys Go tests by import path, so two packages with the same directory name no longer share one test's ID.
		- Fixed: a compile error now prints under the package it broke. Its output was filed under a misread key and never shown. Same key, same code, so it is fixed here rather than filed apart.
		- Note: the `wpx` note is out of date. Item 22 already used it.
	- Verified: output is byte-identical before and after for all five tools, across their options and error exits, apart from the compile error lines above. The demo gif comes out identical to the committed one. The bases table matches `--list` and the README row for row.
	- Verified: ruff is clean from the repo root and fails on a camelCase function in each renamed file. mypy is clean on all five with untyped defs disallowed. Harness 555 of 555.
	- Swept: no other `find` result in the five files goes unchecked, and no other private Pillow call is left. The report's test keys and its build-output key both moved to import path. Callers checked: `cicd.bash`, `config.bash`, `test.bash`, contributing.md, the style guide and the private notes.
	- Test case: `ErnEi9h` (one-word command), `ErnEiAv` (same directory name), `ErnEiCC` (compile error). Each fails on the old code and passes now. The private Pillow call has no test, since nothing visible changed: the new check matched the old one on every codepoint tried.
	- Acceptance signoff: closed without it. The compile-error fix is the same keying code as the listed bug, and has its own test.
	- Closed: 20261004
	- Branch: py-style
	- Commit: de915f7

- Small Go style fixes. (Code review 20261004 item 24)
	- ID: 2026100413480024
	- Type: Enhancement
	- Status: Done
	- Priority: Low
	- Opened: 20261004-134800
	- Opened by: Code review 20261004
	- Target OS: Any
	- Note: `SpecOpts` is exported but only `mkSpec` uses it. `real` shadows the builtin in `configupgrade.go:93`. Seven comments in `bases.go` use a section sign where ASCII would do.
	- Note: errors are dropped with `_` and no comment in the `convert_test.go` benchmarks and two `reactor-host` writes.
	- Note: `lib/wasm` and `lib/reactor` repeat the 100000 precision and width limits as literals beside the constants.
	- Origin: several commits. Not seen by an earlier round. Confirmed by grep.
	- Note: `SpecOpts` stays exported. It is in the tagged `lib/v0.1.0`, and both library design docs list it as public. Dropping it breaks any `go get` user who names it. A v0 module may do that, but in a release that says so, not as a style fix.
	- Done: the seven comments say "section N". `real` is now `target`. The benchmarks check every error through two small helpers.
	- Done: `lib/wasm` has its own `maxPrecision`, and both modules build their limit messages from the constants.
	- Swept: every `_` drop in our Go code under `lib/` and `cicd/`, shcl left out as vendored. The ones in `stream.go`, `configupgrade.go`, `userconfig_test.go` and the reactor-host runtime close got a short reason too. The section signs still in `bases.go` are digits in a listed alphabet. No 100000 literal is left beside its constant.
	- Verified: 20261004. go vet (linux, windows, darwin, js, wasip1), golangci-lint and `go test ./...` clean. `make reactor` and `make web` build. Each benchmark runs once clean, and reactor-host passes.
	- Test case: `Ern7YZg` TestPrecisionBound in the browser module, and new cap checks in reactor-host, `Elmd2Y4`. They pin both modules' 100000 caps to the command's, and fail with either cap moved to 99999. The rest is style, with no behavior to test.
	- Branch: go-lows
	- Commit: 36e8857
	- Acceptance signoff: Self-closed: mechanical. `SpecOpts` left as public API, as the note says.
	- Closed: 20261004-200019

- The reactor scans every open region for each pointer a host passes. (Code review 20261004 item 29)
	- ID: 2026100413480029
	- Type: Enhancement
	- Status: Done
	- Priority: Low
	- Opened: 20261004-134800
	- Opened by: Code review 20261004
	- Target OS: Any
	- Note: a convert call took 67 us with no other allocations open, 948 us with 1,000 and 8.3 ms with 10,000.
	- Probable fix: an exact lookup on the start pointer first, with the scan only for pointers into the middle of a region.
	- Origin: `reactor/main.go:136-148`, from 36d7ccc on 2026-08-02. Not seen by an earlier round. Confirmed with a scratch reactor-host bench.
	- Done: as the probable fix. A pointer to a region's start is found in the map at once. Only a pointer into the middle of a region still walks them all.
	- Verified: 20261004. 25 converts took about 0.8 ms with no other regions open. With 10,000 open they took 38 ms before and 0.8 ms after, 46 times as long against 1.1. go vet, golangci-lint, `go test ./...` and `make reactor` clean.
	- Test case: `Ern7YaC`, reactor-host `--regions`. It fails when a convert with 10,000 regions open takes over 3 times as long as with none. It failed at 44 to 46 times before the fix and passed at 1.1 after, run through the harness section too. reactor-host `Elmd2Y4` now also passes an interior pointer, and a length past a region's end from its start and from its middle.
	- Branch: go-lows
	- Commit: 314421e
	- Acceptance signoff: Self-closed: did what the item asked, and its test fails before and passes after.
	- Closed: 20261004-200057

- A config migration can lose an edit made to the original during the backup. (Code review 20261004 item 30)
	- ID: 2026100413480030
	- Type: Enhancement
	- Status: Done
	- Priority: Low
	- Opened: 20261004-134800
	- Opened by: Code review 20261004
	- Target OS: Any
	- Note: the backup is a hard link to the original. An in-place write between the backup check and the rename goes into both, and `keepBackup` then puts the old bytes over it. The window is milliseconds.
	- Probable fix: when the backup no longer matches, write the old bytes under a new name.
	- Origin: `configupgrade.go:157-161`, from 9acc437 on 2026-10-03. Not seen by an earlier round. Plausible.
	- Reproduced: 20261004, with the write step held open by a test. An append made in that window was in no file afterward. The config held the converted old text, and the backup the old text.
	- Done: when the backup holds neither the original nor the converted text after the write, it holds an edit. That file goes back at the path, so the config is just as it was edited. The run notes that the file changed while it was being converted, and reads it the old way, as when the change is seen before the write. The next run converts it.
		- If it can't go back, it stays under the backup name, and the note says the edited text is there.
		- A backup that went missing, or that holds the converted text, still gets the original put back, and the conversion stands.
	- Decisions:
		- Not the probable fix. That would leave the converted pre-edit text at the path, and the edit under a backup name. Putting the edited file back keeps the config where it is edited, and matches what an edit seen before the write already does. `createFile` has no use here, since nothing new is created.
	- Note: two windows are left, and no fix here can close them without a compare-and-swap replace. Where hard links don't work the backup is a copy, so an in-place edit in the window still goes with the old file. An editor that saves by rename in the window is still replaced by the converted file. Both were true before.
	- Note: no changelog line. The migration is new since v3.0.0.
	- Swept: `keepBackup` has one caller. The other link-based write, `createFile`, makes a new file and has nothing to lose.
	- Verified: 20261004. go vet (linux, windows, darwin), golangci-lint and `go test ./...` clean. The three tests pass 20 times over under the race detector.
	- Test case: `Ern8m1y` TestUpgradeConfigFileEditDuringWrite, plain and through a symlink, and `Ern925t` TestUpgradeConfigFileEditStaysInBackup. Both fail on the old code and pass now. `Ern924g` TestUpgradeConfigFileKeepsBackup pins the missing and written-through cases, and passes both ways.
	- Branch: go-lows
	- Commit: 6e8854e
	- Acceptance signoff: closed without it. Putting the edited file back keeps the edit where the user expects it, and matches what the code already did for a change seen before the write. The two gaps left need a compare-and-swap replace the OS doesn't give, so they stay as notes here.
	- Closed: 20261004

- Python tools use three naming styles. Which one should they follow? (Code review 20261004 item 32)
	- ID: 2026100413480032
	- Type: Task
	- Status: Done
	- Priority: Low
	- Opened: 20261004-134800
	- Opened by: Code review 20261004
	- Note: the cicd tools use `fCamelCase`, `gen-bases-table.py` uses camelCase, and `test-ids.py` and the research scripts use snake_case.
	- Note: the directives point two ways. Code style says the language's case conventions win, which means PEP 8 snake_case. The Profiling section says to match silkterm's Python, which is `fCamelCase`.
	- Question: snake_case everywhere, or `fCamelCase` as the house rule with ruff's N8xx rules turned off? Item 22 needs the answer for its ruff config.
		- Answered: idiomatic Python for code written here. Code written by hand keeps its case, and so does a script copied in from elsewhere.
	- Progress log:
		- Done: the Code style directive now says PEP 8 names, with those two exceptions, and the profiling section no longer reads as asking for silkterm's names.
		- Note: `flame-report.py` came from silkterm and keeps its names. `pprof2flame.py`, `gen-demo-gif.py` and `gen-bases-table.py` move to snake_case under item 25. `test-ids.py` and the research scripts already use it.
	- Test case: none, a directive change.
	- Closed: 20261004-140028

- Five project helper scripts are GPL, where helpers are usually MIT. (Code review 20261004 item 33)
	- ID: 2026100413480033
	- Type: Task
	- Status: Done
	- Priority: Low
	- Opened: 20261004-134800
	- Opened by: Code review 20261004
	- Note: `check-release.bash`, `check-vendor.bash`, `package.bash`, `release-notes.bash` and `interop/fetch.bash` all carry the Bubbles copyright with GPL. The other cicd helpers are MIT.
	- Question: keep them GPL since they only make sense in this project, or move them to MIT?
		- Answered: MIT.
	- Progress log:
		- Done: the five scripts are MIT, with the same header as the other helpers.
		- Done: the two interop drivers, `qntm.mjs` and `llfourn2048/src/main.rs`, were also Bubbles and GPL, and were missed by the review. They are MIT now too.
		- Done: eight Unicode research scripts under `utility/` were Bubbles and GPL as well. Asked, and moved to MIT.
		- Note: the package license in `package.bash` stays GPL-2.0-or-later, since it is the command's.
	- Test case: none, license headers only.
	- Closed: 20261004-140028

- `filter_2_messy.py` ends with a block of requirements written as instructions for a code generator. (Code review 20261004 item 34)
	- ID: 2026100413480034
	- Type: Task
	- Status: Done
	- Priority: Low
	- Opened: 20261004-134800
	- Opened by: Code review 20261004
	- Note: `utility/include/filter_2_messy.py:449-477`, a bare string after the main block, from de93848 on 2026-05-08. It is public on main and in three tags.
	- Note: the text is the project's own. It is filed only because it reads as a prompt, which no word scrub can catch.
	- Question: delete it, fold the real requirements into the Purpose header, or keep it as is? History stays untouched either way.
		- Answered: clean it up.
	- Progress log:
		- Done: the trailing block is gone. Its list of what gets filtered out moved into the Purpose header in its own words, without the lines aimed at whoever was writing the script. A spelling slip in the header was fixed.
		- Note: the bitmap item lost its "can't fix" remark, since the script does filter box drawing, block elements and Braille by range.
	- Verified: the same input gives the same output before and after.
	- Test case: none, comments only, and the research scripts have no tests.
	- Closed: 20261004-140028

- macOS gets a universal binary for both amd64 and ARM.
	- ID: 2026100313304792
	- Type: Enhancement
	- Status: Done
	- Needs external testing: Run `convert-base-v2-darwin-universal` from a release build on an Apple silicon Mac. The Intel half passed on b26. Check `--version` and one conversion, and that Gatekeeper treats it the same as the per-arch build.
	- Opened: 20261003-133047
	- Opened by: JC
	- Target OS: macOS
	- Progress log:
		- 20261003: `package.bash` builds darwin/amd64 and darwin/arm64 as two separate tarballs now.
		- Done: packaging adds `convert-base-v2-darwin-universal.tgz` and the bare `convert-base-v2-darwin-universal`. Both are in `checksums.txt`.
		- Done: the new `cicd/utility/macho-fat` joins the two builds, since there is no lipo here. Slices are aligned the way lipo does it, 4K for x86_64 and 16K for arm64. It reads its output back and compares each slice to its input before writing.
		- Note: the Go linker signs the arm64 build itself, ad hoc. The slice goes in unchanged, so the signature still matches. The x86_64 build is unsigned, as before.
	- Decisions:
		- The universal build is added, not swapped in. The per-arch macOS assets stay, so `install.bash` and old download links keep working, and the installer still fetches the per-arch build because it is half the size.
		- The universal build is made only when both macOS builds were, so `--no-arm` skips it.
	- Verified: a full package run made all three macOS assets, and `checksums.txt` checks out. `file` reports a universal binary with x86_64 and arm64 executables. Each slice is byte-identical to its per-arch binary, and starts on a 4K or 16K boundary. Every page hash in the arm64 signature matches the slice as it sits in the universal file. A `--no-arm` run makes no universal asset.
	- Branch: mac-universal
	- Commit: 22452c9
	- Test case: `ErftBA8` "macho-fat tests", which runs `ErftBA9` TestLayout, `ErftBAA` TestSecondSliceAlignment, `ErftBAB` TestRejects, `ErftBAC` TestVerifyCatchesChangedSlice and `ErftBAD` TestRealCommand from `cicd/utility/macho-fat/main_test.go`. They fail with the arm64 alignment or slice order broken.
	- Verified: 20261004, on an Intel Mac with macOS 15.8.1. The universal binary, the per-arch x86_64 one and the one from the universal `.tgz` all print the same version and build line. A hex to base-62 conversion and a bytes to base-64 one match the Linux build. Gatekeeper rejects the universal and per-arch builds the same way, unsigned, with and without the quarantine flag.
	- Acceptance signoff: Closed on review: the arm64 slice is byte-identical to the per-arch build, and its signature's page hashes match in place. The Apple silicon run stays a check at the next beta.
	- Closed: 20261004-182334

- Support `--help`, `--about` and `--donate`, in a similar way as sister project shcl.
	- ID: 2026100313304797
	- Type: Enhancement
	- Status: Done
	- Needs local test suite run?: No. The full `cicd/test.bash` passed 467 of 467 on the cfg-migrate branch, which had this merged.
	- Opened: 20261003-133047
	- Opened by: JC
	- Target OS: Any
	- Requirements  [Feature]:
		- `--about` gives the version, copyright, project home, license and a short description.
		- `--donate` lists GitHub Sponsors and Ko-fi.
	- Progress log:
		- 20261003: `-h`, `-help` and `-version` exist already. `--about` and `--donate` don't.
		- 20261003: `--help` and `--version` already worked with two dashes, since Go's flag package takes either.
		- Done: `--about` and `--donate` added. `--help`, `--examples`, `--version`, `--about` and `--donate` can be combined, and each prints once, in the order given, with one blank line between. `--about` covers `--version`. A lone output is unchanged, so `--version` is still one bare line.
		- Done: help lists the five under a "Program info" heading. Its copyright line now uses the © sign, to match `--about`.
		- Done: Ko-fi added to `.github/FUNDING.yml` and the README support section, taken from the unmerged `ko-fi` branch.
		- Note: everything but the help now prints before the config files load, as `--version` already did. So `--examples` no longer creates the default config or fails on a broken one. That's fine.
		- Fixed: the stale comments in `.github/FUNDING.yml`, which pointed at another project's DONATE.md, are gone.
		- Note: an info flag after the NUMBER is still read as a positional, as before: `convert-base-v2 255 --about` reports an unknown base. shcl takes these flags anywhere; this project keeps flags before the NUMBER.
		- Done: `-v` and `-V` work as `--version`, as in shcl.
	- Verified: go vet, golangci-lint and the new unit tests pass. The six new harness checks fail on the dev build and pass on this one.
	- Branch: about-donate
	- Commit: c420170, 67d980e
	- Test case: `Erfqe2I` TestInfoFlagOrder, `Erfqe2J` TestPrintInfoLoneIsUnchanged, `Erfqe2K` TestPrintInfoSeparation and `Erfqe2L` TestAboutAndDonateContent; `Erfqe2C` to `Erfqe2H` and `ErgVwO8` in the harness.
	- Acceptance signoff: Self-closed: its tests pass, and the full `cicd/test.bash` passed 467 of 467.
	- Closed: 20261003-180637

- When a shcl upgrade breaks compatibility with the application config file(s).
	- ID: 2026100313304802
	- Type: Feature
	- Status: Done
	- Needs local test suite run?: No. The full `cicd/test.bash` passed 467 of 467 on the branch.
	- Opened: 20261003-133047
	- Opened by: JC
	- Target OS: Any
	- Requirements  [Feature]:
		- Check if the new shcl version has breaking changes. If so:
			- Rename the latest config file `[origname]_backup_YYYYmmDD-HHMMSS_format-v[shcl version].shcl`.
			- Write a new config file with the same previous path and name, from scratch through shcl, using whatever settings and conversions shcl can handle.
		- FYI future versions of shcl might do the config backup and conversion for you. So just be careful not to race, conflict, or trample what shcl might try to do. (And first, while wiring up a new version of shcl in code, see if it has a new API to do or at least assist with the conversion for you.)
	- Progress log:
		- 20261003: the vendored shcl is v1.2.0, and v2.0.0 is out. Its one format break is escapes in field names, which no config field here uses.
		- 20261003: first half done. The second half is the backup and rewrite, plus the child test 2026100313304807.
			- Done: shcl's 3.0 dev build is vendored, pinned to commit `f8e27a22` of `yottacore/shcl`, where the project moved. It needed no code change, and the loader is as strict as before.
			- Done: the vendor check takes a commit as well as a tag. It stays strict, and prints a pre-release notice on every run while the pin is a commit.
			- Done: the config file written on the first run ends with SHCL's info block. Its Format line says which rules the file was written under, and older files have none, so `shcl.FormatVersion` tells them apart.
			- Done: the 3.0 escape rules only change values with backslashes in them. No shipped config, test fixture or doc example has one, and every base they define resolves to the same symbols, markers and encoding under both versions. The default config, README and changelog now say how a backslash is read.
			- Left: when an existing file has no Format line, back it up and write it again. `shcl.Migrate(text, true)` rewrites a 1.x or 2.x file for the 3.0 rules and stamps it. On every fixture here it kept every value the same. `MigrateUnstamped` plus `GenBanner` is the pair for a program that writes its own block.
			- Left: the backup name in the requirement differs from shcl's own plan for the same feature (its 2026100313461649), which puts the old file's format version in the name. shcl may later do this itself, so the two should agree.
			- Left: `ensureUserConfig` writes with a plain file write. A rewrite of an existing file should go through shcl's save or an atomic rename. shcl's optional `shcl_windows.go` is not vendored, and a Windows save through the library needs it to keep file attributes.
			- Note: dev's copy had stopped matching its v1.2.0 pin when the 2026-09-09 copyright sweep edited its header, so the vendor check would have failed. The new copy is verbatim.
		- 20261003: shcl friction found on the dev build. None needed a workaround in code here.
			- The Go file does not compile for a 32-bit target: `GOARCH=386 go build ./...` fails because `math.MaxUint32` overflows `int`. v1.2.0 built fine. Expected: it builds on any Go target. Missing capability. Nothing shipped here is 32-bit, but a 32-bit program that imports the library can't build. Not in shcl's backlog, which treats 32-bit as no target.
				- Fine as is. 32-bit is no target here either.
			- The info block's Syntax link names tag `v3.0.0-beta1`, which does not exist yet, so a config written by a build from this pin carries a dead link. Expected: a link that resolves. Rough edge, and on purpose upstream, since the tag comes with the release.
			- A file ending inside an unclosed raw block, such as `~~~` alone, comes back from `Migrate` unchanged, unstamped and not `Current`, with nothing to say why. A caller that rewrites until the file is current would loop. Expected: some signal. Rough edge. The loader here refuses such a file anyway.
			- A file stamped Format 3 now reads as current to every later 3.0 build, and shcl plans more breaking changes before 3.0.0 (its 2026100207032800: no backslash escapes, no spaces in bare values, brackets for arrays, `- ` for list items). Under those, `aliases: a, b` and `* x` lines would be refused here. Known upstream as 2026100115403385. Missing capability.
			- Answered: no wait. The next release is a beta. A file written by a release on this pin says Format 3 but follows the dev rules, and a later shcl would not migrate it.
		- 20261003: second half done, with the child test 2026100313304807.
			- Done: a config with no Format line, or an older one, is read the old way. `LoadConfig` converts it in memory through shcl's `Migrate` before loading, so the library and the command agree.
			- Done: the user and /etc files are converted on disk once. The original is kept beside the file as `convert-base-v2_backup_YYYYmmDD-HHMMSS_format-v1.shcl`, and the converted text replaces it through shcl's atomic write. One stderr note names the backup.
			- Done: a file `Migrate` cannot fully keep, or whose converted text the strict loader refuses, is left as it is. The run stops with an error naming the line.
			- Done: a failed write, such as a read-only directory, loses nothing. The run converts the file in memory, and says so on stderr when that changes a value.
			- Done: a file named with `--config` is never rewritten. It is read the old way, with a note naming `shcl migrate --write --from-2x` when that changes a value.
			- Done: lib/wasm and lib/reactor still load no config files.
			- Note: the library is v0.2.0, for the new `UpgradeConfig`.
			- Note: `TestConfigBackslashLayers` and the "config bare backslash escape" and "config bad escape rejected" checks pin the current rules, so their files now end with the Format line. Without it, six of their cases read the old way and fail. Nothing was removed.
			- Note: the names differ. This backup says `format-v1`. shcl's `migrate --write` keeps `NAME_old_v2.EXT`, its plan for this feature (its 2026100313461649) calls an unstamped file `format-v2`, and `Migrate` writes "Migrated from SHCL 2.x." into the file. They should agree once shcl does the backup itself.
			- shcl friction found in this half. Both have a workaround, marked in `configformat.go`.
				- Known bug 3 above, the unclosed raw block. The result is refused when it names no current format, so the file is never taken as old on every load. The strict loader refuses such a file anyway, so only the message changes.
				- New: `Migrate("x: [ab]\n", true)` gives `x: ab` and counts nothing lost. The 1.2.0 and 2.0.0 Go parsers read that line with an error ("missing colon", E015), so the old loader refused the file. Expected: the line left as written or counted lost, since a strict caller refused it. Rough edge, and on purpose upstream, which counts this sugar as clean. Workaround: refused when the current parser flags E019 on the original, which it does for every such line.
			- Verified: go vet, golangci-lint, staticcheck and `go test ./...` pass. The full `cicd/test.bash` passed 467 of 467. The old readings in the new tests match what v3.0.0, the last release on SHCL 1.x, gives for the same files. Each new Go test and harness check failed with its part of the change taken out, or with a fault put in.
			- Answered: an unstamped file's backup says `format-v1`, what every release here read it with, not shcl's `format-v2`.
	- Decisions:
		- Built on shcl's unreleased 3.0 dev tree, not v2.0.0 and not waiting for 3.0.0. That breaks the "pin only released tags" rule on purpose until 3.0.0 is out.
		- 20261003: a config with no Format line is old, and is read with its old meaning. A hand-written file meant for the current rules needs the Format line.
		- 20261003: the file is converted with `Migrate`, not written again from scratch. It keeps comments and layout, where a fresh file would drop whatever else the old one held. The result goes through the strict loader before anything is written.
		- 20261003: the backup name uses the format the file was written for, so `format-v1` for a file with no Format line, since every release here read it with SHCL 1.x.
		- 20261003: the backup is a hard link to the original, made before the atomic write replaces the path, so the path always holds a whole file. A copy is the fallback where links don't work. After a failed write the backup goes only while the path still holds the same bytes.
		- 20261003: refusing beats converting. A file that can't be fully kept stops the run, even the default user file, since loading the rest could leave an alias on a built-in alphabet.
		- 20261003: a file named with `--config` is converted in memory only, with a note, and never renamed.
		- 20261003: /etc is converted like the user file, since the program finds it on its own. Without write access it is converted in memory.
		- 20261003: a note for an in-memory conversion shows only when a value had to be written differently, so a read-only /etc with no backslashes stays quiet.
	- Verified: go vet, golangci-lint, staticcheck and `go test ./...` pass. The full `cicd/test.bash` passed 445 of 445. The command builds for every shipped target and the three WASM ones. The vendor check failed on a made-up commit, a wrong commit, an edited copy, and the old tag against the new file. The new tests fail against the old build or the old shcl.
	- Branch: shcl3, cfg-migrate
	- Commit: 51f59b6, 9acc437
	- Test case: `Erg0gZ2` TestConfigBackslashLayers and `Erg0gZ1` TestUserConfigIsStamped; `Erg0gYy`, `Erg0gYz` and `Erg0gZ0` in the harness.
		- Second half: `ErgDzUX` TestUpgradeConfigKeepsOldMeaning, `ErgDzUY` TestUpgradeConfigCurrentIsLeftAlone, `ErgDzUZ` TestUpgradeConfigRefuses, the TestUpgradeConfigFile tests `ErgDzUQ` to `ErgDzUV`, and `ErgDzUW` TestExplicitConfigNote; the "Config migration" section, `ErgDzU8` to `ErgDzUP`, in the harness.
	- Acceptance signoff: Self-closed: its tests pass, and the full `cicd/test.bash` passed 467 of 467.
	- Closed: 20261003-180637

- Write a test as part of CICD that creates old shcl file versions for settings, and tests the automatic (non-shcl-assisted) conversion.
	- Note: the conversion now goes through shcl's own `Migrate`. "Non-shcl-assisted" is read as: the program does the backup and rewrite itself, rather than shcl's CLI doing it.
	- ID: 2026100313304807
	- Type: Task
	- Status: Done
	- Opened: 20261003-133047
	- Opened by: JC
	- Parent ID: 2026100313304802
	- Target OS: Any
	- Progress log:
		- 20261003: waits on its parent.
		- 20261003: done with the parent's second half.
			- Done: the "Config migration" section of `cicd/test.bash` writes an old user config with no Format line, as the SHCL 1.x releases did, with a bare `\t` and a `\#` whose meaning changed in 3.0. Each case runs in its own config dir under the harness's temp dir.
			- Done: it checks that the backup exists under the right name with the original bytes, that the new file names format 3, keeps its comment and resolves the same alphabet and marker, and that a second run prints nothing and changes nothing.
			- Done: it checks that a file the conversion can't fully keep is refused and left alone, that a read-only config dir loses nothing and still reads the old way, and that a `--config` file is read the old way and left alone.
			- Done: when git and go are there, it builds v3.0.0 from its tag and checks that the converted file gives the same symbols and marker that v3.0.0 gives on the original. Otherwise that part is skipped with a warning.
			- Done: Go tests cover the same ground, plus a failed write after the backup and a symlinked config.
			- Verified: the full `cicd/test.bash` passed 467 of 467. Against a dev build 15 of the new checks fail, against a build without the command's part 6 fail, and the "left alone", "keeps its comments" and "loses nothing" checks each failed with a fault put in.
	- Branch: cfg-migrate
	- Commit: 9acc437
	- Test case: the "Config migration" section, `ErgDzU8` to `ErgDzUP`, plus the tests named on the parent.
	- Acceptance signoff: Self-closed: its tests pass, and the full `cicd/test.bash` passed 467 of 467.
	- Closed: 20261003-180637

- The Unicode research pipeline repeats expensive work per chunk. (Code review 20261004 item 31)
	- ID: 2026100413480031
	- Type: Enhancement
	- Status: Deferred
	- Priority: Low
	- Opened: 20261004-134800
	- Opened by: Code review 20261004
	- Target OS: Linux
	- Note: each filter call reparses `confusables.txt` and reloads four fonts, and the populate script runs all three filters on the same 683 chunks for each of three spreadsheets.
	- Note: reopen when the alphabet research is next run. These are one-off tools, so minutes of rework don't matter until then.
	- Origin: b3e719f and de93848, 2026-05. Not seen by an earlier round. Plausible, not timed.

## Old format

### Bugs

### Features and enhancements

### Done

#### Done - Bugs

- ✅ A build made from a clone reported the library's version instead of the tool's.
	- Cause: the package tag and the tool's tag land on the same commit, and the command that reads the newest tag picked the package one.
	- Fixed: that command now skips the package tags. Released builds were never affected, since the workflow passes the version in.
	- Verified: a fresh build reports the tool's version again.
	- Test case: `ErkSf4k` "--version is the command's tag, not the library's". Only a build from a clone can show it, and dev is such a commit today.

- ✅ Two kinds of config file mistake were accepted and then ignored.
	- Reproduced: a field written twice, and a field whose name is in quotes. Both loaded without complaint, and the base came out different from what the file said.
	- Cause: a field given more than once reads back as nothing at all, and the loader treated that as absent, falling back to a default. A quoted name was left out of the list the check walks, so a quoted misspelling was never seen.
	- Fixed: the check now walks the field names as written, keeping repeats, and refuses both. It names the base and the field.
	- Note: this is the third thing the config loader is strict about on purpose. A wrong alphabet produces output that looks perfectly fine, so a mistake has to be refused where it is written.
	- Verified: new tests for each field a repeat can hit and each shape a quoted name can take. All nine fail against the previous build.
	- Test case: `Em1008w` TestConfigRejectsRepeatedField and `Em1008x` TestConfigRejectsQuotedUnknownField; `Em1008v` and `Em1008u` in the harness.

- ✅ Slicing a value with a very large count crashed instead of clamping. (Code review 20260802 item 1)
	- Reproduced: asking for more symbols than the value holds is documented to clamp, and it does, until the count approaches the largest whole number the machine handles. Then it crashes.
	- Cause: the check added the start and the count together, and that sum wraps around to a negative number, so the too-long count read as short enough.
	- Fixed: the count is compared against how many symbols are left instead, which cannot wrap.
	- Note: reachable from the library and from a 32-bit build long before the limit, and not from the module, whose count is a smaller number.
	- Verified: a new test covers both ends, and the rest of the suite is unchanged.
	- Test case: `ElprYuW` TestSymbolSliceHugeCount.

- ✅ A wild fixed-width value from a host killed the module instead of being refused. (Code review 20260802 item 2)
	- Reproduced: asking the module to pad a value to the largest width its argument can express stops the module dead. The host gets a crash, not an error.
	- Cause: padding to a width allocates that many symbols, and the width had no upper limit. Running the module out of memory cannot be caught and recovered from.
	- Note: the conversion call already caps its precision for the same reason, so the two were inconsistent.
	- Fixed: width is capped at the same generous limit, and anything larger is refused. The fields this exists for are tens of symbols wide.
	- Verified: the host exerciser now asks for the largest possible width and requires a refusal. Confirmed to fail before the fix.
	- Test case: `Elmd2Y4` reactor ABI. Its host asks for the largest width and wants a refusal.

- ✅ Writing control characters by name got slower the longer the value was. (Code review 20260802 item 3)
	- Cause: one control character's name can run into the text after it, so each name is read back against what follows before it is written. That check was copying the whole rest of the value every time, which turns a long value into a lot of copying.
	- Fixed: only a name's worth of the following text can change how a name reads, so that is all the check looks at now.
	- Verified: cost now rises evenly with length instead of with its square. A 200 KB value went from about a third of a second to seven thousandths, and the gap widens from there. Output is unchanged, and the test covering every control against every character it can be followed by still passes.
	- Test case: `ErkSf4f` TestEscapeControlsIsLinear. It counts bytes allocated, since a timing check would be noise on a shared machine.

- ✅ The browser module reported a confusing error for a value that was not a real number. (Code review 20260802 item 4)
	- Cause: a number that is not finite was formatted as a word and then reported as an unrecognized digit. The precision setting already checked for this and the value did not.
	- Fixed: it is refused with a message that says what is wrong.
	- Test case: `ErkSf4h` TestConvertRefusesNonFinite, run under node by `ErkSf4j` "browser module tests".

- ✅ The fuzz stage failed a run with nothing but "context deadline exceeded".
	- Reproduced: intermittent, and only at the point where the run's time limit expires. No failing input was ever recorded, and the same target passes on a rerun.
	- Cause: two separate things. Go itself reports the time limit as the run's error when it reads one of its own cancellation signals a moment before that signal has propagated, so a clean finish is scored as a failure. Separately the run had slowed to a crawl by then, which is what made the timing gap easy to hit.
	- Fixed: the stage now fails only on a real find, which Go always names by writing the failing input to a file. A bare time-limit report is passed with a note.
	- Fixed: the slowdown had two causes of its own. Converting a number is quadratic in its length, so the fuzzer was spending a whole run on ever longer values that reached nothing new; values are now capped at a length that still reaches every branch. And Go's default budget for shrinking a new find is a minute, longer than the whole run, so a single find parked a worker for the remainder; that budget is now a small slice of the run.
	- Verified: three times as many cases per run on the number target and four times on the streaming one, with more new coverage found in every case, and no run stalls. The guard was checked against a real crash, a hang, and a bare time-limit report.
	- Test case: None. It is the pipeline reading a Go toolchain race, which can't be made to happen on demand. Checked by hand against a real crash, a hang and a bare deadline report.

- ✅ Wrapped base-45 would not decode.
	- Reproduced: encode to base 45, wrap the text at any width, decode it back, and the newline is reported as not a base-45 symbol. Every other base that carries raw bytes tolerates wraps.
	- Cause: base-45 has space as a digit, so it skipped no whitespace at all. CR and LF are not digits, so there was never a reason to include them in that.
	- Fixed: base-45 decoding drops CR and LF and nothing else. Space still means what it always did.
	- Test case: `El5P4dm` TestWrappedBinaryDecode, and `El5P4dk` "wrapped input decodes" over every raw base.

- ✅ Stale base names in the README table, the changelog, and the tests.
	- Cause: `64programmer`, `69nice`, and `69emoji` were renamed, and nothing checked that a documented name still resolves.
	- Fixed: names corrected, and the test suite now fails if any base named in the README table no longer resolves.
	- Test case: `ElWMN5U` "README bases table resolves".

- ✅ Piped input was ignored when a value was also given on the command line. (BxZNl-1)
	- Note: the command line still wins. Changing that would break scripts that pass a value while their input happens to be an inherited pipe, and could consume a pipe the tool should not touch.
	- Fixed: a pipe carrying data, plus a lone argument that names a known base, now prints a note pointing at the `-` form. The usage line was corrected to require `-` for reading a pipe.
	- Test case: `ErkSf4l` and `ErkSf4t`, for the note and for its absence.

- ✅ Custom alphabets where one symbol started another decoded wrong. (BxZNl-2)
	- Cause: reading left to right, the shorter symbol matched first and the rest of the longer one was read as separate digits.
	- Fixed: such an alphabet is now refused where it is defined. Only multi-character symbols can hit this, so no built-in base was affected.
	- Test case: `EjeDvPT` TestFinalizeRejections.

- ✅ A marker inside a multi-character digit corrupted parsing. (BxZNl-3)
	- Fixed: a base whose negative or decimal marker appears inside any digit is refused where it is defined.
	- Test case: `EjeDvPT` TestFinalizeRejections and `EjeFbjH` "spec marker-in-digit".

- ✅ Streaming encode treated a read error as the end of the input. (BxZNl-4)
	- Cause: any read failure finished the output as though the data had run out, so a truncated read produced a complete-looking result.
	- Fixed: a real read error is reported. Only a genuine end of input finishes the stream.
	- Test case: `ErkSf4b` TestStreamReadErrorIsReported, both directions on both streaming paths.

- ✅ Tab and newline escapes in symbol specs did nothing. (BxZNl-5)
	- Cause: they were expanded before the spec was split on whitespace, so they were consumed as separators.
	- Fixed: they are held aside during the split, the same way an escaped space already was.
	- Test case: The "bare tab escape" case in `Erg0gZ2` TestConfigBackslashLayers, and `EjeFbjG` "spec escaped-space digit".

- ✅ Decoding was stricter from a pipe than from an argument. (BxZNl-6)
	- Fixed: line breaks are tolerated either way, a digit after padding is refused either way, and base91 refuses junk instead of skipping it.
	- Test case: `Em1DQ5d` and `Em1DQ5e` for padding, `El5P4dk` for line breaks, and `ErkSf4e` "base91 refuses junk, argv and pipe".

- ✅ Fractional output was cut short instead of rounded. (BxZNl-7)
	- Fixed: the fraction rounds half up, and a carry rolls into the whole part. Converting `0.1` to another base and back is stable now.
	- Test case: `EjYV8Gm` "fractional rounding", `EjeFbjA`, and the rounding case in `EjeDvPM` TestNumberVectors.

- ✅ Tiny fractions printed as "0.000" or "-0.000". (BxZNl-8)
	- Fixed: a value smaller than one output digit rounds to nothing, so there is no invented zero fraction and no sign on it. Same rewrite as the item above.
	- Test case: `ErkSf4c` TestTinyFractionRoundsToZero.

- ✅ The version stamped into release builds was discarded. (BxZNl-9)
	- Cause: the version was a constant, and the linker can only patch a variable. The build flag looked right and did nothing.
	- Fixed: it is a variable.
	- Test case: `ErkSf4g` TestVersionIsPatchable. It builds the command with a stamp and reads it back.

- ✅ A config file that replaced a built-in base left the base list wrong. (BxZNl-10)
	- Fixed: a built-in that is fully replaced drops out of the list and the index, and only names that still resolve are shown.
	- Test case: `ErkSf4Z` TestConfigShadowedBuiltinDropsOut.

- ✅ A mistyped `--config` path was ignored instead of reported. (BxZNl-11)
	- Fixed: a config file named on the command line has to exist. The two paths nobody types stay optional.
	- Test case: `EjeFbjL` "explicit missing config errors".

- ✅ The check that a base alias is not a bare number was easy to slip past. (BxZNl-12)
	- Fixed: every alias is checked, not only the first, and against its normalized form.
	- Test case: `ErkSf4Y` TestRegisterChecksEveryNumericAlias.

- ✅ Comma-separated digits only worked in a single-token spec. (BxZNl-13)
	- Fixed: every token is split on commas, so `0,1 2 3` is four digits.
	- Test case: `EjeFbjF` "spec comma-split -> base4" and `EjeDvPS` TestSpecParser.

- ✅ An empty `pad:` in a config file could not switch padding off. (BxZNl-14)
	- Fixed: an empty value clears it. A separate field allows a pad that is accepted on input but never written.
	- Test case: `ErkSf4u` TestConfigPadFields.

- ✅ A reserved noncharacter in a spec silently became a space digit. (BxZNl-15)
	- Cause: those characters are used internally to hold escaped whitespace aside during the split.
	- Fixed: a spec containing one is refused up front.
	- Test case: `ErkSf4d` TestSpecRejectsNoncharacters.

#### Done - Features and enhancements

- ✅ Push the first `lib/v0.1.0` tag, so the Go module can be fetched.
	- Cause: nothing could import the package at any version, because the tag that addresses a module in a subdirectory had never been pushed.
	- Done: the tag ships with v3.0.0, alongside the command's own tag.
	- Note: a second project was waiting on it, and can drop its local path override.
	- Test case: None. It was a one-time release step.

- ✅ Say which line of a config file is wrong.
	- Cause: every complaint named the base and the field but not the line, so a long file had to be read through to find it. The parser could not place a field written twice, which is the mistake that most wants a line.
	- Done: the vendored parser moved up to its 1.2.0 release, which added the call that answers with every line a name was bound on.
	- Done: all eight ways a config file can be refused now cite a line, and a repeat names both the line it recurred on and the line it was first given.
	- Verified: a test pins the line for each of the eight, and the rest of the suite is unchanged.
	- Test case: `Em2MFrs` TestConfigErrorsCiteLines, plus the harness refusals that name a line, such as `ElHp3yZ` and `Erg4X7I`.

- ✅ Retire `2048tt`, and rebuild the family on code-point-ordered alphabets.
	- Cause: the alphabet was assembled out of code point order, so `2048tt` could not be corrected without leaving two different alphabets answering to one name.
	- Done: `2048tt` removed, and `2048tz` put in its place. The old alphabet is kept as a comment in `bases.go`, since builds carrying it did produce output.
	- Done: two ordered alphabets now, `534tt` without CJK and `2048tz` with it. They are identical for their first 384 symbols, so everything below 512 is one base under two names; `512tt` and `512tz` are separate; above 512 only `tz` continues.
	- Done: `256tt` and `512tt` write different digits as a result. `32tt`, `64tt`, and `128tt` are unchanged.
	- Done: `10blocks` is in code point order too. It is new in this release, so nothing was written with the earlier arrangement.
	- Done: the release is v3.0.0, since bases that shipped in a build now decode differently.
	- Fixed: the base 1024 block was named `1024tt` while drawing from the `tz` alphabet, which its own comment and the family rule both contradicted. It is `1024tz`.
	- Fixed: the two alphabets are equal through 384 symbols, not the 369 the comments claimed.
	- Verified: harness 426/426, unit tests, vet, and gofmt clean. Every base round-trips as a number and as a byte stream, and the README table was regenerated from the binary.
	- Test case: `ErkSf4W` TestTTFamilyOrdered: code point order, the shared 384, each size a prefix of its family, and `2048tt` gone.

- ✅ Cut and pad a value on symbol boundaries, for callers with fixed-width fields.
	- Done: two new calls on a base. One takes a range of symbols out of a value, the other fits a value to a width. Fitting left-fills with the base's own zero symbol and keeps the rightmost symbols when the value is too long.
	- Done: both count symbols rather than bytes, so a multi-byte alphabet works. Both refuse a sign, a decimal marker, or a digit the base does not carry.
	- Done: three matching reactor exports, including a combined convert-then-fit, since that is the pairing a caller asked for.
	- Done: the empty-result rule is now part of the reactor contract. A zero return with no error means an empty result, not a failure.
	- Verified: unit tests over single-byte and multi-byte bases, the host exerciser drives all three exports, full suite passes.
	- Test case: `ElpbexU` TestSymbolSlice, `ElpbexV` TestFit, and `Elmd2Y4` reactor ABI for the exports.

- ✅ For base "keyboard", allow encoding tab, newline, CR, etc.
	- Done: they can be written by name, as `⊳LF`, `⊳TAB`, `⊳CR`, and so on for every control character. Input takes named and raw forms mixed, in one value, always. Output writes them only when `--escape-controls` asks, so nothing that already reads that base's output changes.
	- Done: the marker is a character outside the range such a base draws its digits from, which is what settles the escape question. It can never be a digit, so there is nothing to escape twice and no recursion to bottom out.
	- Done: a word form for the ones people actually mean (`⊳NEWLINE`, `⊳TAB`, `⊳RETURN`), the shell-awkward printables (`⊳DQUOTE`, `⊳SQUOTE`, `⊳BACKSLASH`), and a hex form for anything at all. Names read either case.
	- Done: `--show-symbols --escape-controls` prints the alphabet legibly, which it could not do before.
	- Note: an escape naming something the base does not carry fails exactly as the raw character would, as an unrecognized digit. Asking for escaped output in byte mode is refused rather than accepted and ignored.
	- Note: the one thing that can go wrong is a name running into the text after it, since one control's name is the start of another's. Output checks each name against what follows and writes the hex form where the name would not survive. A test covers every control against every character it could be followed by, and was confirmed to catch the mistake before the real code went in.
	- Test case: `Elotfax` to `Elotfb2` in escapes_test.go, and `Elotfai` to `Elotfaw` in the harness.

- ✅ A WebAssembly reactor module, so other languages can call this instead of running it. Design: `design_docs/20260801_wasm_reactor.md`.
	- Done: the one-shot half. Conversion, base lookup, the radix and padding symbol of a base, symbol counting, the memory calls, a stable numeric error code set, and readable error text. The contract is written down beside the module.
	- Done: streaming, as the push API: open, write, finish, free, plus an open-stream counter. Streams run the library's own constant-memory paths; codec pairs buffer and emit at finish, same as the command.
	- Done: a host-side exerciser drives the whole contract each test run, including leak checks that must end with nothing left allocated and a memory ceiling that catches a stream quietly buffering.
	- Done: frontend parity in the test suite. The same requests run through the command, the Go module directly, and the reactor, and the answers must agree byte for byte over every base, both directions, errors included. Piped payloads run through the command and the reactor streams the same way. The compat and interop suites stay on the command; parity carries what they establish over to the other two.
	- The `go.mod` floor stays at 1.21. Only the toolchain building this one target has to be 1.24 or newer.
	- Test case: `Elmd2Y4` reactor ABI, `EloQXv8` "reactor answers match the command" and `EloQXv9` "stream parity".

- ✅ Library error text no longer names command-line flags.
	- Cause: messages like "see --list for all bases" came from the library, so a Go program or a browser page got advice about flags that do not exist there.
	- Fixed: the library states these conditions in neutral terms, and the command adds its own pointers on the way out. Four cases: an unknown base (the "did you mean" suggestions stay, since those help everywhere), a missing negative or decimal marker, a default marker that collides with a digit, and a retired marker token in a symbol spec. Each is a distinct error type, so any caller can recognize the condition and add advice in its own words.
	- Verified: the command's output is unchanged. Every affected error path was compared against the previous build character for character, including the wrapped forms, and the full test suite passes.
	- Note: this also sets up the planned WebAssembly reactor module, which wants to hand error text to a host program - that text now reads correctly outside a terminal.
	- Test case: `ErkSf4a` TestLibraryErrorsNameNoFlags.

- ✅ Speed-up and advanced conversion algorithms epic:
	- ✅ Say publicly which algorithms the number path uses, and what they are worth.
		- Cause: the three speed passes were recorded here in plain terms, but nothing outside the repo said what the method actually is. A claim of "fast" with no algorithm behind it is not worth much to anyone deciding whether to use this on a large value.
		- Done: the README speed section now splits into the streaming path and the number path, and the number path names its sources: Schonhage's divide and conquer radix conversion from Brent and Zimmermann, Karatsuba multiplication, Burnikel-Ziegler recursive division, and the classical sub-base packing from Knuth. Each gets a sentence on how it is used and what it is worth. Same citations added to the source and to the design notes.
		- Verified: measured fresh against a schoolbook implementation using the same arithmetic library on the same machine, from a thousand digits up to a million. Four times faster at the short end, three hundred and ten times at a million digits, where schoolbook takes a hundred and seven seconds and this takes a third of a second.
		- Verified: the exponent was fitted rather than assumed. Schoolbook measures 2.00, this measures 1.15 at the short end rising to 1.53 at the long end, which is the shape the method predicts.
		- Note: the underlying multiply and divide come from the standard library, which is stated plainly rather than implied to be ours.
		- Test case: None. It is README and design text. The speed claims come from benchmarks.
	- ✅ Speed up converting long numbers between two bases that are not powers of two. Third and last planned pass.
		- Cause: even with the earlier batching, every batch still took a pass over the whole number, so the total effort grew with the square of the length. That is the method's own cost, not an implementation detail.
		- Fixed: a long number is now split in half, each half converted on its own, and the two results joined with one wide multiply or divide. The halves split again in turn, down to a size where the earlier batch loop takes over. The joining steps ride on the arithmetic library's fast large-number multiply, so the whole thing finally grows a little faster than the length itself rather than its square.
		- Verified: a 16,000 digit conversion went from 2.8 to about 1 millisecond, a 64,000 digit one from an extrapolated 45 down to 6.5. A 160,000 digit number now converts through the command in under a tenth of a second, most of which is startup. Short numbers are unchanged.
		- Verified: across all three passes together, that same 16,000 digit conversion started at 251 milliseconds and 882 megabytes of scratch memory. It now takes 1 millisecond and about a megabyte, roughly 250 times faster. Doubling the length used to quadruple the time; now it roughly doubles it.
		- Verified: compared against the previous build across about 1,300 conversions at every length near a split seam, plus fractions, negatives, and both precision modes. All identical. Also checked against the standard library's own independent conversion for every base it can express, at every seam length.
		- Note: the split seams are the one place this can go wrong - a short lower half must keep its leading zeros - and a mistake there still looks like a plausible number. New tests pin every seam, and they were confirmed to catch both seeded mistakes before the real code went in.
		- Note: delegating half the work to the standard library was considered, measured as no faster end to end, and declined - one algorithm everywhere beats two things to get right.
		- Note: the fuzzing length cap rose from 256 to 1,024 digits now that long values are cheap, so fuzzing reaches the new seams too.
		- Test case: `ElmJ1ea` TestDivideConquerBoundaries. Speed itself is a benchmark, not a test, since timing is noise on a shared machine.
	- ✅ Speed up converting long numbers between two bases that are not powers of two. Second of three planned passes.
		- Cause: the number was read in one digit at a time and written out one digit at a time. Each of those steps costs a pass over the whole number, however long it is, so a short digit gets the same expensive treatment as the entire value.
		- Fixed: digits are now handled a batch at a time, as many as fit in one of the machine's own numbers. That is nineteen digits at once for base ten, twelve for base thirty-six, five for base 2048. The batch is assembled with ordinary arithmetic, which is free next to a pass over a long number.
		- Verified: a 16,000 digit conversion went from 29 to 2.8 milliseconds, so about ten times faster again. A 40,000 digit one went from a quarter of a second to seven hundredths. Shorter numbers gain about five times.
		- Verified: results were compared against the previous build across about 1,200 conversions covering every length near a batch boundary, plus fractions, negatives, and both fixed and automatic precision. All identical.
		- Note: two new tests pin the batch boundaries, one for whole numbers and one for fractions. That is the only place this could go wrong, and a wrong answer there would still look like a plausible number.
		- Note: one more pass is planned, changing the method itself rather than its cost per step.
		- Test case: `Elm99Wy` TestDigitChunkBoundaries and `Elm99Wz` TestFractionChunkBoundaries.
	- ✅ Speed up converting long numbers between two bases that are not powers of two. First of three planned passes.
		- Cause: each new digit of the answer was added to the front of a list. Everything already in the list has to shift along to make room, so the effort grows with the square of the answer's length. That was piled on top of the arithmetic, which is already the slow part for a long number.
		- Fixed: digits are now collected in the order the arithmetic hands them back, and the list is flipped around once at the end. Same answer, none of the shuffling. The list is also sized up front rather than being regrown as it fills.
		- Verified: a 16,000 digit conversion went from 251 to 29 milliseconds, and from 882 megabytes of scratch memory down to about one. Shorter numbers gain too, roughly four times faster at 1,000 digits.
		- Note: new benchmarks cover this path at three input lengths, because the cost curves upward rather than rising evenly, so one length would not show the shape. Run them with `go test -run x -bench Positional ./convertbase`.
		- Note: long numbers are still slower than they need to be. Two further passes are planned, one to cut the constant cost and one to change the method itself.
		- Test case: `EjeDvPV` TestRoundTripNumber and `EizUJEA` "oversized input round-trips". Speed is in the benchmarks.

- ✅ Animated gif demo: run the motion at 50 frames per second, and make the scroll and the cursor buttery smooth.
	- Done: every moving frame is now 20 ms. That is the fastest a gif can run, since browsers clamp shorter delays up to a tenth of a second. Motion used to sit at 80 ms.
	- Done: the scroll holds one constant velocity. Output lines are fed in against the scroll rather than each one settling to a stop first, which used to cost a short frame at every line boundary and read as judder once the frame rate was high enough to see it.
	- Done: the cursor eases between cells instead of jumping, and never overruns the keystroke it belongs to, so fast digits keep their pace.
	- Done: scrolling is 10 percent faster.
	- Done: a step whose output is taller than the window starts on a cleared screen, so a long list scrolls through once instead of first chasing the previous step's output off the top. Nothing types a clear command.
	- Done: gifsicle takes a lossless pass at the end when it is installed, which is worth about a sixth of the file. Pixels and timing come out identical. A machine without it just gets a bigger gif.
	- Note: the file still grows, from about five to about nine megabytes, and nearly all of that is the base list scrolling by. Its scroll rate is the lever if the size matters more than reading along with it.
	- Test case: None. The gif is demo media and is judged by eye.

- ✅ Animated gif demo: Come up with better examples and reencode.
	- Test case: None. Demo media.

- ✅ Let other programs use this as a library, not just as a command. Design: `design_docs/20260731_linkable_library.md`.
	- Done: Go package split, so the conversion core can be imported instead of shelled out to. Module path fixed at the same time, since nothing could fetch it before.
	- Done: the library is Apache-2.0, the command stays GPL-2.0-or-later. GPL reaches through a static link into the caller, and Go links statically only, so the split is what makes the package importable at all. Apache was picked for attribution: its notice file is what carries the credit into someone else's product.
	- Done: the Go tree moved to `lib/`, and the package carries its own version starting at v0.1.0. Go welds a module's major version into its import path above v1, so sharing the command's number would have meant every major release of the tool broke callers over a change that never touched the package.
	- Done: WebAssembly, two builds. The browser module is Apache-2.0 like the library, since it compiles into someone else's page; the WASI build is the whole command and stays GPL.
	- Done: a demo page that runs the library in the browser, published from `web/`.
	- Note: the demo page link needs Pages switched on in the repository settings before it resolves.
	- Note: a C shared library is no longer the obvious next step. WebAssembly reaches the same languages with no permanent ABI, no cgo, and no per-platform build, so the C interface waits for someone who specifically needs in-process native speed.
	- Note: an unreadable config file used to be fatal even for the path nobody types, which is what surfaced first under WebAssembly. Only "not there" was forgiven, so a sandbox reporting a different error killed every run.
	- Test case: `EloQXv6` "module answers match the command", and `ErkSf4j` "browser module tests". The license split has nothing to test.

- ✅ Test the four big bases against the implementations that defined them, instead of against vectors copied down by hand.
	- Done: qntm's base2048, base32768 and base65536, and LLFourn's separate base2048, are kept verbatim from their published releases under `cicd/utility/interop/thirdparty`, with the version, download and hash of each recorded next to them.
	- Done: the harness runs randomized bytes through both sides and checks three things per base. Our encoding matches theirs, we read back what they wrote, and they read back what we wrote. Crossing the outputs is the point: two implementations can share a misreading of the tail rules and agree with each other.
	- Done: sample lengths count up from zero before turning random, since every disagreement these bases have ever had was about the final partial chunk.
	- Done: an edited or missing reference fails the run. A reference that has been changed is worse than none, because everything would still pass, against something nobody published. A missing toolchain only warns, since that means the checks did not run rather than that they failed.
	- Verified: all four agree in all three directions. 370 checks, up from 357.
	- Test case: `EleGcFX`, `EleGcFU`, `EleGcFV` and `EleGcFW`.

- ✅ Make every `69emoji` digit a graphical emoji.
	- Cause: four of the sixty-nine were text-presentation by Unicode definition, so they drew as line art rather than color. One of those was also carrying a presentation selector to force the issue, which made it the only multi-codepoint digit in the base.
	- Fixed: scissors became crossed fingers, the heavy black heart became revolving hearts, the curving arrow became a rocket, and the bed became a person in bed. Alphabet re-sorted into code point order.
	- Verified: checked against `emoji-data.txt` from unicode.org, so the call is the Unicode property and not how one font happens to draw it.
	- Test case: `ErkSf4X` TestEmojiDigits. It has no copy of the Unicode data, so it checks one code point per digit, no selector or skin tone, and none of the four old ones.

- ✅ Trim the README bases table so it stops overflowing on GitHub.
	- Done: dropped the Description and Specification columns, renamed Chars to Char count, added UTF-8 byte count next to it, and renamed Number representation to Output.
	- Done: the example number is now `-86434491232548995369.314`, dropping to the bare integer `86434491232548995369` for the nine alphabets that use every candidate character as a digit and so carry no negative or decimal marker.
	- Done: long output values wrap. Line count is picked from an estimated rendered width, counting a double-width character as two, so a CJK or emoji row ends up about as wide as a Latin one instead of twice as wide. Widest cell went from 101 to 28.
	- Done: the generator is `utility/gen-bases-table.py`, replacing the stale `gen-example-table.bash`, which still produced the old three-column table. It also emits the `bytes` row, which used to be added by hand.
	- Done: narrowed again, since the widest rows still ran off the page. Target width dropped from thirty to twenty, and a digit above the basic plane counts as double width now, which is what `10rods` and `20mayan` needed. Nothing has a rendered width over twenty.
	- Done: the table reads the shipped config, so `10emoji` is listed alongside the built-ins. A fresh install has it, so leaving it out was misleading. Pass `--config /dev/null` for built-ins only.
	- Done: `64emoji` shows the signed fractional form now that it carries the markers.
	- Test case: None. The table is generated. `ElWMN5U` keeps its names resolving.

- ✅ Rationalize base names and aliases, per `design_docs/20260730_base_naming.md`.
	- Done: one scheme now - lowercase, radix first, at most four aliases in a fixed order, bare numbers only where unambiguous. Every v1/v1b name still resolves; dropped spellings error with a near-match suggestion.
	- Done: legacy maps in test.bash fixed (`code64` had gone stale) and moved to the new canonical names; README bases table rebuilt from the binary, now with a single First alias column; examples, changelog, and demo scenario updated.
	- Verified: 356/356 harness checks, including both legacy cross-check suites.
	- Test case: `ElXEFcO` TestLegacyAliasesArePreserved, the v1 and v1b checks, and `Eje7f0i` "unknown base near-match".

- ✅ Cover the added and renamed power-of-2 bases in the tests, and cross-check the compatibility bases against both older tools.
	- Cause: the test lists named bases by hand, so a base added or renamed after they were written was simply never tested. `64tt` and `256tt` were missing from the length sweeps, and the rename to `code64` had already broken the cross-checks against both older tools.
	- Fixed: the power-of-2 and raw base lists now come from `--list`, and the equivalence test reads them from the registry. Adding or renaming a base needs no test edit.
	- Fixed: the memory ceiling, which is the only check that catches a base quietly falling back to buffering, now covers every power-of-2 base instead of five of them.
	- Fixed: wrapped-input decoding is checked on every base that carries raw bytes, not seven of them.
	- Done: a base each older tool shares is checked against both, one only a single tool has is checked against that one, and every output base either tool offers must be mapped or listed as excused.
	- Done: a missing older script skips its suite and warns, and the summary repeats the warning so it can't read as a pass.
	- Verified: 389 checks pass, and both the coverage guard and the skip path were exercised on purpose.
	- Test case: The scrape floors `EjeFbjM`, `ElWMN5V` and `EjeFbjN`, coverage `ElWMN5X` and `ElWMN5Y`, and `El5P4dl` "constant memory".

- ✅ Hold the alias notes in `bases.go` to the alias lists, and settle the two older bases that have no counterpart here.
	- Note: `bases.go` marks each alias the older tools call, and says which tool needs it. Nothing read those notes, so a rename could drop one and only the older tools would notice.
	- Done: a test reads those notes and checks each named alias is still on the base it sits on, and still resolves. Eighteen of them.
	- Done: every alphabet either older tool offers was walked symbol by symbol against every base here, which confirmed all the cross-check pairings and turned up exactly two with no counterpart: v1's 38-symbol username and v1's hex-ordered base 64. Both are permanent, so they are recorded as excused and named in the passing line rather than reported as a problem every run.
	- Test case: `ElXEFcO` TestLegacyAliasesArePreserved, and `ElWMN5X` names the two excused bases.

- ✅ Pin the vendored SHCL binding to an upstream release and check it on every pipeline run.
	- Note: SHCL reached v1.0.0, so the question was whether to depend on it as a Go module instead of keeping the copy.
	- Done: kept the copy. It leaves the program at standard library plus its own source, and upstream declares a higher `go` version than this project needs.
	- Done: the pin lives in `cicd/vendor-pins.env`; the check compares the local file against that tag before anything is built.
	- Note: a copy that no longer matches its tag stops the pipeline, since lint skips vendored paths and a parser reading an alphabet slightly wrong still produces output that looks fine. A newer upstream release is only a notice.
	- Verified: match, edited copy, missing file, wrong tag, and no network all behave as intended.
	- Test case: No ID. `check-vendor.bash` is a gate that runs before every pipeline build.

- ✅ Switch the config engine from YAML to SHCL, create a user config on first run, and move `emoji10` into it as the worked example.
	- Note: SHCL comes as one drop-in source file per language, so its Go binding is copied verbatim into `lib/shcl/`. That leaves the program with no external dependencies at all, since YAML was the last one.
	- Note: a base is now a named block (`base: hex`) with an optional `aliases:` field, instead of a list entry whose first alias was the canonical name.
	- Note: SHCL distinguishes a missing field from an empty one, which is exactly the tri-state the markers already used, so an empty `negative:` still means "switched off on purpose".
	- Note: the default config is embedded in the binary and written on first run, so the shipped example and the file people edit cannot drift apart. `example.conf` is gone.
	- Note: an unknown field is now an error. A typo that silently dropped a marker would give a wrong alphabet, and no output would ever reveal it.
	- Verified: harness at 306 checks, including both list spellings, an alias, a disabled marker, a symbol carrying a space, two rejected typos, and the first-run creation itself.
	- Test case: The config section, `EjeFbjJ` to `EjeFbjL` and `ElHp3yS` to `ElHp3yZ`, plus `ElHp3ya` "first run creates the user config" and `ElczR2W`.

- ✅ Base set overhaul: bases and aliases added, renamed, and removed, and the v1/v1b compatibility bases split out into their own group.
	- Note: `Base.Compat` marks them; `--list` skips them and the new `--list-compat` shows only them. Both listings stay contiguous because compatibility bases sort last, so `--by-index` still reaches every base.
	- Verified: every compatibility alphabet matches the bundled `convert-base-v1` and `convert-base-v1b` scripts symbol for symbol, and the harness now cross-checks against both binaries instead of just v1b.
	- Fixed: `69emoji` was one emoji short, with a stray presentation selector standing in as an invisible digit.
	- Note: three legacy bases are left uncovered on purpose. Two have no counterpart here, and the third differs only in case.
	- Test case: `ElG9gVM`, `ElG9gVN`, `ElG9gVO` and `ElG9gVP`, and the v1 and v1b checks `ElG9gVS`, `ElG9gVT`, `Ej0q2ga` and `Ej0q2gb`.

- ✅ Document the shell aliases that keep binary mode and number mode apart.
	- Done: added to the end of the README Usage section, right after the help pointer, so it reads as a follow-on to the examples.
	- Verified: both aliases do what the note says. `--binary` encodes and round-trips through base 64, `--number` converts positionally and silences the mode note.
	- Test case: None. Docs only.

- ✅ Stream binary encode and decode for the multi-byte bases, not just the single-character ones.
	- Cause: the tuned path is a byte-table design end to end, so it can only hold one-byte digits. Everything else buffered the whole input and the whole output.
	- Done: a second streaming path for digits that are one character but several bytes, covering the bases above 8 bits per digit as well. The tuned path is untouched.
	- Done: `512tt`, `1024tt`, and `2048tt` gained a tail character, which is what let them stream; their binary layout changed and none had shipped.
	- Verified: peak memory is flat near 20 MB for every base. Encoding 48 MB to `emoji64` went from 1.2 GB to 20 MB, decoding `128tt` from 753 MB to 21 MB and about three times faster.
	- Verified: 625 streamed-against-buffered comparisons, 121000 fuzz round-trips, harness at 252 checks including a peak-memory ceiling per base.
	- Done: closed the last gap with a `tail:` config field and `--from-tail`/`--to-tail` flags, so a base of your own above 8 bits can stream too. A 24 MB encode drops from 244 MB to 21 MB. Without a tail the length-prefixed layout still works, so nothing had to change.
	- Verified: round-trips at every awkward length on both layouts, the width and overlap guards reject a tail that could never be used, and the config and flag forms agree.
	- Test case: `El5P4dl` "constant memory", `EjeDvPU` TestStreamBufferedEquivalence, `El5mcJr` TestUserDefinedTail, `El5mcJt` TestTailValidation, and `El5mcJk` to `El5mcJq`.

- ✅ User-defined alphabets:
	- Need flags to define negative, decimal, and pad - not all in one string.
	- Ditto for config definitions.
	- Done. Six flags: `--from-neg`/`--from-dec`/`--from-pad` and the `--to-` three. An empty value disables a marker, an omitted flag changes nothing.
	- Markers now work on named bases too, not just custom alphabets. `--from hex --from-neg '~'` reads `~ff` as -255.
	- A symbol spec is digits only. Config files keep their `negative:`, `decimal:` and `pad:` fields, and the in-string form is gone from both.
	- The retired `neg=`/`dec=`/`pad=` tokens are a hard error naming the replacement, so a stale spec can't quietly turn one into a digit and shift the alphabet.
	- Designed in `design_docs/20260725_neg_dec_pad_config_cli.md`.
	- Test case: `El4bQKu` to `El4bQL0` in the harness, `El4bQL1` TestRetiredMarkerTokensRejected and `El4bQL2` TestApplyMarkers.

- ✅ Design new bases (all just shorter versions of the `tt` alphabet, which starts with base 62h):
	- ✅ Blocks: ▁ ▂ ▃ ▄ ▅ ▆ ▇ █ ▒ ▓
	- ✅ 512tt
		0 1 2 3 4 5 6 7 8 9 A B C D E F G H I J K L M N O P Q R S T U V W X Y Z a b c d e f g h i j k l m n o p q r s t u v w x y z ¡ ¢ £ ¤ ¥ § © « ® ° ± µ · » ¿ Ø Þ ß æ ð ÷ ø þ ŋ ƅ Ɔ ƌ ƒ ƨ Ʊ ƶ ƹ ƾ ǂ ǝ ȸ ȹ ɀ Ʌ ɐ ɒ ɔ ɘ ə ɛ ɞ ɤ ɥ ɮ ɷ ɸ ɹ ʁ ʃ ʅ ʇ ʉ ʊ ʌ ʎ ʘ ʚ ʞ ʬ ʭ ͳ ͷ ͼ ͽ Δ Ω α δ ζ θ λ μ ξ π φ ψ ω ϑ ϕ ϖ ϝ ϟ Ϡ ϡ ϣ ϥ ϧ ϩ ϰ ϱ ϵ ϶ ϸ Ͻ Ͼ Ͽ ж л п я ѧ ѳ ҂ ҩ ԃ ԅ ԉ ԋ ԏ թ ժ ի կ ձ ճ մ ն չ պ վ ր ֏ ۲ ۳ ۴ ۶ ۸ ५ ६ ७ ८ ଌ ୧ ୫ ୬ ୯ ఠ వ ก ข ค ฅ ฆ ง จ ฉ ช ถ ท ธ ป ร ฤ ล ฦ ว ศ ษ ส ห อ ฮ ฯ ะ า ๑ ๓ ๖ ๙ ა ბ გ დ ე თ ი კ ლ ჟ რ ს ტ უ ფ ქ ღ ყ შ ჩ ც წ ჭ ჯ ჰ ჲ ჵ ჶ ჸ ჹ ჺ ዓ ዖ ዛ ዞ የ ዶ ገ ጌ ግ ጎ ጓ ጻ ጾ ፀ ህ ለ ላ ል ረ ሪ ሬ ር ስ ባ ቦ ኣ ኦ ካ ኮ ᚠ ᚢ ᚣ ᚦ ᚨ ᚬ ᚭ ᚮ ᚯ ᚳ ᚴ ᚸ ᚻ ᚼ ᚾ ᚿ ᛃ ᛄ ᛅ ᛆ ᛇ ᛉ ᛋ ᛎ ᛏ ᛓ ᛔ ᛗ ᛘ ᛚ ᛛ ᛜ ᛝ ᛟ ᛠ ᛡ ᛢ ᛣ ᛦ ᛨ ᛩ ᛪ ᛮ ᛯ ᛳ ᛶ ᛷ ᛸ ᥛ ᥝ ᥢ ᥰ ᥳ ᨑ ᲆ ᲇ ᲈ ᴈ ᴉ ᴎ ᴐ ᴒ ᴖ ᴗ ᴙ ᴚ ᴝ ᴟ ᴤ ᴧ ᴨ ᴫ ᵷ ẟ • ‣ ₢ ₣ ₤ € ₶ ₺ ℈ ℧ ℶ ℸ ⅃ ⅄ ⅋ ⅎ ↊ ↋ ← ↑ → ↓ ∂ ∃ ∆ ∇ ∋ ∩ ∻ ≈ ⊲ ⊳ ⋏ ⌂ ⌔ ⍢ ⍨ ⟂ ⟅ ⟠ ⦁ ⦂ ⦅ ⦛ ⦠ ⧎ ⧖ ぁ ぅ ぇ ぉ か こ さ す そ ち て と ひ ま め ゃ ゅ ょ り ゐ ゑ を ゕ ゖ ァ ゥ ォ カ キ ク ケ サ シ ス セ ソ タ チ ッ テ ヌ ネ ホ ャ ン ヵ ㄅ ㄆ ㄉ ㄊ ㄌ ㄓ ㄔ ㄘ ㄛ ㄝ ㄞ ㄠ ㄡ ㄤ ㅅ ㅈ ㅊ ㅍ ㅎ ㆄ ꓕ ꓘ ꓛ ꓞ ꓤ ꓥ ꓨ ꓩ ꓭ ꓱ ꓵ ꓶ 𐀀 𐀁 𐀂 𐀈 𐀍 𐀑 𐀒 𐀓 𐀔 𐀕 𐀖 𐀗 𐀘 𐀙 𐀚 𐀛 𐀣
			- After exhaustive exercise (basically following "how to design a new base").
	- ✅ 256tt
	- ✅ 128tt
	- ✅ 64tt
	- ✅ 32tt
	- Test case: `ErkSf4W` TestTTFamilyOrdered, `EizUJED` "all-base matrix" and `ElWMN5W` "binary round-trip".

- ✅ Automatic fractional precision.
	- Done: `--precision` defaults to `auto`, which sizes the output fraction to the input's own precision instead of always stretching to fifty digits. A short decimal input no longer grows an invented tail in another base.
	- Done: `--precision N` still forces a fixed count, for padded or lossless round-trip output.
	- Note: automatic round-trips are lossy by design, since each hop keeps only the digits the input justified.
	- Test case: `Ejlud4y` to `Ejlud55` in the harness, and `Ejlud57` TestAutoPrecision.

- ✅ CI/CD improvements. The v1.1.0-beta7 release was cut by the new flow itself.
	- ✅ Minimal hosted CI: `.github/workflows/ci.yml` vets, tests, and builds on every push and PR to dev and main. The full local pipeline is unchanged.
	- ✅ Dev branch + release on main: `dev` is now the integration branch and `main` is release-only. Merging dev to main tags the version from `source/main.go` (if that tag doesn't exist yet) and publishes the release automatically; a merge without a version bump is a no-op. Flow documented in `design.md`.
	- ✅ goreleaser packaging: superseded 20260712. Replaced by self-contained `cicd/utility/package.bash` (tarballs/zips, `.deb`/`.rpm` via nfpm, Windows installers via makensis, checksums) run by both `make release` and the workflow; goreleaser and `.goreleaser.yaml` retired. See `design.md`.
	- ✅ Full release packaging + build split + main guard (20260712): packages every platform for both arches (adds freebsd, deb/rpm, Windows installers); split debug (test/profile) vs optimized (dogfood) native builds; main merge now hard-fails via `check-release.bash` unless the version was bumped and the Lifecycle badge matches.
	- ✅ Pinned tool versions + dependabot: pins live in `cicd/tool-versions.env` (the pipeline installs anything missing or drifted before stage 1); dependabot files grouped weekly update PRs against dev.
	- ✅ README badges: dynamic Go version, CI status, and latest release, replacing the static Go and Status badges.
	- Test case: None. It is the pipeline. `check-release.bash` guards the main merge.

- ✅ Some hosted or hook-based CI gate. (BxZNl-24)
	- Note: deferred at first. Nothing ran unless the pipeline was invoked by hand, and `make test` already covered the real logic locally.
	- Done: a hosted workflow now vets, tests, and builds on every push and pull request to the two long-lived branches. It is a safety net only; the full pipeline stays local.
	- Test case: None. It is the CI.

- ✅ Docs accuracy sweep. (BxZNl-26)
	- Done: the README bases table was rebuilt from the program, matching rows by alphabet, so two swapped rows corrected themselves and every alias listed resolves.
	- Fixed: the serial number example named the wrong base, one example output row was stale, and one example used a base name that no longer existed.
	- Fixed: the byte-count table for UTF-16 and UTF-32 was wrong in the companion document, a config claim about disabling a marker was wrong, and one config field was undocumented.
	- Fixed: year typos in the changelog.
	- Test case: `ElWMN5U`. The rest was doc text.

- ✅ Closed the blind spots in the test suite. (BxZNl-23)
	- Cause: several bases were only ever checked against themselves, so a round trip could be wrong in both directions and still pass.
	- Done: known values pinned for those bases, plus more fractional cases, config file loading, alphabet parser edge cases, and a symbol count pin.
	- Done: minimum counts on the base listings, so a listing that quietly shrinks fails.
	- Done: a missing older reference script now reports as skipped instead of passing quietly.
	- Test case: The pins `EjeFbjB` to `EjeFbjE`, `ElG9gVQ` and `ElG9gVR`, the scrape floors, and `ElG9gVM`.

- ✅ Two binary paths kept separate but pinned, rather than merged. (BxZNl-25)
	- Note: streaming and buffered conversion are different jobs with different costs, and the fast streaming path was hard won. Merging them was judged the wrong move.
	- Done: the two are held together by an equivalence test instead, which fails if they ever disagree.
	- Test case: `EjeDvPU` TestStreamBufferedEquivalence.

- ✅ Real unit tests, so `make test` covers the conversion logic instead of running only benchmarks. (BxZNl-22)
	- Done: fixed values for signs, fractions, leading zeros and rounding, the codec and big-base reference values, padding, the asymmetric Crockford rule, custom alphabets and markers, and the cases that should be refused.
	- Done: the streaming-against-buffered equivalence test, which is the one that matters most. It compares both paths byte for byte across every power-of-two base at many lengths.
	- Test case: The Go tests themselves, `EjeDvPM` to `EjeDvPV` first.

- ✅ Padding settled: it depends on the mode, not on the base. (BxZNl-20)
	- Done: number output is never padded. Binary-to-text output pads every RFC 4648 variant to the group boundary, which is what the strict standard decoders expect.
	- Done: decoding stays lenient, and takes padded or unpadded input either way.
	- Test case: `EjGXlOS` to `EjGXlOZ` and `EjeCdXk` to `EjeCdXn`, `EjeCdXo` "base64url number unpadded" and `EjeDvPP` TestRFCPaddingVectors.

- ✅ `--list` now has a leading INDEX column (the value `--by-index` takes), and `--by-index` outside a query prints a stderr note that it is ignored. (BxZNl-19) Help wording for `--by-index` now points at the INDEX column instead of a fragile "above".
	- Test case: `EjeBOHQ`, `EjeBOHR` and `EjeBOHS`.

- ✅ `--help` and `--examples` now write to stdout when explicitly requested, so `--help | less` works. (BxZNl-18) The no-args error path keeps help on stderr (exit 2, clean stdout). Threaded a writer through printHelp/printExamples/printCopyright.
	- Test case: `Eje9ui0`, `Eje9ui1` and `Eje9ui2`.

- ✅ Conflicting base selectors now emit a stderr note instead of silently picking one. (BxZNl-17) `--from-symbols` over `--from`, `--to-symbols` over any output name, and `--to` over a positional OUTBASE. A `--to` and positional that name the same base stay quiet. Behavior unchanged (note only), matching the BxZNl-1 approach.
	- Test case: `Eje8sS8`, `Eje8sS9` and `Eje8sSA`.

- ✅ Friendlier messages for the four common stumbles. (BxZNl-16) Flags after the NUMBER now say flags come first; a bare `-123` points at the `--` separator; an unknown flag points at `--help`; an unknown base points at `--list` and suggests near matches (prefix or small edit distance, closest tier only). Flag parsing moved to ContinueOnError so these can be caught.
	- Test case: `Eje7f0i` to `Eje7f0m`.

- ✅ Crockford base 32 now follows its own asymmetric rule. (BxZNl-21)
	- Done: on input it reads O as zero and I or L as one, in either case. Output stays strict.
	- Done: this needed a general input-only alias mechanism on a base, which any base can now use.
	- Test case: `Eje5hGK` to `Eje5hGP`, and `EjeDvPQ` TestCrockfordAsymmetric.

- ✅ Allow any base to be prefaced with "base", "base-", or "base_", and still work. (github #8)
	- Test case: `EjUSzQO` to `EjUSzQT`.

- ✅ `--show-symbols` should list with no delimiters. (Currently lists with newline in between each.) #1n4xq9d
	- Now concatenated with a single trailing newline. Added `--show-symbols-0` (NUL-separated) so scripts can still split multi-char symbols; fuzz harness uses it.
	- Test case: `EjUH4Lo`. The NUL form is read by `EjeFbjI` and the symbol fuzz.

- ✅ Added a `--upper` flag, the opposite of `--lower`. Uppercases text output, and like `--lower` errors on a mixed-case output base (where changing case would collide two distinct digits). The two flags reject each other.
	- Test case: `ErkSf4m`, `ErkSf4n` and `ErkSf4o`, plus `Em1DQ5Z` for markers.

- ✅ Byte-mode re-encoding between text bases. Two power-of-2 text bases (e.g. hex and base-64) used to convert only as a positional number, which silently drops leading zeros and is not a byte re-encoding.
	- Now `--binary` (`--bin`, `-b`) re-encodes them as byte data the way `basenc` does, by routing through the raw-byte base; piped input streams.
	- `--number` (`--num`, `-N`) asserts the numeric reading.
	- With neither flag, a power-of-2 text-to-text conversion prints a note on stderr so the ambiguity is no longer silent.
	- Test case: The --binary section, `EjU6h0i` to `EjU6h0s`.

- ✅ Renamed the 256-value raw-byte base to `bytes` and dropped its `binary`/`bin`/`raw` aliases, so the base name no longer collides with the new `--binary` mode flag (and "binary" no longer misleadingly names the byte base rather than base-2).
	- Test case: `ErkSf4p` "retired byte-base names do not resolve".

- ✅ Renamed the `--raw` output flag to `--no-newline` (`-n`), matching `echo -n`; its old name was unclear and overlapped the raw-byte base.
	- Test case: `EjTpGMi`, and `ErkSf4q` "--raw is not a flag".

- ✅ Raw binary conversion now covers, besides the powers of two, the defined streaming binary-to-text codecs: base45, Ascii85, Z85, and base91, each implemented per its official spec.
	- Any other non-2^N base has no byte-exact mapping and is refused in binary mode.
	- `--list` shows which bases qualify (RAW column). (An earlier attempt to make every base work via whole-value base-x was reverted in favor of this, since a positional whole-value encoding isn't what a streaming codec means.)
	- Test case: `EjK8KIi` "raw round-trip", the codec vectors `EjK8KIk` to `EjK8KIp`, and `EjK8KIj` for the refusals.

- ✅ Screenshots retired. The README no longer shows them and the CICD stage is off by default; the generator is kept so they can be made again if wanted. Dropped the orphaned image files.
	- Test case: None. A pipeline setting.

- ✅ Rigorous CICD testing. Raw round-trips now cover every base (not just powers of two) at lengths that force padding, with fixed base-x vectors pinning the leading-zero convention. Added a resource profile (peak memory and wall time) and a base-x timing guard, both skipped by `--quick`.
	- Test case: `EjK8KIi`, plus `EjGnHfk` and `EjK8KIq` on runs with the performance section.

- ✅ Create a new base that covers all possible printable keyboard characters in a plain text document. (Including programming code, regular human writing, email addresses, newline, return, tab, etc.)
	- Without worrying about higher unicode alternatives (e.g. curly-quotes, mdash, etc.) - those would have to go through some separate conversion preprocessing in order to work with this base. I believe this should also covers Rich-Text format (which I believe has no special characters), MD, HTML, XML, JSON, embedded base64, etc., as-is.
	- Test case: `EjGqhx2` and `EjGqhx3`.

- ✅ Create a base64 that's all emojis
	- Only emojis noted/suggested by unicode to print graphically.
	- Symbols in LANG=C order.
	- Use generic yellow emojis for skintone-based ones, not skin-tone variants.
	- Skip emojis that look too similar; use only the first one.
	- Test case: `ErkSf4X` TestEmojiDigits for the order and the single code points.

- ✅ Improve the performance of streaming binary-to-text conversion and vice-versa, to better approach existing linux utilities. Go should be able to get close.
	- Test case: `EjGnHfk` "perf" and `El5P4dl` "constant memory". The throughput number is information, not a pass mark.

- ✅ An optional padding scheme for custom bases (not necessarily `===`). The published big bases and the RFC base32/base64 bases already pad correctly; this is about letting user-defined bases opt into padding too.
	- Test case: `EjGkfrU` to `EjGkfrX`.

- ✅ Update comments in code, help output, readme.md, and design.md to properly use "radix" and/or "base" in context, etc. But not the actual program interface, don't change that.
	- Test case: None. Wording only.

- ✅ Base64 (RFC 4648 s4) and base32 (RFC 4648 s6) binary output is now padded with `=` to the standard group boundary, matching the RFC test vectors. The URL and hex variants stay unpadded, and decoding accepts input with or without padding.
	- Test case: `EjGXlOS` to `EjGXlOZ` and `EjeCdXk` to `EjeCdXn`, and `EjeDvPP` TestRFCPaddingVectors.

- ✅ Binary conversions to the big published bases (both base 2048's, 32768, 65536) round-trip at any input length and match the reference encoders byte-for-byte, using each one's own secondary alphabet for the final partial chunk. Odd-length tails no longer come back a byte long. Fixed vectors from the reference implementations guard the interop.
	- Test case: `EjGTP6O` to `EjGTP6b`, and the interop checks.

- ✅ Bases with '-' in the symbol set now use '~' as the negative marker instead of the en-dash. '~' was free in all four affected bases (45, 64u, 64h, 69prsh).
	- Test case: `ErkSf4r` "a dash digit is never the negative marker", over every base.

- ✅ Help: clarified the text for the index-related flags (`--get-index-count`, `--get-base-name`, `--show-symbols`, `--by-index`).
	- Test case: None. Wording only.

- ✅ `--list`: the NAME is no longer repeated in the ALIASES column.
	- Test case: `ErkSf4s` "--list ALIASES never repeats the NAME".

### Deferred

### Canceled

- 🚫 Backwards compatible base '128v1compat' may have a subtly incorrect alphabet definition. (github #1)
	- Cause: the v1 base-128 definition is a "word-safe" version, which base 256 and 288 are not. Base 128 should have been a subset of 256. When writing v2, an incorrect assumption was made about the base-128 structure instead of copying v1 verbatim. Because 128 is a power of two, the difference could be as small as a single character in some binary encodings.
	- Verified: compared v2 against the bundled v1b for all 128 values. `128v1compat` and `128jc1` are byte-for-byte identical to v1b, and the v1 cross-check passes.
	- Note: cannot confirm any discrepancy without the original v1 (not v1b) alphabet, and changing it now would break the verified v1b compatibility.

## Template

### Old format

- 🔘 Not started

- 🛠️ Started, and/or partially complete

- 🔬 Testing not started or finished

- ✋ Defer

- ✅ Complete

- 🚫 Canceled

### New format

- Notes:

	- Only use rows that you actually need or expect will be filled in. Always fill in the title, ID, Type, Status, Opened and Created by.

	- The ID is the local time to the hundredth of a second. Opened is when it was written down, which may differ. (Use a keyboard macro and possibly something like project 'zuid' to generate.)

	- Status values meaning: Testing means the fix is in and checks are running or still to run. Waiting on signoff means automated testing passed. Moot means something else changed that made it irrelevant. Canceled means it still applies but was decided against. Waiting for testing means the fix is in and waits on a long CI run or an outside test host. Can't reproduce means a real attempt to reproduce it failed.

	- As issues are worked, and statuses change, place them in correct sorting order within the list:
		- First by status: Waiting for answers, Waiting on signoff, Testing, Waiting for testing, Can't reproduce, Stalled, Started, Queued, Done, Deferred, Canceled, Moot
		- Then by severity|priority: Critical, High, Avg, Low
		- Then by type: Bugs, [not bugs together]

	- Rows marked [Bug] are for bugs only, and rows marked [Feature] for features and enhancements. Priority and Severity share one row and one scale. Priority is for a Feature or Enhancement, and Severity for a Bug. Children are not nested. They sit at the top level and point back with Parent ID.

Template:

- Title
	- ID: YYYYmmDDHHMMSSNN
	- Type: [Bug|Feature|Enhancement|Task]
	- Status: [Queued|Waiting for answers|Waiting on signoff|Waiting for testing|Started|Testing|Stalled|Can't reproduce|Moot|Canceled|Deferred|Done]
	- Needs local test suite run?:
	- Needs external testing:
	- Priority [Feature|Enhancement] | Severity [Bug]: [Critical|High|Avg|Low]
	- Opened:
	- Opened by:
	- Assigned to:
	- Parent ID:
	- Prereq IDs:
	- Related IDs:
	- Target OS:
	- Test environment:
	- Version and build:
	- Requirements  [Feature]:
		- Hierarchical bulleted list.
	- Steps to reproduce [Bug]:
		- …
	- Incorrect behavior [Bug]:
	- Expected behavior [Bug]:
	- Reproduced [Bug]: [No, or when, where and how]
	- Possible cause [Bug]:
	- Actual cause [Bug]:
		- …
	- Estimated effort: [High|Avg|Low]
	- Actual effort: [High|Avg|Low]
	- Progress log:
		- …
	- Decisions:
		- …
	- Actual fix [Bug]:
	- Branch:
	- Commit:
	- Test case: [Reason not applicable, or CI test case #]
	- Acceptance signoff:
	- Superseded by ID:
	- Closed:
