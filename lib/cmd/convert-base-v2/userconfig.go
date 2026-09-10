//	Copyright © 2023-2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
//	Licensed under the GNU General Public License v2.0 or later. Full text at:
//		https://spdx.org/licenses/GPL-2.0-or-later.html
//	SPDX-License-Identifier: GPL-2.0-or-later

package main

import (
	_ "embed"
	"os"
	"path/filepath"
	"strings"
)

// defaultConfig is written verbatim to the user config path on first run, so
// the documented example and the file people actually edit can't drift apart.
//
//go:embed default-config.shcl
var defaultConfig string

// ensureUserConfig writes the shipped default the first time the program runs,
// so the path in the help text points at a real file to read and edit instead
// of at nothing. Reports whether it created one.
//
// Failure is deliberately silent: the config is optional, every built-in base
// still works without it, and a read-only home shouldn't make every run noisy.
//
// This lives with the tool, not the library. Creating files in someone's home
// directory is a thing a program may do on its own behalf and a library may not.
func ensureUserConfig(path string) bool {
	if path == "" {
		return false
	}
	if _, err := os.Stat(path); err == nil || !os.IsNotExist(err) {
		return false
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return false
	}
	return os.WriteFile(path, []byte(defaultConfig), 0o644) == nil
}

// legacyConfigPath is the pre-SHCL name of a config file. Nothing reads one any
// more, so the only thing left to do about it is say so once, when its
// replacement is created.
func legacyConfigPath(path string) string {
	return strings.TrimSuffix(path, ".shcl") + ".conf"
}
