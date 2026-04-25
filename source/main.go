//	Copyright © 2026 Jim Collier (ID: 1cv◂‡Vᛦ)
//	Licensed under the GNU General Public License v2.0 or later. Full text at:
//		https://spdx.org/licenses/GPL-2.0-or-later.html
//	SPDX-License-Identifier: GPL-2.0-or-later

package main

import (
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
)

const version = "v1.1.0-beta1"
const (
	copyrightYear = "2023-2026"
	author        = "Jim Collier (ID: 1cv◂‡Vᛦ)"
)

const etcConfigPath = "/etc/convert-base-v2/convert-base-v2.conf"

func main() {
	if err := run(); err != nil {
		fmt.Fprintf(os.Stderr, "error: %v\n", err)
		os.Exit(1)
	}
}

func run() error {
	var (
		fromName     = flag.String("from", "", "input base name/alias (e.g. 10, hex, 64u); default 10")
		toName       = flag.String("to", "", "output base name/alias; default 10; also accepted as a positional arg")
		fromSymbols  = flag.String("from-symbols", "", `custom input base (spec form: "SYMS [neg=X] [dec=Y]")`)
		toSymbols    = flag.String("to-symbols", "", `custom output base (spec form: "SYMS [neg=X] [dec=Y]")`)
		precision    = flag.Int("precision", 50, "max fractional digits in output")
		lower        = flag.Bool("lower", false, "lowercase output (errors if output base has mixed-case digits)")
		raw          = flag.Bool("raw", false, "write output as raw bytes with no trailing newline (for binary output)")
		list         = flag.Bool("list", false, "list all known bases and exit")
		configFile   = flag.String("config", userConfigPath(), "user-level YAML config file; /etc is always tried too (missing file is OK)\n        ")
		showVersion  = flag.Bool("version", false, "print version and exit")
		helpFlag     = flag.Bool("help", false, "show help and exit")
		hFlag        = flag.Bool("h", false, "alias for -help")
		examplesFlag = flag.Bool("examples", false, "show usage examples and exit")
	)

	// Suppress Go's default auto-exit on -h/-help; we handle help ourselves
	// so we can show config-file status and base-resolution info.
	flag.CommandLine.Usage = func() {} // no-op; we print help manually
	flag.Parse()

	if *showVersion {
		fmt.Println(version)
		return nil
	}

	// Build registry and layer on config files (lowest to highest precedence):
	//   built-in  <  /etc  <  user config  <  CLI flags
	// Later-registered aliases overwrite earlier ones.
	reg, err := NewRegistry()
	if err != nil {
		return err
	}
	if err := reg.LoadConfig(etcConfigPath); err != nil {
		return fmt.Errorf("config %s: %w", etcConfigPath, err)
	}
	// Only load user config if it's a different path (avoid double-registering
	// if user explicitly set -config=/etc/...).
	userPath := *configFile
	if userPath != "" && userPath != etcConfigPath {
		if err := reg.LoadConfig(userPath); err != nil {
			return fmt.Errorf("config %s: %w", userPath, err)
		}
	}

	// --help (with or without accompanying flags).
	if *helpFlag || *hFlag {
		printHelp(reg, etcConfigPath, userPath, *fromName, *toName, *fromSymbols, *toSymbols)
		return nil
	}

	// --examples
	if *examplesFlag {
		printExamples()
		return nil
	}

	if *list {
		reg.Print(os.Stdout)
		return nil
	}

	// Defaults: both input and output default to base 10.
	inBaseName := *fromName
	if inBaseName == "" && *fromSymbols == "" {
		inBaseName = "10"
	}
	from, err := resolveBase(reg, inBaseName, *fromSymbols)
	if err != nil {
		return fmt.Errorf("input base: %w", err)
	}

	args := flag.Args()

	// NUMBER: from args, or from stdin if arg is "-" or missing-and-piped.
	var number string
	switch {
	case len(args) >= 1 && args[0] != "-":
		number = args[0]
	case len(args) >= 1 && args[0] == "-":
		number, err = readStdin(from)
		if err != nil {
			return err
		}
	case len(args) == 0 && !isTerminal(os.Stdin):
		number, err = readStdin(from)
		if err != nil {
			return err
		}
	default:
		// No args and stdin is a terminal - nothing to do. Show help.
		printHelp(reg, etcConfigPath, userPath, *fromName, *toName, *fromSymbols, *toSymbols)
		os.Exit(2)
	}

	// OUTBASE: --to flag wins over positional. Positional is args[1] when
	// args[0] is the number (or "-"). Default to "10" if neither set.
	outBaseName := *toName
	posOut := ""
	if len(args) >= 2 {
		posOut = args[1]
	}
	if outBaseName == "" {
		outBaseName = posOut
	}
	if outBaseName == "" && *toSymbols == "" {
		outBaseName = "10"
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
		return fmt.Errorf("unexpected extra positional argument: %q", args[expectedPositionals])
	}

	to, err := resolveBase(reg, outBaseName, *toSymbols)
	if err != nil {
		return fmt.Errorf("output base: %w", err)
	}

	if *precision < 0 {
		return fmt.Errorf("precision must be >= 0")
	}

	// --lower: error out if the output base has mixed-case digits (previously
	// silently ignored; now strict, per user preference).
	if *lower && !canLowercase(to) {
		return fmt.Errorf("--lower is invalid for mixed-case output base %q: lowercasing its digits would change their meaning", to.Name())
	}

	result, err := Convert(number, from, to, *precision)
	if err != nil {
		return err
	}
	if *lower {
		result = strings.ToLower(result)
	}

	if *raw || to.Binary {
		_, err := os.Stdout.WriteString(result)
		return err
	}
	fmt.Println(result)
	return nil
}

// resolveBase returns a Base either from the registry (by name) or from a
// custom symbols spec (which, if provided, takes precedence over the name).
// CLI-supplied custom bases are tagged with Source indicating the flag name.
func resolveBase(reg *Registry, name, customSpec string) (*Base, error) {
	if customSpec != "" {
		sp, err := ParseSymbolSpec(customSpec)
		if err != nil {
			return nil, err
		}
		b := &Base{
			Aliases:  []string{fmt.Sprintf("custom(%d)", len(sp.Symbols))},
			Symbols:  sp.Symbols,
			Negative: sp.Negative,
			Decimal:  sp.Decimal,
			Source:   "--from-symbols / --to-symbols (CLI flag)",
		}
		if err := b.finalize(); err != nil {
			return nil, err
		}
		return b, nil
	}
	if name == "" {
		return nil, fmt.Errorf("no base specified")
	}
	return reg.Lookup(name)
}

// readStdin reads all of stdin as bytes. Trims exactly one trailing '\n' (and
// an optional preceding '\r') unless '\n' is a valid digit in the input base,
// in which case every byte is data.
func readStdin(from *Base) (string, error) {
	data, err := io.ReadAll(os.Stdin)
	if err != nil {
		return "", fmt.Errorf("reading stdin: %w", err)
	}
	// Keep all bytes if newline is a digit (i.e. base binary - every byte is valid).
	if from.allOneByte && from.byteValue['\n'] >= 0 {
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
func canLowercase(b *Base) bool {
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

// isTerminal reports whether f appears to be an interactive terminal (not a pipe/file).
func isTerminal(f *os.File) bool {
	fi, err := f.Stat()
	if err != nil {
		return true
	}
	return (fi.Mode() & os.ModeCharDevice) != 0
}

// userConfigPath returns the default path for the user-level config file.
func userConfigPath() string {
	if x := os.Getenv("XDG_CONFIG_HOME"); x != "" {
		return filepath.Join(x, "convert-base-v2", "convert-base-v2.conf")
	}
	if h, err := os.UserHomeDir(); err == nil {
		return filepath.Join(h, ".config", "convert-base-v2", "convert-base-v2.conf")
	}
	return ""
}

// printHelp prints the program's help text plus a contextual report on config
// file visibility and, if the user passed any --from/--to/-*-symbols flags,
// where each base would be resolved from in a real run.
func printHelp(reg *Registry, etcPath, userPath, fromName, toName, fromSyms, toSyms string) {
	out := os.Stderr
	printCopyright()
	fmt.Fprintf(out, `Convert an arbitrarily large number to/from arbitrary bases.

Usage:
  convert-base-v2 [flags] NUMBER [OUTBASE]
  convert-base-v2 [flags] - [OUTBASE]              # read NUMBER from stdin
  something | convert-base-v2 [flags] [OUTBASE]    # read NUMBER from stdin if no arg

If --from is unset, input base defaults to 10. If neither --to nor OUTBASE is
given, output base also defaults to 10.

Flags:
`, version)

	// This replaces flag.PrintDefaults(), so that flags are printed more clearly with leading '--', instead of just '-'.
	flag.VisitAll(func(f *flag.Flag) {
		// Don't show help for some stuff
		switch f.Name {
		case "h":
			return
		}
		typeName, _ := flag.UnquoteUsage(f)
		if typeName != "" {
			//fmt.Fprintf(out, "  --%s %s\n", f.Name, typeName)
			fmt.Fprintf(out, "  --%s VAL\n", f.Name)
		} else {
			fmt.Fprintf(out, "  --%s\n", f.Name)
		}
		fmt.Fprintf(out, "        %s", f.Usage)
		if f.DefValue != "" && f.DefValue != "false" && f.DefValue != "0" {
			fmt.Fprintf(out, " (default %q)", f.DefValue)
		}
		fmt.Fprintln(out)
	})

	fmt.Fprintln(out)

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
	} else {
		//	fmt.Fprintln(out)
		// fmt.Fprintln(out, "(Pass --from / --to / --from-symbols / --to-symbols to see where each base would resolve from.)")
	}
	fmt.Fprintln(out)
}

// pathLoaded reports whether reg.LoadConfig(path) actually loaded that file.
func pathLoaded(reg *Registry, path string) bool {
	for _, p := range reg.LoadedConfigs {
		if p == path {
			return true
		}
	}
	return false
}

// reportSide describes how one side (input or output) would be resolved.
func reportSide(out io.Writer, label string, reg *Registry, name, symbols, flagName string) {
	switch {
	case symbols != "":
		sp, err := ParseSymbolSpec(symbols)
		if err != nil {
			fmt.Fprintf(out, "  %s: %s — INVALID SPEC: %v\n", label, flagName, err)
			return
		}
		fmt.Fprintf(out, "  %s: custom spec via %s — %d digits", label, flagName, len(sp.Symbols))
		if sp.Negative != nil {
			fmt.Fprintf(out, ", neg=%s", fmtMarker(sp.Negative))
		}
		if sp.Decimal != nil {
			fmt.Fprintf(out, ", dec=%s", fmtMarker(sp.Decimal))
		}
		fmt.Fprintln(out)
	case name != "":
		b, err := reg.Lookup(name)
		if err != nil {
			fmt.Fprintf(out, "  %s: alias %q -> UNRESOLVED (%v)\n", label, name, err)
			return
		}
		fmt.Fprintf(out, "  %s: alias %q -> base %q (%d digits), source: %s\n",
			label, name, b.Name(), len(b.Symbols), b.Source)
	default:
		fmt.Fprintf(out, "  %s: (unset — would default to base 10, source: built-in)\n", label)
	}
}

func fmtMarker(p *string) string {
	if p == nil {
		return "(default)"
	}
	if *p == "" {
		return "(disabled)"
	}
	return fmt.Sprintf("%q", *p)
}

func printCopyright() {
	fmt.Fprintf(os.Stderr, `convert-base-v2 %s
Copyright (c) %s %s.
Licensed under the GNU General Public License v2.0 or later. Full text at:
  https://spdx.org/licenses/GPL-2.0-or-later.html
There is no warranty, to the extent permitted by law.

`, version, copyrightYear, author)
}

func printExamples() {
	fmt.Fprint(os.Stderr, `Examples:
  # Convert 255 (in default base-10) to hex output; = FF
  convert-base-v2  255  16

  # Convert from hex (to default base-10 output); = 255
  convert-base-v2  --from 16  FF

  # Negative base-10 value to hex ( -- to end flags); = -1E240
  convert-base-v2  --  -123456  16

  # Big base-10 value to qntm's base-2048; = ɼధശಳপݷટථރŦၓƨ൝
  convert-base-v2  1234567899999999999999999999999999987654321  2048

  # Custom base and input value, to base-10; = 148.25
  convert-base-v2 --from-symbols ABCD  --to 10  CBBA.B

  # Custom base and input value, to wordsafe base-20 output; = -9FCC.8M6
  convert-base-v2  --from-symbols "aeiouy.-_0 neg=~ dec=/"  --to 20w  "~y0-._/ooo"

  # Convert a binary file to any 2^N base (i.e. 4, 8, 16, 32, 64 ... 65536)
  # Unlike base-to-base conversion in N(O^2) time, this is done in linear time.
  # But 'basenc' is much faster, and base-64 is maximally efficient in UTF-8
  # vs larger bases. TLDR, for speed and compactness, use 'basenc --base64'.
  cat file.bin | convert-base-v2 --from binary --to 64u > out.b64

  cat out.b64  | convert-base-v2 --from 64u --to binary > file2.bin       # base64url -> File (bit-perfect)

	`)
}
