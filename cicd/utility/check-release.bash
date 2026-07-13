#!/usr/bin/env bash

#  shellcheck disable=2086  ## integer word-splitting is fine.

##	Purpose:
##		- Release-readiness guard, run on a push to main before anything is
##		  tagged or published. Hard-fails (exit 1) unless:
##		    1. `var version` in source/main.go is set,
##		    2. its tag does not already exist (i.e. the version was bumped),
##		    3. it sorts strictly after the newest existing release tag (no going
##		       backwards),
##		    4. the README Lifecycle badge matches the version's stage
##		       (alpha/beta/rc/none -> Alpha/Beta/RC/Stable).
##		- On success, and when $GITHUB_OUTPUT is set, writes ver= and new=1 so
##		  the release workflow can reuse the resolved version.
##		- Also runnable by hand on dev to see whether a merge to main would
##		  release cleanly.
##	History: At bottom.

##	Copyright © 2026 Jim Collier
##	Licensed under GNU GPL v2 <https://www.gnu.org/licenses/gpl-2.0.html>. No warranty.
##	SPDX-License-Identifier: GPL-2.0-or-later

set -Eeuo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${here}/../.." && pwd)"
[[ "${1:-}" == "--repo" && -n "${2:-}" ]] && root="$2"

main_go="${root}/source/main.go"
readme="${root}/README.md"

fFail(){ echo "release check FAILED: $*" >&2; exit 1; }

## 1. Version must be set.
ver="$(sed -n 's/^var version = "\(v[0-9][^"]*\)".*/\1/p' "${main_go}")"
[[ -n "${ver}" ]] || fFail "no 'var version' in ${main_go}"

## 2. Its tag must not exist yet (bumped since the last release).
if git -C "${root}" rev-parse -q --verify "refs/tags/${ver}" >/dev/null 2>&1; then
	fFail "tag ${ver} already exists - bump 'var version' in source/main.go before merging to main"
fi

## 3. Must sort strictly after the newest existing release tag. Map '-' to '~'
## so a pre-release sorts before its final, the way sort -V (and dpkg/rpm) read it.
cand="${ver//-/\~}"
newest="$(git -C "${root}" tag --list 'v[0-9]*' | sed 's/-/~/g' | sort -V | tail -1)"
if [[ -n "${newest}" ]]; then
	top="$(printf '%s\n%s\n' "${newest}" "${cand}" | sort -V | tail -1)"
	[[ "${top}" == "${cand}" && "${cand}" != "${newest}" ]] \
		|| fFail "version ${ver} does not sort after the newest tag (${newest//\~/-}) - it must go forward"
fi

## 4. Lifecycle badge must match the version stage.
case "${ver,,}" in
	*alpha*) want="Alpha" ;;
	*beta*)  want="Beta"  ;;
	*rc*)    want="RC"    ;;
	*)       want="Stable" ;;
esac
have="$(grep -oE 'Lifecycle-[A-Za-z]+-' "${readme}" | head -1 | sed -E 's/^Lifecycle-(.*)-$/\1/')"
[[ -n "${have}" ]] || fFail "no Lifecycle badge found in README.md"
[[ "${have,,}" == "${want,,}" ]] \
	|| fFail "README Lifecycle badge is '${have}' but version ${ver} is '${want}' - update the badge"

echo "release check OK: ${ver} (stage ${want}), newest tag ${newest:-none}"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
	{ echo "ver=${ver}"; echo "new=1"; } >> "${GITHUB_OUTPUT}"
fi


##	History:
##		- 2026-07-12 JC: Created. Version-bump + Lifecycle-badge guard for the release path.
