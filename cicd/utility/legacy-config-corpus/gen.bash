#!/usr/bin/env bash

##	Purpose:
##		- Rebuild lib/convertbase/testdata/legacy-config-corpus.jsonl from every
##		  SHCL release before 3.0, which TestLegacyConfigCorpus then walks on
##		  every test run.
##		- Fetches each release's Go binding into a scratch copy of this folder,
##		  so nothing old is kept in the tree. Needs the network; the test does not.
##		- Fails, and writes nothing, when the current loader loads any text to a
##		  base some old release read differently.
##		- Usage: cicd/utility/legacy-config-corpus/gen.bash [-full N] [-keep N]
##	History: At bottom.

##	Copyright © 2023-2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
##	Licensed under the GPL, Version 2 or later. Full text in ../../../license.md, or:
##		https://spdx.org/licenses/GPL-2.0-or-later.html
##	SPDX-License-Identifier: GPL-2.0-or-later

set -Eeuo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${here}/../../.." && pwd)"

## Every release before 3.0, prereleases included. None of them wrote a
## Format line, so a file without one could be from any.
tags=(v1.0.0-beta1 v1.0.0-beta2 v1.0.0-rc1 v1.0.0 v1.1.0 v1.2.0 v2.0.0)

source "${here}/../include/safe-rm.bash"
tmpRoot="$(realpath -- "${TMPDIR:-/tmp}")"
work="$(mktemp -d "${tmpRoot}/legacy-corpus.XXXXXX")"
trap 'fSafeRmUnder "${tmpRoot}" "${work}" || true' EXIT

## Go ignores a go.mod in the temp root itself, so the module and its own
## temp folder each get one under it.
gen="${work}/gen"
mkdir -p "${gen}" "${work}/tmp"
cp -r "${here}/." "${gen}/"
sed -i "s#=> ../../../lib#=> ${root}/lib#" "${gen}/go.mod"
for tag in "${tags[@]}"; do
	dir="${tag//./_}"; dir="${gen}/old/${dir//-/_}"
	mkdir -p "${dir}"
	curl -sSfL --max-time 30 -o "${dir}/shcl.go" \
		"https://raw.githubusercontent.com/yottacore/shcl/${tag}/source/go/shcl.go"
	cp "${gen}/adapter.go.tmpl" "${dir}/adapter.go"
	grep -q '^func QuoteSegment' "${dir}/shcl.go" \
		|| sed -i 's/"base."+QuoteSegment(f)/"base."+f/' "${dir}/adapter.go"
done

(cd "${gen}" && TMPDIR="${work}/tmp" go run . -out "${root}/lib/convertbase/testdata/legacy-config-corpus.jsonl" "$@")


##	History:
##		- 2026-11-06: Created, for the move to SHCL 3.0.0-beta1.
