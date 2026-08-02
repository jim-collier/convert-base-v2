//	Copyright © 2023-2026 Jim Collier (CryptogID: ѳ6ᴚ℈𐀘𐇦ɛ𐊁¥Mﾏb϶Δ𐌞)
//	Licensed under the GNU General Public License v2.0 or later. Full text at:
//		https://spdx.org/licenses/GPL-2.0-or-later.html
//	SPDX-License-Identifier: GPL-2.0-or-later

package main

import (
	"bufio"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/jim-collier/convert-base-v2/lib/convertbase"
)

// version is overwritten at build time via -ldflags "-X main.version=...". It
// must be a var, not a const: the linker can only patch a var, so a const here
// made the Makefile's version injection a silent no-op.
var version = "v2.1.0"

const (
	copyrightYear = "2023-2026"
	author        = "Jim Collier (ID: 1cv◂‡Vᛦ)"
)

const etcConfigPath = "/etc/convert-base-v2/convert-base-v2.shcl"

func main() {
	if err := run(); err != nil {
		fmt.Fprintf(os.Stderr, "error: %v\n", hintErr(err))
		os.Exit(1)
	}
}

// hintErr appends the command's own pointers to library errors the library
// states neutrally (it has no idea flags exist). Every wrap on the way up is
// prefix-style, so appending here lands the hint where it always was.
func hintErr(err error) error {
	var (
		unknown *convertbase.UnknownBaseError
		missing *convertbase.MissingMarkerError
		markDef *convertbase.MarkerDefaultError
		retired *convertbase.RetiredTokenError
	)
	switch {
	case errors.As(err, &unknown):
		return fmt.Errorf("%w (see --list for all bases)", err)
	case errors.As(err, &missing):
		return fmt.Errorf("%w; set one with --to-%s", err, missing.Marker[:3])
	case errors.As(err, &markDef):
		return fmt.Errorf("%w (--from-%s/--to-%s, or the %q field in a config file)",
			err, markDef.Marker[:3], markDef.Marker[:3], markDef.Marker+":")
	case errors.As(err, &retired):
		return fmt.Errorf("%w; use --from-%s/--to-%s on the command line, or the %q field in a config file",
			err, retired.Marker[:3], retired.Marker[:3], retired.Marker+":")
	}
	return err
}

func run() error {
	var (
		fromName      = flag.String("from", "", "input base name/alias (e.g. 10, hex, 64url); default 10")
		toName        = flag.String("to", "", "output base name/alias; default 10; also accepted as a positional arg")
		fromSymbols   = flag.String("from-symbols", "", "custom input base: the digit symbols, whitespace-delimited")
		toSymbols     = flag.String("to-symbols", "", "custom output base (same form)")
		precision     = flag.String("precision", "auto", "max fractional digits, or 'auto' to match the input's precision")
		lower         = flag.Bool("lower", false, "lowercase output (errors if output base has mixed-case digits)")
		upper         = flag.Bool("upper", false, "uppercase output (errors if output base has mixed-case digits)")
		escapeCtrl    = flag.Bool("escape-controls", false, "write control-character digits as named escapes (⊳LF, ⊳TAB, ...); input accepts them either way")
		noNewline     = flag.Bool("no-newline", false, "do not append a trailing newline to text output (like echo -n)")
		nFlag         = flag.Bool("n", false, "alias for -no-newline")
		binaryMode    = flag.Bool("binary", false, "treat both sides as raw byte data (byte encode/decode, like basenc); an omitted --from/--to defaults to bytes")
		binFlag       = flag.Bool("bin", false, "alias for -binary")
		bFlag         = flag.Bool("b", false, "alias for -binary")
		numberMode    = flag.Bool("number", false, "treat input as a positional number value (the default); silences the byte-vs-number note")
		numFlag       = flag.Bool("num", false, "alias for -number")
		nCapFlag      = flag.Bool("N", false, "alias for -number")
		list          = flag.Bool("list", false, "list all known bases and exit")
		listCompat    = flag.Bool("list-compat", false, "list only the convert-base-v1/v1b compatibility bases and exit")
		getIndexCount = flag.Bool("get-index-count", false, "print how many bases are defined, then exit; valid --by-index values run 0 to count-1")
		getBaseName   = flag.Bool("get-base-name", false, "print a base's canonical name, then exit; pick the base with a name/alias argument or --by-index")
		showSymbols   = flag.Bool("show-symbols", false, "print a base's symbols concatenated with no delimiters, then exit; pick the base with a name/alias argument or --by-index")
		showSymbols0  = flag.Bool("show-symbols-0", false, "like --show-symbols but NUL-separated, for machine parsing of multi-char symbols")
		byIndex       = flag.Int("by-index", -1, "pick a base by its INDEX column in --list (0-based); used with --get-base-name / --show-symbols")
		configFile    = flag.String("config", userConfigPath(), "user-level SHCL config file; /etc is always tried too (missing file is OK)\n        ")
		showVersion   = flag.Bool("version", false, "print version and exit")
		helpFlag      = flag.Bool("help", false, "show help and exit")
		hFlag         = flag.Bool("h", false, "alias for -help")
		examplesFlag  = flag.Bool("examples", false, "show usage examples and exit")
	)

	// Per-side overrides. These apply to whatever base the side resolved to,
	// named or custom. An empty value disables the marker; an absent flag
	// leaves the base's own setting alone.
	fromMarkers := &sideFlags{prefix: "--from"}
	toMarkers := &sideFlags{prefix: "--to"}
	flag.Var(&fromMarkers.neg, "from-neg", `negative marker for the input base (default "-"; empty disables)`)
	flag.Var(&fromMarkers.dec, "from-dec", `decimal marker for the input base (default "."; empty disables)`)
	flag.Var(&fromMarkers.pad, "from-pad", "padding character stripped from input in binary mode")
	flag.Var(&fromMarkers.tail, "from-tail", "tail symbols for a >8-bit input base in binary mode")
	flag.Var(&toMarkers.neg, "to-neg", `negative marker for the output base (default "-"; empty disables)`)
	flag.Var(&toMarkers.dec, "to-dec", `decimal marker for the output base (default "."; empty disables)`)
	flag.Var(&toMarkers.pad, "to-pad", "padding character written in binary mode")
	flag.Var(&toMarkers.tail, "to-tail", "tail symbols for a >8-bit output base in binary mode")

	// Suppress Go's default auto-exit on -h/-help; we handle help ourselves
	// so we can show config-file status and base-resolution info. ContinueOnError
	// (instead of the default ExitOnError) lets us turn flag's terse errors into
	// hints about the two most common stumbles: a negative number typed without a
	// "--" separator, and a mistyped flag.
	flag.CommandLine.Init(os.Args[0], flag.ContinueOnError)
	flag.CommandLine.SetOutput(io.Discard) // we print our own message
	flag.CommandLine.Usage = func() {}     // no-op; we print help manually
	if perr := flag.CommandLine.Parse(os.Args[1:]); perr != nil {
		return improveFlagError(perr)
	}

	if *showVersion {
		fmt.Println(version)
		return nil
	}

	// Build registry and layer on config files (lowest to highest precedence):
	//   built-in  <  /etc  <  user config  <  CLI flags
	// Later-registered aliases overwrite earlier ones.
	reg, err := convertbase.NewRegistry()
	if err != nil {
		return err
	}
	// Nobody types the system path, so a copy that will not open at all just
	// means there is no system config. A file that opens and will not parse
	// still stops us, since that one was put there on purpose.
	if err := reg.LoadConfig(etcConfigPath); err != nil && !convertbase.IsConfigUnreadable(err) {
		return fmt.Errorf("config %s: %w", etcConfigPath, err)
	}
	// Only load user config if it's a different path (avoid double-registering
	// if user explicitly set -config=/etc/...).
	userPath := *configFile
	configExplicit := false
	flag.Visit(func(f *flag.Flag) {
		if f.Name == "config" {
			configExplicit = true
		}
	})
	if configExplicit && userPath == etcConfigPath {
		// Already loaded above, where a file that will not open is forgiven.
		// That forgiveness is only for the paths nobody typed; a typed
		// --config still has to open.
		f, openErr := os.Open(userPath)
		if openErr != nil {
			return fmt.Errorf("config %s: %w", userPath, openErr)
		}
		_ = f.Close() // opened only to prove it opens; nothing was written
	}
	if userPath != "" && userPath != etcConfigPath {
		// A missing default config path is fine, but if the user explicitly typed
		// --config, a missing/unreadable file is almost certainly a typo - error
		// instead of silently dropping their custom bases.
		if configExplicit {
			if _, statErr := os.Stat(userPath); statErr != nil {
				return fmt.Errorf("config %s: %w", userPath, statErr)
			}
		} else if ensureUserConfig(userPath) {
			// First run: there is now a real file at the path the help text
			// names, with a working example base in it.
			fmt.Fprintf(os.Stderr, "note: created default config %s\n", userPath)
			if legacy := legacyConfigPath(userPath); legacy != userPath {
				if _, statErr := os.Stat(legacy); statErr == nil {
					fmt.Fprintf(os.Stderr, "note: %s is the older YAML config and is no longer read\n", legacy)
				}
			}
		}
		// A typed --config already failed above if it was not readable, so the
		// only unreadable file reaching here is the default path, same case as
		// the system one.
		if err := reg.LoadConfig(userPath); err != nil && (configExplicit || !convertbase.IsConfigUnreadable(err)) {
			return fmt.Errorf("config %s: %w", userPath, err)
		}
	}

	// --help (with or without accompanying flags). Explicitly requested, so it
	// goes to stdout (pipeable); the no-args error path below keeps stderr.
	if *helpFlag || *hFlag {
		printHelp(os.Stdout, reg, etcConfigPath, userPath, *fromName, *toName, *fromSymbols, *toSymbols)
		return nil
	}

	// --examples (explicitly requested -> stdout).
	if *examplesFlag {
		printExamples(os.Stdout)
		return nil
	}

	// --list shows the everyday bases, --list-compat the v1/v1b compatibility
	// ones. Both together print both tables, everyday first.
	if *list || *listCompat {
		if *list {
			reg.Print(os.Stdout, false)
		}
		if *listCompat {
			if *list {
				fmt.Println()
			}
			reg.Print(os.Stdout, true)
		}
		return nil
	}

	// Base-introspection query modes. Each prints one thing and exits, like
	// --list. They let scripts enumerate bases (count, name-by-index, symbols)
	// without parsing the human-readable --list table.
	if *getIndexCount {
		fmt.Println(len(reg.OrderedBases()))
		return nil
	}
	if *getBaseName || *showSymbols || *showSymbols0 {
		posName := ""
		if a := flag.Args(); len(a) >= 1 {
			posName = a[0]
		}
		b, err := selectBase(reg, *byIndex, posName)
		if err != nil {
			return err
		}
		if *getBaseName {
			fmt.Println(b.Name())
			return nil
		}
		// --show-symbols: all symbols concatenated, no delimiters, one trailing
		// newline. --show-symbols-0 NUL-separates them so scripts can still split
		// multi-char symbols. Buffered for the big bases (up to 65536).
		w := bufio.NewWriter(os.Stdout)
		if *showSymbols0 {
			for i, s := range b.Symbols {
				if i > 0 {
					fmt.Fprint(w, "\x00")
				}
				fmt.Fprint(w, s)
			}
		} else {
			for _, s := range b.Symbols {
				if *escapeCtrl {
					s = convertbase.EscapeControls(s, b)
				}
				fmt.Fprint(w, s)
			}
			fmt.Fprintln(w)
		}
		return w.Flush()
	}

	// --by-index only selects a base for the query flags above. Reaching here with
	// it set means a normal conversion, where it does nothing - say so rather than
	// silently ignoring it.
	if *byIndex >= 0 {
		fmt.Fprintf(os.Stderr, "note: --by-index is ignored here; it only picks a base for --get-base-name / --show-symbols\n")
	}

	// Mode flags up front: an omitted base defaults to bytes under --binary
	// (so `--from hex --binary` implies `--to bytes`), else to base 10.
	byteMode := *binaryMode || *binFlag || *bFlag
	numMode := *numberMode || *numFlag || *nCapFlag
	if byteMode && numMode {
		return fmt.Errorf("choose either --binary or --number, not both")
	}
	defaultBase := "10"
	if byteMode {
		defaultBase = "bytes"
	}

	// Defaults: an unspecified side falls back to defaultBase.
	inBaseName := *fromName
	if inBaseName == "" && *fromSymbols == "" {
		inBaseName = defaultBase
	}
	// Conflicting input selectors: --from-symbols silently wins over --from. Say
	// so, so a script mistake isn't masked (note to stderr; stdout stays clean).
	if *fromSymbols != "" && *fromName != "" {
		fmt.Fprintf(os.Stderr, "note: --from-symbols overrides --from %q\n", *fromName)
	}
	from, err := convertbase.ResolveBase(reg, inBaseName, *fromSymbols, fromMarkers.options())
	if err != nil {
		return fmt.Errorf("input base: %w", err)
	}

	args := flag.Args()

	// NUMBER comes from stdin only for an explicit "-", or a pipe with no
	// positional. When a positional NUMBER is given it always wins - changing
	// that would break the common `prog NUMBER` form in scripts whose stdin is an
	// inherited pipe (a read-loop, this being run under another pipe, etc.), and
	// would make the tool consume a pipe it was never meant to touch.
	fromStdin := (len(args) >= 1 && args[0] == "-") || (len(args) == 0 && !isTerminal(os.Stdin))

	// OUTBASE: --to flag wins over positional (args[1], after NUMBER or "-").
	// Default to defaultBase if neither set. Resolved up front (it doesn't depend
	// on the number) so the streaming path below can be chosen before a byte is
	// read.
	outBaseName := *toName
	posOut := ""
	if len(args) >= 2 {
		posOut = args[1]
	}
	if outBaseName == "" {
		outBaseName = posOut
	}
	if outBaseName == "" && *toSymbols == "" {
		outBaseName = defaultBase
	}

	// Conflicting output selectors: --to-symbols wins over any name, and --to
	// wins over a positional OUTBASE. Both are silent today; warn (stderr) when
	// two selectors disagree so a mistake isn't masked. A --to and positional that
	// name the same base is not a conflict and stays quiet.
	switch {
	case *toSymbols != "" && (*toName != "" || posOut != ""):
		other := *toName
		if other == "" {
			other = posOut
		}
		fmt.Fprintf(os.Stderr, "note: --to-symbols overrides output base %q\n", other)
	case *toName != "" && posOut != "" && !sameBase(reg, *toName, posOut):
		fmt.Fprintf(os.Stderr, "note: --to %q overrides positional output base %q\n", *toName, posOut)
	}

	// Extra positional guard.
	expectedPositionals := 0
	if len(args) >= 1 {
		expectedPositionals = 1 // NUMBER or "-"
	}
	if posOut != "" {
		expectedPositionals++
	}
	if len(args) > expectedPositionals {
		extra := args[expectedPositionals]
		// A leftover that looks like a flag means the user put flags after the
		// NUMBER; flag parsing stops at the first non-flag, so they were never seen.
		if strings.HasPrefix(extra, "-") && extra != "-" {
			return fmt.Errorf("flags must come before the NUMBER: move %q ahead of it, e.g. %s %s NUMBER BASE (see --help)", extra, filepath.Base(os.Args[0]), extra)
		}
		return fmt.Errorf("unexpected extra positional argument: %q (see --help for usage)", extra)
	}

	// Kill the silent-wrong-output trap: `echo 255 | prog 16` reads "16" as the
	// NUMBER and never touches the pipe, so it prints "16" with exit 0. Detect the
	// telltale shape - a real pipe with data, one positional, and that positional
	// naming a known base - and point the user at "-". A bare number positional
	// (the ordinary read-loop case) does not trip this.
	if !fromStdin && len(args) == 1 && isNamedPipe(os.Stdin) {
		if _, lerr := reg.Lookup(args[0]); lerr == nil {
			fmt.Fprintf(os.Stderr, "note: reading %q as the NUMBER, not the output base; stdin (piped) was ignored. To convert piped input, use: something | %s - %s\n",
				args[0], filepath.Base(os.Args[0]), args[0])
		}
	}

	to, err := convertbase.ResolveBase(reg, outBaseName, *toSymbols, toMarkers.options())
	if err != nil {
		return fmt.Errorf("output base: %w", err)
	}

	// -1 is the auto sentinel Convert understands; an explicit value must be >= 0.
	precVal := -1
	if !strings.EqualFold(strings.TrimSpace(*precision), "auto") {
		n, perr := strconv.Atoi(strings.TrimSpace(*precision))
		if perr != nil || n < 0 {
			return fmt.Errorf("precision must be a non-negative integer or 'auto'")
		}
		precVal = n
	}

	if *lower && *upper {
		return fmt.Errorf("choose either --lower or --upper, not both")
	}

	// --lower/--upper: error out if the output base has mixed-case digits
	// (previously silently ignored; now strict, per user preference).
	if *lower && !canLowercase(to) {
		return fmt.Errorf("--lower is invalid for mixed-case output base %q: lowercasing its digits would change their meaning", to.Name())
	}
	if *upper && !canUppercase(to) {
		return fmt.Errorf("--upper is invalid for mixed-case output base %q: uppercasing its digits would change their meaning", to.Name())
	}
	// Escapes are a text notation, so they only reach the number path. Byte mode
	// writes raw bytes or a fixed codec alphabet, where the flag would be
	// accepted and then do nothing.
	if *escapeCtrl && (byteMode || from.Binary || to.Binary) {
		return fmt.Errorf("--escape-controls applies to number conversions only, not byte mode")
	}

	// No number and stdin is a terminal - nothing to do. This is the error path
	// (exit 2), so help goes to stderr, leaving stdout clean.
	if len(args) == 0 && !fromStdin {
		printHelp(os.Stderr, reg, etcConfigPath, userPath, *fromName, *toName, *fromSymbols, *toSymbols)
		os.Exit(2)
	}

	// --binary is meaningful only between two text bases; if either side is
	// already the bytes base the conversion is byte-exact anyway, so ignore it.
	routeBytes := byteMode && !from.Binary && !to.Binary
	var bytes *convertbase.Base
	if routeBytes {
		bytes, err = reg.Lookup("bytes")
		if err != nil {
			return err
		}
	}

	// Loud note for the silent-ambiguous case: two power-of-2 text bases with no
	// mode given. The value is converted as a number (leading zeros dropped),
	// which differs from a byte re-encoding. Goes to stderr so pipes stay clean.
	if !byteMode && !numMode && !from.Binary && !to.Binary &&
		convertbase.PowerOfTwoBits(len(from.Symbols)) > 0 && convertbase.PowerOfTwoBits(len(to.Symbols)) > 0 {
		fmt.Fprintln(os.Stderr, "FYI: Converted as a positional notation number (assumed '--number' flag). If you meant to do binary encode/decode, add the --binary flag.")
	}

	// Streaming fast path: for the bit-packed conversions, pipe stdin straight to
	// stdout with no whole-file buffering. --lower/--upper would need per-chunk
	// rewriting, so they fall through to the buffered path.
	if fromStdin && !*lower && !*upper {
		var handled bool
		var serr error
		if routeBytes {
			handled, serr = convertbase.StreamBytesRoute(os.Stdin, os.Stdout, from, to, bytes)
		} else {
			handled, serr = convertbase.StreamConvert(os.Stdin, os.Stdout, from, to)
		}
		if serr != nil {
			return serr
		}
		if handled {
			// Text output normally ends in a newline (as the buffered path's
			// Println does); no-newline and binary output stay byte-exact.
			if !to.Binary && !*noNewline && !*nFlag {
				fmt.Println()
			}
			return nil
		}
	}

	// Buffered path: read the whole number (from stdin or argv), convert, emit.
	var number string
	if fromStdin {
		number, err = readStdin(from)
		if err != nil {
			return err
		}
	} else {
		number = args[0]
	}

	var result string
	if routeBytes {
		// from-digits -> raw bytes -> to-digits, matching the streaming route and
		// basenc byte-for-byte (whole-byte checks and RFC padding included).
		mid, cerr := convertbase.Convert(number, from, bytes, precVal)
		if cerr != nil {
			return cerr
		}
		result, err = convertbase.Convert(mid, bytes, to, precVal)
	} else {
		result, err = convertbase.Convert(number, from, to, precVal)
	}
	if err != nil {
		return err
	}
	if *lower {
		result = strings.ToLower(result)
	}
	if *upper {
		result = strings.ToUpper(result)
	}
	if *escapeCtrl {
		result = convertbase.EscapeControls(result, to)
	}

	if *noNewline || *nFlag || to.Binary {
		_, err := os.Stdout.WriteString(result)
		return err
	}
	fmt.Println(result)
	return nil
}

// improveFlagError turns flag's terse parse errors into a hint for the two
// common stumbles. A "-123"-style undefined flag is almost always a negative
// number that needs a "--" separator; any other undefined/bad flag gets a
// pointer to --help.
func improveFlagError(err error) error {
	prog := filepath.Base(os.Args[0])
	msg := err.Error()
	const undef = "flag provided but not defined: "
	if strings.HasPrefix(msg, undef) {
		tok := strings.TrimPrefix(msg, undef) // e.g. "-123" or "-lowr"
		bare := strings.TrimLeft(tok, "-")
		if looksLikeNumber(bare) {
			return fmt.Errorf("to pass a negative number, put it after a \"--\" separator, e.g.: %s -- %s BASE", prog, tok)
		}
		return fmt.Errorf("unknown flag %q; flags must come before the NUMBER (see --help for the flag list)", tok)
	}
	return fmt.Errorf("%s (see --help for usage)", msg)
}

// looksLikeNumber reports whether s is a bare (unsigned) number in some base:
// digits with an optional single fractional dot. Used only to guess that a
// "-123"-style undefined flag was meant as a negative number.
func looksLikeNumber(s string) bool {
	if s == "" {
		return false
	}
	dots := 0
	for _, c := range s {
		switch {
		case c >= '0' && c <= '9':
		case c >= 'a' && c <= 'z', c >= 'A' && c <= 'Z':
			// allow hex-ish / higher-base digits
		case c == '.':
			dots++
		default:
			return false
		}
	}
	// require at least one actual digit and at most one dot
	if dots > 1 {
		return false
	}
	for _, c := range s {
		if c >= '0' && c <= '9' {
			return true
		}
	}
	return false
}

// selectBase picks a base for the query flags: by --list index if byIndex >= 0,
// otherwise by name/alias. Index order matches --list (see OrderedBases).
func selectBase(reg *convertbase.Registry, byIndex int, name string) (*convertbase.Base, error) {
	if byIndex >= 0 {
		ordered := reg.OrderedBases()
		if byIndex >= len(ordered) {
			return nil, fmt.Errorf("--by-index=%d out of range (have %d bases: 0..%d)", byIndex, len(ordered), len(ordered)-1)
		}
		return ordered[byIndex], nil
	}
	if name == "" {
		return nil, fmt.Errorf("select a base by name/alias argument or --by-index=N")
	}
	return reg.Lookup(name)
}

// sameBase reports whether two base names/aliases resolve to the same base. An
// unresolvable name counts as different (so a genuine conflict still warns). Used
// only to suppress a redundant conflict note when --to and the positional agree.
func sameBase(reg *convertbase.Registry, a, b string) bool {
	ba, ea := reg.Lookup(a)
	bb, eb := reg.Lookup(b)
	return ea == nil && eb == nil && ba == bb
}

// optString is a string flag that remembers whether it was given, so an absent
// flag stays distinguishable from an explicit empty value. That is what lets the
// marker flags carry the same three states as Base.Negative/Base.Decimal:
// unset (leave the base alone), empty (disable), or a value.
type optString struct {
	value string
	set   bool
}

func (o *optString) String() string {
	if o == nil {
		return ""
	}
	return o.value
}

func (o *optString) Set(s string) error {
	o.value = s
	o.set = true
	return nil
}

// sideFlags groups one side's per-base overrides: the three markers and the
// binary tail repertoire. Prefix is "--from" or "--to", used only in messages.
type sideFlags struct {
	neg, dec, pad, tail optString
	prefix              string
}

// options converts the flags into the library's override struct. The flag types
// exist to satisfy the flag package; Options is what the conversion code takes.
func (m *sideFlags) options() *convertbase.Options {
	if m == nil {
		return nil
	}
	o := &convertbase.Options{
		Label:  m.prefix,
		Source: "--from-symbols / --to-symbols (CLI flag)",
	}
	if m.neg.set {
		v := m.neg.value
		o.Negative = &v
	}
	if m.dec.set {
		v := m.dec.value
		o.Decimal = &v
	}
	if m.pad.set {
		v := m.pad.value
		o.Pad = &v
	}
	if m.tail.set {
		v := m.tail.value
		o.Tail = &v
	}
	return o
}

// readStdin reads all of stdin as bytes. Trims exactly one trailing '\n' (and
// an optional preceding '\r') unless '\n' is a valid digit in the input base,
// in which case every byte is data.
func readStdin(from *convertbase.Base) (string, error) {
	data, err := io.ReadAll(os.Stdin)
	if err != nil {
		return "", fmt.Errorf("reading stdin: %w", err)
	}
	// Keep all bytes if newline is a digit (i.e. base binary - every byte is valid).
	if from.HasByteDigit('\n') {
		return string(data), nil
	}
	s := string(data)
	s = strings.TrimSuffix(s, "\n")
	s = strings.TrimSuffix(s, "\r")
	return s, nil
}

// canLowercase reports whether strings.ToLower on the output would still be a
// valid representation. False when the base contains both the upper- and lower-
// case form of the same letter (i.e. mixed-case digits).
func canLowercase(b *convertbase.Base) bool {
	seen := make(map[string]struct{}, len(b.Symbols))
	for _, s := range b.Symbols {
		seen[s] = struct{}{}
	}
	for _, s := range b.Symbols {
		l := strings.ToLower(s)
		if l != s {
			if _, both := seen[l]; both {
				return false
			}
		}
	}
	return true
}

// canUppercase is the --upper counterpart of canLowercase: false when the base
// carries both cases of the same letter, since uppercasing would collide them.
func canUppercase(b *convertbase.Base) bool {
	seen := make(map[string]struct{}, len(b.Symbols))
	for _, s := range b.Symbols {
		seen[s] = struct{}{}
	}
	for _, s := range b.Symbols {
		u := strings.ToUpper(s)
		if u != s {
			if _, both := seen[u]; both {
				return false
			}
		}
	}
	return true
}

// isTerminal reports whether f appears to be an interactive terminal (not a pipe/file).
func isTerminal(f *os.File) bool {
	fi, err := f.Stat()
	if err != nil {
		return true
	}
	return (fi.Mode() & os.ModeCharDevice) != 0
}

// isNamedPipe reports whether f is an actual pipe (the `|` case), as opposed to
// a terminal, a regular-file redirect, or /dev/null. Used only to decide whether
// a likely piped-input mistake is worth a diagnostic.
func isNamedPipe(f *os.File) bool {
	fi, err := f.Stat()
	if err != nil {
		return false
	}
	return (fi.Mode() & os.ModeNamedPipe) != 0
}

// userConfigPath returns the default path for the user-level config file.
func userConfigPath() string {
	if x := os.Getenv("XDG_CONFIG_HOME"); x != "" {
		return filepath.Join(x, "convert-base-v2", "convert-base-v2.shcl")
	}
	if h, err := os.UserHomeDir(); err == nil {
		return filepath.Join(h, ".config", "convert-base-v2", "convert-base-v2.shcl")
	}
	return ""
}

// printHelp prints the program's help text plus a contextual report on config
// file visibility and, if the user passed any --from/--to/-*-symbols flags,
// where each base would be resolved from in a real run.
func printHelp(out io.Writer, reg *convertbase.Registry, etcPath, userPath, fromName, toName, fromSyms, toSyms string) {
	printCopyright(out)
	fmt.Fprint(out, `Convert an arbitrarily large number to/from arbitrary bases.

Usage:
  convert-base-v2 [flags] NUMBER [OUTBASE]
  convert-base-v2 [flags] - [OUTBASE]              # read NUMBER from stdin
  something | convert-base-v2 [flags] - [OUTBASE]  # read NUMBER from stdin (a
                                                   # positional NUMBER always wins,
                                                   # so use - to read the pipe)

If --from is unset, input base defaults to 10. If neither --to nor OUTBASE is
given, output base also defaults to 10.

`)

	// Grouped by function, aliases combined, one line each. Handwritten instead
	// of flag.VisitAll so related flags sit together and the six aliases don't
	// each spawn a stub entry.
	fmt.Fprintf(out, `Base selection:
  --from NAME          Input base name/alias (e.g. 10, hex, 64url)  [default 10]
  --to NAME            Output base; also accepted as a positional OUTBASE arg
  --from-symbols SYMS  Custom input base: the digit symbols, whitespace-delimited
  --to-symbols SYMS    Custom output base (same form)

Markers (apply to any base, named or custom; empty value disables):
  --from-neg X         Negative marker for the input base   [default "-"]
  --from-dec X         Decimal marker for the input base    [default "."]
  --from-pad X         Padding stripped from input in binary mode
  --from-tail SYMS     Tail symbols for a >8-bit input base in binary mode
  --to-neg X           Negative marker for the output base  [default "-"]
  --to-dec X           Decimal marker for the output base   [default "."]
  --to-pad X           Padding written in binary mode
  --to-tail SYMS       Tail symbols for a >8-bit output base in binary mode

Conversion mode:
  --binary, --bin, -b  Treat both sides as raw bytes (encode/decode like basenc)
  --number, --num, -N  Treat input as a positional notation number (default)
  --precision N|auto   Max fractional digits, or auto to match input  [default auto]
  --lower / --upper    Force output case (errors on mixed-case digit bases)
  --escape-controls    Write control-character digits as ⊳LF, ⊳TAB, ⊳CR, ...
                       Input accepts those and the raw characters, mixed, always.
  --no-newline, -n     Omit trailing newline on text output (like echo -n)

Base info (each prints one value, then exits):
  --list               List all known bases
  --list-compat        List only the v1/v1b compatibility bases
  --get-index-count    Print how many bases are defined
  --get-base-name      Print a base's canonical name
  --show-symbols       Print a base's symbols, concatenated
  --show-symbols-0     Like --show-symbols but NUL-separated (machine-readable)
  --by-index N         Select the base by its INDEX column in --list (0-based)

Other:
  --config FILE        User SHCL config; /etc is always tried too. Written with
                       a commented example on first run.
                       [default %s]
  --examples           Show usage examples and exit
  --version            Print version and exit
  --help, -h           Show this help

`, userConfigPath())

	// Config file status.
	fmt.Fprintln(out, "Config files (applied in order; later entries override earlier ones):")
	fmt.Fprintf(out, "  %-50s  %s\n", "(built-in predefined bases)", "(always)")
	describePath := func(label, path string) {
		if path == "" {
			fmt.Fprintf(out, "  %-50s  %s\n", "(unset)", "")
			return
		}
		status := "not found"
		if _, err := os.Stat(path); err == nil {
			status = "loaded"
		}
		fmt.Fprintf(out, "  %-50s  [%s]\n", path, status)
	}
	describePath("/etc", etcConfigPath)
	if userPath == etcConfigPath {
		fmt.Fprintf(out, "  %-50s  %s\n", "user: (same path as /etc; skipped)", "")
	} else {
		describePath("user", userPath)
	}
	// If both exist, note precedence.
	etcLoaded := pathLoaded(reg, etcConfigPath)
	userLoaded := userPath != "" && userPath != etcConfigPath && pathLoaded(reg, userPath)
	if etcLoaded && userLoaded {
		fmt.Fprintf(out, "  -> %s takes precedence over %s (and both override built-in).\n", userPath, etcConfigPath)
	} else if etcLoaded {
		fmt.Fprintf(out, "  -> %s overrides built-in aliases.\n", etcConfigPath)
	} else if userLoaded {
		fmt.Fprintf(out, "  -> %s overrides built-in aliases.\n", userPath)
	}

	// Addition: Don't forget to note user-specified flags
	fmt.Fprintln(out, "  (optional user-specified flags)")

	// If the user passed any base-selection flags, report where each side
	// would be sourced from in a real run.
	if fromName != "" || toName != "" || fromSyms != "" || toSyms != "" {
		fmt.Fprintln(out)
		fmt.Fprintln(out, "Base resolution for this invocation:")
		reportSide(out, "Input  (--from)", reg, fromName, fromSyms, "--from-symbols")
		reportSide(out, "Output (--to)  ", reg, toName, toSyms, "--to-symbols")
	}
	fmt.Fprintln(out)
}

// pathLoaded reports whether reg.LoadConfig(path) actually loaded that file.
func pathLoaded(reg *convertbase.Registry, path string) bool {
	for _, p := range reg.LoadedConfigs {
		if p == path {
			return true
		}
	}
	return false
}

// reportSide describes how one side (input or output) would be resolved.
func reportSide(out io.Writer, label string, reg *convertbase.Registry, name, symbols, flagName string) {
	switch {
	case symbols != "":
		parsed, err := convertbase.ParseSymbolSpec(symbols)
		if err != nil {
			fmt.Fprintf(out, "  %s: %s -> INVALID SPEC: %v\n", label, flagName, hintErr(err))
			return
		}
		fmt.Fprintf(out, "  %s: custom spec via %s -> %d digits\n", label, flagName, len(parsed))
	case name != "":
		b, err := reg.Lookup(name)
		if err != nil {
			fmt.Fprintf(out, "  %s: alias %q -> UNRESOLVED (%v)\n", label, name, hintErr(err))
			return
		}
		fmt.Fprintf(out, "  %s: alias %q -> base %q (%d digits), source: %s\n",
			label, name, b.Name(), len(b.Symbols), b.Source)
	default:
		fmt.Fprintf(out, "  %s: (unset, would default to base 10, source: built-in)\n", label)
	}
}

func printCopyright(out io.Writer) {
	fmt.Fprintf(out, `convert-base-v2 %s
Copyright (c) %s %s.
Licensed under the GNU General Public License v2.0 or later. Full text at:
  https://spdx.org/licenses/GPL-2.0-or-later.html
There is no warranty, to the extent permitted by law.

`, version, copyrightYear, author)
}

func printExamples(out io.Writer) {
	fmt.Fprint(out, `Examples:
  # Convert 255 (in default base-10) to hex output; = FF
  convert-base-v2  255  16

  # Convert from hex (to default base-10 output); = 255
  convert-base-v2  --from 16  FF

  # Negative base-10 value to hex ( -- to end flags); = -1E240
  convert-base-v2  --  -123456  16

  # Big base-10 value to qntm's base-2048; = ɼధശಳপݷટථރŦၓƨ൝
  convert-base-v2  1234567899999999999999999999999999987654321  2048qntm

  # Custom base and input value, to base-10; = 148.25
  convert-base-v2 --from-symbols ABCD  --to 10  CBBA.B

  # Custom base and input value, to wordsafe base-20 output; = -9FCC.8M6
  # The alphabet uses "-" and "." as digits, so pick markers that are free.
  convert-base-v2  --from-symbols "aeiouy.-_0" --from-neg '~' --from-dec '/'  --to 20ws  "~y0-._/ooo"

  # Markers work on named bases too, not just custom alphabets
  convert-base-v2  --from hex --from-neg '~'  --to 10  -- '~ff'

  # 98keyboard holds tab, newline and return as digits, so they can be named.
  # Input takes named and raw forms mixed; output writes them only if asked.
  convert-base-v2  --from keyboard --to 10  -n 'hi⊳LFthere'             # 3772491441706426
  convert-base-v2  --from 10 --to keyboard --escape-controls  -n 3772491441706426
  convert-base-v2  --show-symbols --escape-controls  keyboard           # the readable alphabet

  # Convert a binary file to any 2^N base (i.e. 4, 8, 16, 32, 64 ... 65536)
  # Streams in linear time at speeds competitive with basenc/base64. The draw is
  # the bases nothing else has: 2048, 65536, or your own 2^N alphabet.
  cat file.bin | convert-base-v2 --from bytes --to 64url > out.b64

  cat out.b64  | convert-base-v2 --from 64url --to bytes > file2.bin     # base64url -> File (bit-perfect)

  # Re-encode between two text bases as BYTE DATA (like basenc), not as a number.
  # Without --binary the value converts numerically and leading zeros are lost.
  echo -n deadbeef | convert-base-v2 --binary --from 16 --to 64rfc       # 3q2+7w==

  # With --binary an omitted side means bytes, so these pipe raw through:
  convert-base-v2 --binary --from 16 0B195901 | convert-base-v2 --binary --to 16

	`)
}
