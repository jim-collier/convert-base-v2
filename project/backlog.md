<!-- markdownlint-disable MD007 -- Unordered list indentation -->
<!-- markdownlint-disable MD010 -- No hard tabs -->
<!-- markdownlint-disable MD033 -- No inline html -->
<!-- markdownlint-disable MD055 -- Table pipe style [Expected: leading_and_trailing; Actual: leading_only; Missing trailing pipe] -->
<!-- markdownlint-disable MD041 -- First line in a file should be a top-level heading -->

<!-- TOC ignore:true -->
# Project backlog

This is a product backlog just for pre-v1.0.0 release. After that, bugs, features, and enhancements will be managed in Github Issues, and/or [todo.md](../todo.md)

<!-- TOC ignore:true -->
## Table of contents
<!-- TOC -->

- [Conventions](#conventions)
- [Backlog](#backlog)
	- [Bugs](#bugs)
	- [New features and enhancements](#new-features-and-enhancements)
	- [Done](#done)
		- [Done - Bugs](#done---bugs)
		- [Done - New features and enhancements](#done---new-features-and-enhancements)
	- [Deferred](#deferred)
	- [Canceled](#canceled)

<!-- /TOC -->

## Conventions

In each section, items are listed approximately from newest to oldest.

| Icon | Status
| :--: | :--
| 🔘   | Not started
| 🛠️   | Started, and/or partially complete
| ✋   | Defer
| ✅   | Complete
| 🚫   | Canceled

## Backlog

### Bugs

### New features and enhancements

- 🔘 Allow arbitrary-length binary-to-text encoding conversions (and vice-versa) that don't align on 2^n.

- 🔘 Pad binary-to-text conversions properly (and vice-versa).
	- For my custom bases, not necessarily with just '===' etc. (Except for the standard binary encoding bases like base64 that expect specific, defined encoding characters.)
	- Some existing third-party big bases actually shrink down to smaller bases for the padding, and use lower unicode/ascii characters that aren't in the base definition, as padding (e.g. 0-9). Notably the two base 2048's, base 32768, and 65536.

- 🔘 Process the third-party binary big-base conversions properly, according to their own online published specs. Specifically, their more complex padding implementation. This may require carefully reading and reverse-engineering some of their JS, Python, and/or Rust code. (Or maybe their spec definitions are enough to figure it out.)

- 🔘 Update comments in code, help output, readme.md, and design.md to properly use "radix" and/or "base" in context, etc. But not the actual program interface, don't change that.

- 🔘 Improve the performance of streaming binary-to-text conversion and vice-versa, to better approach existing linux utilities. Go should be able to get close.

### Done

#### Done - Bugs

#### Done - New features and enhancements

- ✅ Bases with '-' in the symbol set now use '~' as the negative marker instead of the en-dash. '~' was free in all four affected bases (45, 64u, 64h, 69prsh).

- ✅ Help: clarified the text for the index-related flags (`--get-index-count`, `--get-base-name`, `--show-symbols`, `--by-index`).

- ✅ `--list`: the NAME is no longer repeated in the ALIASES column.

### Deferred

### Canceled
