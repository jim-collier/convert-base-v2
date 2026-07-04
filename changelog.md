<!-- markdownlint-disable MD007 -- Unordered list indentation -->
<!-- markdownlint-disable MD010 -- No hard tabs -->
<!-- markdownlint-disable MD024 -- No duplicate headings [OK with no TOC] -->
<!-- markdownlint-disable MD033 -- No inline html -->
<!-- markdownlint-disable MD041 -- First line in a file should be a top-level heading -->
<!-- markdownlint-disable MD055 -- Table pipe style [Expected: leading_and_trailing; Actual: leading_only; Missing trailing pipe] -->
# Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

<!--
## NEXT VERSION

### Notes

### Added

### Changed

### Removed

### Other work
-->

## v1.1.0-beta5 (unreleased) - WIP

### Added

- Base-introspection flags for scripting: `--get-index-count`, `--get-base-name`, and `--show-symbols`, with a base selectable by name, alias, or `--by-index`.
- Screenshots section in the README, with a responsive grid that links to full-size images.

### Other work

- Reworked the CI/CD scripts [20260703]:
	- Split the pipeline into a generic engine and a per-project config, matching the sister project's layout.
	- The pipeline now formats, builds, tests, cross-compiles, dogfoods a fixed-name local copy, then backs up and publishes quietly.
	- Replaced the test harness with a self-contained, table-driven one. It covers the CLI, conversions, custom bases, errors, oversized and hostile input, binary round-trips, and fuzzing across every defined base. The base list is read from the program, so new bases are tested automatically.
	- Added byte-for-byte back-compat checks against v1 for every shared base, in both directions.
	- Kept the previous scripts under `legacy/`.

- Updated to CI/CD scripts [20250519]:
	- Updated for less boilerplate.
	- Changed license (of CI/CD scripts) from GPL2 to MIT.
	- Moved from ./utility to ./cicd/utility to be more logical, and consistent with other projects.
	- Refreshed local copies of n8git_backup-and-publish and n8lib_test.
	- Updated to side-step known potential edge-case unexpected behavior in `while...do...done`, by following all `done` with 'true'.

## v1.1.0-beta5 - 2026-05-12

### Added

- Uncommented base-45 definition, got it working with " " space as a valid symbol, and fixed a bug related to that.

### Changed

- Addressed Issue #6, "[Need a better way to define neg, dec, pad](https://github.com/jim-collier/convert-base-v2/issues/6)". Neg and dec are now defined independently of the base symbols, using structs. (Per [design document](https://github.com/jim-collier/convert-base-v2/blob/main/design_docs/20260503_rethink_neg_dec_pad.md).)

### Other work

- Renamed ci/cd scripts from `.sh` to `.bash` to make it clear they aren't POSIX scripts.

- Created helper utilities to help with base symbol selection
	- Python scripts
		- `filter_1_junk.py`
		- `filter_2_messy.py`
		- `filter_3_visual.py`
		- `populate_unicode_spreadsheets_with_filtered_results.py`
	- Bash wrappers:
		- `test_filter_all_from_xclipboard_input.bash`
		- `unicode_1_junk_alter_xclipboard_contents.bash`
		- `unicode_2_messy_alter_xclipboard_contents.bash`
		- `unicode_3_visual_alter_xclipboard_contents.bash`

- Exported `unicode_good_base_symbols.gnumeric` to `unicode_good_base_symbols.ods`, as the new main spreadsheet and single-source of truth.
	- Data from that trickles down to `unicode_good_base_symbols.gnumeric` and `unicode_good_base_symbols.xlsx`.
	- Notes:
		- The `.xlsx` is _way_ too slow and painful to be the main spreadsheet. And is the most likely to be out of sync. It's essentially unusable for actual editing.
		- The `.gnumeric` sheet used to be the main, because Gnumeric seems to be the fastest by far with this much data, but...
		- Once you use the `.ods` sheet for a while, it speeds up. Must be some memory caching or optimizing hapening. It starts out as slow as Excel (basically unusable), but slowly speeds up to rival Gnumeric. So given that, and the better features of LibreOffice sheets over Gnumeric, LibreOffice is the new main.

- Not-trivial updates to `how_to_design_a_numeric_base.md`.

## v1.1.0-beta4 - 2026-05-03

### Changed

- Fixed a bug that only affects backwards-compatibility, which are already discouraged to be used in help and README. [20260428]

### Other work

- Added CI/CD scripts. [20260428]

- Minor tweaks to `cicd.sh` to make paths more explicit and hopefully less prone to future errors. [20250503]

- Minor updates to this file be more "changelog idiomatic". [20250503]

- Minor corrections to README.md, including lifecycle and status badges. [20250503]

## v1.0.0-rc3 - 2025-04-19

### Added

- Added over a dozen more bases, including other languages for base-10, a few novelty bases, and v1 backwards-compatibility bases.  [20260419]

### Changed

- Made word-safe bases all consistent, while maintaining backward-compatibility with `convert-base-v1`. [20260419]
- Fixed an _eggregious_ bug where RFCs 4648 §4 and §5 were defined completely wrong. Like not even close.
	- They were defined - totally rationally - as "hex-style".
	- But the RFC standards define numbers as coming almost last, inexplicably.
	- As a streaming binary-to-text encoder, that's fine.
		- But it also means that as a base converter, 3→"C", and "12"→"M". Which is weird.
		- For most bases ≥ 12, 3→"3", 12→"C".
		- But, it's the published RFC standard. We say it's the RFC standard base, and not compute the RFC standard base.
- Added a _new_ hex-style base-64, with a new name "64hex", which the old base-64-URL RFC was previously defined as..

## v1.0.0-rc2 - 2026-04-19

### Changed

- Now errors if binary conversion doesn't align on boundary, to avoid losing data at end. (Will add padding in future release.)

### Other work

- Added README.md, license.md, changelog.md, todo.md

## v1.0.0-rc1 - 2026-04-18

### Added

- First binary release.

### Other work

- Created repo and project structure [20260417]
- Finished first draft of README.md [20260418]
- Added testing script. (Tests pass for most common scenarios - e.g. all integers with bases <= 288.)
