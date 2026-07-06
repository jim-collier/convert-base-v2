#!/usr/bin/env bash
#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## gen-screenshots.bash
##
##	Renders README screenshots for convert-base-v2. Since the program is a CLI,
##	these are terminal transcripts of real command output, drawn to sharp
##	1920x1080 PNGs and downsampled to 640x360 thumbnails.
##
##	Output:
##		<repo>/assets/screenshots/large/*.png   (1920x1080 originals)
##		<repo>/assets/screenshots/*.png          (640x360 thumbnails)
##
##	Usage:
##		gen-screenshots.bash [REPO_GITHUB_DIR] [BIN]
##		  REPO_GITHUB_DIR : the 'github' working dir (default: env CBV_REPO, or cwd)
##		  BIN             : the binary to invoke (default: env CBV_BIN, or built copy)
##
##	Content is deliberately anonymous: neutral prompt, made-up paths, no
##	names or usernames.
##
##	Deps: ImageMagick 7 with the pango delegate, a monospace font, and Unifont
##	installed for wide-unicode fallback.
##
##	History: at bottom.
#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••

##	Copyright © 2026 Jim Collier (ID: 1cv◂‡Vᛦ)
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT


set -Eeuo pipefail
export LANG="C.UTF-8" LC_ALL="C.UTF-8"
## Pin the timestamp ImageMagick would otherwise stamp into each PNG, so repeated
## runs produce byte-identical files (no git churn). Paired with -strip below.
export SOURCE_DATE_EPOCH=0

## bash 5.2 turns '&' in a ${var//pat/repl} replacement into the matched text.
## The markup escaper below wants a literal '&', so turn that behavior off.
shopt -u patsub_replacement 2>/dev/null || true


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Setup: locate the repo and the binary
#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
REPO="${1:-${CBV_REPO:-$PWD}}"
[[ -d "${REPO}/source" ]] || { echo "gen-screenshots: '${REPO}' is not the github dir (no source/)" >&2; exit 1; }

BIN="${2:-${CBV_BIN:-}}"
if [[ -z "${BIN}" ]]; then
	for cand in "${REPO}/source/bin/convert-base-v2" "${REPO}/source/convert-base-v2"; do
		[[ -x "${cand}" ]] && { BIN="${cand}"; break; }
	done
fi
[[ -x "${BIN}" ]] || { echo "gen-screenshots: build the binary first (make -C source local)" >&2; exit 1; }

command -v magick >/dev/null 2>&1 || { echo "gen-screenshots: ImageMagick 'magick' not found" >&2; exit 1; }
magick -list format 2>/dev/null | grep -qi pango || { echo "gen-screenshots: ImageMagick lacks the pango delegate" >&2; exit 1; }

LARGE="${REPO}/assets/screenshots/large"
SMALL="${REPO}/assets/screenshots"
mkdir -p "${LARGE}" "${SMALL}"

WORK="$(mktemp -d)"; trap 'rm -rf "${WORK}"' EXIT


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Terminal look
#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## pango: resolves a fontconfig family name; -annotate (IM freetype) needs a
## real font file. Fira Code ships both a TTF and a matching family name.
FONT_FAMILY="Fira Code"
FONT_FILE="$(fc-match -f '%{file}' 'Fira Code:style=Regular')"
[[ -r "${FONT_FILE}" ]] || FONT_FILE="$(fc-match -f '%{file}' 'DejaVu Sans Mono')"
PT=30
BG="#0d1117"          # github dark
BAR="#161b22"
C_PROMPT="#3fb950"    # green $
C_CMD="#e6edf3"       # bright command text
C_OUT="#9da7b3"       # muted output
C_CMT="#6e7681"       # comments
C_TITLE="#8b949e"

## esc TEXT  : escape text for pango markup. Double-escaped on purpose: the IM
## pango coder decodes one XML entity layer before handing the string to pango,
## so a single &amp; would reach pango as a bare '&' and abort the parse. The
## span tags carry no entities, so they pass through that decode unchanged.
esc(){ local s="$1"; s="${s//&/&amp;amp;}"; s="${s//</&amp;lt;}"; s="${s//>/&amp;gt;}"; printf '%s' "$s"; }

MARKUP=""   # accumulates the current transcript
reset_markup(){ MARKUP=""; }
## p CMD          : a prompt line ("$ CMD")
## o LINE         : an output line
## c TEXT         : a comment line
## blank          : a spacer line
p(){     MARKUP+="<span foreground=\"${C_PROMPT}\">\$</span> <span foreground=\"${C_CMD}\">$(esc "$1")</span>"$'\n'; }
o(){     MARKUP+="<span foreground=\"${C_OUT}\">$(esc "$1")</span>"$'\n'; }
c(){     MARKUP+="<span foreground=\"${C_CMT}\">$(esc "$1")</span>"$'\n'; }
blank(){ MARKUP+=$'\n'; }

## render NAME TITLE  : draw the accumulated MARKUP to a 1920x1080 PNG
render(){
	local name="$1" title="$2"
	## Markup is passed inline: IM's default policy blocks reading text via @file.
	## The pango composite must come before any -gravity North: an ambient North
	## gravity leaks into the pango coder and renders the text rotated 180. So the
	## title bar text is annotated last, after the transcript is in place.
	magick -size 1920x1080 "xc:${BG}" \
		-fill "${BAR}"     -draw "rectangle 0,0 1920,72" \
		-fill "#ff5f56"    -draw "circle 46,36 46,47" \
		-fill "#ffbd2e"    -draw "circle 84,36 84,47" \
		-fill "#27c93f"    -draw "circle 122,36 122,47" \
		\( -background none -font "${FONT_FAMILY}" -pointsize "${PT}" "pango:${MARKUP}" \) \
		-gravity NorthWest -geometry +72+116 -composite \
		-font "${FONT_FILE}" -pointsize 22 -fill "${C_TITLE}" -gravity North -annotate +0+24 "${title}" \
		-strip -define png:exclude-chunks=date,time -define png:compression-level=9 \
		"${LARGE}/${name}.png"
	## Downsample only (source is always 1920x1080 >= 640x360). A 256-colour
	## palette roughly halves the thumbnail with no visible loss at this size.
	magick "${LARGE}/${name}.png" -filter Lanczos -resize 640x360 -colors 256 \
		-strip -define png:exclude-chunks=date,time -define png:compression-level=9 "${SMALL}/${name}.png"
	echo "  ${name}.png"
}

## run ARGS...  : run the binary, echo its stdout (trailing newline trimmed)
run(){ "${BIN}" "$@"; }


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## 1. Everyday conversions
#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
reset_markup
c "# Everyday conversions"
blank
p "convert-base-v2 255 16";              o "$(run 255 16)"
p "convert-base-v2 --from 16 FF";        o "$(run --from 16 FF)"
p "convert-base-v2 -- -123456 16";       o "$(run -- -123456 16)"
p "convert-base-v2 255 octal";           o "$(run 255 octal)"
p "convert-base-v2 --from 2 11111111";   o "$(run --from 2 11111111)"
p "convert-base-v2 3.14159 16";          o "$(run 3.14159 16)"
render "01-everyday" "convert-base-v2  -  everyday conversions"


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## 2. Big numbers, exotic bases
#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
reset_markup
big="1234567899999999999999999999999999987654321"
enc2048twitter="$(run "${big}" 2048twitter)"
c "# Arbitrary size, exotic bases"
blank
p "convert-base-v2 ${big} 62";       o "$(run "${big}" 62)"
p "convert-base-v2 ${big} 256jc1";   o "$(run "${big}" 256jc1)"
p "convert-base-v2 ${big} 2048twitter";     o "${enc2048twitter}"
p "convert-base-v2 --from 2048twitter '${enc2048twitter}'"; o "$(run --from 2048twitter "${enc2048twitter}")"
render "02-bignum" "convert-base-v2  -  arbitrary size, exotic bases"


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## 3. Custom alphabets and markers
#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
reset_markup
c "# Define your own alphabet, negative and decimal markers"
blank
p "convert-base-v2 --from-symbols ABCD --to 10 CBBA.B"
o "$(run --from-symbols ABCD --to 10 CBBA.B)"
blank
p "convert-base-v2 --from-symbols \"aeiouy.-_0 neg=~ dec=/\" --to 20w \"~y0-._/ooo\""
o "$(run --from-symbols "aeiouy.-_0 neg=~ dec=/" --to 20w "~y0-._/ooo")"
blank
p "convert-base-v2 --to-symbols \"🌑🌒🌓🌔🌕🌖🌗🌘\" 1234"
o "$(run --to-symbols "🌑🌒🌓🌔🌕🌖🌗🌘" 1234)"
render "03-custom" "convert-base-v2  -  custom alphabets"


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## 4. Binary / streaming round-trip
#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
reset_markup
## Deterministic payload so the rendered image is stable across runs (no git
## churn on repeated cicd runs). Built without a pipe to avoid a SIGPIPE trip.
src="${WORK}/archive.bin"; payload="convert-base-v2 sample archive payload 0123456789ABCDEF "
data=""; while ((${#data} < 512)); do data+="${payload}"; done
printf '%s' "${data:0:512}" >"${src}"
b64="$(run --from binary --to 64u <"${src}")"
run --from 64u --to binary <<<"${b64}" >"${WORK}/archive2.bin"
cmpmsg="bit-perfect"; cmp -s "${src}" "${WORK}/archive2.bin" || cmpmsg="differ"
snippet="${b64:0:64}..."
c "# Stream any file to a power-of-2 base and back, bit-perfect"
blank
p "cat ~/data/archive.bin | convert-base-v2 --from binary --to 64u > archive.b64"
p "head -c 64 archive.b64";  o "${snippet}"
blank
p "cat archive.b64 | convert-base-v2 --from 64u --to binary > archive2.bin"
p "cmp ~/data/archive.bin archive2.bin && echo ${cmpmsg}";  o "${cmpmsg}"
render "04-binary" "convert-base-v2  -  binary streaming round-trip"


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## 5. Configuration and the base list (the CLI's "settings")
#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
reset_markup
c "# User config adds your own bases; --list shows them all"
blank
p "cat ~/.config/convert-base-v2/convert-base-v2.conf"
o "- aliases: [pentary, myfive]"
o "  symbols: \"0 1 2 3 4\""
o "- aliases: [moon8]"
o "  symbols: \"🌑 🌒 🌓 🌔 🌕 🌖 🌗 🌘\""
blank
p "convert-base-v2 --list | head -10"
while IFS= read -r line; do o "${line}"; done < <(run --list | head -10)
render "05-settings" "convert-base-v2  -  configuration and base list"


echo "gen-screenshots: wrote 5 originals to ${LARGE} and thumbnails to ${SMALL}"


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## History
##		- 2026-07-04 JC: First version. Five terminal transcripts (everyday,
##		  exotic bases, custom alphabets, binary streaming, config + list).
#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
