<!-- markdownlint-disable MD007 -- Unordered list indentation -->
<!-- markdownlint-disable MD010 -- No hard tabs -->
<!-- markdownlint-disable MD055 -- Table pipe style [Expected: leading_and_trailing; Actual: leading_only; Missing trailing pipe] -->
<!-- markdownlint-disable MD041 -- First line in a file should be a top-level heading -->
<!-- TOC ignore:true -->
# Set up a development environment

Back to the [README](README.md).

Prerequisites, in the order you are likely to need them.

- Go 1.21 or newer is the only requirement for the command, the library, and the tests. The build fetches nothing, so it works offline after the clone. The tests use one third-party module, goleak, which Go fetches the first time they run.

- Go 1.24 or newer is required only to build the reactor module, which uses a newer export directive. The declared minimum stays at 1.21, so an older toolchain builds everything else.

- The pipeline scripts need Bash 4 and the usual GNU tools, which is what all the checks run under.

- Docker, for the default pipeline run, which builds and tests in an image with every tool pinned. `--host` runs without it.

- Optional tools, for `--host` runs only, are skipped with a warning when missing: `golangci-lint`, `staticcheck`, `shellcheck`, `ruff`, `pwsh` with PSScriptAnalyzer, `govulncheck`, a C compiler such as `gcc` for the race detector, `nfpm`, `makensis` and `goversioninfo` for packaging, `node` and `cargo` for the third-party comparison tests, `gifsicle` and Python with Pillow for the demo animation. CodeQL, for the leak checks, is only in the image, so a `--host` run skips it with a warning.

The Go tree is under `lib/`. The command is in `lib/cmd/convert-base-v2/`, the conversion core in `lib/convertbase/`, and the WebAssembly entry points in `lib/wasm/` and `lib/reactor/`.

Build targets, all run from `lib/`.

| Target                  | Result
| :---------------------- | :-----------------------------------------------------------
| `make local`            | The optimized native binary, the same build that is released
| `make debug`            | Native with symbols kept, for tests and the profiler
| `make test`             | Unit tests
| `make vet` / `make fmt` | Static checks and formatting
| `make web`              | The browser module and its loader, into `web/`
| `make wasm`             | The whole command as a WASI module
| `make reactor`          | The callable WebAssembly module
| `make release`          | Cross-builds and packages every platform

Everything else runs from one script, `cicd/cicd.bash`. It goes through formatting, build, lint, the test suites, profiling, cross-compiling and packaging every platform, and publishing, and stops at the first thing that fails. A plain run includes the exhaustive tests and the leak checks. `--quick` skips them and the other slow parts, `--long` and `--leakcheck` add them back to a quick run, `--gate` runs only the quick checks, and most stages have a `--no-...` switch. The build and test stages run in a docker image that has every tool installed at a pinned version, and `--host` runs them on your own machine instead. A plain run also copies the build into a local bin folder, and commits and pushes, so use `cicd/cicd.bash --quick --no-dogfood --no-publish -y` for a local check.

Hosted CI on GitHub does much the same: it builds that image from a layer cache and runs a `--quick` pass in it, with no publish and no demo gif, on every push to `dev` or `main` and every pull request. A plain Go vet, test, and build runs beside it.

Tests sandbox their own config directory, so running them won't read or write the config file in your home directory.

To send a change, see [contributing.md](contributing.md). The code style, and the reasons for it, are in the [style guide](project/style-guide_code.md).
