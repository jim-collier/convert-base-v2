BINARY := convert-base-v2
## Skip the lib/vX.Y.Z module tags - they sit on the same commits as the command's
## own tags, and describe would otherwise stamp the library's version on the binary.
VERSION := $(shell git describe --tags --always --dirty --exclude 'lib/*' 2>/dev/null || echo dev)
## The build number comes from the commit's time, never the clock, so a rebuild of
## one commit gives the same bytes. Empty outside a clone: no build number then.
BUILD_EPOCH := $(shell git log -1 --format=%ct 2>/dev/null)
STAMP := -X main.version=$(VERSION) -X main.buildEpoch=$(BUILD_EPOCH)

# Optimized (release/dogfood): stripped, no symbol/DWARF. Debug (test/profile):
# keep symbols so delve works and flamegraphs read cleanly; still optimized so
# the profile is representative.
LDFLAGS       := -s -w $(STAMP)
LDFLAGS_DEBUG := $(STAMP)
## The browser module has no main.version var (it reports convertbase.Version).
LDFLAGS_WEB   := -s -w

DIST := dist
## package.bash and clean empty $(DIST) only when it has this mark, so a target
## that makes the dir marks it too. A dir that was already there is left as is.
DIST_MARK := .convert-base-v2-dist
MKDIST = [ -d '$(DIST)' ] || { mkdir -p '$(DIST)' && echo 'Made by make, and cleared by make release or make clean.' >'$(DIST)/$(DIST_MARK)'; }

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
	bash ../cicd/utility/package.bash --version '$(VERSION)' --build-epoch '$(BUILD_EPOCH)' --out '$(DIST)'

# The whole command, for any WASI runtime. Streams through real stdin/stdout,
# so it behaves like the native binary rather than like a cut-down build.
wasm:
	$(MKDIST)
	GOOS=wasip1 GOARCH=wasm go build -trimpath -ldflags '$(LDFLAGS)' -o $(DIST)/$(BINARY).wasm ./cmd/$(BINARY)

# The reactor library module: any host runtime loads it and calls exported
# functions directly (ABI in reactor/README.md). Needs a Go 1.24+ toolchain;
# the go.mod floor stays put, only the machine building this artifact cares.
reactor:
	$(MKDIST)
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
	rm -rf $(BINARY)
	if [ -f '$(DIST)/$(DIST_MARK)' ]; then rm -rf '$(DIST)'; elif [ -d '$(DIST)' ]; then rmdir '$(DIST)' 2>/dev/null || { echo '$(DIST) has files in it and no sign a build made them; left alone' >&2; exit 1; }; fi
