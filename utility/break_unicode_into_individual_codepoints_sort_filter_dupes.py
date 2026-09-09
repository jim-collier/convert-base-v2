#!/usr/bin/env python3

"""
Purpose:
	Given unicode input string:
		- Ignores spaces.
		- Splits the string into individual Unicode code points.
		- Sorts by code point.
		- Removes duplicates.
		- Returns the resulting list of space-delimited symbols.

Copyright (c) 2026 Bubbles
Licensed under the GNU General Public License v2.0 or later. Full text at:
	https://spdx.org/licenses/GPL-2.0-or-later.html
SPDX-License-Identifier: GPL-2.0-or-later
"""

import sys

def iter_codepoints(text):
    """Yield every Unicode code point in text, ignoring whitespace."""
    for ch in text:
        if not ch.isspace():
            yield ch

def main():
    if len(sys.argv) > 1:
        text = " ".join(sys.argv[1:])
    else:
        text = sys.stdin.read()

    chars = sorted(set(iter_codepoints(text)), key=ord)

    print(" ".join(chars))

if __name__ == "__main__":
    main()
