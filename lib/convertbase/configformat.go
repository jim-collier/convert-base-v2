//	Copyright © 2023-2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
//	Licensed under the Apache License, Version 2.0. Full text in ./LICENSE, or:
//		https://spdx.org/licenses/Apache-2.0.html
//	SPDX-License-Identifier: Apache-2.0

package convertbase

import (
	"errors"
	"fmt"

	"github.com/jim-collier/convert-base-v2/lib/shcl"
)

// unstampedFormat is the SHCL format of a config file with no Format line.
// Every release before that line existed read its config with SHCL 1.x.
const unstampedFormat = 1

// ConfigUpgrade is a config file written for an older SHCL format, converted
// so the current parser reads it the way the old one did.
type ConfigUpgrade struct {
	// FromFormat is the SHCL format the file was written for. A file that
	// names none is taken as format 1.
	FromFormat int
	// Text is the converted file. It ends with the current Format line, so
	// converting it again changes nothing.
	Text string
	// Respelled is true when some value had to be written differently to keep
	// its meaning. When false, the file reads the same under both formats and
	// only gained the Format line.
	Respelled bool
}

// UpgradeConfig converts the text of a config file written for an older SHCL
// format, so that it loads to the same bases it did then. It returns nil when
// the text already names the current format. A file that names no format is
// an old one.
//
// It refuses rather than guess. When a line cannot be carried over, or the
// converted text would not load, the error says why, and nothing should be
// loaded from the file: a different alphabet with no error is worse than none.
func UpgradeConfig(text string) (*ConfigUpgrade, error) {
	from, stamped := shcl.FormatVersion(text)
	if stamped && from >= shcl.FormatMajor {
		return nil, nil
	}
	if !stamped {
		from = unstampedFormat
	}
	refuse := func(err error) (*ConfigUpgrade, error) {
		return nil, fmt.Errorf("written for SHCL format %d, and cannot be converted to format %d as it is: %w",
			from, shcl.FormatMajor, err)
	}
	// Workaround for shcl's Migrate, which turns old selector sugar such as
	// `symbols: [ab]` into `symbols: ab` with nothing lost. The SHCL 1.x and
	// 2.0 parsers read that line with an error (E015), so the old loader
	// refused the file. The current parser flags each such line E019.
	for _, d := range shcl.Parse(text).Diagnostics() {
		if d.Code == "E019" {
			return refuse(fmt.Errorf("line %d: %s", d.Line, d.Message))
		}
	}
	m := shcl.Migrate(text, true)
	// Workaround for shcl's Migrate: a file ending inside an unclosed raw block
	// comes back unchanged and unstamped, with nothing to say why. Unstamped,
	// it would be taken for an old file again on every load.
	if v, ok := shcl.FormatVersion(m.Text); !ok || v < shcl.FormatMajor {
		return refuse(errors.New("the conversion did not finish; check for a raw block with no closing fence"))
	}
	// Registering checks nothing against the bases already there, so an empty
	// registry finds every fault a real load would, without building the
	// built-in set again.
	scratch := &Registry{byAlias: make(map[string]*Base)}
	if err := scratch.loadConfigText("", m.Text); err != nil {
		return refuse(err)
	}
	if n := m.Lost + m.Ambiguous; n > 0 {
		return refuse(fmt.Errorf("%d line(s) have no spelling in format %d", n, shcl.FormatMajor))
	}
	return &ConfigUpgrade{
		FromFormat: from,
		Text:       m.Text,
		Respelled:  shcl.MigrateUnstamped(text, true).Text != text,
	}, nil
}
