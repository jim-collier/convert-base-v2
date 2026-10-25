#!/usr/bin/env bash

##	Purpose:
##		- The CodeQL part of the leak checks (cicd.bash stage 4d). Builds a Go
##		  database from a scratch copy of lib/ with the dependencies vendored, so
##		  third-party code is in it too, runs the query suite beside this script
##		  over it, and writes the SARIF where it's told.
##		- Exit 1 on any result, or when the database is missing a part it should
##		  have, since a scan of nothing would pass.
##		- Needs the pinned CodeQL in the container image. Never install it here.
##		- Syntax: cicd/utility/codeql-scan.bash SARIF_OUT
##	History: At bottom.

##	Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT

set -Eeuo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${here}/../.." && pwd)"
sarif="${1:?usage: codeql-scan.bash SARIF_OUT}"
suite="${here}/codeql/leak-checks.qls"
## cicd hands it the heavy step count as GOMAXPROCS. Run by hand, it works one
## out the same way, since 0 here would mean every core.
threads="${GOMAXPROCS:-}"
if [[ ! "${threads}" =~ ^[1-9][0-9]*$ ]]; then
	source "${here}/include/machine-use.bash"
	fMachineJobs "$(fMachineCpus)" "$(fMachineLoad1)"; threads="${machineJobsHeavy}"
fi

## Each of these must be in the database's source archive. The browser and
## reactor modules only build for wasm, so each gets its own pass below.
mustHave=(cmd/convert-base-v2/main.go convertbase/convert.go convertbase/convert_test.go internal/errcode/ shcl/shcl.go
	wasm/main.go reactor/main.go vendor/go.uber.org/goleak/)

tmp="$(mktemp -d "${TMPDIR:-/tmp}/codeql.XXXXXX")"
fCleanup(){ if [[ -d "${tmp}" && "${tmp}" == "${TMPDIR:-/tmp}/codeql."* ]]; then rm -rf "${tmp}"; fi; }
trap fCleanup EXIT

## go mod vendor writes into the module, so it never runs in the repo.
mkdir "${tmp}/lib"
tar -C "${root}/lib" --exclude=./bin --exclude=./dist --exclude=./convert-base-v2 --exclude='*.wasm' -cf - . | tar -C "${tmp}/lib" -xf -
(cd "${tmp}/lib" && go mod vendor)

## The extractor is called the way the bundle's own autobuild does it, once per
## target. A traced `go build` leaves out the tests, and with them goleak, the
## one module vendored. It logs every file, so that goes aside unless it fails.
cat >"${tmp}/build.bash" <<'EOF'
set -e
x="${CODEQL_EXTRACTOR_GO_ROOT}/tools/${CODEQL_PLATFORM}/go-extractor"
log="${0%/*}/extract.log"
fExtract(){ "${x}" -mod=vendor "$@" 2>>"${log}" || { tail -20 "${log}" >&2; exit 1; }; }
fExtract ./...
GOOS=js GOARCH=wasm fExtract ./wasm
GOOS=wasip1 GOARCH=wasm fExtract ./reactor
EOF
codeql database create "${tmp}/db" --quiet --language=go --source-root="${tmp}/lib" --threads="${threads}" \
	--extractor-option go.extract_vendor_dirs=true --extractor-option go.extract_tests=true \
	--command="bash ${tmp}/build.bash"

python3 -I - "${tmp}/db/src.zip" "${tmp}/lib" "${mustHave[@]}" <<'EOF'
import sys, zipfile
names = zipfile.ZipFile(sys.argv[1]).namelist()
base = sys.argv[2].lstrip("/") + "/"
rel = [n.split(base, 1)[1] for n in names if base in n]
missing = [p for p in sys.argv[3:] if not any(r.startswith(p) for r in rel)]
if missing:
    sys.exit("CodeQL: the database has nothing from " + ", ".join(missing))
print(f"CodeQL: {len(rel)} source files in the database")
EOF

mkdir -p "$(dirname "${sarif}")"
codeql database analyze "${tmp}/db" "${suite}" --quiet --format=sarif-latest --output="${sarif}" --threads="${threads}"

## Every result fails, wherever it is. Paths print as the repo has them.
python3 -I - "${sarif}" <<'EOF'
import json, sys
runs = json.load(open(sys.argv[1]))["runs"]
found = 0
for run in runs:
    for r in run.get("results", []):
        loc = r["locations"][0]["physicalLocation"]
        print(f"lib/{loc['artifactLocation']['uri']}:{loc.get('region', {}).get('startLine', 0)}: {r['ruleId']}: {r['message']['text']}")
        found += 1
rules = sum(1 for run in runs for c in [run["tool"]["driver"], *run["tool"].get("extensions", [])]
            for q in c.get("rules", []) if q.get("properties", {}).get("kind", "").endswith("problem"))
if not rules:
    sys.exit("CodeQL: no queries ran")
print(f"CodeQL: {found} result(s) from {rules} queries" if found else f"CodeQL: no results from {rules} queries")
sys.exit(1 if found else 0)
EOF


##	History:
##		- 2026-10-19 JC: Created.
