//	Copyright © 2023-2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
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
	"slices"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/jim-collier/convert-base-v2/lib/convertbase"
)

// version is overwritten at build time via -ldflags "-X main.version=...". It
// must be a var, not a const: the linker can only patch a var, so a const here
// made the Makefile's version injection a silent no-op.
var version = "v3.0.0"

const (
	copyrightYear = "2023-2026"
	author        = "Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]"
)

const etcConfigPath = "/etc/convert-base-v2/convert-base-v2.shcl"

// A fractional digit costs quadratic time and the scale factor is one power of
// the output base, so a mistyped precision asks for gigabytes: 100 million
// digits already wants several. The browser module and the reactor bound it for
// the same reason, at the same generous value.
const maxPrecision = 100000

func main() {
	err := run()
	if err == nil {
		return
	}
	var status exitStatus
	if errors.As(err, &status) {
		os.Exit(int(status))
	}
	fmt.Fprintf(os.Stderr, "error: %v\n", hintErr(err))
	var usage usageError
	if errors.As(err, &usage) {
		os.Exit(exitUsage)
	}
	os.Exit(1)
}

// A command line that can't be parsed exits 2, as Go's flag package and getopt
// tools do, so a script can tell a wrong call from input that won't convert.
const exitUsage = 2

// exitStatus ends the run with that exit code and no message, for a run that
// has already said what went wrong.
type exitStatus int

func (s exitStatus) Error() string { return fmt.Sprintf("exit status %d", int(s)) }

// usageError is a command line that can't be parsed. It exits exitUsage.
type usageError struct{ error }

func (e usageError) Unwrap() error { return e.error }

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

func run() (err error) {
	// Everything but the streams writes stdout through this one writer. It
	// keeps the first write error, and the flush hands it back, so a full disk
	// or a closed pipe fails the run instead of exiting 0 with nothing written.
	stdout := bufio.NewWriter(os.Stdout)
	defer func() {
		if ferr := stdout.Flush(); err == nil {
			err = ferr
		}
	}()

	f, err := parseFlags(os.Args[1:])
	if err != nil {
		return err
	}

	// --about opens with the version line, so it covers --version. Only the help
	// reports on the config files, so everything else prints before they load.
	if f.asked.has("about") {
		f.asked.drop("version")
	}
	if len(f.asked) > 0 && !f.asked.has("help") {
		return printInfo(stdout, f.asked, nil)
	}

	reg, configErrs, err := loadConfigs(f)
	if err != nil {
		return err
	}
	help := func(w io.Writer) {
		printHelp(w, reg, configErrs, etcConfigPath, f.configFile, f.fromName, f.toName, f.fromSymbols, f.toSymbols)
	}

	// --help (with or without accompanying flags). Explicitly requested, so it
	// goes to stdout (pipeable); the no-number help below keeps stderr.
	if len(f.asked) > 0 {
		return printInfo(stdout, f.asked, help)
	}
	if q := f.query(); q != "" {
		return runQuery(stdout, reg, f, q)
	}

	c, err := planConversion(reg, f)
	if err != nil {
		return err
	}
	// No number and stdin is a terminal - nothing to do. This is the error path
	// (exit 2), so help goes to stderr, leaving stdout clean.
	if len(f.args) == 0 && !c.fromStdin {
		help(os.Stderr)
		return exitStatus(exitUsage)
	}
	// Every note is known before a byte of input is read, so a stream starts
	// with them already out of the way.
	printNotes(c.notes)
	return c.run(stdout, reg)
}

// cliFlags is the parsed command line. Each alias sets the same field as the
// flag it stands for.
type cliFlags struct {
	fromName, toName       string
	fromSymbols, toSymbols string
	precision              string
	lower, upper           bool
	escapeCtrl             bool
	noNewline              bool
	binary, number         bool
	list, listCompat       bool
	getIndexCount          bool
	getBaseName            bool
	showSymbols            bool
	showSymbols0           bool
	byIndex                int
	configFile             string
	configExplicit         bool // --config was typed, not defaulted
	precisionSet           bool
	asked                  infoAsks
	fromMarkers, toMarkers sideFlags
	args                   []string // positionals: NUMBER or "-", then OUTBASE
	fs                     *flag.FlagSet
}

func parseFlags(args []string) (*cliFlags, error) {
	f := &cliFlags{
		fromMarkers: sideFlags{prefix: "--from"},
		toMarkers:   sideFlags{prefix: "--to"},
	}
	// ContinueOnError rather than the default ExitOnError, so -h/-help don't
	// auto-exit (the help reports on config files and base resolution) and
	// flag's terse errors can become hints about the two most common stumbles:
	// a negative number typed without a "--" separator, and a mistyped flag.
	fs := flag.NewFlagSet(os.Args[0], flag.ContinueOnError)
	fs.SetOutput(io.Discard) // we print our own message
	fs.Usage = func() {}     // no-op; we print help manually
	f.fs = fs

	fs.StringVar(&f.fromName, "from", "", "input base name/alias (e.g. 10, hex, 64url); default 10")
	fs.StringVar(&f.toName, "to", "", "output base name/alias; default 10; also accepted as a positional arg")
	fs.StringVar(&f.fromSymbols, "from-symbols", "", "custom input base: the digit symbols, whitespace-delimited")
	fs.StringVar(&f.toSymbols, "to-symbols", "", "custom output base (same form)")
	fs.StringVar(&f.precision, "precision", "auto", "max fractional digits, or 'auto' to match the input's precision")
	fs.BoolVar(&f.lower, "lower", false, "lowercase output (errors if output base has mixed-case digits)")
	fs.BoolVar(&f.upper, "upper", false, "uppercase output (errors if output base has mixed-case digits)")
	fs.BoolVar(&f.escapeCtrl, "escape-controls", false, "write control-character digits as named escapes (⊳LF, ⊳TAB, ...); input accepts them either way")
	fs.BoolVar(&f.noNewline, "no-newline", false, "do not append a trailing newline to text output (like echo -n)")
	fs.BoolVar(&f.noNewline, "n", false, "alias for -no-newline")
	fs.BoolVar(&f.binary, "binary", false, "treat both sides as raw byte data (byte encode/decode, like basenc); an omitted --from/--to defaults to bytes")
	fs.BoolVar(&f.binary, "bin", false, "alias for -binary")
	fs.BoolVar(&f.binary, "b", false, "alias for -binary")
	fs.BoolVar(&f.number, "number", false, "treat input as a positional number value (the default); silences the byte-vs-number note")
	fs.BoolVar(&f.number, "num", false, "alias for -number")
	fs.BoolVar(&f.number, "N", false, "alias for -number")
	fs.BoolVar(&f.list, "list", false, "list all known bases and exit")
	fs.BoolVar(&f.listCompat, "list-compat", false, "list only the convert-base-v1/v1b compatibility bases and exit")
	fs.BoolVar(&f.getIndexCount, "get-index-count", false, "print how many bases are defined, then exit; valid --by-index values run 0 to count-1")
	fs.BoolVar(&f.getBaseName, "get-base-name", false, "print a base's canonical name, then exit; pick the base with a name/alias argument or --by-index")
	fs.BoolVar(&f.showSymbols, "show-symbols", false, "print a base's symbols concatenated with no delimiters, then exit; pick the base with a name/alias argument or --by-index")
	fs.BoolVar(&f.showSymbols0, "show-symbols-0", false, "like --show-symbols but NUL-separated, for machine parsing of multi-char symbols")
	fs.IntVar(&f.byIndex, "by-index", -1, "pick a base by its INDEX column in --list (0-based); used with --get-base-name / --show-symbols")
	fs.StringVar(&f.configFile, "config", userConfigPath(), "user-level SHCL config file; /etc is always tried too (missing file is OK)\n        ")

	fs.Var(f.asked.flag("help"), "help", "show help and exit")
	fs.Var(f.asked.flag("help"), "h", "alias for -help")
	fs.Var(f.asked.flag("version"), "version", "print version and exit")
	fs.Var(f.asked.flag("version"), "v", "alias for -version")
	fs.Var(f.asked.flag("version"), "V", "alias for -version")
	fs.Var(f.asked.flag("about"), "about", "print version, copyright, license and project home, then exit")
	fs.Var(f.asked.flag("donate"), "donate", "print ways to support the project, then exit")
	fs.Var(f.asked.flag("examples"), "examples", "show usage examples and exit")

	// Per-side overrides. These apply to whatever base the side resolved to,
	// named or custom. An empty value disables the marker; an absent flag
	// leaves the base's own setting alone.
	fs.Var(&f.fromMarkers.neg, "from-neg", `negative marker for the input base (default "-"; empty disables)`)
	fs.Var(&f.fromMarkers.dec, "from-dec", `decimal marker for the input base (default "."; empty disables)`)
	fs.Var(&f.fromMarkers.pad, "from-pad", "padding character stripped from input in binary mode")
	fs.Var(&f.fromMarkers.tail, "from-tail", "tail symbols for a >8-bit input base in binary mode")
	fs.Var(&f.toMarkers.neg, "to-neg", `negative marker for the output base (default "-"; empty disables)`)
	fs.Var(&f.toMarkers.dec, "to-dec", `decimal marker for the output base (default "."; empty disables)`)
	fs.Var(&f.toMarkers.pad, "to-pad", "padding character written in binary mode")
	fs.Var(&f.toMarkers.tail, "to-tail", "tail symbols for a >8-bit output base in binary mode")

	if err := fs.Parse(args); err != nil {
		return nil, usageError{improveFlagError(err)}
	}
	fs.Visit(func(fl *flag.Flag) {
		switch fl.Name {
		case "config":
			f.configExplicit = true
		case "precision":
			f.precisionSet = true
		}
	})
	f.args = fs.Args()
	return f, nil
}

// loadConfigs builds the registry and layers the config files on it, lowest to
// highest precedence: built-in < /etc < user config < CLI flags. Later-registered
// aliases overwrite earlier ones. The map has each config that did not load.
func loadConfigs(f *cliFlags) (*convertbase.Registry, map[string]error, error) {
	reg, err := convertbase.NewRegistry()
	if err != nil {
		return nil, nil, err
	}
	l := &configLoad{reg: reg, errs: make(map[string]error), helpAsked: f.asked.has("help")}
	now := time.Now()
	if note := upgradeConfigFile(etcConfigPath, now); note != "" {
		fmt.Fprintln(os.Stderr, note)
	}
	// Nobody types the system path, so a copy that will not open at all just
	// means there is no system config. A file that opens and will not parse
	// still stops us, since that one was put there on purpose.
	if err := l.load(etcConfigPath, true); err != nil {
		return nil, nil, err
	}

	userPath := f.configFile
	switch {
	case userPath == etcConfigPath:
		// Already loaded above, and only once, where a file that will not open
		// is forgiven. That forgiveness is only for the paths nobody typed; a
		// typed --config still has to open.
		if f.configExplicit {
			if err := checkOpens(userPath); err != nil && !l.helpAsked {
				return nil, nil, fmt.Errorf("config %s: %w", userPath, err)
			}
		}
	case userPath != "":
		if f.configExplicit {
			if err := checkTypedConfig(userPath, l.helpAsked); err != nil {
				return nil, nil, err
			}
		} else {
			prepareDefaultConfig(userPath, now)
		}
		// Outside --help a typed --config already failed above if it was not
		// readable, so the only unreadable file reaching here is the default
		// path, same case as the system one.
		if err := l.load(userPath, !f.configExplicit); err != nil {
			return nil, nil, err
		}
	}
	return reg, l.errs, nil
}

// configLoad loads config files into reg. A config that will not load stops
// every run but --help, which shows why in its config section and prints the
// rest. Every other run stays strict, since a dropped file means converting
// with the wrong bases. Forgiven failures are kept in errs too, so the help
// never calls a skipped file loaded.
type configLoad struct {
	reg       *convertbase.Registry
	errs      map[string]error
	helpAsked bool
}

// load loads one file. forgiveUnreadable lets a file that will not open at all
// count as no file, which is only right for a path nobody typed.
func (l *configLoad) load(path string, forgiveUnreadable bool) error {
	err := l.reg.LoadConfig(path)
	if err == nil {
		return nil
	}
	forgiven := l.helpAsked || (forgiveUnreadable && convertbase.IsConfigUnreadable(err))
	if !forgiven {
		return fmt.Errorf("config %s: %w", path, err)
	}
	l.errs[path] = err
	return nil
}

func checkOpens(path string) error {
	f, err := os.Open(path)
	if err != nil {
		return err
	}
	_ = f.Close() // opened only to prove it opens; nothing was written
	return nil
}

// checkTypedConfig refuses a typed --config that is missing or unreadable,
// which is almost certainly a typo, instead of silently dropping the custom
// bases. Under --help the load finds the same fault, and the help shows it.
func checkTypedConfig(path string, helpAsked bool) error {
	if _, err := os.Stat(path); err != nil {
		if helpAsked {
			return nil
		}
		return fmt.Errorf("config %s: %w", path, err)
	}
	if note := explicitConfigNote(path); note != "" {
		fmt.Fprintln(os.Stderr, note)
	}
	return nil
}

// prepareDefaultConfig creates the default user config on a first run, or
// upgrades an old one. A missing default path is fine either way.
func prepareDefaultConfig(path string, now time.Time) {
	if !ensureUserConfig(path) {
		if note := upgradeConfigFile(path, now); note != "" {
			fmt.Fprintln(os.Stderr, note)
		}
		return
	}
	// First run: there is now a real file at the path the help text names,
	// with a working example base in it.
	fmt.Fprintf(os.Stderr, "note: created default config %s\n", path)
	if legacy := legacyConfigPath(path); legacy != path {
		if _, err := os.Stat(legacy); err == nil {
			fmt.Fprintf(os.Stderr, "note: %s is the older YAML config and is no longer read\n", legacy)
		}
	}
}

// printLists prints --list, the everyday bases, and --list-compat, the v1/v1b
// compatibility ones. Both together print both tables, everyday first.
func printLists(out io.Writer, reg *convertbase.Registry, everyday, compat bool) {
	if everyday {
		reg.Print(out, false)
	}
	if compat {
		if everyday {
			fmt.Fprintln(out)
		}
		reg.Print(out, true)
	}
}

// query names the query flag that runs, or "" for a conversion. --list and
// --list-compat print together; otherwise the first in this order wins.
func (f *cliFlags) query() string {
	switch {
	case f.list:
		return "list"
	case f.listCompat:
		return "list-compat"
	case f.getIndexCount:
		return "get-index-count"
	case f.getBaseName:
		return "get-base-name"
	case f.showSymbols0:
		return "show-symbols-0"
	case f.showSymbols:
		return "show-symbols"
	}
	return ""
}

func takesBase(query string) bool {
	return query == "get-base-name" || query == "show-symbols" || query == "show-symbols-0"
}

// runQuery answers the query flags, which print and exit, so scripts can read
// the base set (count, name by index, symbols) without parsing --list.
func runQuery(out *bufio.Writer, reg *convertbase.Registry, f *cliFlags, q string) error {
	if err := checkQueryArgs(f, q); err != nil {
		return err
	}
	var b *convertbase.Base
	if takesBase(q) {
		posName := ""
		if len(f.args) >= 1 {
			posName = f.args[0]
		}
		var err error
		if b, err = selectBase(reg, f.byIndex, posName); err != nil {
			return err
		}
	}
	printNotes(idleNotes(f, func(name string) string { return queryIdle(q, name) }))
	switch q {
	case "list", "list-compat":
		printLists(out, reg, f.list, f.listCompat)
	case "get-index-count":
		fmt.Fprintln(out, len(reg.OrderedBases()))
	default:
		printBaseQuery(out, b, f)
	}
	return nil
}

// checkQueryArgs refuses an argument the query has no use for. Nothing past
// the BASE was ever read, so `--show-symbols hex --lower` printed hex's
// symbols and dropped the flag.
func checkQueryArgs(f *cliFlags, q string) error {
	allowed, what := 0, "no arguments"
	switch {
	case takesBase(q) && f.byIndex >= 0:
		what = "no BASE argument with --by-index"
	case takesBase(q):
		allowed, what = 1, "one BASE"
	}
	if len(f.args) <= allowed {
		return nil
	}
	return usageError{fmt.Errorf("unexpected extra argument %q: --%s takes %s (see --help)", f.args[allowed], q, what)}
}

// queryIdle is where a flag does nothing beside query q, or "" if it is used.
func queryIdle(q, name string) string {
	switch name {
	case q, "config":
		return ""
	case "list-compat":
		if q == "list" {
			return ""
		}
	case "binary", "number":
		// The README suggests these as shell aliases, so they come along on
		// every call, queries included.
		return ""
	case "by-index":
		if takesBase(q) {
			return ""
		}
	case "escape-controls":
		if q == "show-symbols" {
			return ""
		}
	}
	return "with --" + q
}

// printBaseQuery prints a query about one base.
func printBaseQuery(out *bufio.Writer, b *convertbase.Base, f *cliFlags) {
	switch {
	case f.getBaseName:
		fmt.Fprintln(out, b.Name())
	case f.showSymbols0:
		// NUL-separated so scripts can still split multi-char symbols.
		for i, s := range b.Symbols {
			if i > 0 {
				out.WriteString("\x00")
			}
			out.WriteString(s)
		}
	default:
		// --show-symbols: all symbols concatenated, no delimiters, one
		// trailing newline.
		for _, s := range b.Symbols {
			if f.escapeCtrl {
				s = convertbase.EscapeControls(s, b)
			}
			out.WriteString(s)
		}
		out.WriteString("\n")
	}
}

// given lists the flags set for this run by long name, in the help's order. A
// bool turned back off with =false is not set.
func (f *cliFlags) given() []string {
	var on []string
	add := func(name string, set bool) {
		if set {
			on = append(on, name)
		}
	}
	add("from", f.fromName != "")
	add("to", f.toName != "")
	add("from-symbols", f.fromSymbols != "")
	add("to-symbols", f.toSymbols != "")
	for _, m := range []*sideFlags{&f.fromMarkers, &f.toMarkers} {
		side := strings.TrimPrefix(m.prefix, "--")
		add(side+"-neg", m.neg.set)
		add(side+"-dec", m.dec.set)
		add(side+"-pad", m.pad.set)
		add(side+"-tail", m.tail.set)
	}
	add("binary", f.binary)
	add("number", f.number)
	add("precision", f.precisionSet)
	add("lower", f.lower)
	add("upper", f.upper)
	add("escape-controls", f.escapeCtrl)
	add("no-newline", f.noNewline)
	add("list", f.list)
	add("list-compat", f.listCompat)
	add("get-index-count", f.getIndexCount)
	add("get-base-name", f.getBaseName)
	add("show-symbols", f.showSymbols)
	add("show-symbols-0", f.showSymbols0)
	add("by-index", f.byIndex >= 0)
	add("config", f.configExplicit)
	return on
}

// idleNotes has one note for each flag given that does nothing in this run.
// why says where it does nothing, or "" where it does something. The rule is
// the "Flags by mode" table in design.md.
func idleNotes(f *cliFlags, why func(name string) string) []string {
	var notes []string
	for _, name := range f.given() {
		if where := why(name); where != "" {
			notes = append(notes, fmt.Sprintf("note: --%s does nothing %s", name, where))
		}
	}
	return notes
}

// printNotes writes each note once. Scripts that pass the same flags to every
// call get one line per flag, not a repeat.
func printNotes(notes []string) {
	seen := make(map[string]bool, len(notes))
	for _, n := range notes {
		if !seen[n] {
			seen[n] = true
			fmt.Fprintln(os.Stderr, n)
		}
	}
}

// conversion is a number conversion, worked out from the flags and positionals
// before any input is read.
type conversion struct {
	f         *cliFlags
	from, to  *convertbase.Base
	bytes     *convertbase.Base // set when --binary routes two text bases through bytes
	fromStdin bool
	precision int
	notes     []string // stderr notes, printed once planning is done
}

func (c *conversion) note(format string, a ...any) {
	c.notes = append(c.notes, "note: "+fmt.Sprintf(format, a...))
}

// byteMode is a byte conversion: --binary, or the bytes base on a side.
func (c *conversion) byteMode() bool {
	return c.f.binary || c.from.Binary || c.to.Binary
}

// planConversion resolves both bases and checks the flags against them. The
// checks run in a fixed order, so the same mistake always gets the same error.
func planConversion(reg *convertbase.Registry, f *cliFlags) (*conversion, error) {
	// A command line that can't be parsed is refused before any base is
	// looked up.
	if err := checkPositionals(reg, f); err != nil {
		return nil, err
	}
	if err := checkFlagPairs(f); err != nil {
		return nil, err
	}
	c := &conversion{f: f}
	var err error
	if c.precision, err = parsePrecision(f.precision); err != nil {
		return nil, usageError{err}
	}

	// An omitted base defaults to bytes under --binary (so `--from hex
	// --binary` implies `--to bytes`), else to base 10.
	defaultBase := "10"
	if f.binary {
		defaultBase = "bytes"
	}
	if c.from, err = c.resolveInputBase(reg, defaultBase); err != nil {
		return nil, err
	}

	// NUMBER comes from stdin only for an explicit "-", or a pipe with no
	// positional. When a positional NUMBER is given it always wins - changing
	// that would break the common `prog NUMBER` form in scripts whose stdin is an
	// inherited pipe (a read-loop, this being run under another pipe, etc.), and
	// would make the tool consume a pipe it was never meant to touch.
	args := f.args
	c.fromStdin = (len(args) >= 1 && args[0] == "-") || (len(args) == 0 && !isTerminal(os.Stdin))

	outName := c.outputBaseName(reg, defaultBase)
	c.notePipeIgnored(reg)
	if c.to, err = convertbase.ResolveBase(reg, outName, f.toSymbols, f.toMarkers.options()); err != nil {
		return nil, fmt.Errorf("output base: %w", err)
	}

	if err := c.checkOutputFlags(); err != nil {
		return nil, err
	}
	c.notes = append(c.notes, idleNotes(f, c.idle)...)
	c.noteNumberReading()
	return c, nil
}

// checkFlagPairs refuses flags that can't go together, whatever the bases.
func checkFlagPairs(f *cliFlags) error {
	if f.binary && f.number {
		return usageError{errors.New("choose either --binary or --number, not both")}
	}
	if f.lower && f.upper {
		return usageError{errors.New("choose either --lower or --upper, not both")}
	}
	return nil
}

// idle is where a flag does nothing in this conversion, or "" if it is used.
func (c *conversion) idle(name string) string {
	byteMode := c.byteMode()
	switch name {
	case "precision", "number":
		if byteMode {
			return "in byte mode"
		}
	case "no-newline":
		if c.to.Binary {
			return "when the output is raw bytes"
		}
	case "from-neg", "from-dec", "to-neg", "to-dec":
		if byteMode && !c.markerFreesDigit(name) {
			return "in byte mode"
		}
	case "from-pad", "from-tail", "to-pad", "to-tail":
		if !byteMode {
			return "in number mode"
		}
	case "by-index":
		return "here; it only picks a base for --get-base-name and --show-symbols"
	}
	return ""
}

// markerFreesDigit is a marker flag on a custom alphabet that has the default
// marker as a digit. The alphabet can't be built until the marker moves, so
// the flag does its job even where markers are never written.
func (c *conversion) markerFreesDigit(name string) bool {
	side, kind, _ := strings.Cut(name, "-")
	spec, b := c.f.fromSymbols, c.from
	if side == "to" {
		spec, b = c.f.toSymbols, c.to
	}
	def := "-"
	if kind == "dec" {
		def = "."
	}
	return spec != "" && slices.Contains(b.Symbols, def)
}

// resolveInputBase resolves the input side; an unspecified one falls back to
// defaultBase.
func (c *conversion) resolveInputBase(reg *convertbase.Registry, defaultBase string) (*convertbase.Base, error) {
	f := c.f
	name := f.fromName
	if name == "" && f.fromSymbols == "" {
		name = defaultBase
	}
	// Conflicting input selectors: --from-symbols silently wins over --from. Say
	// so, so a script mistake isn't masked (note to stderr; stdout stays clean).
	if f.fromSymbols != "" && f.fromName != "" {
		c.note("--from-symbols overrides --from %q", f.fromName)
	}
	from, err := convertbase.ResolveBase(reg, name, f.fromSymbols, f.fromMarkers.options())
	if err != nil {
		return nil, fmt.Errorf("input base: %w", err)
	}
	return from, nil
}

// outputBaseName picks the OUTBASE name: the --to flag wins over the positional
// (args[1], after NUMBER or "-"), and defaultBase is used if neither is set. It
// doesn't depend on the number, so the streaming path can be chosen before a
// byte is read.
func (c *conversion) outputBaseName(reg *convertbase.Registry, defaultBase string) (name string) {
	f := c.f
	posOut := ""
	if len(f.args) >= 2 {
		posOut = f.args[1]
	}
	name = f.toName
	if name == "" {
		name = posOut
	}
	if name == "" && f.toSymbols == "" {
		name = defaultBase
	}

	// Conflicting output selectors: --to-symbols wins over any name, and --to
	// wins over a positional OUTBASE. Both are silent today; warn (stderr) when
	// two selectors disagree so a mistake isn't masked. A --to and positional that
	// name the same base is not a conflict and stays quiet.
	switch {
	case f.toSymbols != "" && (f.toName != "" || posOut != ""):
		other := f.toName
		if other == "" {
			other = posOut
		}
		c.note("--to-symbols overrides output base %q", other)
	case f.toName != "" && posOut != "" && !sameBase(reg, f.toName, posOut):
		c.note("--to %q overrides positional output base %q", f.toName, posOut)
	}
	return name
}

// checkPositionals refuses a flag typed after the NUMBER, and anything past
// NUMBER (or "-") and OUTBASE. Flag parsing stops at the first non-flag, so a
// flag after the NUMBER is left here as a positional and was never seen.
func checkPositionals(reg *convertbase.Registry, f *cliFlags) error {
	args := f.args
	if len(args) >= 2 && looksLikeFlag(args[1]) {
		// A config may name a base "-x"; a real base is never a misplaced flag.
		if _, err := reg.Lookup(args[1]); err != nil {
			return flagAfterNumber(f.fs, args[1:])
		}
	}
	if len(args) <= 2 {
		return nil
	}
	extra := args[2]
	if looksLikeFlag(extra) {
		return flagAfterNumber(f.fs, args[2:])
	}
	return usageError{fmt.Errorf("unexpected extra positional argument: %q (see --help for usage)", extra)}
}

// looksLikeFlag is "--" and anything after it, or "-" and a letter. "-5" is a
// negative number, never a flag, so it gets no flag hint.
func looksLikeFlag(s string) bool {
	if strings.HasPrefix(s, "--") {
		return true
	}
	return len(s) >= 2 && s[0] == '-' && (s[1] >= 'a' && s[1] <= 'z' || s[1] >= 'A' && s[1] <= 'Z')
}

// flagAfterNumber names the first misplaced flag in rest, with its value in the
// example when it takes one.
func flagAfterNumber(fs *flag.FlagSet, rest []string) error {
	tok := rest[0]
	example := tok
	name, _, hasValue := strings.Cut(strings.TrimLeft(tok, "-"), "=")
	if fl := fs.Lookup(name); fl != nil && !hasValue && !isBoolFlag(fl) {
		if len(rest) >= 2 {
			example += " " + rest[1]
		} else {
			example += " VALUE"
		}
	}
	return usageError{fmt.Errorf("flags must come before the NUMBER: move %q ahead of it, e.g. %s %s NUMBER BASE (see --help)", tok, filepath.Base(os.Args[0]), example)}
}

func isBoolFlag(fl *flag.Flag) bool {
	b, ok := fl.Value.(interface{ IsBoolFlag() bool })
	return ok && b.IsBoolFlag()
}

// notePipeIgnored kills the silent-wrong-output trap: `echo 255 | prog 16` reads
// "16" as the NUMBER and never touches the pipe, so it prints "16" with exit 0.
// Detect the telltale shape - a real pipe, one positional, and that positional
// naming a known base - and point the user at "-". A bare number positional (the
// ordinary read-loop case) does not trip this. Whether the pipe actually holds
// data is deliberately not tested: finding out means reading it, and that is
// the one thing this path must not do.
func (c *conversion) notePipeIgnored(reg *convertbase.Registry) {
	args := c.f.args
	if c.fromStdin || len(args) != 1 || !isNamedPipe(os.Stdin) {
		return
	}
	if _, err := reg.Lookup(args[0]); err == nil {
		c.note("reading %q as the NUMBER, not the output base; stdin (piped) was ignored. To convert piped input, use: something | %s - %s",
			args[0], filepath.Base(os.Args[0]), args[0])
	}
}

// parsePrecision reads --precision. -1 is the auto sentinel Convert
// understands; an explicit value must be >= 0.
func parsePrecision(s string) (int, error) {
	s = strings.TrimSpace(s)
	if strings.EqualFold(s, "auto") {
		return -1, nil
	}
	n, err := strconv.Atoi(s)
	if err != nil || n < 0 {
		return 0, errors.New("precision must be a non-negative integer or 'auto'")
	}
	if n > maxPrecision {
		return 0, fmt.Errorf("precision must be at most %d", maxPrecision)
	}
	return n, nil
}

// checkOutputFlags refuses the output flags that can't apply to these bases.
// One the mode refuses is a usage error. One the output base's digits can't
// take exits 1, as an unknown base does.
func (c *conversion) checkOutputFlags() error {
	f, to := c.f, c.to
	// Escapes are a text notation, so they only reach the number path. Byte mode
	// writes raw bytes or a fixed codec alphabet, where the flag would be
	// accepted and then do nothing.
	if f.escapeCtrl && c.byteMode() {
		return usageError{errors.New("--escape-controls applies to number conversions only, not byte mode")}
	}
	// --lower/--upper: error out if the output base has mixed-case digits
	// (previously silently ignored; now strict, per user preference).
	for _, cf := range []struct {
		on     bool
		flag   string
		verb   string
		recase func(string) string
	}{{f.lower, "--lower", "lowercasing", strings.ToLower}, {f.upper, "--upper", "uppercasing", strings.ToUpper}} {
		if !cf.on {
			continue
		}
		if !canRecase(to, cf.recase) {
			return fmt.Errorf("%s is invalid for mixed-case output base %q: %s its digits would change their meaning", cf.flag, to.Name(), cf.verb)
		}
		if digit, what := recaseClash(to, cf.recase); what != "" {
			return fmt.Errorf("%s is invalid for output base %q: %s digit %q gives its %s", cf.flag, to.Name(), cf.verb, digit, what)
		}
	}
	return nil
}

// run converts the number, streaming it when it can.
func (c *conversion) run(stdout *bufio.Writer, reg *convertbase.Registry) error {
	// --binary is meaningful only between two text bases; if either side is
	// already the bytes base the conversion is byte-exact anyway, so ignore it.
	if c.f.binary && !c.from.Binary && !c.to.Binary {
		var err error
		if c.bytes, err = reg.Lookup("bytes"); err != nil {
			return err
		}
	}
	if c.fromStdin && c.byteMode() {
		return c.stream(stdout)
	}
	return c.convertBuffered(stdout)
}

// noteNumberReading is the loud note for the silent-ambiguous case: two
// power-of-2 text bases with no mode given. The value is converted as a number
// (leading zeros dropped), which differs from a byte re-encoding. Goes to
// stderr so pipes stay clean.
func (c *conversion) noteNumberReading() {
	if c.f.binary || c.f.number || c.from.Binary || c.to.Binary {
		return
	}
	if convertbase.PowerOfTwoBits(len(c.from.Symbols)) > 0 && convertbase.PowerOfTwoBits(len(c.to.Symbols)) > 0 {
		c.note("converted as a positional notation number (assumed '--number' flag). If you meant to do binary encode/decode, add the --binary flag.")
	}
}

// stream is piped byte mode, stdin to stdout through the library, which
// streams every pair it can and buffers the rest. It writes os.Stdout itself
// and returns its own write errors; nothing is in the stdout buffer yet, so
// the order holds.
func (c *conversion) stream(stdout *bufio.Writer) error {
	var out io.Writer = os.Stdout
	var rw *recaseWriter
	if c.f.lower || c.f.upper {
		rw = newRecaseWriter(os.Stdout, c.f.upper, keptRunes(c.to)...)
		out = rw
	}
	if err := convertbase.ConvertStream(os.Stdin, out, c.from, c.to, c.f.binary); err != nil {
		return err
	}
	if rw != nil {
		if err := rw.flush(); err != nil {
			return err
		}
	}
	// Text output normally ends in a newline (as the buffered path's
	// Println does); no-newline and binary output stay byte-exact.
	if !c.to.Binary && !c.f.noNewline {
		fmt.Fprintln(stdout)
	}
	return nil
}

// convertBuffered reads the whole number (from stdin or argv), converts, emits.
func (c *conversion) convertBuffered(stdout *bufio.Writer) error {
	var number string
	if c.fromStdin {
		var err error
		if number, err = readStdin(c.from); err != nil {
			return err
		}
	} else {
		number = c.f.args[0]
	}

	result, err := c.convert(number)
	if err != nil {
		return err
	}
	if c.f.lower || c.f.upper {
		if c.bytes != nil || c.from.Binary || c.to.Binary {
			result = recaseBytePath(result, c.to, c.f.upper)
		} else {
			result = recaseDigits(result, c.to, c.f.upper)
		}
	}
	if c.f.escapeCtrl {
		result = convertbase.EscapeControls(result, c.to)
	}

	stdout.WriteString(result)
	if !c.f.noNewline && !c.to.Binary {
		stdout.WriteString("\n")
	}
	return nil
}

func (c *conversion) convert(number string) (string, error) {
	if c.bytes == nil {
		return convertbase.Convert(number, c.from, c.to, c.precision)
	}
	// from-digits -> raw bytes -> to-digits, matching the streaming route and
	// basenc byte-for-byte (whole-byte checks and RFC padding included).
	mid, err := convertbase.Convert(number, c.from, c.bytes, c.precision)
	if err != nil {
		return "", err
	}
	return convertbase.Convert(mid, c.bytes, c.to, c.precision)
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

// infoAsks is the informational outputs asked for, each once, in the order first
// asked. flag.Visit walks flags sorted by name, so the order is kept as the
// flags are set.
type infoAsks []string

func (a *infoAsks) flag(name string) *infoFlag { return &infoFlag{name: name, asks: a} }

func (a infoAsks) has(name string) bool {
	for _, n := range a {
		if n == name {
			return true
		}
	}
	return false
}

func (a *infoAsks) drop(name string) {
	kept := (*a)[:0]
	for _, n := range *a {
		if n != name {
			kept = append(kept, n)
		}
	}
	*a = kept
}

// infoFlag is a bool flag that records itself in an infoAsks when set.
type infoFlag struct {
	name string
	asks *infoAsks
}

func (f *infoFlag) String() string   { return "" }
func (f *infoFlag) IsBoolFlag() bool { return true }

func (f *infoFlag) Set(s string) error {
	on, err := strconv.ParseBool(s)
	if err != nil {
		return err
	}
	if !on {
		f.asks.drop(f.name)
	} else if !f.asks.has(f.name) {
		*f.asks = append(*f.asks, f.name)
	}
	return nil
}

// printInfo writes each informational output asked for, in order, with one
// blank line between them. A lone one prints just as it would by itself, so
// --version stays one bare line for scripts.
func printInfo(out io.Writer, asked infoAsks, help func(io.Writer)) error {
	var all strings.Builder
	for i, name := range asked {
		if i > 0 && !strings.HasSuffix(all.String(), "\n\n") {
			all.WriteString("\n")
		}
		switch name {
		case "help":
			help(&all)
		case "version":
			fmt.Fprintln(&all, versionText())
		case "about":
			printAbout(&all)
		case "donate":
			printDonate(&all)
		case "examples":
			printExamples(&all)
		}
	}
	_, err := io.WriteString(out, all.String())
	return err
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
		return nil, usageError{errors.New("select a base by name/alias argument or --by-index=N")}
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

// recaseDigits applies --lower/--upper to the digits of a result and leaves the
// base's markers as they are. The markers are not digits, so recasing them can
// produce a value the same base will not read back - a base whose negative
// marker is "N" would answer "-255" as "nff", which is not that base's spelling
// of anything. A marker never appears inside a digit symbol (Finalize refuses
// that), so the first occurrence of the decimal marker is the real split.
func recaseDigits(s string, b *convertbase.Base, upper bool) string {
	recase := strings.ToLower
	if upper {
		recase = strings.ToUpper
	}
	prefix := ""
	if neg := b.NegSym(); neg != "" && strings.HasPrefix(s, neg) {
		prefix, s = neg, s[len(neg):]
	}
	if dec := b.DecSym(); dec != "" {
		if at := strings.Index(s, dec); at >= 0 {
			return prefix + recase(s[:at]) + dec + recase(s[at+len(dec):])
		}
	}
	return prefix + recase(s)
}

// recaseBytePath is --lower/--upper for buffered byte-path output, which has
// no markers. It goes through the same writer as a stream so both give the
// same bytes.
func recaseBytePath(s string, b *convertbase.Base, upper bool) string {
	var out strings.Builder
	rw := newRecaseWriter(&out, upper, keptRunes(b)...)
	// A strings.Builder write can't fail.
	_, _ = rw.Write([]byte(s))
	_ = rw.flush()
	return out.String()
}

// keptRunes are the pad and tail symbols, which the case flags leave alone.
// They aren't digits, so a recased one is no symbol of the base at all.
// Finalize makes each of them one character.
func keptRunes(b *convertbase.Base) []rune {
	var keep []rune
	for _, s := range append([]string{b.PadSymbol}, b.TailSymbols...) {
		if r, size := utf8.DecodeRuneInString(s); size > 0 && size == len(s) {
			keep = append(keep, r)
		}
	}
	return keep
}

// recaseWriter is --lower/--upper for byte-path output. That output is digits,
// pad and tail symbols, never a marker, and in a stream every one of them is a
// single character, so the kept runes are exactly the pad and tail. A rune
// split across two writes waits for its last byte, since recasing half of one
// turns it into U+FFFD.
type recaseWriter struct {
	w      io.Writer
	recase func(string) string
	ascii  [utf8.RuneSelf]byte
	keep   map[rune]bool
	carry  []byte
	buf    []byte
}

func newRecaseWriter(w io.Writer, upper bool, keep ...rune) *recaseWriter {
	rw := &recaseWriter{w: w, recase: strings.ToLower}
	if upper {
		rw.recase = strings.ToUpper
	}
	for i := range rw.ascii {
		rw.ascii[i] = rw.recase(string(rune(i)))[0]
	}
	if len(keep) > 0 {
		rw.keep = make(map[rune]bool, len(keep))
	}
	for _, r := range keep {
		rw.keep[r] = true
		if r < utf8.RuneSelf {
			rw.ascii[r] = byte(r)
		}
	}
	return rw
}

func (rw *recaseWriter) Write(p []byte) (int, error) {
	n := len(p)
	if len(rw.carry) > 0 {
		p = append(rw.carry, p...)
		rw.carry = nil
	}
	whole := len(p)
	for i := len(p) - 1; i >= 0 && i >= len(p)-utf8.UTFMax; i-- {
		if utf8.RuneStart(p[i]) {
			if !utf8.FullRune(p[i:]) {
				whole = i
			}
			break
		}
	}
	if whole < len(p) {
		rw.carry = append([]byte(nil), p[whole:]...)
	}
	if err := rw.emit(p[:whole]); err != nil {
		return 0, err
	}
	return n, nil
}

// flush writes a rune the stream ended in the middle of.
func (rw *recaseWriter) flush() error {
	if len(rw.carry) == 0 {
		return nil
	}
	err := rw.emit(rw.carry)
	rw.carry = nil
	return err
}

func (rw *recaseWriter) emit(p []byte) error {
	if len(p) == 0 {
		return nil
	}
	if cap(rw.buf) < len(p) {
		rw.buf = make([]byte, len(p))
	}
	out := rw.buf[:len(p)]
	for i, b := range p {
		if b >= utf8.RuneSelf {
			out = rw.recaseWide(out[:i], p[i:])
			break
		}
		out[i] = rw.ascii[b]
	}
	rw.buf = out
	_, err := rw.w.Write(out)
	return err
}

// recaseWide appends p recased to out, leaving the kept runes as they are.
// Everything between two kept runes goes through recase whole, which gives the
// same bytes as recasing it rune by rune, invalid bytes included.
func (rw *recaseWriter) recaseWide(out, p []byte) []byte {
	if len(rw.keep) == 0 {
		return append(out, rw.recase(string(p))...)
	}
	from := 0
	for i := 0; i < len(p); {
		r, size := utf8.DecodeRune(p[i:])
		// size 1 is an invalid byte, not a kept U+FFFD.
		if rw.keep[r] && (r != utf8.RuneError || size > 1) {
			out = append(out, rw.recase(string(p[from:i]))...)
			out = append(out, p[i:i+size]...)
			from = i + size
		}
		i += size
	}
	return append(out, rw.recase(string(p[from:]))...)
}

// recaseClash finds a digit that recase turns into the pad, a tail symbol or a
// marker, which the same base would then read as that instead. Finalize keeps
// the case flip of a one-letter ASCII digit clear of all of those, so it takes
// another script or a longer digit to hit this. what is empty when nothing
// clashes.
func recaseClash(b *convertbase.Base, recase func(string) string) (digit, what string) {
	others := map[string]string{}
	if neg := b.NegSym(); neg != "" {
		others[neg] = "negative marker"
	}
	if dec := b.DecSym(); dec != "" {
		others[dec] = "decimal marker"
	}
	for _, t := range b.TailSymbols {
		others[t] = "tail symbol"
	}
	if b.PadSymbol != "" {
		others[b.PadSymbol] = "padding symbol"
	}
	for _, s := range b.Symbols {
		if r := recase(s); r != s {
			if what, hit := others[r]; hit {
				return s, what
			}
		}
	}
	return "", ""
}

// canRecase reports whether recasing the output's digits with recase keeps
// them a valid representation. False when the base has both cases of the same
// letter as digits (mixed-case digits), since recasing would collide them.
func canRecase(b *convertbase.Base, recase func(string) string) bool {
	seen := make(map[string]struct{}, len(b.Symbols))
	for _, s := range b.Symbols {
		seen[s] = struct{}{}
	}
	for _, s := range b.Symbols {
		r := recase(s)
		if r != s {
			if _, both := seen[r]; both {
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
// where each base would be resolved from in a real run. configErrs has the
// load failure for each config path that did not load.
func printHelp(out io.Writer, reg *convertbase.Registry, configErrs map[string]error, etcPath, userPath, fromName, toName, fromSyms, toSyms string) {
	printCopyright(out)
	fmt.Fprint(out, `Convert an arbitrarily large number to/from arbitrary bases.

Usage:
  convert-base-v2 [flags] NUMBER [OUTBASE]
  convert-base-v2 [flags] - [OUTBASE]              # read NUMBER from stdin
  something | convert-base-v2 [flags]              # read NUMBER from the pipe
  something | convert-base-v2 [flags] - [OUTBASE]  # same, with OUTBASE as an
                                                   # argument (a NUMBER argument
                                                   # always wins over the pipe)

Flags go before the NUMBER.

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

Base info (print, then exit; BASE is a base name/alias argument):
  --list               List all known bases
  --list-compat        List only the v1/v1b compatibility bases
  --get-index-count    Print how many bases are defined
  --get-base-name BASE Print a base's canonical name
  --show-symbols BASE  Print a base's symbols, concatenated
  --show-symbols-0 BASE
                       Like --show-symbols but NUL-separated (machine-readable)
  --by-index N         Pick the base by its INDEX column in --list (0-based),
                       in place of BASE

Other:
  --config FILE        User SHCL config; /etc is always tried too. Written with
                       a commented example on first run.
                       [default %s]

Program info (several in one run each print once, in order, then exit):
  --help, -h           Show this help
  --examples           Show usage examples
  --version, -v, -V    Print version and build number
  --about              Print version, copyright, license and project home
  --donate             Print ways to support the project

Exit status:
  0                    Success
  1                    The conversion failed, such as an unknown base, a value
                       the base can't take, a digit not in the base, or a
                       failed write
  2                    The command line could not be used, such as an unknown
                       flag or a bad flag value, flags that can't go together,
                       a flag after the NUMBER or an extra argument, or no
                       NUMBER or BASE was given

`, userConfigPath())

	// Config file status.
	fmt.Fprintln(out, "Config files (applied in order; later entries override earlier ones):")
	fmt.Fprintf(out, "  %-50s  %s\n", "(built-in predefined bases)", "(always)")
	describePath := func(label, path string) {
		if path == "" {
			fmt.Fprintf(out, "  %-50s  %s\n", "("+label+": unset)", "")
			return
		}
		err := configErrs[path]
		switch {
		case err == nil && pathLoaded(reg, path):
			fmt.Fprintf(out, "  %-50s  [loaded]\n", path)
		case err == nil:
			fmt.Fprintf(out, "  %-50s  [not found]\n", path)
		case convertbase.IsConfigUnreadable(err):
			fmt.Fprintf(out, "  %-50s  [unreadable]\n", path)
		default:
			fmt.Fprintf(out, "  %-50s  [not loaded]\n      %v\n", path, err)
		}
	}
	describePath("system", etcPath)
	if userPath == etcPath {
		fmt.Fprintf(out, "  %-50s  %s\n", "user: (same path as the system file; skipped)", "")
	} else {
		describePath("user", userPath)
	}
	// If both exist, note precedence.
	etcLoaded := pathLoaded(reg, etcPath)
	userLoaded := userPath != "" && userPath != etcPath && pathLoaded(reg, userPath)
	switch {
	case etcLoaded && userLoaded:
		fmt.Fprintf(out, "  -> %s takes precedence over %s (and both over built-in).\n", userPath, etcPath)
	case etcLoaded:
		fmt.Fprintf(out, "  -> a name defined in %s takes precedence over built-in.\n", etcPath)
	case userLoaded:
		fmt.Fprintf(out, "  -> a name defined in %s takes precedence over built-in.\n", userPath)
	}

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
Copyright © %s %s.
Licensed under the GNU General Public License v2.0 or later. Full text at:
  https://spdx.org/licenses/GPL-2.0-or-later.html
There is no warranty, to the extent permitted by law.

`, versionText(), copyrightYear, author)
}

func printAbout(out io.Writer) {
	printCopyright(out)
	fmt.Fprint(out, `A universal base converter. It converts a number of any size, negative or
fractional, between any two bases: dozens of named ones, the RFC 4648
standards, or an alphabet of your own. It also streams raw binary data through
power-of-2 bases, the way basenc does.

Project home: https://github.com/jim-collier/convert-base-v2
`)
}

func printDonate(out io.Writer) {
	fmt.Fprint(out, `convert-base-v2 is free software, and stays that way.

If it saves you time and you want to give something back:
  https://github.com/sponsors/jim-collier
  https://ko-fi.com/jimcollier

A star on the project, a clear bug report, or a mention to someone who needs it
are worth just as much.
`)
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
