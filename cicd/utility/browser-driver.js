//	Copyright © 2023-2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
//	Licensed under the GPL, Version 2 or later. Full text in ../../license.md, or:
//		https://spdx.org/licenses/GPL-2.0-or-later.html
//	SPDX-License-Identifier: GPL-2.0-or-later

// Batch driver for the browser module, run under node:
//
//	node browser-driver.js WASM_EXEC.js convert-base.wasm < requests
//
// Reads the module-driver protocol (FROM <tab> TO <tab> PRECISION <tab>
// HEX(VALUE)) and answers each line through convertBase.convert(), the call a
// page makes: "ok" <tab> HEX(RESULT), or "err" <tab> CODE, the same as
// reactor-host --batch-codes. A negative precision means auto, so it is left
// out of the options rather than passed.
//
// Go's own node loader is not used, since it hands the module the whole
// environment and sets up a real fs. A page has neither.

"use strict";

const fs = require("fs");

if (process.argv.length !== 4) {
	console.error("usage: node browser-driver.js WASM_EXEC.js convert-base.wasm < requests");
	process.exit(2);
}

function die(msg) {
	console.error("browser-driver: FAIL: " + msg);
	process.exit(1);
}

require(process.argv[2]);

async function main() {
	const go = new Go();
	go.env = {};
	const { instance } = await WebAssembly.instantiate(fs.readFileSync(process.argv[3]), go.importObject);
	// Not awaited: main parks in select {} and the promise never settles. The
	// exports are set before it parks.
	go.run(instance);
	const api = globalThis.convertBase;
	if (!api || typeof api.convert !== "function") die("convertBase.convert missing after load");

	const out = [];
	for (const line of fs.readFileSync(0, "utf8").split("\n")) {
		if (line === "") continue;
		const f = line.split("\t");
		if (f.length !== 4) die("bad request line " + JSON.stringify(line));
		const opts = { from: f[0], to: f[1], value: Buffer.from(f[3], "hex").toString("utf8") };
		const prec = Number(f[2]);
		if (!Number.isInteger(prec)) die("bad precision " + JSON.stringify(f[2]));
		if (prec >= 0) opts.precision = prec;
		const res = api.convert(opts);
		if (res.ok) {
			out.push("ok\t" + Buffer.from(res.value, "utf8").toString("hex"));
		} else {
			out.push("err\t" + (Number.isInteger(res.code) ? res.code : "none"));
		}
	}
	fs.writeSync(1, out.length ? out.join("\n") + "\n" : "");
	process.exit(0);
}

main().catch((err) => die(String(err && err.stack || err)));
