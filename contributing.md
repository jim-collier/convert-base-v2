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

- The tools you need are listed in the README, under [Set up a development environment](README.md#set-up-a-development-environment).

- A change users will notice gets a line in [changelog.md](changelog.md), under the `vNEXT` heading.

## Checks to run

For a quick check, run these from `lib/`.

~~~bash
make fmt
make vet
make test
~~~

Before sending a pull request, run the pipeline from the repo root. `--quick` skips the slow stages. `--no-dogfood` keeps it from installing the build over a copy on your PATH, and `--no-publish` from committing and pushing.

~~~bash
cicd/cicd.bash --quick --no-dogfood --no-publish -y
~~~

Stage 3 is the lint stage. `go vet` always runs. golangci-lint, staticcheck, shellcheck and ruff run when they are installed, and are skipped with a warning when they are not. Any finding from one that runs stops the pipeline. Install them all, since the hosted CI only runs vet, the Go tests and the build.

- golangci-lint and staticcheck: `cicd/utility/pin-tools.bash` installs both at the versions in `cicd/tool-versions.env`.

- shellcheck: from your package manager.

- ruff: `pipx install ruff`.

The shellcheck settings are in `.shellcheckrc`, the ruff settings in `pyproject.toml`, and the Go linter set in `lib/.golangci.yml`.

With docker installed, add `--container` and there's nothing else to install. Stages 1 to 4 and 6 then run in an image with every tool at its pinned version, and a missing tool fails the run there instead of being skipped. The image is built from `cicd/container/Dockerfile` the first time, which takes a few minutes and about 3 GB. Only these runs remake the demo gif, since its fonts are pinned in the image.

~~~bash
cicd/cicd.bash --container --quick --no-dogfood --no-publish -y
~~~

## Tests

- Go unit tests sit beside the code they test, under `lib/`.

- The integration harness is `cicd/test.bash`. It runs the built binary from the outside, and most checks are one line. It tests `lib/bin/convert-base-v2`, which the pipeline puts there. To run it against another build, set `CICDTEST_EXE` to that binary.

- Every test has an ID, so a failure, an issue and a commit can all name the same test. An ID is the time the test was written, in base 62. Get a new one with:

	~~~bash
	python3 cicd/utility/test-ids.py new
	~~~

	- A Go test has its ID in a comment on the line above the function, as `// Test ID: XXXXXXX`.
	- A harness check takes its ID as the first argument to `check`, `_pass`, `_fail` and the other reporting helpers.
	- The test stage runs `test-ids.py check` first, and stops on a test with no ID, a bad one, or one that another test already uses.

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
