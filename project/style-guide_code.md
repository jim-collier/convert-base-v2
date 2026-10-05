<!-- markdownlint-disable MD007 -- Unordered list indentation -->
<!-- markdownlint-disable MD010 -- No hard tabs -->
<!-- markdownlint-disable MD041 -- First line in a file should be a top-level heading -->
# Code style

How the code in this repo is written, and why. It covers Go, Bash and Python. How to build, test and send a change is in [contributing.md](../contributing.md).

Where a language has a standard formatter, its output is the style. Where it has none, the house style below applies, and the linter still has the last word. The checks to run are listed in [contributing.md](../contributing.md#checks-to-run).

## Everywhere

- Tabs indent and spaces line things up. gofmt already works that way, Bash has no formatter to disagree, and the Python files here use tabs too. One indent character across the repo means an editor needs one setting.

- Names should be easy to search for. `upperBound` can be found and replaced by hand, and `ub` can't. A one-letter loop index is fine where the language does that. Case follows the language: mixedCaps for Go, PEP 8 for Python, and the house style below for Bash.

- Comments say why, not what. Most code needs none. Save them for what the code can't show, such as an order that matters or a guard against a bug that was hard to find. A long explanation belongs in [design.md](design.md), with a short comment pointing to it.

- Comments are plain ASCII. The `©` in copyright lines is the exception, and so is a comment about a Unicode character, where the character is the point.

- No banner comments or decorative dividers.

- Write the plain, obvious version first. Speed comes from picking the right data structures up front, and after that from measuring. The pipeline has a profiler stage, so a slowdown is a number to look at rather than a guess.

- Every source file has a copyright and license header near the top. The command is GPL-2.0-or-later. The library, the browser module and the reactor module are Apache-2.0. Helper scripts are MIT. Copy the header from a neighbor in the same directory.

- Code copied in from another project keeps its own style and is not reformatted to match.
	- `lib/shcl/shcl.go` is a verbatim copy of the upstream SHCL Go binding, and is never edited here. A fix for it goes upstream. The copy is then refreshed, and its pin in `cicd/vendor-pins.env` updated.

## Go

- gofmt output is the format. Run `make fmt` from `lib/`, or let the editor do it on save.

- `go vet` must pass, and so must golangci-lint and staticcheck when they are installed. `lib/.golangci.yml` has the linter set, with a note on why each extra linter is there.

- Standard library only. The module has no third-party dependencies and no `go.sum`, so a fresh clone builds offline. A new dependency needs a very good reason.

- The minimum is Go 1.21, set in `lib/go.mod`. The reactor module needs 1.24 for `//go:wasmexport`. It builds separately, so the rest still builds on 1.21.

- Check errors where they happen, and return them with context: `fmt.Errorf("reading config: %w", err)`. Wrapping with `%w` keeps the library's typed errors reachable through `errors.As`. No `panic` for ordinary errors. An error dropped with `_` gets a comment saying why.

- Return early, and keep the main path at the left margin. No `else` after a `return`.

- Interfaces stay small and are declared where they are used. Don't add one until there are two implementations, or a test needs the seam.

- Goroutines and channels only where there is real concurrent work. A mutex is simpler when all that's needed is guarded state.

- Exported names get a doc comment that starts with the name.

- The command and the library are split by audience. What a person at a prompt needs, such as flags, help text and creating the config file in a home directory, stays in `lib/cmd/convert-base-v2/`. What a conversion needs goes in `lib/convertbase/`. A library shouldn't write to someone's home directory just because it was linked in. The reasoning is in [the library design doc](design_docs/20260731_linkable_library.md).

- In hot paths, size slices and maps up front when the size is known, and build strings with `strings.Builder`. Profile before anything finer. From `lib/`, `go test -run x -bench . -cpuprofile cpu.out ./convertbase` is one way.

## Bash

Bash has no formatter here, on purpose. The house style is compact, and shellcheck keeps it in line.

- Files end in `.bash`. The first line is `#!/usr/bin/env bash`. Any `shellcheck disable` lines come next, each with a short reason. Then a `##` header with the purpose, copyright and license. The change history goes at the bottom of the file. `cicd/utility/check-vendor.bash` is a short example.

- Scripts run under `set -Eeuo pipefail`.

- Functions are `fCamelCase`, with an underscore to group a family, as in `fEcho` and `fEcho_Clean`. Variables are camelCase. The test harness and a few utility scripts are older and use short lower-case helpers such as `_pass` and `check`. Those stay as they are.

- Use `[[ ]]`, never `[ ]`. Brace and quote every expansion: `"${var}"`. Write `${1:-}` for an argument that may be missing, since `set -u` would otherwise stop the script.

- Declare a function's variables `local`. Pass large arrays and strings by name, with `local -n`. The odd suffixes on those names avoid clashes with the caller's variables, so keep them.

- Compact is fine. A short function can sit on one line, and a run of similar lines can be lined up in columns. A line that has to be read twice gets split.

- Avoid forking inside loops. A `$(...)`, a pipe, or a call to `grep` or `sed` on every pass is where the time goes. Parameter expansion, `[[ ]]` and `$(( ))` do small string and number work without a fork. For a large input, one `awk` or `sed` pass beats a loop over lines.

- Some traps that have caught this code before:
	- `((n++))` returns the old value, so on the first pass it returns 0, and `set -e` ends the script. Use `n=$((n + 1))`.
	- `local x="$(f)"` hides the exit status of `f` behind that of `local`. Declare first, then assign.
	- A function whose last command is a failed `a && b` returns 1, and under `set -e` the caller exits with no message.
	- `[[ ${var} -eq 1 ]]` evaluates `var` as arithmetic, which can run a command hidden in it. Compare as strings when the value comes from outside.

## Python

Python here is tooling only: the pipeline helpers under `cicd/utility/` and the generators under `utility/`. Nothing in it reaches users. There is no Python package, so `pyproject.toml` holds only the ruff settings.

- Names follow PEP 8: `snake_case` for functions and variables, `CapWords` for classes. ruff's naming rules check it.
	- A script copied in from another project keeps its own names. `cicd/utility/flame-report.py` came from silkterm, and `pyproject.toml` exempts it.
	- No other script is exempt, and a new one gets no exemption.
	- The Unicode research scripts under `utility/` were one-off tools. They sit outside the lint check and keep their own style.

- Indent with tabs, as every Python file here does. `pyproject.toml` sets ruff's formatter to match, and to keep quotes as written.

- Target Python 3.11.

- Standard library first. Add an outside package only where a tool really needs one, as the demo gif generator needs Pillow.

- Catch the exceptions you expect, by name, and let the rest through so the error is seen.

- Use `with` for files and anything else that needs closing, and f-strings for formatting.

- Keep functions small and return early. A plain loop beats a comprehension that doesn't fit on one line.
