<!-- markdownlint-disable MD007 -- Unordered list indentation -->
<!-- markdownlint-disable MD010 -- No hard tabs -->
<!-- markdownlint-disable MD041 -- First line in a file should be a top-level heading -->
<!-- TOC ignore:true -->
# Configuration

Back to the [README](README.md).

The first run writes `~/.config/convert-base-v2/convert-base-v2.shcl`, a commented file for defining bases of your own. Nothing rewrites it after that, apart from the one-time format upgrade below. A system-wide `/etc/convert-base-v2/convert-base-v2.shcl` is read first, so the user file wins over it, and both win over the built-in bases: reuse a built-in name and your definition replaces it.

A base is a name and its digits, plus whatever markers it needs.

~~~text
base: 10emoji
	aliases: emoji10
	symbols: "😀 😑 😔 😘 😜 😠 😬 😮 🙄 🤔"
	negative: "🥕"
	decimal: "⚽"
~~~

That base is in the file as a working example to copy from. The format is [SHCL](https://github.com/yottacore/shcl), and the file itself documents every field.

A backslash in a value is plain text, except inside double quotes, where it starts an escape and has to be doubled. The symbol list has escapes of its own on top of that: `symbols: a\ b c` makes `a b` one digit, and in double quotes the same list is `"a\\ b c"`.

Every value is one line, however long the alphabet. A raw block, the lines between two `~~~` fences, is refused under any field. Split over rows, an alphabet could mean one digit per row or one per character.

## Config files from older versions

The file the first run writes ends with a Format line, `##    Format   3`, which names the SHCL rules it follows. A config with no such line, which is every config written before this version, follows the older rules, where a backslash could start an escape outside quotes too. Such a file is read the way the older rules read it, so its bases stay the same.

The user and system config files are also converted once. The original is kept beside the file as `convert-base-v2_backup_YYYYmmDD-HHMMSS_format-v1.shcl`, the converted file takes its place, comments and all, and a note on stderr names the backup. When the file can't be written, it is converted in memory on each run instead, and nothing on disk changes. A file named with `--config` is never rewritten. It is read the old way every time, with a note when that makes a difference.

When part of an old file can't be converted exactly, nothing is loaded from it. The program stops with an error naming the line, and the file is left as it is.
