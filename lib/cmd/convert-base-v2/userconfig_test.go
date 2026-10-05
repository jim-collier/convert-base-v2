//	Copyright © 2023-2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
//	Licensed under the GNU General Public License v2.0 or later. Full text at:
//		https://spdx.org/licenses/GPL-2.0-or-later.html
//	SPDX-License-Identifier: GPL-2.0-or-later

package main

import (
	"errors"
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
// Two threads, because the gap between the check and the create showed on a
// small CI runner and almost never with many cores.
// Test ID: ErlzPLg
func TestUserConfigFirstRunsRace(t *testing.T) {
	defer runtime.GOMAXPROCS(runtime.GOMAXPROCS(2))
	want := userConfigText()
	for trial := 0; trial < 60; trial++ {
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

// A file that turns up after the first run's check is kept. The race above
// only hits that gap now and then; this goes straight to it.
// Test ID: Ermok4L
func TestUserConfigCreateKeepsFile(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "convert-base-v2.shcl")
	const other = "base: theirs\n\tsymbols: 01\n"
	if err := os.WriteFile(path, []byte(other), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := createFile(path, userConfigText()); !errors.Is(err, os.ErrExist) {
		t.Fatalf("createFile over an existing file: %v, want it to exist", err)
	}
	if got := fileText(t, path); got != other {
		t.Fatalf("file replaced with %d bytes", len(got))
	}
	if names := dirNames(t, dir); len(names) != 1 {
		t.Fatalf("files %q", names)
	}
}

// Where hard links don't work, the file is still created once, whole, with
// no temp file left.
// Test ID: Ermok4r
func TestUserConfigCreateWithoutLinks(t *testing.T) {
	saved := linkFile
	linkFile = func(oldname, newname string) error {
		return &os.LinkError{Op: "link", Old: oldname, New: newname, Err: syscall.EPERM}
	}
	t.Cleanup(func() { linkFile = saved })

	dir := t.TempDir()
	path := filepath.Join(dir, "convert-base-v2.shcl")
	want := userConfigText()
	if err := createFile(path, want); err != nil {
		t.Fatal(err)
	}
	if err := createFile(path, "base: second\n"); !errors.Is(err, os.ErrExist) {
		t.Fatalf("second create: %v, want it to exist", err)
	}
	if got := fileText(t, path); got != want {
		t.Fatalf("file is %d bytes, want the %d-byte default", len(got), len(want))
	}
	if names := dirNames(t, dir); len(names) != 1 {
		t.Fatalf("files %q", names)
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
	t.Cleanup(func() { _ = os.Chmod(dir, 0o755) }) // lets TempDir remove it; a failure shows there

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

// appendDuringWrite makes the write hook append to the config in place first,
// which holds open the window between the backup check and the replace.
func appendDuringWrite(t *testing.T, path, extra string) {
	t.Helper()
	saved := writeConfigFile
	writeConfigFile = func(file, text string) error {
		f, err := os.OpenFile(path, os.O_WRONLY|os.O_APPEND, 0)
		if err != nil {
			return err
		}
		if _, err := f.WriteString(extra); err != nil {
			t.Fatal(err)
		}
		if err := f.Close(); err != nil {
			t.Fatal(err)
		}
		return saved(file, text)
	}
	t.Cleanup(func() { writeConfigFile = saved })
}

const addedBase = "base: added\n\tsymbols: 01\n"

// An edit written into the file in place, after the backup is checked and
// before the converted text replaces it, goes into the backup too, since it is
// the same file. That edit is the newest text there is, so it goes back at the
// path and the conversion waits for the next run.
// Test ID: Ern8m1y
func TestUpgradeConfigFileEditDuringWrite(t *testing.T) {
	for _, linked := range []bool{false, true} {
		dir := t.TempDir()
		target := writeOld(t, dir, oldUserConfig)
		path := target
		if linked {
			path = filepath.Join(t.TempDir(), "convert-base-v2.shcl")
			if err := os.Symlink(target, path); err != nil {
				t.Skip("no symlinks here:", err)
			}
		}
		appendDuringWrite(t, target, addedBase)

		note := upgradeConfigFile(path, upgradeTime)
		edited := oldUserConfig + addedBase
		var holders []string
		for _, name := range dirNames(t, dir) {
			if fileText(t, filepath.Join(dir, name)) == edited {
				holders = append(holders, name)
			}
		}
		if got := fileText(t, path); got != edited {
			t.Fatalf("linked %v: the config holds %q, want the edit; files holding it: %q; note %q", linked, got, holders, note)
		}
		if !strings.Contains(note, "changed while it was being converted") {
			t.Fatalf("linked %v: note %q", linked, note)
		}
		if names := dirNames(t, dir); len(names) != 1 {
			t.Fatalf("linked %v: files: %q", linked, names)
		}
		if linked {
			if fi, err := os.Lstat(path); err != nil || fi.Mode()&os.ModeSymlink == 0 {
				t.Fatal("the link was replaced")
			}
		}
		// The next run converts the edited file.
		writeConfigFile = shcl.WriteFileAtomic
		if note := upgradeConfigFile(path, upgradeTime.Add(time.Minute)); !strings.Contains(note, "converted") {
			t.Fatalf("linked %v: next run: %q", linked, note)
		}
		if got := fileText(t, filepath.Join(dir, "convert-base-v2_backup_20261003-140609_format-v1.shcl")); got != edited {
			t.Fatalf("linked %v: next run's backup holds %q", linked, got)
		}
	}
}

// Only an edit counts as one. A backup gone missing, or holding the converted
// text because the write went through the link, gets the original put back,
// and the conversion stands.
// Test ID: Ern924g
func TestUpgradeConfigFileKeepsBackup(t *testing.T) {
	backupPath := func(dir string) string {
		return filepath.Join(dir, "convert-base-v2_backup_20261003-140509_format-v1.shcl")
	}
	for _, c := range []struct {
		name  string
		write func(dir, file, text string) error
	}{
		{"missing", func(dir, file, text string) error {
			if err := shcl.WriteFileAtomic(file, text); err != nil {
				return err
			}
			return os.Remove(backupPath(dir))
		}},
		{"written through", func(_, file, text string) error {
			return os.WriteFile(file, []byte(text), 0o640)
		}},
	} {
		dir := t.TempDir()
		path := writeOld(t, dir, oldUserConfig)
		saved := writeConfigFile
		writeConfigFile = func(file, text string) error { return c.write(dir, file, text) }
		note := upgradeConfigFile(path, upgradeTime)
		writeConfigFile = saved
		if !strings.Contains(note, "converted "+path) {
			t.Fatalf("%s: note %q", c.name, note)
		}
		if got := fileText(t, backupPath(dir)); got != oldUserConfig {
			t.Fatalf("%s: backup holds %q", c.name, got)
		}
		if v, ok := shcl.FormatVersion(fileText(t, path)); !ok || v != shcl.FormatMajor {
			t.Fatalf("%s: config names format %d, %v", c.name, v, ok)
		}
	}
}

// When the edit cannot go back, it stays in the backup, and the note says so.
// Test ID: Ern925t
func TestUpgradeConfigFileEditStaysInBackup(t *testing.T) {
	if os.Geteuid() == 0 || runtime.GOOS == "windows" {
		t.Skip("a read-only mode on a directory does not stop root, or windows")
	}
	dir := t.TempDir()
	path := writeOld(t, dir, oldUserConfig)
	appendDuringWrite(t, path, addedBase)
	inner := writeConfigFile
	writeConfigFile = func(file, text string) error {
		err := inner(file, text)
		if cerr := os.Chmod(dir, 0o555); cerr != nil {
			t.Fatal(cerr)
		}
		return err
	}
	t.Cleanup(func() { _ = os.Chmod(dir, 0o755) }) // lets TempDir remove it; a failure shows there

	note := upgradeConfigFile(path, upgradeTime)
	backup := filepath.Join(dir, "convert-base-v2_backup_20261003-140509_format-v1.shcl")
	if !strings.Contains(note, "edited while it was being converted") || !strings.Contains(note, backup) {
		t.Fatalf("note %q", note)
	}
	if got := fileText(t, backup); got != oldUserConfig+addedBase {
		t.Fatalf("backup holds %q, want the edit", got)
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
