# Vendored SHCL

`shcl.go` is a verbatim copy of the SHCL Go binding, which ships as a single drop-in file per language.

- Upstream: <https://github.com/jim-collier/shcl>, `source/go/shcl.go`
- Copied at commit `66c7e5e` (2026-07-25)

Do not edit it here. To pick up a fix, copy the upstream file over this one and rerun the tests; keeping it byte-identical is what makes that a one-command update. The copy is deliberate rather than a module dependency: SHCL's own distribution story is the drop-in file, and vendoring it leaves this program with no external dependencies at all.
