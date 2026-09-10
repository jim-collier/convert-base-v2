//	Copyright © 2023-2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
//	Licensed under the Apache License, Version 2.0. Full text in ./LICENSE, or:
//		https://spdx.org/licenses/Apache-2.0.html
//	SPDX-License-Identifier: Apache-2.0

package convertbase

// Version is this package's released version, and the source of truth for the
// lib/vX.Y.Z tag the release workflow pushes.
//
// It moves independently of the command's version, which is why it reads v0
// while the tool reads v2. Go welds a module's major version into its import
// path above v1, so sharing one number would mean every major release of the
// command rewrote the import path and broke callers over a change that never
// touched this API. Bump it when this package's surface changes, not when the
// command ships something.
//
// v0 is deliberate for now: it promises nothing about compatibility, which is
// the honest signal for an API published for the first time.
const Version = "v0.1.0"
