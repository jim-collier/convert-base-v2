# Tools for 'cicd.bash --container'. Everything stages 1 to 4, 6 and the demo
# gif call, pinned, so a run doesn't depend on what the host has installed.
# The profiler, dogfood and publish stay on the host.
#
# The tag is a hash of this dir and cicd/tool-versions.env, so editing either
# means a new image. The go-installed tools, shellcheck and ruff take their
# versions from tool-versions.env as build args. Bump one there without its
# checksum here and the build fails on the checksum.
#
# Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
# SPDX-License-Identifier: MIT

FROM debian:trixie-slim@sha256:a29215f6a35e51e22adffa17f89e9d2ef06214e64a2bad10d765c46aea49f11f

# Apt is pinned only as far as the base image is. Pango, cairo and gi are for the
# gif's color emoji. The font packages are the ones the gif falls back on that
# Debian has byte for byte; the rest come from gif-fonts below. No other fonts,
# since one the host lacks could win a glyph there and change the gif.
# rpm and dpkg only read what nfpm writes. cargo builds the llfourn interop adapter.
RUN apt-get update \
	&& apt-get install -y --no-install-recommends \
		bash ca-certificates curl git make xz-utils zip unzip file bc xxd time openssl \
		nsis rpm dpkg cargo rustc gifsicle \
		python3 python3-pil python3-fonttools python3-gi python3-gi-cairo python3-cairo gir1.2-pango-1.0 \
		fontconfig fonts-freefont-ttf fonts-vlgothic fonts-dzongkha \
	&& rm -rf /var/lib/apt/lists/*

ARG GO_VER=1.26.2
ARG GO_SHA256=990e6b4bbba816dc3ee129eaeaf4b42f17c2800b88a2166c265ac1a200262282
ARG NODE_VER=22.23.2
ARG NODE_SHA256=d60acfe00a2932254bb0ad20e01b0d74397a0875595de719654b214f4b03f307
ARG MONASPACE_VER=1.400
ARG MONASPACE_SHA256=ab66d71be751495f679727332a3345597943bd4d7beebca03f5cde04bf994de7
ARG SHELLCHECK_VERSION
# Upstream posts no checksums. Taken from the download, 20261010.
ARG SC_SHA256=8c3be12b05d5c177a04c29e3c78ce89ac86f1595681cab149b65b97c4e227198
ARG RUFF_VERSION
ARG RUFF_SHA256=853462df618fb9f156a9f04d9d899d9e5a9e1a43fbffaec72df4bb159348e71b

WORKDIR /tmp/dl
RUN test -n "${SHELLCHECK_VERSION}" && test -n "${RUFF_VERSION}" \
	&& curl -fsSLo go.tgz "https://go.dev/dl/go${GO_VER}.linux-amd64.tar.gz" \
	&& echo "${GO_SHA256}  go.tgz" | sha256sum -c - \
	&& tar -C /opt -xzf go.tgz \
	&& curl -fsSLo node.txz "https://nodejs.org/dist/v${NODE_VER}/node-v${NODE_VER}-linux-x64.tar.xz" \
	&& echo "${NODE_SHA256}  node.txz" | sha256sum -c - \
	&& mkdir /opt/node && tar -C /opt/node --strip-components=1 -xJf node.txz \
	&& curl -fsSLo sc.txz "https://github.com/koalaman/shellcheck/releases/download/v${SHELLCHECK_VERSION}/shellcheck-v${SHELLCHECK_VERSION}.linux.x86_64.tar.xz" \
	&& echo "${SC_SHA256}  sc.txz" | sha256sum -c - \
	&& tar -C /usr/local/bin --strip-components=1 -xJf sc.txz "shellcheck-v${SHELLCHECK_VERSION}/shellcheck" \
	&& curl -fsSLo ruff.tgz "https://github.com/astral-sh/ruff/releases/download/${RUFF_VERSION}/ruff-x86_64-unknown-linux-musl.tar.gz" \
	&& echo "${RUFF_SHA256}  ruff.tgz" | sha256sum -c - \
	&& tar -C /usr/local/bin --strip-components=1 -xzf ruff.tgz ruff-x86_64-unknown-linux-musl/ruff \
	&& curl -fsSLo mona.zip "https://github.com/githubnext/monaspace/releases/download/v${MONASPACE_VER}/monaspace-static-v${MONASPACE_VER}.zip" \
	&& echo "${MONASPACE_SHA256}  mona.zip" | sha256sum -c - \
	&& mkdir -p /usr/local/share/fonts/monaspace \
	&& unzip -j -q mona.zip '*/Monaspace Argon/*.otf' -d /usr/local/share/fonts/monaspace \
	&& cd / && rm -rf /tmp/dl

ENV PATH=/opt/gotools/bin:/opt/go/bin:/opt/node/bin:${PATH} \
	GOTOOLCHAIN=local

ARG GOLANGCI_LINT_VERSION
ARG STATICCHECK_VERSION
ARG GOVULNCHECK_VERSION
ARG NFPM_VERSION
RUN test -n "${GOLANGCI_LINT_VERSION}" && test -n "${STATICCHECK_VERSION}" && test -n "${GOVULNCHECK_VERSION}" && test -n "${NFPM_VERSION}" \
	&& export GOBIN=/opt/gotools/bin GOPATH=/tmp/gopath GOCACHE=/tmp/gocache \
	&& go install "github.com/golangci/golangci-lint/v2/cmd/golangci-lint@${GOLANGCI_LINT_VERSION}" \
	&& go install "honnef.co/go/tools/cmd/staticcheck@${STATICCHECK_VERSION}" \
	&& go install "golang.org/x/vuln/cmd/govulncheck@${GOVULNCHECK_VERSION}" \
	&& go install "github.com/goreleaser/nfpm/v2/cmd/nfpm@${NFPM_VERSION}" \
	&& rm -rf /tmp/gopath /tmp/gocache

# The gif's other fallback fonts, such as Arial Unicode and Tahoma, which no
# package or release has. cicd.bash passes them in from ../private/fonts/demo-gif,
# never the repo, so this image is for local use only. They must match
# gif-fonts.sha256 exactly. Without them the dir is empty and the gif is skipped.
COPY gif-fonts.sha256 /usr/local/share/fonts/
COPY --from=gif-fonts . /usr/local/share/fonts/demo-gif/
RUN cd /usr/local/share/fonts/demo-gif \
	&& if [ -n "$(ls -A)" ]; then \
		[ "$(ls -A | wc -l)" = "$(wc -l <../gif-fonts.sha256)" ] && sha256sum --quiet -c ../gif-fonts.sha256; \
	fi \
	&& fc-cache -s

# Runs as the caller's uid, which has no passwd entry here. /cache is where the
# named volume goes, and a new volume takes this dir's mode, so anyone can write.
RUN mkdir -m 1777 /cache /cache/home
ENV HOME=/cache/home \
	CICD_IN_CONTAINER=1 \
	CICD_NO_SKIP=1
WORKDIR /
