#!/usr/bin/env bash
set -euo pipefail

##	Purpose:
##		- Keep the go-installed pipeline tools at the versions pinned in
##		  cicd/tool-versions.env. A missing or drifted tool is (re)installed
##		  with `go install`.
##		- Warn-only: an install failure (e.g. offline) keeps whatever is there;
##		  the probe-gated stages still skip a tool that stays missing.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${here}/../tool-versions.env"

## Install where the engine's PATH looks first, so a stale copy elsewhere can't win.
export GOBIN="${HOME}/.go/bin"

fPin(){
	local exe="$1" want="$2" module="$3"; shift 3
	local have=""
	command -v "${exe}" >/dev/null 2>&1 && have="$("${exe}" "$@" 2>&1 || true)"
	if [[ "${have}" == *"${want#v}"* ]]; then
		echo "[ pin: ${exe} ${want} ok ]"
	else
		echo "[ pin: installing ${exe} ${want} ... ]"
		go install "${module}@${want}" || echo "[ pin: WARNING: ${exe} install failed; keeping what's there ]"
	fi
}

fPin golangci-lint "${GOLANGCI_LINT_VERSION}" github.com/golangci/golangci-lint/v2/cmd/golangci-lint version
fPin staticcheck   "${STATICCHECK_VERSION}"   honnef.co/go/tools/cmd/staticcheck                       -version
fPin govulncheck   "${GOVULNCHECK_VERSION}"   golang.org/x/vuln/cmd/govulncheck                        -version
