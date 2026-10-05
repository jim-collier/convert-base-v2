//	Copyright © 2023-2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
//	Licensed under the GNU General Public License v2.0 or later. Full text at:
//		https://spdx.org/licenses/GPL-2.0-or-later.html
//	SPDX-License-Identifier: GPL-2.0-or-later

package main

import (
	"bytes"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/jim-collier/convert-base-v2/lib/convertbase"
	"github.com/jim-collier/convert-base-v2/lib/shcl"
)

// writeConfigFile is how a converted config goes to disk. A var only so a test
// can make the write fail after the backup is made.
var writeConfigFile = shcl.WriteFileAtomic

// upgradeConfigFile converts a config file the program found on its own when
// it was written for an older SHCL format. The original is kept beside it under
// a backup name, and the converted text replaces it. It returns a note for
// stderr, or "" when there is nothing to say.
//
// Anything that stops it leaves the file as it was, and LoadConfig then
// decides: a file that cannot be converted is refused there, and one that
// could not be written is converted again in memory, so the run goes on.
func upgradeConfigFile(path string, now time.Time) string {
	data, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	up, err := convertbase.UpgradeConfig(string(data))
	if up == nil || err != nil {
		return ""
	}
	backup, err := backupConfig(path, data, up.FromFormat, now)
	if err == nil {
		if err = writeConfigFile(path, up.Text); err != nil {
			dropBackup(path, backup)
		} else if !keepBackup(backup, data, up.Text) {
			// The edit is newer than the conversion, so it goes back at the
			// path, and the next run converts it.
			if perr := putBack(path, backup); perr != nil {
				return fmt.Sprintf("note: %s was edited while it was being converted to SHCL format %d; the edited text is in %s",
					path, shcl.FormatMajor, backup)
			}
			err = errChanged
		}
	}
	if err != nil {
		// A file that reads the same either way loses nothing by staying as
		// it is, and a read-only /etc should not make every run noisy.
		if !up.Respelled {
			return ""
		}
		return fmt.Sprintf("note: %s is written for SHCL format %d and could not be converted (%s); it was read the old way for this run",
			path, up.FromFormat, errReason(err))
	}
	return fmt.Sprintf("note: converted %s to SHCL format %d; the original is now %s", path, shcl.FormatMajor, backup)
}

// explicitConfigNote is the note for a file named with --config that was
// written for an older format. That file is never rewritten, since it may be
// anywhere and was not put there by this program, so it is read the old way
// on every run.
func explicitConfigNote(path string) string {
	data, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	up, err := convertbase.UpgradeConfig(string(data))
	if up == nil || err != nil || !up.Respelled {
		return ""
	}
	return fmt.Sprintf("note: %s is written for SHCL format %d and was read the old way; `shcl migrate --write --from-2x %s` converts it",
		path, up.FromFormat, path)
}

// backupName is `NAME_backup_YYYYmmDD-HHMMSS_format-vN.shcl`, beside the file,
// in local time. N is the format the file was written for, which says how to
// read it.
func backupName(path string, format int, now time.Time) string {
	stem := strings.TrimSuffix(filepath.Base(path), ".shcl")
	return filepath.Join(filepath.Dir(path),
		fmt.Sprintf("%s_backup_%s_format-v%d.shcl", stem, now.Format("20060102-150405"), format))
}

// backupConfig keeps the original under its backup name before anything
// replaces it. A hard link keeps the very file, times and mode included, and
// unlike a rename the path never stops holding a whole config. A symlinked
// config is backed up beside its target, which is what the write replaces.
func backupConfig(path string, data []byte, format int, now time.Time) (string, error) {
	target, err := filepath.EvalSymlinks(path)
	if err != nil {
		return "", err
	}
	backup := backupName(target, format, now)
	if err := os.Link(target, backup); err != nil {
		if errors.Is(err, fs.ErrExist) {
			return "", err
		}
		// Some filesystems have no hard links.
		if err := copyNew(target, backup, data); err != nil {
			return "", err
		}
	}
	// The file may have been edited since it was read, and the conversion is
	// of what was read.
	if kept, err := os.ReadFile(backup); err != nil || !bytes.Equal(kept, data) {
		dropBackup(path, backup)
		return "", errChanged
	}
	return backup, nil
}

// copyNew writes data to a file that must not exist yet, with the original's
// mode and times.
func copyNew(from, to string, data []byte) error {
	fi, err := os.Stat(from)
	if err != nil {
		return err
	}
	f, err := os.OpenFile(to, os.O_WRONLY|os.O_CREATE|os.O_EXCL, fi.Mode().Perm())
	if err != nil {
		return err
	}
	_, err = f.Write(data)
	if err == nil {
		err = f.Sync()
	}
	if cerr := f.Close(); err == nil {
		err = cerr
	}
	if err != nil {
		_ = os.Remove(to) // the write error is the one to report
		return err
	}
	_ = os.Chtimes(to, fi.ModTime(), fi.ModTime()) // best effort; the bytes are what matter
	return nil
}

// dropBackup removes a backup that is not needed, but only while the config
// still holds the same bytes. Otherwise the backup may be the only copy left.
func dropBackup(path, backup string) {
	cur, err := os.ReadFile(path)
	if err != nil {
		return
	}
	if kept, err := os.ReadFile(backup); err == nil && bytes.Equal(cur, kept) {
		_ = os.Remove(backup) // a spare copy left behind costs nothing
	}
}

var errChanged = errors.New("the file changed while it was being converted")

// keepBackup makes sure the backup still holds the original after the write,
// and reports false when it holds an edit instead. The backup is a hard link
// to the old file, so text written into that file in place since the check
// went into the backup, and is in no other file. Writing the original over it
// would lose the edit.
//
// A rename never touches the old file, but this is the one copy of it, and the
// bytes are still in memory to put back if it went missing. The converted text
// there would mean the write went through the link, not an edit.
func keepBackup(backup string, data []byte, converted string) bool {
	kept, err := os.ReadFile(backup)
	if err == nil && bytes.Equal(kept, data) {
		return true
	}
	if err == nil && string(kept) != converted {
		return false
	}
	_ = shcl.WriteFileAtomic(backup, string(data)) // a conversion that went through stands without it
	return true
}

// putBack moves an edited backup back over the converted file. A symlinked
// config gets it at the link's target, where the backup was made.
func putBack(path, backup string) error {
	target, err := filepath.EvalSymlinks(path)
	if err != nil {
		return err
	}
	return os.Rename(backup, target)
}

// errReason is the OS's reason without the paths, which the note already names.
func errReason(err error) string {
	var pathErr *fs.PathError
	if errors.As(err, &pathErr) {
		return pathErr.Err.Error()
	}
	var linkErr *os.LinkError
	if errors.As(err, &linkErr) {
		return linkErr.Err.Error()
	}
	return err.Error()
}
