# Vendored SHCL

`shcl.go` is a verbatim copy of the SHCL Go binding, which ships as a single drop-in file per language.

- Upstream: <https://github.com/jim-collier/shcl>, `source/go/shcl.go`
- Pinned to release `v1.0.0`

The pin lives in `cicd/vendor-pins.env`, and `cicd/utility/check-vendor.bash` checks it on every pipeline run: the copy must still be byte-identical to that tag, and a newer upstream release prints a notice. An edit here would otherwise go unnoticed, since lint skips this directory and a config parser that reads an alphabet slightly wrong still produces output that looks perfectly fine.

Do not edit it here. To pick up a fix, copy the upstream file over this one and bump the tag in `cicd/vendor-pins.env` in the same commit.

Upstream is a real Go module (`github.com/jim-collier/shcl/source/go`, tagged `source/go/v1.0.0`), so `go get` would work. The copy is still deliberate: it leaves this program at standard library plus its own source, with no `go.sum` and nothing to fetch at build time, and it keeps the `go` directive here off upstream's higher floor.
