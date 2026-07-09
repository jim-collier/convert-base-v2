BINARY := convert-base-v2
VERSION := $(shell git describe --tags --always --dirty 2>/dev/null || echo dev)
LDFLAGS := -s -w -X main.version=$(VERSION)

DIST := dist

# Cap parallelism at 50% of cores (go build -p and go test both default to all
# cores). cicd exports its own GOMAXPROCS, which ?= leaves untouched.
GOMAXPROCS ?= $(shell n=$$(nproc 2>/dev/null || echo 2); c=$$((n/2)); [ $$c -lt 1 ] && c=1; echo $$c)
export GOMAXPROCS

# platform/arch pairs you want to ship
PLATFORMS := \
	linux/amd64 \
	linux/arm64 \
	darwin/amd64 \
	darwin/arm64 \
	windows/amd64 \
	windows/arm64

.PHONY: all local release clean test vet fmt

# Default: build for the current machine into ./convert-base-v2
all: local

local:
	go build -ldflags '$(LDFLAGS)' -o $(BINARY) ./...

# Cross-compile every platform listed above into ./dist/
release: clean
	@mkdir -p $(DIST)
	@set -e; for p in $(PLATFORMS); do \
		os=$${p%/*}; arch=$${p#*/}; \
		ext=""; [ "$$os" = "windows" ] && ext=".exe"; \
		label="$$arch"; [ "$$arch" = "amd64" ] && label="x86_64"; \
		stage="$(DIST)/$(BINARY)-$$os-$$label"; \
		mkdir -p "$$stage"; \
		echo "building $$stage/$(BINARY)$$ext"; \
		CGO_ENABLED=0 GOOS=$$os GOARCH=$$arch \
			go build -trimpath -ldflags '$(LDFLAGS)' \
			-o "$$stage/$(BINARY)$$ext" ./...; \
		if [ "$$os" = "windows" ]; then \
			( cd "$$stage" && zip -qr "../$(BINARY)-$$os-$$label.zip" . ); \
		else \
			tar -C "$$stage" -czf "$(DIST)/$(BINARY)-$$os-$$label.tgz" . ; \
		fi; \
		rm -rf "$$stage"; \
	done

test:
	go test ./...

vet:
	go vet ./...

fmt:
	gofmt -w .

clean:
	rm -rf $(BINARY) $(DIST)
