# Vendored SHCL

`shcl.go` is a verbatim copy of the SHCL Go binding, which ships as a single drop-in file per language.

- Upstream: <https://github.com/yottacore/shcl>, `source/go/shcl.go`

- Pinned to commit `2317df56` on upstream's `dev` branch, an unreleased 3.0 build. This is on purpose until 3.0.0 is tagged, and then the pin moves to that tag.

The pin lives in `cicd/vendor-pins.env`, and `cicd/utility/check-vendor.bash` checks it on every pipeline run: the copy must still be byte-identical to the pinned tag or commit, a commit pin prints a pre-release notice, and a newer upstream release prints a notice. An edit here would otherwise go unnoticed, since lint skips this directory and a config parser that reads an alphabet slightly wrong still produces output that looks perfectly fine.

Do not edit it here, not even in a tree-wide sweep. To pick up a fix, copy the upstream file over this one and bump the pin in `cicd/vendor-pins.env` in the same commit. `shcl_windows.go` upstream is an optional companion for Windows saves and is not copied, since nothing here saves through the library yet.

Upstream is a real Go module (`github.com/yottacore/shcl/source/go/v2` at this commit), so `go get` would work. The copy is still deliberate: it leaves this program at standard library plus its own source, with no `go.sum` and nothing to fetch at build time.

That is now the only reason left. Upstream used to declare `go 1.24`, so depending on it would have raised the toolchain floor here from 1.21; v1.1.0 dropped that directive to 1.20 and the objection went with it.
