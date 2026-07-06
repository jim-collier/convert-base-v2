#!/usr/bin/env bash
#
# Streaming binary<->text throughput benchmark: convert-base-v2 vs the common
# system encoders (base64, base32, basenc, openssl, xxd).
#
# All I/O happens in a tmpfs (RAM, /dev/shm) so the numbers reflect the codecs,
# not disk speed, and are repeatable on any machine. Each program is fed the
# identical input: one random blob to encode, and each format group's own
# canonical text to decode. Throughput is measured over the binary side.
#
# Usage:   bench-encoders.bash [path-to-convert-base-v2]
# Env:     BENCH_SIZE_MIB (default 256), BENCH_RUNS (default 10)
#
set -Eeuo pipefail

meDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SIZE_MIB="${BENCH_SIZE_MIB:-256}"
RUNS="${BENCH_RUNS:-10}"

# Locate the binary under test: CLI arg, env, repo build, or PATH.
EXE="${1:-${BENCH_EXE:-}}"
if [[ -z "$EXE" ]]; then
	for c in "${meDir}/../source/convert-base-v2" "${meDir}/../source/bin/convert-base-v2"; do
		[[ -x "$c" ]] && { EXE="$c"; break; }
	done
fi
[[ -z "$EXE" ]] && command -v convert-base-v2 >/dev/null 2>&1 && EXE="$(command -v convert-base-v2)"
[[ -x "$EXE" ]] || { echo "convert-base-v2 not found; pass its path as the first argument" >&2; exit 1; }

# Work in RAM so slow disks don't skew the result.
if [[ -d /dev/shm && -w /dev/shm ]]; then
	work="$(mktemp -d /dev/shm/cbench.XXXXXX)"
else
	echo "note: /dev/shm unavailable, falling back to \$TMPDIR (may hit disk)" >&2
	work="$(mktemp -d)"
fi
trap 'rm -rf "$work"' EXIT

blob="${work}/blob"
head -c "$(( SIZE_MIB * 1024 * 1024 ))" /dev/urandom >"$blob"

have()  { command -v "$1" >/dev/null 2>&1; }
comma() { echo "$1" | sed ':a;s/\B[0-9]\{3\}\>/,&/;ta'; }

# Mean MiB/s of `cmd < infile` (output discarded) over $RUNS runs, one warmup.
bench() {
	local infile="$1"; shift
	"$@" <"$infile" >/dev/null 2>&1 || true
	local total=0 r t0 t1
	for ((r = 0; r < RUNS; r++)); do
		t0=$(date +%s.%N)
		"$@" <"$infile" >/dev/null 2>&1
		t1=$(date +%s.%N)
		total=$(awk -v a="$total" -v x="$t0" -v y="$t1" 'BEGIN{printf "%.6f", a + (y - x)}')
	done
	awk -v s="$SIZE_MIB" -v n="$RUNS" -v t="$total" 'BEGIN{printf "%.0f", s * n / t}'
}

# One markdown row: name, then text->binary and binary->text throughput.
row() {
	local name="$1" dec_in="$2" enc_cmd="$3" dec_cmd="$4"
	local d e
	# shellcheck disable=SC2086  # commands are trusted, word-splitting is intended
	d=$(bench "$dec_in" $dec_cmd)
	# shellcheck disable=SC2086
	e=$(bench "$blob" $enc_cmd)
	printf '| %s | %s | %s |\n' "$name" "$(comma "$d")" "$(comma "$e")"
}

# Canonical text per format (prefer the system tool's own output, so every
# decoder in a group sees identical bytes).
b64="${work}/b64"; b32="${work}/b32"; hex="${work}/hex"
if have base64; then base64 <"$blob" >"$b64"; else "$EXE" --from binary --to 64 <"$blob" >"$b64"; fi
if have base32; then base32 <"$blob" >"$b32"; else "$EXE" --from binary --to 32 <"$blob" >"$b32"; fi
if have xxd;    then xxd -p  <"$blob" >"$hex"; else "$EXE" --from binary --to 16 <"$blob" >"$hex"; fi

# Header: what and where.
cpu="$(sed -n 's/^model name[[:space:]]*: //p' /proc/cpuinfo | head -1)"
memgib=$(( $(sed -n 's/^MemTotal:[[:space:]]*\([0-9]*\).*/\1/p' /proc/meminfo) / 1024 / 1024 ))
printf '\n%s MiB random blob, mean of %s runs, one process each, all I/O in RAM.\n' "$SIZE_MIB" "$RUNS"
printf 'CPU: %s (%s threads).  RAM: %s GiB.\n\n' "$cpu" "$(nproc)" "$memgib"

# One table per format, so like-for-like sits together.
table() { printf '\n%s\n\n| Program | text -> binary | binary -> text |\n| :-- | --: | --: |\n' "$1"; }

table "Base-64"
row "convert-base-v2" "$b64" "$EXE --from binary --to 64" "$EXE --from 64 --to binary --raw"
if have base64;  then row "coreutils base64"  "$b64" "base64"          "base64 -d";          fi
if have basenc;  then row "coreutils basenc"  "$b64" "basenc --base64" "basenc -d --base64"; fi
if have openssl; then row "openssl base64"    "$b64" "openssl base64"  "openssl base64 -d";  fi

table "Base-32"
row "convert-base-v2" "$b32" "$EXE --from binary --to 32" "$EXE --from 32 --to binary --raw"
if have base32;  then row "coreutils base32"  "$b32" "base32"          "base32 -d";          fi
if have basenc;  then row "coreutils basenc"  "$b32" "basenc --base32" "basenc -d --base32"; fi

table "Hex"
row "convert-base-v2" "$hex" "$EXE --from binary --to 16" "$EXE --from 16 --to binary --raw"
if have xxd;     then row "xxd"               "$hex" "xxd -p"          "xxd -p -r";          fi
echo
