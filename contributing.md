<!-- markdownlint-disable MD007 -- Unordered list indentation -->
<!-- markdownlint-disable MD010 -- No hard tabs -->
<!-- markdownlint-disable MD041 -- First line in a file should be a top-level heading -->
# Contributing to convert-base-v2

Bug reports and fixes are welcome. So are new bases, if they have a real use or a published spec behind them.

## Reporting a bug

Open an [issue](https://github.com/jim-collier/convert-base-v2/issues) with the command line you ran, what it printed, and what you expected. Include the output of `convert-base-v2 --version`. Questions and ideas can go in [Discussions](https://github.com/jim-collier/convert-base-v2/discussions).

## Sending a change

- `dev` is where work comes together, and `main` only moves when a release is cut. Branch from `dev`, and open the pull request against `dev`.

- Keep a pull request to one change. For anything large, open an issue first, so the approach can be agreed on before the work is done.

- Read the [code style guide](project/style-guide_code.md) first. It is short, and it says why things are the way they are.

- The tools you need are listed in [Set up a development environment](development.md).

- A change users will notice gets a line in [changelog.md](changelog.md), under the `vNEXT` heading.

## Checks to run

For a quick check, run these from `lib/`.

~~~bash
make fmt
make vet
make test
~~~

Before sending a pull request, run the pipeline from the repo root. `--quick` skips the slow tests, the leak checks, and the checks that reach other hosts. `--no-dogfood` keeps it from installing the build over a copy on your PATH, and `--no-publish` from committing and pushing.

~~~bash
cicd/cicd.bash --quick --no-dogfood --no-publish -y
~~~

`cicd/cicd.bash --gate` is the short version: the format check, the linters and the Go tests, on your machine, in under a minute. The first pipeline run sets it up as a git pre-push hook, so a push to `dev` or `main` runs it first and stops if it fails. A full run also fetches before it builds, and fast-forwards when the remote is ahead. `--no-sync` skips that.

The format, build, lint, test and package steps run in a docker image with every tool at its pinned version, so docker is the only thing to install. There, a missing tool fails the run instead of being skipped. The image is built from `cicd/container/Dockerfile` the first time, which takes a few minutes and about 3 GB. The demo gif needs fonts that can't be shared, so it's left out of the image, and the run skips it, unless they're in `../private/fonts/demo-gif/`.

Hosted CI runs the same image on every push to `dev` or `main` and every pull request, as a `--quick` run that publishes nothing. So the harness, the comparison tests against the reference implementations, and all the linters run there too. The image is built on the runner from the GitHub Actions layer cache, and never pushed to a registry. A second job vets, tests, and builds with Go alone.

Without docker, or with `--no-container`, every step runs on your machine. In the lint step, `go vet` always runs. golangci-lint, staticcheck, shellcheck, ruff and PSScriptAnalyzer run when they are installed, and are skipped with a warning when they are not. Any finding from one that runs stops the pipeline. Install them all, since hosted CI runs every one of them.

- golangci-lint and staticcheck: `cicd/utility/pin-tools.bash` installs both at the versions in `cicd/tool-versions.env`.

- shellcheck: from your package manager.

- ruff: `pipx install ruff`.

- PSScriptAnalyzer: install PowerShell 7, then run `Install-Module PSScriptAnalyzer` in it. The install script's tests need PowerShell too.

The shellcheck settings are in `.shellcheckrc`, the ruff settings in `pyproject.toml`, the PSScriptAnalyzer settings in `PSScriptAnalyzerSettings.psd1`, and the Go linter set in `lib/.golangci.yml`.

## Tests

- Go unit tests sit beside the code they test, under `lib/`.

- Each Go test package checks for leftover goroutines once its tests finish, with goleak in its `TestMain`. A run that leaves one running fails, even when every test passed.

- The leak checks run on a full pipeline run, or with `--leakcheck`, and `--no-leakcheck` skips them. They run the Go tests again under the race detector, then a soak test, `TestSoak` in `lib/cmd/convert-base-v2/`. It runs the command's main jobs over and over, and fails if the heap or the goroutine count keeps growing. Its two heap profiles are kept in `cicd/artifacts/soak/`, and `go tool pprof -base` on the pair shows what grew.
	- Last comes CodeQL, which is only in the pipeline image. It scans a copy of `lib/` with the dependencies vendored into it, so goleak and the shcl copy get the same queries as our code. The queries are in `cicd/utility/codeql/leak-checks.qls`. Any result fails the run, and the SARIF report is kept in `cicd/artifacts/codeql/`.

- The integration harness is `cicd/test.bash`. It runs the built binary from the outside, and most checks are one line. It tests `lib/bin/convert-base-v2`, which the pipeline puts there. To run it against another build, set `CICDTEST_EXE` to that binary.

- Every test has an ID, so a failure, an issue and a commit can all name the same test. An ID is the minute the test was written, counted from 2000 and written in lower case Crockford base 32, such as `decp8`. When 2 tests fall in the same minute, the newer one takes the next free minute. Get a new one with:

	~~~bash
	python3 cicd/utility/test-ids.py new
	~~~

	- A Go test has its ID in a comment on the line above the function, as `// Test ID: xxxxx`.
	- A harness check takes its ID as the first argument to `check`, `_pass`, `_fail` and the other reporting helpers.
	- The test stage runs `test-ids.py check` first, and stops on a test with no ID, a bad one, or one that another test already uses.
	- Each test prints one line with its result, ID and name, such as `PASS decp8 empty input round-trips`. The result is `PASS`, `FAIL` or `SKIP`.

## Adding a base

Built-in bases are in `lib/convertbase/bases.go`. The README table of bases is generated, not edited by hand. After adding a base, build, then paste the output of this over the table:

~~~bash
python3 utility/gen-bases-table.py --exe lib/bin/convert-base-v2 --config lib/cmd/convert-base-v2/default-config.shcl
~~~

The harness checks that every name in the table still resolves.

## Licensing

A contribution is under the license of the part of the tree it goes into. That is GPL-2.0-or-later for the command, Apache-2.0 for `lib/convertbase/`, `lib/wasm/` and `lib/reactor/`, and MIT for the helper scripts. Don't bring in code under a license that can't be combined with those.

`lib/shcl/shcl.go` is copied from [SHCL](https://github.com/yottacore/shcl) and is never edited here. Send fixes for it upstream.

## Supporting the project

If convert-base-v2 is useful to you, you can support it through [GitHub Sponsors](https://github.com/sponsors/jim-collier) or [Ko-fi](https://ko-fi.com/jimcollier).
