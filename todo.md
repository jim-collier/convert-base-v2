<!-- markdownlint-disable MD007 -- Unordered list indentation -->
<!-- markdownlint-disable MD010 -- No hard tabs -->
<!-- markdownlint-disable MD033 -- No inline html -->
<!-- markdownlint-disable MD055 -- Table pipe style [Expected: leading_and_trailing; Actual: leading_only; Missing trailing pipe] -->
<!-- markdownlint-disable MD041 -- First line in a file should be a top-level heading -->
# To-do

This is an easier way to brainstorm and prioritize tasks, before creating issues for them (if at all). Also allows for more fields and easier prioritization.

<!-- TOC ignore:true -->
## Table of contents

<!-- TOC -->

- [Column headings defined](#column-headings-defined)
- [Status: Staged](#status-staged)
- [Status: Started](#status-started)
- [Status: Canceled, moot](#status-canceled-moot)
- [Status: Done](#status-done)

<!-- /TOC -->

## Column headings defined

| Abbreviation | Full name or description     | Values
| :--          | :--                          | :--
| Score        | Average of next 4 values     | Floating point, lower=higher priority
| Imp          | Importance                   | 1=highest, 3=default, 5=lowest
| Urg          | Urgency                      | 1=highest, 3=default, 5=lowest
| Eff          | Estimated effort             | 1=quickest, 3=default, 5=maximum effort
| Aff          | Actual effort in retrospect  | 1=quickest, 3=default, 5=maximum effort

## Status: Staged

| Created  |Issue#|Score|Imp|Urg|Eff|Aff| Started  | by | Completed | Description | Notes
| :------  | :--- | --: |--:|--:|--:|--:| :------  |:---| :-------- | :---------- | :----
| 20260511 |      |     | 4 | 4 |   | 4 |          |    |           | Update "How to design a base" from detailed notes file
| 20260711 |      |     | 4 | 4 | 1 |   |          |    |           | Decide whether README should embed assets/demo.gif | One image line; the gif already regenerates on each full cicd run
<!--
| 2026     |      |     |   |   |   |   |          |    |           |
-->

## Status: Started

| Created  |Issue#|Score|Imp|Urg|Eff|Aff| Started  | by | Completed | Description | Notes
| :------  | :--- | --: |--:|--:|--:|--:| :------  |:---| :-------- | :---------- | :----

## Status: Canceled, moot

| Created  |Issue#|Score|Imp|Urg|Eff|Aff| Started  | by | Completed | Description | Notes
| :------  | :--- | --: |--:|--:|--:|--:| :------  |:---| :-------- | :---------- | :----

## Status: Done

| Created  |Issue#|Score|Imp|Urg|Eff|Aff| Started  | by | Completed | Description | Notes
| :------  | :--- | --: |--:|--:|--:|--:| :------  |:---| :-------- | :---------- | :----
| 20260420 |      | 2.7 | 3 | 3 | 2 |   |          | JC | 20260422  | Add known issues to Github.
| 20260703 |      | 2.5 | 3 | 3 | 2 | 2 | 20260703 | JC | 20260703  | Add base query flags (count, name, symbols) and full-coverage self round-trip tests | Every base is now fuzzed with its own random symbols, source to target and back.
| 20260709 |      | 2.5 | 3 | 3 | 3 | 3 | 20260709 | JC | 20260709  | cicd: quiet/message flags, sister-project output style, lint + fuzz + security + profiler stages | -q/-m + Ctrl+C message prompt; go vet/golangci/staticcheck; go fuzz; govulncheck; flamegraph SVG + report, all rotated under cicd/artifacts
| 20260711 |      | 2.7 | 3 | 3 | 3 | 3 | 20260711 | JC | 20260711  | cicd: animated demo gif stage | cicd/utility/gen-demo-gif.py types cicd/demo-scenario.toml into a fake terminal and renders assets/demo.gif; runs the tested binary so output never goes stale; seeded and byte-stable; skipped by --quick / --no-demogif
| 20260711 |      | 2.7 | 3 | 3 | 3 | 3 | 20260711 | JC | 20260711  | demo gif: smooth scrolling and cursor, content rework | Pixel-smooth scroll and gliding cursor; opens with crockford and emoji bases, explicit --from/--to, full base list scrolls by at reading pace, byte-encode section piped from a real /bin binary; faster digit typing
| 20260711 |      | 2.5 | 3 | 3 | 3 | 3 | 20260711 | JC | 20260711  | demo gif: smooth text, color emoji, faster pacing | Antialiased text is back on a shared 256-color palette (about 6.7 MiB now); emoji render as real color glyphs; the prompt stays hidden until a command's output is done; typing 50% faster, scrolling 25% faster at a higher frame rate; 32wordsafe replaces 32c and 2048twitter joins the codec section
| 20260713 |      | 2.5 | 3 | 3 | 3 | 3 | 20260713 | JC | 20260713  | demo gif: end hold + black, out-of-tree archive | Loop holds the last frame 3s then cuts to black 2s before repeating (end_hold/end_black knobs); cicd keeps a timestamped original under ../private/demos/gif with GFS rotation only when the render changes, then lands it at assets/demo.gif
| 20260711 |      | 2.0 | 2 | 2 | 1 | 3 | 20260711 | JC | 20260711  | Rename base 65536 to 65536qntm | Canonical name is now 65536qntm (alias 65536utf32), matching 32768qntm and 2048*; the bare 65536 name is dropped so it can't collide with a future base of that size
| 20260712 |      | 3.5 | 3 | 3 | 4 | 4 | 20260712 | JC | 20260712  | cicd: full release packaging + debug/release build split + main guard | Self-contained package.bash builds deb/rpm (nfpm), Windows installer .exe (makensis), and freebsd/darwin/linux/windows tarballs+zips for amd64/arm64 plus checksums; goreleaser retired; two native builds (debug for test/profile, optimized for dogfood); check-release.bash fails a main merge that didn't bump the version or whose Lifecycle badge is stale
| 20260712 |      | 2.5 | 3 | 3 | 2 | 2 | 20260713 | JC | 20260713  | Fix flaky integration fuzz tests in test.bash | A positional lone `-` is the read-stdin sentinel; the symbol-fuzz and randomized-fuzz loops occasionally generated it (a base whose digit is `-`, e.g. hostname value 36) and counted the correct "empty input" error as a failure. Both loops now skip that one value on input and on encoded output. The v1-compat 32c symptom was not a bug: v2 matched the legacy v1b in 10000+ samples, so that one-off was a transient in the legacy bash reference.
