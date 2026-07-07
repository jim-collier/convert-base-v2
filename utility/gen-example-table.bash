#!/usr/bin/env bash
#
# Generate the README "Example output" table: one fixed base-10 number shown in
# every displayable base, with a character count. Regenerate whenever the set of
# bases (or their alphabets) changes, and paste the output into README.md under
# the "Example output" heading.
#
# Usage:  gen-example-table.bash [path-to-convert-base-v2]
# Env:    CBTABLE_NUM (the base-10 number to show; has a sensible default)
#
set -Eeuo pipefail

meDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXE="${1:-${meDir}/../source/convert-base-v2}"
[[ -x "$EXE" ]] || EXE="$(command -v convert-base-v2 2>/dev/null || true)"
[[ -x "$EXE" ]] || { echo "convert-base-v2 not found; pass its path" >&2; exit 1; }

NUM="${CBTABLE_NUM:-2023090613425900000000000000001}"

# Markdown-escape a table cell: backslash, pipe, backtick, and the control-char
# digits (tab/newline/return, which the keyboard base can emit) shown as escapes.
esc() {
	sed -e 's/\\/\\\\/g' -e 's/|/\\|/g' -e 's/`/\\`/g' \
	    -e 's/\t/\\t/g' | awk 'BEGIN{ORS=""} {print sep $0; sep="\\n"}'
}

printf '| Base | Chars | Number representation\n'
printf '| :-- | --: | :--\n'
while read -r name _; do
	# binary is raw bytes, not displayable as text.
	if [[ "$name" == "binary" ]]; then continue; fi
	rep="$("$EXE" --from 10 --to "$name" -- "$NUM" 2>/dev/null)" || continue
	chars="$(printf '%s' "$rep" | LC_ALL=C.UTF-8 wc -m | tr -d ' ')"
	printf '| %s | %s | %s\n' "$name" "$chars" "$(printf '%s' "$rep" | esc)"
done < <("$EXE" --list | tail -n +2)
