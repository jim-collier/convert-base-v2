//	Copyright © 2023-2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
//	Licensed under the GNU General Public License v2.0 or later. Full text at:
//		https://spdx.org/licenses/GPL-2.0-or-later.html
//	SPDX-License-Identifier: GPL-2.0-or-later

package main

import (
	_ "embed"
	"errors"
	"math/rand"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/jim-collier/convert-base-v2/lib/shcl"
)

// defaultConfig is written to the user config path on first run, so the
// documented example and the file people actually edit can't drift apart.
//
//go:embed default-config.shcl
var defaultConfig string

// userConfigText is the file the first run writes: the shipped default, then
// SHCL's own info block. The block's Format line is what lets a later version
// tell a file written under these rules from an older one (shcl.FormatVersion).
// It comes from the library rather than the embedded file, so it moves with
// the vendored copy.
func userConfigText() string {
	return strings.TrimRight(defaultConfig, "\n") + "\n\n\n" + shcl.GenBanner
}

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
	if _, err := os.Lstat(path); !os.IsNotExist(err) {
		return false
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return false
	}
	return createFile(path, userConfigText()) == nil
}

// linkFile is os.Link, swapped out by tests to reach the fallback.
var linkFile = os.Link

// createFile writes a new file whole, and fails with os.ErrExist if anything
// is at the path by then. Another first run may have made it since the check
// in ensureUserConfig, and that one is kept. shcl.WriteFileAtomic can't do
// this: it checks for the file itself, and replaces one it finds.
//
// The text goes to a synced temp file beside the path, and a hard link puts
// it in place. A link never replaces anything, so the check and the create
// are one step. Where links don't work, an exclusive create in place still
// keeps it to one creator, but a crash there can leave half a file.
func createFile(path, text string) error {
	dir, base := filepath.Split(path)
	var tmp *os.File
	var err error
	for attempt := 0; attempt < 8; attempt++ {
		name := filepath.Join(dir, "."+base+".tmp"+strconv.Itoa(os.Getpid())+"."+strconv.FormatUint(rand.Uint64(), 36))
		tmp, err = os.OpenFile(name, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o666)
		if err == nil {
			break
		}
	}
	if err != nil {
		return err
	}
	// After a link this is a second name for the file; after a failure it is
	// the only one. Either way it goes, and a temp left behind is no reason
	// to fail a create that went through.
	defer func() { _ = os.Remove(tmp.Name()) }()
	if err := writeAndClose(tmp, text); err != nil {
		return err
	}
	lerr := linkFile(tmp.Name(), path)
	if lerr == nil || errors.Is(lerr, os.ErrExist) {
		return lerr
	}
	f, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o666)
	if err != nil {
		return err
	}
	if err := writeAndClose(f, text); err != nil {
		_ = os.Remove(path) // ours, and only part written
		return err
	}
	return nil
}

func writeAndClose(f *os.File, text string) error {
	_, err := f.WriteString(text)
	if err == nil {
		err = f.Sync()
	}
	if cerr := f.Close(); err == nil {
		err = cerr
	}
	return err
}

// legacyConfigPath is the pre-SHCL name of a config file. Nothing reads one any
// more, so the only thing left to do about it is say so once, when its
// replacement is created.
func legacyConfigPath(path string) string {
	return strings.TrimSuffix(path, ".shcl") + ".conf"
}
