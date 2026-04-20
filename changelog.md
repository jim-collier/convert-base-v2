<!-- markdownlint-disable MD007 -- Unordered list indentation -->
<!-- markdownlint-disable MD010 -- No hard tabs -->
<!-- markdownlint-disable MD024 -- No duplicate headings [OK with no TOC] -->
<!-- markdownlint-disable MD033 -- No inline html -->
<!-- markdownlint-disable MD041 -- First line in a file should be a top-level heading -->
<!-- markdownlint-disable MD055 -- Table pipe style [Expected: leading_and_trailing; Actual: leading_only; Missing trailing pipe] -->
# Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## v1.0.0-rc4

### Added

- CI/CD scripts.

### Changed

- Fixed a bug that only affects backwards-compatibility, which are already discouraged to be used in help and README. The bug.

## v1.0.0-rc3

### Added

- Added at over a dozen more bases, including other languages for base-10, a few novelty bases, and v1 backwards-compatibility bases.  [20260419]

### Changed

- Made word-safe bases all consistent, while maintaining backward-compatibility with `convert-base-v1`. [20260419]

- Fixed an _eggregious_ bug where RFCs 4648 §4 and §5 were defined completely wrong. Like not even close.

	- They were defined - totally rationally - as "hex-style".

	- But the RFC standards define numbers as coming almost last, inexplicably.

	- As a streaming binary-to-text encoder, that's fine. But it also means that as a base converter, "12" = "M".

- Added a _new_ hex-style base-64, with a new "64hex", which the old base-64 RFC was previously defined as. The RFC version is now named "64rfc".

## v1.0.0-rc2

### Changed

- Now errors if binary conversion doesn't align on boundary, to avoid losing data at end. (Will add padding in future release.)

- Added README.md, license.md, changelog.md, todo.md

## v1.0.0-rc1

### Added

- Created repo and project structure [20260417]

- Finished first draft of README.md [20260418]

- Added testing script. (Tests pass for most common scenarios - e.g. all integers with bases <= 288.)

## NEXT VERSION

### Notes

### Added

### Changed

### Removed

### Other work

