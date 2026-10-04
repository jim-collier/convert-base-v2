//	Copyright © 2023-2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
//	Licensed under the GNU General Public License v2.0 or later. Full text at:
//		https://spdx.org/licenses/GPL-2.0-or-later.html
//	SPDX-License-Identifier: GPL-2.0-or-later

package main

import (
	"io/fs"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"testing"
	"time"

	"github.com/jim-collier/convert-base-v2/lib/convertbase"
	"github.com/jim-collier/convert-base-v2/lib/shcl"
)

// The written file has to name its format, or a later version cannot tell it
// from one written under older rules. It also has to load cleanly and define
// the worked example.
// Test ID: Erg0gZ1
func TestUserConfigIsStamped(t *testing.T) {
	path := filepath.Join(t.TempDir(), "sub", "convert-base-v2.shcl")
	if !ensureUserConfig(path) {
		t.Fatal("ensureUserConfig did not create the file")
	}
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	text := string(data)
	if v, ok := shcl.FormatVersion(text); !ok || v != shcl.FormatMajor {
		t.Fatalf("FormatVersion = %d, %v; want %d, true", v, ok, shcl.FormatMajor)
	}
	if m := shcl.Migrate(text, false); !m.Current {
		t.Fatal("Migrate does not see the written file as current")
	}
	if _, ok := shcl.FormatVersion(defaultConfig); ok {
		t.Fatal("the embedded file names a format of its own; the stamp should come only from shcl.GenBanner")
	}
	doc := shcl.Parse(text)
	for _, d := range doc.Diagnostics() {
		t.Errorf("line %d: %s %s", d.Line, d.Code, d.Message)
	}
	// The block has to be the one shcl recognizes, so a library rewrite
	// replaces it rather than adding a second.
	if n := doc.SetBanner(true); n != 1 {
		t.Fatalf("SetBanner found %d old info blocks, want 1", n)
	}

	reg, err := convertbase.NewRegistry()
	if err != nil {
		t.Fatal(err)
	}
	if err := reg.LoadConfig(path); err != nil {
		t.Fatalf("written config does not load: %v", err)
	}
	b, err := convertbase.ResolveBase(reg, "emoji10", "", nil)
	if err != nil {
		t.Fatal(err)
	}
	if got := strings.Join(b.Symbols, " "); got != "😀 😑 😔 😘 😜 😠 😬 😮 🙄 🤔" {
		t.Fatalf("10emoji symbols = %q", got)
	}
	if ensureUserConfig(path) {
		t.Fatal("ensureUserConfig rewrote an existing file")
	}
}

// First runs started together: one of them creates the file, the rest leave
// it be, and what is there is the whole default with no temp files beside it.
// A plain write let several create it, each truncating the others.
// Test ID: ErlzPLg
func TestUserConfigFirstRunsRace(t *testing.T) {
	want := userConfigText()
	for trial := 0; trial < 20; trial++ {
		dir := t.TempDir()
		path := filepath.Join(dir, "convert-base-v2.shcl")
		var created atomic.Int32
		var ready, done sync.WaitGroup
		start := make(chan struct{})
		for runner := 0; runner < 16; runner++ {
			ready.Add(1)
			done.Add(1)
			go func() {
				defer done.Done()
				ready.Done()
				<-start
				if ensureUserConfig(path) {
					created.Add(1)
				}
			}()
		}
		ready.Wait()
		close(start)
		done.Wait()
		if n := created.Load(); n != 1 {
			t.Fatalf("trial %d: %d runs created the file, want 1", trial, n)
		}
		if got := fileText(t, path); got != want {
			t.Fatalf("trial %d: file is %d bytes, want the %d-byte default", trial, len(got), len(want))
		}
		if names := dirNames(t, dir); len(names) != 1 {
			t.Fatalf("trial %d: files %q", trial, names)
		}
	}
}

// An old file as the v1.2.0 shcl era wrote one: no Format line, and a bare
// `\t` that was a tab then and is two characters now.
const oldUserConfig = "# my bases\nbase: oldtab\n\tsymbols: 0\\t1\\t2\\t3\n"

func oldTabSymbols(t *testing.T, path string) string {
	t.Helper()
	reg, err := convertbase.NewRegistry()
	if err != nil {
		t.Fatal(err)
	}
	if err := reg.LoadConfig(path); err != nil {
		t.Fatal(err)
	}
	b, err := convertbase.ResolveBase(reg, "oldtab", "", nil)
	if err != nil {
		t.Fatal(err)
	}
	return strings.Join(b.Symbols, "|")
}

func writeOld(t *testing.T, dir, text string) string {
	t.Helper()
	path := filepath.Join(dir, "convert-base-v2.shcl")
	if err := os.WriteFile(path, []byte(text), 0o640); err != nil {
		t.Fatal(err)
	}
	return path
}

func dirNames(t *testing.T, dir string) []string {
	t.Helper()
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatal(err)
	}
	var names []string
	for _, e := range entries {
		names = append(names, e.Name())
	}
	return names
}

func fileText(t *testing.T, path string) string {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return string(data)
}

var upgradeTime = time.Date(2026, 10, 3, 14, 5, 9, 0, time.Local)

// Test ID: ErgDzUQ
func TestUpgradeConfigFile(t *testing.T) {
	dir := t.TempDir()
	path := writeOld(t, dir, oldUserConfig)
	note := upgradeConfigFile(path, upgradeTime)

	backup := filepath.Join(dir, "convert-base-v2_backup_20261003-140509_format-v1.shcl")
	if !strings.Contains(note, "converted "+path) || !strings.Contains(note, backup) {
		t.Fatalf("note %q does not name the file and its backup", note)
	}
	if got := fileText(t, backup); got != oldUserConfig {
		t.Fatalf("backup holds %q, want the original bytes", got)
	}
	if fi, err := os.Stat(path); err != nil || fi.Mode().Perm() != 0o640 {
		t.Fatalf("converted file mode %v, %v; want 0640", fi.Mode().Perm(), err)
	}
	text := fileText(t, path)
	if v, ok := shcl.FormatVersion(text); !ok || v != shcl.FormatMajor {
		t.Fatalf("converted file names format %d, %v", v, ok)
	}
	if !strings.HasPrefix(text, "# my bases\n") {
		t.Fatalf("comment lost:\n%s", text)
	}
	if got := oldTabSymbols(t, path); got != "0|1|2|3" {
		t.Fatalf("converted file reads %q, want the old tab-split 0|1|2|3", got)
	}

	// The second run finds a current file and leaves it alone.
	if note := upgradeConfigFile(path, upgradeTime.Add(time.Minute)); note != "" {
		t.Fatalf("second run: %q", note)
	}
	if got := fileText(t, path); got != text {
		t.Fatal("second run changed the file")
	}
	if names := dirNames(t, dir); len(names) != 2 {
		t.Fatalf("files after the second run: %q", names)
	}
}

// A file the conversion cannot carry over is left exactly as it is, with no
// backup, for LoadConfig to refuse.
// Test ID: ErgDzUR
func TestUpgradeConfigFileRefused(t *testing.T) {
	dir := t.TempDir()
	const text = "base: x\n\tsymbols: [ab]\n"
	path := writeOld(t, dir, text)
	if note := upgradeConfigFile(path, upgradeTime); note != "" {
		t.Fatalf("note %q", note)
	}
	if got := fileText(t, path); got != text {
		t.Fatalf("file changed to %q", got)
	}
	if names := dirNames(t, dir); len(names) != 1 {
		t.Fatalf("files: %q", names)
	}
	reg, err := convertbase.NewRegistry()
	if err != nil {
		t.Fatal(err)
	}
	if err := reg.LoadConfig(path); err == nil || !strings.Contains(err.Error(), "cannot be converted") {
		t.Fatalf("LoadConfig: %v", err)
	}
}

// A directory that cannot be written loses nothing, and the run still reads
// the file the old way.
// Test ID: ErgDzUS
func TestUpgradeConfigFileReadOnlyDir(t *testing.T) {
	if os.Geteuid() == 0 || runtime.GOOS == "windows" {
		t.Skip("a read-only mode on a directory does not stop root, or windows")
	}
	dir := t.TempDir()
	path := writeOld(t, dir, oldUserConfig)
	if err := os.Chmod(dir, 0o555); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(dir, 0o755) })

	note := upgradeConfigFile(path, upgradeTime)
	if !strings.Contains(note, "could not be converted") || !strings.Contains(note, "read the old way") {
		t.Fatalf("note %q", note)
	}
	if got := fileText(t, path); got != oldUserConfig {
		t.Fatalf("file changed to %q", got)
	}
	if names := dirNames(t, dir); len(names) != 1 {
		t.Fatalf("files: %q", names)
	}
	if got := oldTabSymbols(t, path); got != "0|1|2|3" {
		t.Fatalf("read %q, want 0|1|2|3", got)
	}
}

// The backup is made and then the write fails: the original stays at its
// path, and the backup, now a second copy of it, goes.
// Test ID: ErgDzUT
func TestUpgradeConfigFileWriteFails(t *testing.T) {
	dir := t.TempDir()
	path := writeOld(t, dir, oldUserConfig)
	saved := writeConfigFile
	writeConfigFile = func(string, string) error { return &fs.PathError{Op: "write", Path: path, Err: syscall.ENOSPC} }
	t.Cleanup(func() { writeConfigFile = saved })

	note := upgradeConfigFile(path, upgradeTime)
	if !strings.Contains(note, "no space left on device") {
		t.Fatalf("note %q", note)
	}
	if got := fileText(t, path); got != oldUserConfig {
		t.Fatalf("file changed to %q", got)
	}
	if names := dirNames(t, dir); len(names) != 1 {
		t.Fatalf("files: %q", names)
	}
}

// A file that reads the same under both formats only gains the Format line.
// When that cannot be written there is nothing to tell anyone.
// Test ID: ErgDzUU
func TestUpgradeConfigFileQuietWhenSame(t *testing.T) {
	dir := t.TempDir()
	path := writeOld(t, dir, "base: plain\n\tsymbols: 0123\n")
	saved := writeConfigFile
	writeConfigFile = func(string, string) error { return syscall.EROFS }
	t.Cleanup(func() { writeConfigFile = saved })
	if note := upgradeConfigFile(path, upgradeTime); note != "" {
		t.Fatalf("note %q", note)
	}
}

// A symlinked config, as a dotfiles checkout makes, stays a link. The target
// is converted, and the backup sits beside it.
// Test ID: ErgDzUV
func TestUpgradeConfigFileSymlink(t *testing.T) {
	realDir, linkDir := t.TempDir(), t.TempDir()
	target := writeOld(t, realDir, oldUserConfig)
	link := filepath.Join(linkDir, "convert-base-v2.shcl")
	if err := os.Symlink(target, link); err != nil {
		t.Skip("no symlinks here:", err)
	}
	if note := upgradeConfigFile(link, upgradeTime); !strings.Contains(note, "converted") {
		t.Fatalf("note %q", note)
	}
	if fi, err := os.Lstat(link); err != nil || fi.Mode()&os.ModeSymlink == 0 {
		t.Fatal("the link was replaced")
	}
	if got := fileText(t, filepath.Join(realDir, "convert-base-v2_backup_20261003-140509_format-v1.shcl")); got != oldUserConfig {
		t.Fatalf("backup holds %q", got)
	}
	if got := oldTabSymbols(t, link); got != "0|1|2|3" {
		t.Fatalf("read %q", got)
	}
}

// A file named with --config is read the old way and never rewritten.
// Test ID: ErgDzUW
func TestExplicitConfigNote(t *testing.T) {
	dir := t.TempDir()
	path := writeOld(t, dir, oldUserConfig)
	if note := explicitConfigNote(path); !strings.Contains(note, "shcl migrate --write --from-2x "+path) {
		t.Fatalf("note %q", note)
	}
	if got := fileText(t, path); got != oldUserConfig {
		t.Fatal("file changed")
	}
	plain := writeOld(t, t.TempDir(), "base: plain\n\tsymbols: 0123\n")
	if note := explicitConfigNote(plain); note != "" {
		t.Fatalf("a file that reads the same got a note: %q", note)
	}
}
