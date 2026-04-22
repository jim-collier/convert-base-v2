# AI prompt

## Opus 4.7 Adaptive prompt (20260422):

Create a CSV of printable unicode characters from 0 up to U+1FBF9.

Reorder them all like this:

The main grouping should be 1 byte, 2 bytes, 3 bytes, 4 bytes.

Next, group in manageable groups of less than 256 characters or so, by things like:

- Circumflex, Tilde, Diaeresis, Diaeresis and macron, Acute, Double acute, Macron, Caron, Stroke, Hook, Middle tilde, Bar, etc.

And:

- Circle balls, solid balls, playing cards, straight arrows, empty triangles, etc.

Reorder them to follow more common-sense rules, like:

- 0 to 9 first (or 10 to 9 if there's no 0), or equivalent numbers.

- Variations of A-Z, or approximations, and any extra characters. But don't group multiple "A"-like characters together, for example. List all similar alphabets out A-Z (or approximation), then the next variation, etc.

- Arrows and triangles pointing in this order: Up (north), northeast, Right (east), southeast, Down (south), southwest, Left (west), northwest?. If arrows or triangles are in the same family or similar, make sure they follow that order without any repeats within a group, if possible.

- Blocks moving left to right, down to up, rightmost to left, bottom to top, etc.

- Empty shapes then filled.

- Use these rules to extrapolate other rules, and this approximate order of importance, to resolve the inevitable confliclicting rules.

Columns in CSV:

- Unicode range(s). If a range is itself from start to finish, just list it once with a comma. Put this list in quotes, so CSV doesn't get confused by the comma-delimited list of ranges.

- Number of UTF-8 bytes (e.g. 1, 2, 3, 4)

- A name that you find approprite (e.g. "Triangles" or "Clear numbered balls")

- The space-delimited list of characters based on the rules above.
