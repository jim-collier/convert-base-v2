BINARY := convert-base-v2
VERSION := $(shell git describe --tags --always --dirty 2>/dev/null || echo dev)

# Optimized (release/dogfood): stripped, no symbol/DWARF. Debug (test/profile):
# keep symbols so delve works and flamegraphs read cleanly; still optimized so
# the profile is representative.
LDFLAGS       := -s -w -X main.version=$(VERSION)
LDFLAGS_DEBUG := -X main.version=$(VERSION)
## The browser module has no main.version var (it reports convertbase.Version).
LDFLAGS_WEB   := -s -w

DIST := dist

# Cap parallelism at 50% of cores (go build -p and go test both default to all
# cores). cicd exports its own GOMAXPROCS, which ?= leaves untouched.
GOMAXPROCS ?= $(shell n=$$(nproc 2>/dev/null || echo 2); c=$$((n/2)); [ $$c -lt 1 ] && c=1; echo $$c)
export GOMAXPROCS

.PHONY: all local debug release wasm web reactor clean test vet fmt

# Where the demo page lives, and where Go keeps the JS loader it requires (it
# moved out of misc/ in 1.24, so try both rather than pinning a layout).
WEB       := ../web
WASM_EXEC := $(firstword $(wildcard $(shell go env GOROOT)/lib/wasm/wasm_exec.js $(shell go env GOROOT)/misc/wasm/wasm_exec.js))

# Default: optimized build for the current machine into ./convert-base-v2
all: local

# Optimized native build (dogfood + hand use).
local:
	go build -ldflags '$(LDFLAGS)' -o $(BINARY) ./cmd/$(BINARY)

# Debug native build: symbols kept, for the test + profiler stages.
debug:
	go build -ldflags '$(LDFLAGS_DEBUG)' -o $(BINARY) ./cmd/$(BINARY)

# Cross-compile + package every shipping platform into ./dist/. The whole
# release pipeline (build, archive, deb/rpm, Windows installer, checksums)
# lives in the self-contained packager so local runs and CI stay identical.
release:
	bash ../cicd/utility/package.bash --version '$(VERSION)' --out '$(DIST)'

# The whole command, for any WASI runtime. Streams through real stdin/stdout,
# so it behaves like the native binary rather than like a cut-down build.
wasm:
	mkdir -p $(DIST)
	GOOS=wasip1 GOARCH=wasm go build -trimpath -ldflags '$(LDFLAGS)' -o $(DIST)/$(BINARY).wasm ./cmd/$(BINARY)

# The reactor library module: any host runtime loads it and calls exported
# functions directly (ABI in reactor/README.md). Needs a Go 1.24+ toolchain;
# the go.mod floor stays put, only the machine building this artifact cares.
reactor:
	mkdir -p $(DIST)
	GOOS=wasip1 GOARCH=wasm go build -trimpath -buildmode=c-shared -ldflags '$(LDFLAGS_WEB)' -o $(DIST)/convert-base-reactor.wasm ./reactor

# The browser module plus the loader Go requires, staged into the demo page.
web:
	@[ -n "$(WASM_EXEC)" ] || { echo "wasm_exec.js not found under $$(go env GOROOT)" >&2; exit 1; }
	GOOS=js GOARCH=wasm go build -trimpath -ldflags '$(LDFLAGS_WEB)' -o $(WEB)/convert-base.wasm ./wasm
	cp '$(WASM_EXEC)' $(WEB)/wasm_exec.js

test:
	go test ./...

vet:
	go vet ./...

fmt:
	gofmt -w .

clean:
	rm -rf $(BINARY) $(DIST)
