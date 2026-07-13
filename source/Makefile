BINARY := convert-base-v2
VERSION := $(shell git describe --tags --always --dirty 2>/dev/null || echo dev)

# Optimized (release/dogfood): stripped, no symbol/DWARF. Debug (test/profile):
# keep symbols so delve works and flamegraphs read cleanly; still optimized so
# the profile is representative.
LDFLAGS       := -s -w -X main.version=$(VERSION)
LDFLAGS_DEBUG := -X main.version=$(VERSION)

DIST := dist

# Cap parallelism at 50% of cores (go build -p and go test both default to all
# cores). cicd exports its own GOMAXPROCS, which ?= leaves untouched.
GOMAXPROCS ?= $(shell n=$$(nproc 2>/dev/null || echo 2); c=$$((n/2)); [ $$c -lt 1 ] && c=1; echo $$c)
export GOMAXPROCS

.PHONY: all local debug release clean test vet fmt

# Default: optimized build for the current machine into ./convert-base-v2
all: local

# Optimized native build (dogfood + hand use).
local:
	go build -ldflags '$(LDFLAGS)' -o $(BINARY) ./...

# Debug native build: symbols kept, for the test + profiler stages.
debug:
	go build -ldflags '$(LDFLAGS_DEBUG)' -o $(BINARY) ./...

# Cross-compile + package every shipping platform into ./dist/. The whole
# release pipeline (build, archive, deb/rpm, Windows installer, checksums)
# lives in the self-contained packager so local runs and CI stay identical.
release:
	bash ../cicd/utility/package.bash --version '$(VERSION)' --out '$(DIST)'

test:
	go test ./...

vet:
	go vet ./...

fmt:
	gofmt -w .

clean:
	rm -rf $(BINARY) $(DIST)
