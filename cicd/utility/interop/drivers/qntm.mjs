#!/usr/bin/env node

//	Batch adapter over qntm's published base2048, base32768 and base65536
//	packages, so the interop suite can compare a whole run of samples against
//	them in one process instead of spawning node per sample.
//
//	usage: qntm.mjs <2048|32768|65536> <encode|decode>
//	  encode: stdin is one lowercase hex string per line, stdout is the encoded
//	          text, one line per input.
//	  decode: the reverse. A line the reference refuses comes back as "!error",
//	          which can never collide with real output (every alphabet here is
//	          non-ASCII) and so shows up as a mismatch rather than a crash.
//
//	Copyright © 2026 Bubbles (ID: XଌฅრX۳ᛟԃლፀƅꓩหδლც)
//	Licensed under GNU GPL v2 <https://www.gnu.org/licenses/gpl-2.0.html>. No warranty.
//	SPDX-License-Identifier: GPL-2.0-or-later

import { readFileSync } from 'node:fs'

const PACKAGES = {
	'2048': '../thirdparty/base2048-qntm/src/index.js',
	'32768': '../thirdparty/base32768-qntm/src/index.js',
	'65536': '../thirdparty/base65536-qntm/src/index.js'
}

const [size, mode] = process.argv.slice(2)
if (!(size in PACKAGES) || (mode !== 'encode' && mode !== 'decode')) {
	process.stderr.write('usage: qntm.mjs <2048|32768|65536> <encode|decode>\n')
	process.exit(2)
}

const ref = await import(new URL(PACKAGES[size], import.meta.url))

const hexToBytes = hex => {
	const out = new Uint8Array(hex.length / 2)
	for (let i = 0; i < out.length; i++) {
		out[i] = parseInt(hex.substr(i * 2, 2), 16)
	}
	return out
}
const bytesToHex = bytes => Array.from(bytes, b => b.toString(16).padStart(2, '0')).join('')

// A trailing newline would otherwise read as one extra empty sample.
const input = readFileSync(0, 'utf8')
const lines = input.length === 0 ? [] : input.replace(/\n$/, '').split('\n')

const out = lines.map(line => {
	try {
		return mode === 'encode' ? ref.encode(hexToBytes(line)) : bytesToHex(ref.decode(line))
	} catch {
		return '!error'
	}
})

process.stdout.write(out.map(line => line + '\n').join(''))
