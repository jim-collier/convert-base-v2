<!-- markdownlint-disable MD007 -- Unordered list indentation -->
<!-- markdownlint-disable MD010 -- No hard tabs -->
<!-- markdownlint-disable MD033 -- No inline html -->
<!-- markdownlint-disable MD055 -- Table pipe style [Expected: leading_and_trailing; Actual: leading_only; Missing trailing pipe] -->
<!-- markdownlint-disable MD041 -- First line in a file should be a top-level heading -->

<!-- TOC ignore:true -->
# Project backlog

This is a product backlog just for pre-v1.0.0 release. After that, bugs, features, and enhancements will be managed in Github Issues, and/or [todo.md](../todo.md)

<!-- TOC ignore:true -->
## Table of contents
<!-- TOC -->

- [Conventions](#conventions)
- [Backlog](#backlog)
	- [Todo](#todo)
	- [Bugs](#bugs)
	- [New features and enhancements](#new-features-and-enhancements)
	- [Done](#done)
		- [Done - Bugs](#done---bugs)
		- [Done - New features and enhancements](#done---new-features-and-enhancements)
	- [Deferred](#deferred)
	- [Canceled](#canceled)

<!-- /TOC -->

## Conventions

In each section, items are listed approximately from newest to oldest.

| Icon | Status
| :--: | :--
| 🔘   | Not started
| 🛠️   | Started, and/or partially complete
| ✋   | Defer
| ✅   | Complete
| 🚫   | Canceled

Sub-bullets can be prefaced with a short tag so the note's role is clear at a glance: `Reproduced:`, `Cause:`, `Probable fix:`, `Fixed:`, `Done:`, `Verified:`, or `Note:`.

## Backlog

### Todo

### Bugs

### New features and enhancements

- 🔘 Push the first `lib/v0.1.0` tag, so the Go module can be fetched.
	- Note: nothing can import the package until the tag exists, and the README should not claim otherwise before then.
	- Note: a second project is waiting on it, and carries a local path override in the meantime.
	- Note: blocked only on the current work branch merging.

### Done

#### Done - Bugs

- ✅ Slicing a value with a very large count crashed instead of clamping. (Code review 20260802 item 1)
	- Reproduced: asking for more symbols than the value holds is documented to clamp, and it does, until the count approaches the largest whole number the machine handles. Then it crashes.
	- Cause: the check added the start and the count together, and that sum wraps around to a negative number, so the too-long count read as short enough.
	- Fixed: the count is compared against how many symbols are left instead, which cannot wrap.
	- Note: reachable from the library and from a 32-bit build long before the limit, and not from the module, whose count is a smaller number.
	- Verified: a new test covers both ends, and the rest of the suite is unchanged.

- ✅ A wild fixed-width value from a host killed the module instead of being refused. (Code review 20260802 item 2)
	- Reproduced: asking the module to pad a value to the largest width its argument can express stops the module dead. The host gets a crash, not an error.
	- Cause: padding to a width allocates that many symbols, and the width had no upper limit. Running the module out of memory cannot be caught and recovered from.
	- Note: the conversion call already caps its precision for the same reason, so the two were inconsistent.
	- Fixed: width is capped at the same generous limit, and anything larger is refused. The fields this exists for are tens of symbols wide.
	- Verified: the host exerciser now asks for the largest possible width and requires a refusal. Confirmed to fail before the fix.

- ✅ Writing control characters by name got slower the longer the value was. (Code review 20260802 item 3)
	- Cause: one control character's name can run into the text after it, so each name is read back against what follows before it is written. That check was copying the whole rest of the value every time, which turns a long value into a lot of copying.
	- Fixed: only a name's worth of the following text can change how a name reads, so that is all the check looks at now.
	- Verified: cost now rises evenly with length instead of with its square. A 200 KB value went from about a third of a second to seven thousandths, and the gap widens from there. Output is unchanged, and the test covering every control against every character it can be followed by still passes.

- ✅ The browser module reported a confusing error for a value that was not a real number. (Code review 20260802 item 4)
	- Cause: a number that is not finite was formatted as a word and then reported as an unrecognized digit. The precision setting already checked for this and the value did not.
	- Fixed: it is refused with a message that says what is wrong.

- ✅ The fuzz stage failed a run with nothing but "context deadline exceeded".
	- Reproduced: intermittent, and only at the point where the run's time limit expires. No failing input was ever recorded, and the same target passes on a rerun.
	- Cause: two separate things. Go itself reports the time limit as the run's error when it reads one of its own cancellation signals a moment before that signal has propagated, so a clean finish is scored as a failure. Separately the run had slowed to a crawl by then, which is what made the timing gap easy to hit.
	- Fixed: the stage now fails only on a real find, which Go always names by writing the failing input to a file. A bare time-limit report is passed with a note.
	- Fixed: the slowdown had two causes of its own. Converting a number is quadratic in its length, so the fuzzer was spending a whole run on ever longer values that reached nothing new; values are now capped at a length that still reaches every branch. And Go's default budget for shrinking a new find is a minute, longer than the whole run, so a single find parked a worker for the remainder; that budget is now a small slice of the run.
	- Verified: three times as many cases per run on the number target and four times on the streaming one, with more new coverage found in every case, and no run stalls. The guard was checked against a real crash, a hang, and a bare time-limit report.

- ✅ Wrapped base-45 would not decode.
	- Reproduced: encode to base 45, wrap the text at any width, decode it back, and the newline is reported as not a base-45 symbol. Every other base that carries raw bytes tolerates wraps.
	- Cause: base-45 has space as a digit, so it skipped no whitespace at all. CR and LF are not digits, so there was never a reason to include them in that.
	- Fixed: base-45 decoding drops CR and LF and nothing else. Space still means what it always did.

- ✅ Stale base names in the README table, the changelog, and the tests.
	- Cause: `64programmer`, `69nice`, and `69emoji` were renamed, and nothing checked that a documented name still resolves.
	- Fixed: names corrected, and the test suite now fails if any base named in the README table no longer resolves.

- ✅ Piped input was ignored when a value was also given on the command line. (BxZNl-1)
	- Note: the command line still wins. Changing that would break scripts that pass a value while their input happens to be an inherited pipe, and could consume a pipe the tool should not touch.
	- Fixed: a pipe carrying data, plus a lone argument that names a known base, now prints a note pointing at the `-` form. The usage line was corrected to require `-` for reading a pipe.

- ✅ Custom alphabets where one symbol started another decoded wrong. (BxZNl-2)
	- Cause: reading left to right, the shorter symbol matched first and the rest of the longer one was read as separate digits.
	- Fixed: such an alphabet is now refused where it is defined. Only multi-character symbols can hit this, so no built-in base was affected.

- ✅ A marker inside a multi-character digit corrupted parsing. (BxZNl-3)
	- Fixed: a base whose negative or decimal marker appears inside any digit is refused where it is defined.

- ✅ Streaming encode treated a read error as the end of the input. (BxZNl-4)
	- Cause: any read failure finished the output as though the data had run out, so a truncated read produced a complete-looking result.
	- Fixed: a real read error is reported. Only a genuine end of input finishes the stream.

- ✅ Tab and newline escapes in symbol specs did nothing. (BxZNl-5)
	- Cause: they were expanded before the spec was split on whitespace, so they were consumed as separators.
	- Fixed: they are held aside during the split, the same way an escaped space already was.

- ✅ Decoding was stricter from a pipe than from an argument. (BxZNl-6)
	- Fixed: line breaks are tolerated either way, a digit after padding is refused either way, and base91 refuses junk instead of skipping it.

- ✅ Fractional output was cut short instead of rounded. (BxZNl-7)
	- Fixed: the fraction rounds half up, and a carry rolls into the whole part. Converting `0.1` to another base and back is stable now.

- ✅ Tiny fractions printed as "0.000" or "-0.000". (BxZNl-8)
	- Fixed: a value smaller than one output digit rounds to nothing, so there is no invented zero fraction and no sign on it. Same rewrite as the item above.

- ✅ The version stamped into release builds was discarded. (BxZNl-9)
	- Cause: the version was a constant, and the linker can only patch a variable. The build flag looked right and did nothing.
	- Fixed: it is a variable.

- ✅ A config file that replaced a built-in base left the base list wrong. (BxZNl-10)
	- Fixed: a built-in that is fully replaced drops out of the list and the index, and only names that still resolve are shown.

- ✅ A mistyped `--config` path was ignored instead of reported. (BxZNl-11)
	- Fixed: a config file named on the command line has to exist. The two paths nobody types stay optional.

- ✅ The check that a base alias is not a bare number was easy to slip past. (BxZNl-12)
	- Fixed: every alias is checked, not only the first, and against its normalized form.

- ✅ Comma-separated digits only worked in a single-token spec. (BxZNl-13)
	- Fixed: every token is split on commas, so `0,1 2 3` is four digits.

- ✅ An empty `pad:` in a config file could not switch padding off. (BxZNl-14)
	- Fixed: an empty value clears it. A separate field allows a pad that is accepted on input but never written.

- ✅ A reserved noncharacter in a spec silently became a space digit. (BxZNl-15)
	- Cause: those characters are used internally to hold escaped whitespace aside during the split.
	- Fixed: a spec containing one is refused up front.

#### Done - New features and enhancements

- ✅ Cut and pad a value on symbol boundaries, for callers with fixed-width fields.
	- Done: two new calls on a base. One takes a range of symbols out of a value, the other fits a value to a width. Fitting left-fills with the base's own zero symbol and keeps the rightmost symbols when the value is too long.
	- Done: both count symbols rather than bytes, so a multi-byte alphabet works. Both refuse a sign, a decimal marker, or a digit the base does not carry.
	- Done: three matching reactor exports, including a combined convert-then-fit, since that is the pairing a caller asked for.
	- Done: the empty-result rule is now part of the reactor contract. A zero return with no error means an empty result, not a failure.
	- Verified: unit tests over single-byte and multi-byte bases, the host exerciser drives all three exports, full suite passes.

- ✅ For base "keyboard", allow encoding tab, newline, CR, etc.
	- Done: they can be written by name, as `⊳LF`, `⊳TAB`, `⊳CR`, and so on for every control character. Input takes named and raw forms mixed, in one value, always. Output writes them only when `--escape-controls` asks, so nothing that already reads that base's output changes.
	- Done: the marker is a character outside the range such a base draws its digits from, which is what settles the escape question. It can never be a digit, so there is nothing to escape twice and no recursion to bottom out.
	- Done: a word form for the ones people actually mean (`⊳NEWLINE`, `⊳TAB`, `⊳RETURN`), the shell-awkward printables (`⊳DQUOTE`, `⊳SQUOTE`, `⊳BACKSLASH`), and a hex form for anything at all. Names read either case.
	- Done: `--show-symbols --escape-controls` prints the alphabet legibly, which it could not do before.
	- Note: an escape naming something the base does not carry fails exactly as the raw character would, as an unrecognized digit. Asking for escaped output in byte mode is refused rather than accepted and ignored.
	- Note: the one thing that can go wrong is a name running into the text after it, since one control's name is the start of another's. Output checks each name against what follows and writes the hex form where the name would not survive. A test covers every control against every character it could be followed by, and was confirmed to catch the mistake before the real code went in.

- ✅ A WebAssembly reactor module, so other languages can call this instead of running it. Design: `design_docs/20260801_wasm_reactor.md`.
	- Done: the one-shot half. Conversion, base lookup, the radix and padding symbol of a base, symbol counting, the memory calls, a stable numeric error code set, and readable error text. The contract is written down beside the module.
	- Done: streaming, as the push API: open, write, finish, free, plus an open-stream counter. Streams run the library's own constant-memory paths; codec pairs buffer and emit at finish, same as the command.
	- Done: a host-side exerciser drives the whole contract each test run, including leak checks that must end with nothing left allocated and a memory ceiling that catches a stream quietly buffering.
	- Done: frontend parity in the test suite. The same requests run through the command, the Go module directly, and the reactor, and the answers must agree byte for byte over every base, both directions, errors included. Piped payloads run through the command and the reactor streams the same way. The compat and interop suites stay on the command; parity carries what they establish over to the other two.
	- The `go.mod` floor stays at 1.21. Only the toolchain building this one target has to be 1.24 or newer.

- ✅ Library error text no longer names command-line flags.
	- Cause: messages like "see --list for all bases" came from the library, so a Go program or a browser page got advice about flags that do not exist there.
	- Fixed: the library states these conditions in neutral terms, and the command adds its own pointers on the way out. Four cases: an unknown base (the "did you mean" suggestions stay, since those help everywhere), a missing negative or decimal marker, a default marker that collides with a digit, and a retired marker token in a symbol spec. Each is a distinct error type, so any caller can recognize the condition and add advice in its own words.
	- Verified: the command's output is unchanged. Every affected error path was compared against the previous build character for character, including the wrapped forms, and the full test suite passes.
	- Note: this also sets up the planned WebAssembly reactor module, which wants to hand error text to a host program - that text now reads correctly outside a terminal.

- ✅ Speed-up and advanced conversion algorithms epic:
	- ✅ Say publicly which algorithms the number path uses, and what they are worth.
		- Cause: the three speed passes were recorded here in plain terms, but nothing outside the repo said what the method actually is. A claim of "fast" with no algorithm behind it is not worth much to anyone deciding whether to use this on a large value.
		- Done: the README speed section now splits into the streaming path and the number path, and the number path names its sources: Schonhage's divide and conquer radix conversion from Brent and Zimmermann, Karatsuba multiplication, Burnikel-Ziegler recursive division, and the classical sub-base packing from Knuth. Each gets a sentence on how it is used and what it is worth. Same citations added to the source and to the design notes.
		- Verified: measured fresh against a schoolbook implementation using the same arithmetic library on the same machine, from a thousand digits up to a million. Four times faster at the short end, three hundred and ten times at a million digits, where schoolbook takes a hundred and seven seconds and this takes a third of a second.
		- Verified: the exponent was fitted rather than assumed. Schoolbook measures 2.00, this measures 1.15 at the short end rising to 1.53 at the long end, which is the shape the method predicts.
		- Note: the underlying multiply and divide come from the standard library, which is stated plainly rather than implied to be ours.
	- ✅ Speed up converting long numbers between two bases that are not powers of two. Third and last planned pass.
		- Cause: even with the earlier batching, every batch still took a pass over the whole number, so the total effort grew with the square of the length. That is the method's own cost, not an implementation detail.
		- Fixed: a long number is now split in half, each half converted on its own, and the two results joined with one wide multiply or divide. The halves split again in turn, down to a size where the earlier batch loop takes over. The joining steps ride on the arithmetic library's fast large-number multiply, so the whole thing finally grows a little faster than the length itself rather than its square.
		- Verified: a 16,000 digit conversion went from 2.8 to about 1 millisecond, a 64,000 digit one from an extrapolated 45 down to 6.5. A 160,000 digit number now converts through the command in under a tenth of a second, most of which is startup. Short numbers are unchanged.
		- Verified: across all three passes together, that same 16,000 digit conversion started at 251 milliseconds and 882 megabytes of scratch memory. It now takes 1 millisecond and about a megabyte, roughly 250 times faster. Doubling the length used to quadruple the time; now it roughly doubles it.
		- Verified: compared against the previous build across about 1,300 conversions at every length near a split seam, plus fractions, negatives, and both precision modes. All identical. Also checked against the standard library's own independent conversion for every base it can express, at every seam length.
		- Note: the split seams are the one place this can go wrong - a short lower half must keep its leading zeros - and a mistake there still looks like a plausible number. New tests pin every seam, and they were confirmed to catch both seeded mistakes before the real code went in.
		- Note: delegating half the work to the standard library was considered, measured as no faster end to end, and declined - one algorithm everywhere beats two things to get right.
		- Note: the fuzzing length cap rose from 256 to 1,024 digits now that long values are cheap, so fuzzing reaches the new seams too.
	- ✅ Speed up converting long numbers between two bases that are not powers of two. Second of three planned passes.
		- Cause: the number was read in one digit at a time and written out one digit at a time. Each of those steps costs a pass over the whole number, however long it is, so a short digit gets the same expensive treatment as the entire value.
		- Fixed: digits are now handled a batch at a time, as many as fit in one of the machine's own numbers. That is nineteen digits at once for base ten, twelve for base thirty-six, five for base 2048. The batch is assembled with ordinary arithmetic, which is free next to a pass over a long number.
		- Verified: a 16,000 digit conversion went from 29 to 2.8 milliseconds, so about ten times faster again. A 40,000 digit one went from a quarter of a second to seven hundredths. Shorter numbers gain about five times.
		- Verified: results were compared against the previous build across about 1,200 conversions covering every length near a batch boundary, plus fractions, negatives, and both fixed and automatic precision. All identical.
		- Note: two new tests pin the batch boundaries, one for whole numbers and one for fractions. That is the only place this could go wrong, and a wrong answer there would still look like a plausible number.
		- Note: one more pass is planned, changing the method itself rather than its cost per step.
	- ✅ Speed up converting long numbers between two bases that are not powers of two. First of three planned passes.
		- Cause: each new digit of the answer was added to the front of a list. Everything already in the list has to shift along to make room, so the effort grows with the square of the answer's length. That was piled on top of the arithmetic, which is already the slow part for a long number.
		- Fixed: digits are now collected in the order the arithmetic hands them back, and the list is flipped around once at the end. Same answer, none of the shuffling. The list is also sized up front rather than being regrown as it fills.
		- Verified: a 16,000 digit conversion went from 251 to 29 milliseconds, and from 882 megabytes of scratch memory down to about one. Shorter numbers gain too, roughly four times faster at 1,000 digits.
		- Note: new benchmarks cover this path at three input lengths, because the cost curves upward rather than rising evenly, so one length would not show the shape. Run them with `go test -run x -bench Positional ./convertbase`.
		- Note: long numbers are still slower than they need to be. Two further passes are planned, one to cut the constant cost and one to change the method itself.

- ✅ Animated gif demo: run the motion at 50 frames per second, and make the scroll and the cursor buttery smooth.
	- Done: every moving frame is now 20 ms. That is the fastest a gif can run, since browsers clamp shorter delays up to a tenth of a second. Motion used to sit at 80 ms.
	- Done: the scroll holds one constant velocity. Output lines are fed in against the scroll rather than each one settling to a stop first, which used to cost a short frame at every line boundary and read as judder once the frame rate was high enough to see it.
	- Done: the cursor eases between cells instead of jumping, and never overruns the keystroke it belongs to, so fast digits keep their pace.
	- Done: scrolling is 10 percent faster.
	- Done: a step whose output is taller than the window starts on a cleared screen, so a long list scrolls through once instead of first chasing the previous step's output off the top. Nothing types a clear command.
	- Done: gifsicle takes a lossless pass at the end when it is installed, which is worth about a sixth of the file. Pixels and timing come out identical. A machine without it just gets a bigger gif.
	- Note: the file still grows, from about five to about nine megabytes, and nearly all of that is the base list scrolling by. Its scroll rate is the lever if the size matters more than reading along with it.

- ✅ Animated gif demo: Come up with better examples and reencode.

- ✅ Let other programs use this as a library, not just as a command. Design: `design_docs/20260731_linkable_library.md`.
	- Done: Go package split, so the conversion core can be imported instead of shelled out to. Module path fixed at the same time, since nothing could fetch it before.
	- Done: the library is Apache-2.0, the command stays GPL-2.0-or-later. GPL reaches through a static link into the caller, and Go links statically only, so the split is what makes the package importable at all. Apache was picked for attribution: its notice file is what carries the credit into someone else's product.
	- Done: the Go tree moved to `lib/`, and the package carries its own version starting at v0.1.0. Go welds a module's major version into its import path above v1, so sharing the command's number would have meant every major release of the tool broke callers over a change that never touched the package.
	- Done: WebAssembly, two builds. The browser module is Apache-2.0 like the library, since it compiles into someone else's page; the WASI build is the whole command and stays GPL.
	- Done: a demo page that runs the library in the browser, published from `web/`.
	- Note: the demo page link needs Pages switched on in the repository settings before it resolves.
	- Note: a C shared library is no longer the obvious next step. WebAssembly reaches the same languages with no permanent ABI, no cgo, and no per-platform build, so the C interface waits for someone who specifically needs in-process native speed.
	- Note: an unreadable config file used to be fatal even for the path nobody types, which is what surfaced first under WebAssembly. Only "not there" was forgiven, so a sandbox reporting a different error killed every run.

- ✅ Test the four big bases against the implementations that defined them, instead of against vectors copied down by hand.
	- Done: qntm's base2048, base32768 and base65536, and LLFourn's separate base2048, are kept verbatim from their published releases under `cicd/utility/interop/thirdparty`, with the version, download and hash of each recorded next to them.
	- Done: the harness runs randomized bytes through both sides and checks three things per base. Our encoding matches theirs, we read back what they wrote, and they read back what we wrote. Crossing the outputs is the point: two implementations can share a misreading of the tail rules and agree with each other.
	- Done: sample lengths count up from zero before turning random, since every disagreement these bases have ever had was about the final partial chunk.
	- Done: an edited or missing reference fails the run. A reference that has been changed is worse than none, because everything would still pass, against something nobody published. A missing toolchain only warns, since that means the checks did not run rather than that they failed.
	- Verified: all four agree in all three directions. 370 checks, up from 357.

- ✅ Make every `69emoji` digit a graphical emoji.
	- Cause: four of the sixty-nine were text-presentation by Unicode definition, so they drew as line art rather than colour. One of those was also carrying a presentation selector to force the issue, which made it the only multi-codepoint digit in the base.
	- Fixed: scissors became crossed fingers, the heavy black heart became revolving hearts, the curving arrow became a rocket, and the bed became a person in bed. Alphabet re-sorted into code point order.
	- Verified: checked against `emoji-data.txt` from unicode.org, so the call is the Unicode property and not how one font happens to draw it.

- ✅ Trim the README bases table so it stops overflowing on GitHub.
	- Done: dropped the Description and Specification columns, renamed Chars to Char count, added UTF-8 byte count next to it, and renamed Number representation to Output.
	- Done: the example number is now `-86434491232548995369.314`, dropping to the bare integer `86434491232548995369` for the nine alphabets that use every candidate character as a digit and so carry no negative or decimal marker.
	- Done: long output values wrap. Line count is picked from an estimated rendered width, counting a double-width character as two, so a CJK or emoji row ends up about as wide as a Latin one instead of twice as wide. Widest cell went from 101 to 28.
	- Done: the generator is `utility/gen-bases-table.py`, replacing the stale `gen-example-table.bash`, which still produced the old three-column table. It also emits the `bytes` row, which used to be added by hand.
	- Done: narrowed again, since the widest rows still ran off the page. Target width dropped from thirty to twenty, and a digit above the basic plane counts as double width now, which is what `10rods` and `20mayan` needed. Nothing has a rendered width over twenty.
	- Done: the table reads the shipped config, so `10emoji` is listed alongside the built-ins. A fresh install has it, so leaving it out was misleading. Pass `--config /dev/null` for built-ins only.
	- Done: `64emoji` shows the signed fractional form now that it carries the markers.

- ✅ Rationalize base names and aliases, per `design_docs/20260730_base_naming.md`.
	- Done: one scheme now - lowercase, radix first, at most four aliases in a fixed order, bare numbers only where unambiguous. Every v1/v1b name still resolves; dropped spellings error with a near-match suggestion.
	- Done: legacy maps in test.bash fixed (`code64` had gone stale) and moved to the new canonical names; README bases table rebuilt from the binary, now with a single First alias column; examples, changelog, and demo scenario updated.
	- Verified: 356/356 harness checks, including both legacy cross-check suites.

- ✅ Cover the added and renamed power-of-2 bases in the tests, and cross-check the compatibility bases against both older tools.
	- Cause: the test lists named bases by hand, so a base added or renamed after they were written was simply never tested. `64tt` and `256tt` were missing from the length sweeps, and the rename to `code64` had already broken the cross-checks against both older tools.
	- Fixed: the power-of-2 and raw base lists now come from `--list`, and the equivalence test reads them from the registry. Adding or renaming a base needs no test edit.
	- Fixed: the memory ceiling, which is the only check that catches a base quietly falling back to buffering, now covers every power-of-2 base instead of five of them.
	- Fixed: wrapped-input decoding is checked on every base that carries raw bytes, not seven of them.
	- Done: a base each older tool shares is checked against both, one only a single tool has is checked against that one, and every output base either tool offers must be mapped or listed as excused.
	- Done: a missing older script skips its suite and warns, and the summary repeats the warning so it can't read as a pass.
	- Verified: 389 checks pass, and both the coverage guard and the skip path were exercised on purpose.

- ✅ Hold the alias notes in `bases.go` to the alias lists, and settle the two older bases that have no counterpart here.
	- Note: `bases.go` marks each alias the older tools call, and says which tool needs it. Nothing read those notes, so a rename could drop one and only the older tools would notice.
	- Done: a test reads those notes and checks each named alias is still on the base it sits on, and still resolves. Eighteen of them.
	- Done: every alphabet either older tool offers was walked symbol by symbol against every base here, which confirmed all the cross-check pairings and turned up exactly two with no counterpart: v1's 38-symbol username and v1's hex-ordered base 64. Both are permanent, so they are recorded as excused and named in the passing line rather than reported as a problem every run.

- ✅ Pin the vendored SHCL binding to an upstream release and check it on every pipeline run.
	- Note: SHCL reached v1.0.0, so the question was whether to depend on it as a Go module instead of keeping the copy.
	- Done: kept the copy. It leaves the program at standard library plus its own source, and upstream declares a higher `go` version than this project needs.
	- Done: the pin lives in `cicd/vendor-pins.env`; the check compares the local file against that tag before anything is built.
	- Note: a copy that no longer matches its tag stops the pipeline, since lint skips vendored paths and a parser reading an alphabet slightly wrong still produces output that looks fine. A newer upstream release is only a notice.
	- Verified: match, edited copy, missing file, wrong tag, and no network all behave as intended.

- ✅ Switch the config engine from YAML to SHCL, create a user config on first run, and move `emoji10` into it as the worked example.
	- Note: SHCL comes as one drop-in source file per language, so its Go binding is copied verbatim into `lib/shcl/`. That leaves the program with no external dependencies at all, since YAML was the last one.
	- Note: a base is now a named block (`base: hex`) with an optional `aliases:` field, instead of a list entry whose first alias was the canonical name.
	- Note: SHCL distinguishes a missing field from an empty one, which is exactly the tri-state the markers already used, so an empty `negative:` still means "switched off on purpose".
	- Note: the default config is embedded in the binary and written on first run, so the shipped example and the file people edit cannot drift apart. `example.conf` is gone.
	- Note: an unknown field is now an error. A typo that silently dropped a marker would give a wrong alphabet, and no output would ever reveal it.
	- Verified: harness at 306 checks, including both list spellings, an alias, a disabled marker, a symbol carrying a space, two rejected typos, and the first-run creation itself.

- ✅ Base set overhaul: bases and aliases added, renamed, and removed, and the v1/v1b compatibility bases split out into their own group.
	- Note: `Base.Compat` marks them; `--list` skips them and the new `--list-compat` shows only them. Both listings stay contiguous because compatibility bases sort last, so `--by-index` still reaches every base.
	- Verified: every compatibility alphabet matches the bundled `convert-base-v1` and `convert-base-v1b` scripts symbol for symbol, and the harness now cross-checks against both binaries instead of just v1b.
	- Fixed: `69emoji` was one emoji short, with a stray presentation selector standing in as an invisible digit.
	- Note: three legacy bases are left uncovered on purpose. Two have no counterpart here, and the third differs only in case.

- ✅ Document the shell aliases that keep binary mode and number mode apart.
	- Done: added to the end of the README Usage section, right after the help pointer, so it reads as a follow-on to the examples.
	- Verified: both aliases do what the note says. `--binary` encodes and round-trips through base 64, `--number` converts positionally and silences the mode note.

- ✅ Stream binary encode and decode for the multi-byte bases, not just the single-character ones.
	- Cause: the tuned path is a byte-table design end to end, so it can only hold one-byte digits. Everything else buffered the whole input and the whole output.
	- Done: a second streaming path for digits that are one character but several bytes, covering the bases above 8 bits per digit as well. The tuned path is untouched.
	- Done: `512tt`, `1024tt`, and `2048tt` gained a tail character, which is what let them stream; their binary layout changed and none had shipped.
	- Verified: peak memory is flat near 20 MB for every base. Encoding 48 MB to `emoji64` went from 1.2 GB to 20 MB, decoding `128tt` from 753 MB to 21 MB and about three times faster.
	- Verified: 625 streamed-against-buffered comparisons, 121000 fuzz round-trips, harness at 252 checks including a peak-memory ceiling per base.
	- Done: closed the last gap with a `tail:` config field and `--from-tail`/`--to-tail` flags, so a base of your own above 8 bits can stream too. A 24 MB encode drops from 244 MB to 21 MB. Without a tail the length-prefixed layout still works, so nothing had to change.
	- Verified: round-trips at every awkward length on both layouts, the width and overlap guards reject a tail that could never be used, and the config and flag forms agree.

- ✅ User-defined alphabets:
	- Need flags to define negative, decimal, and pad - not all in one string.
	- Ditto for config definitions.
	- Done. Six flags: `--from-neg`/`--from-dec`/`--from-pad` and the `--to-` three. An empty value disables a marker, an omitted flag changes nothing.
	- Markers now work on named bases too, not just custom alphabets. `--from hex --from-neg '~'` reads `~ff` as -255.
	- A symbol spec is digits only. Config files keep their `negative:`, `decimal:` and `pad:` fields, and the in-string form is gone from both.
	- The retired `neg=`/`dec=`/`pad=` tokens are a hard error naming the replacement, so a stale spec can't quietly turn one into a digit and shift the alphabet.
	- Designed in `design_docs/20260725_neg_dec_pad_config_cli.md`.

- ✅ Design new bases (all just shorter versions of 1024tt, which starts with base 62h):
	- ✅ Blocks: ▁ ▂ ▃ ▄ ▅ ▆ ▇ █ ▒ ▓
	- ✅ 512tt
		0 1 2 3 4 5 6 7 8 9 A B C D E F G H I J K L M N O P Q R S T U V W X Y Z a b c d e f g h i j k l m n o p q r s t u v w x y z ¡ ¢ £ ¤ ¥ § © « ® ° ± µ · » ¿ Ø Þ ß æ ð ÷ ø þ ŋ ƅ Ɔ ƌ ƒ ƨ Ʊ ƶ ƹ ƾ ǂ ǝ ȸ ȹ ɀ Ʌ ɐ ɒ ɔ ɘ ə ɛ ɞ ɤ ɥ ɮ ɷ ɸ ɹ ʁ ʃ ʅ ʇ ʉ ʊ ʌ ʎ ʘ ʚ ʞ ʬ ʭ ͳ ͷ ͼ ͽ Δ Ω α δ ζ θ λ μ ξ π φ ψ ω ϑ ϕ ϖ ϝ ϟ Ϡ ϡ ϣ ϥ ϧ ϩ ϰ ϱ ϵ ϶ ϸ Ͻ Ͼ Ͽ ж л п я ѧ ѳ ҂ ҩ ԃ ԅ ԉ ԋ ԏ թ ժ ի կ ձ ճ մ ն չ պ վ ր ֏ ۲ ۳ ۴ ۶ ۸ ५ ६ ७ ८ ଌ ୧ ୫ ୬ ୯ ఠ వ ก ข ค ฅ ฆ ง จ ฉ ช ถ ท ธ ป ร ฤ ล ฦ ว ศ ษ ส ห อ ฮ ฯ ะ า ๑ ๓ ๖ ๙ ა ბ გ დ ე თ ი კ ლ ჟ რ ს ტ უ ფ ქ ღ ყ შ ჩ ც წ ჭ ჯ ჰ ჲ ჵ ჶ ჸ ჹ ჺ ዓ ዖ ዛ ዞ የ ዶ ገ ጌ ግ ጎ ጓ ጻ ጾ ፀ ህ ለ ላ ል ረ ሪ ሬ ር ስ ባ ቦ ኣ ኦ ካ ኮ ᚠ ᚢ ᚣ ᚦ ᚨ ᚬ ᚭ ᚮ ᚯ ᚳ ᚴ ᚸ ᚻ ᚼ ᚾ ᚿ ᛃ ᛄ ᛅ ᛆ ᛇ ᛉ ᛋ ᛎ ᛏ ᛓ ᛔ ᛗ ᛘ ᛚ ᛛ ᛜ ᛝ ᛟ ᛠ ᛡ ᛢ ᛣ ᛦ ᛨ ᛩ ᛪ ᛮ ᛯ ᛳ ᛶ ᛷ ᛸ ᥛ ᥝ ᥢ ᥰ ᥳ ᨑ ᲆ ᲇ ᲈ ᴈ ᴉ ᴎ ᴐ ᴒ ᴖ ᴗ ᴙ ᴚ ᴝ ᴟ ᴤ ᴧ ᴨ ᴫ ᵷ ẟ • ‣ ₢ ₣ ₤ € ₶ ₺ ℈ ℧ ℶ ℸ ⅃ ⅄ ⅋ ⅎ ↊ ↋ ← ↑ → ↓ ∂ ∃ ∆ ∇ ∋ ∩ ∻ ≈ ⊲ ⊳ ⋏ ⌂ ⌔ ⍢ ⍨ ⟂ ⟅ ⟠ ⦁ ⦂ ⦅ ⦛ ⦠ ⧎ ⧖ ぁ ぅ ぇ ぉ か こ さ す そ ち て と ひ ま め ゃ ゅ ょ り ゐ ゑ を ゕ ゖ ァ ゥ ォ カ キ ク ケ サ シ ス セ ソ タ チ ッ テ ヌ ネ ホ ャ ン ヵ ㄅ ㄆ ㄉ ㄊ ㄌ ㄓ ㄔ ㄘ ㄛ ㄝ ㄞ ㄠ ㄡ ㄤ ㅅ ㅈ ㅊ ㅍ ㅎ ㆄ ꓕ ꓘ ꓛ ꓞ ꓤ ꓥ ꓨ ꓩ ꓭ ꓱ ꓵ ꓶ 𐀀 𐀁 𐀂 𐀈 𐀍 𐀑 𐀒 𐀓 𐀔 𐀕 𐀖 𐀗 𐀘 𐀙 𐀚 𐀛 𐀣
			- After exhaustive excercise (basically following "how to design a new base").
	- ✅ 256tt
	- ✅ 128tt
	- ✅ 64tt
	- ✅ 32tt

- ✅ Automatic fractional precision.
	- Done: `--precision` defaults to `auto`, which sizes the output fraction to the input's own precision instead of always stretching to fifty digits. A short decimal input no longer grows an invented tail in another base.
	- Done: `--precision N` still forces a fixed count, for padded or lossless round-trip output.
	- Note: automatic round-trips are lossy by design, since each hop keeps only the digits the input justified.

- ✅ CI/CD improvements. The v1.1.0-beta7 release was cut by the new flow itself.
	- ✅ Minimal hosted CI: `.github/workflows/ci.yml` vets, tests, and builds on every push and PR to dev and main. The full local pipeline is unchanged.
	- ✅ Dev branch + release on main: `dev` is now the integration branch and `main` is release-only. Merging dev to main tags the version from `source/main.go` (if that tag doesn't exist yet) and publishes the release automatically; a merge without a version bump is a no-op. Flow documented in `design.md`.
	- ✅ goreleaser packaging: superseded 20260712. Replaced by self-contained `cicd/utility/package.bash` (tarballs/zips, `.deb`/`.rpm` via nfpm, Windows installers via makensis, checksums) run by both `make release` and the workflow; goreleaser and `.goreleaser.yaml` retired. See `design.md`.
	- ✅ Full release packaging + build split + main guard (20260712): packages every platform for both arches (adds freebsd, deb/rpm, Windows installers); split debug (test/profile) vs optimized (dogfood) native builds; main merge now hard-fails via `check-release.bash` unless the version was bumped and the Lifecycle badge matches.
	- ✅ Pinned tool versions + dependabot: pins live in `cicd/tool-versions.env` (the pipeline installs anything missing or drifted before stage 1); dependabot files grouped weekly update PRs against dev.
	- ✅ README badges: dynamic Go version, CI status, and latest release, replacing the static Go and Status badges.
- ✅ Some hosted or hook-based CI gate. (BxZNl-24)
	- Note: deferred at first. Nothing ran unless the pipeline was invoked by hand, and `make test` already covered the real logic locally.
	- Done: a hosted workflow now vets, tests, and builds on every push and pull request to the two long-lived branches. It is a safety net only; the full pipeline stays local.

- ✅ Docs accuracy sweep. (BxZNl-26)
	- Done: the README bases table was rebuilt from the program, matching rows by alphabet, so two swapped rows corrected themselves and every alias listed resolves.
	- Fixed: the serial number example named the wrong base, one example output row was stale, and one example used a base name that no longer existed.
	- Fixed: the byte-count table for UTF-16 and UTF-32 was wrong in the companion document, a config claim about disabling a marker was wrong, and one config field was undocumented.
	- Fixed: year typos in the changelog.

- ✅ Closed the blind spots in the test suite. (BxZNl-23)
	- Cause: several bases were only ever checked against themselves, so a round trip could be wrong in both directions and still pass.
	- Done: known values pinned for those bases, plus more fractional cases, config file loading, alphabet parser edge cases, and a symbol count pin.
	- Done: minimum counts on the base listings, so a listing that quietly shrinks fails.
	- Done: a missing older reference script now reports as skipped instead of passing quietly.

- ✅ Two binary paths kept separate but pinned, rather than merged. (BxZNl-25)
	- Note: streaming and buffered conversion are different jobs with different costs, and the fast streaming path was hard won. Merging them was judged the wrong move.
	- Done: the two are held together by an equivalence test instead, which fails if they ever disagree.

- ✅ Real unit tests, so `make test` covers the conversion logic instead of running only benchmarks. (BxZNl-22)
	- Done: fixed values for signs, fractions, leading zeros and rounding, the codec and big-base reference values, padding, the asymmetric Crockford rule, custom alphabets and markers, and the cases that should be refused.
	- Done: the streaming-against-buffered equivalence test, which is the one that matters most. It compares both paths byte for byte across every power-of-two base at many lengths.

- ✅ Padding settled: it depends on the mode, not on the base. (BxZNl-20)
	- Done: number output is never padded. Binary-to-text output pads every RFC 4648 variant to the group boundary, which is what the strict standard decoders expect.
	- Done: decoding stays lenient, and takes padded or unpadded input either way.

- ✅ `--list` now has a leading INDEX column (the value `--by-index` takes), and `--by-index` outside a query prints a stderr note that it is ignored. (BxZNl-19) Help wording for `--by-index` now points at the INDEX column instead of a fragile "above".

- ✅ `--help` and `--examples` now write to stdout when explicitly requested, so `--help | less` works. (BxZNl-18) The no-args error path keeps help on stderr (exit 2, clean stdout). Threaded a writer through printHelp/printExamples/printCopyright.

- ✅ Conflicting base selectors now emit a stderr note instead of silently picking one. (BxZNl-17) `--from-symbols` over `--from`, `--to-symbols` over any output name, and `--to` over a positional OUTBASE. A `--to` and positional that name the same base stay quiet. Behavior unchanged (note only), matching the BxZNl-1 approach.

- ✅ Friendlier messages for the four common stumbles. (BxZNl-16) Flags after the NUMBER now say flags come first; a bare `-123` points at the `--` separator; an unknown flag points at `--help`; an unknown base points at `--list` and suggests near matches (prefix or small edit distance, closest tier only). Flag parsing moved to ContinueOnError so these can be caught.

- ✅ Crockford base 32 now follows its own asymmetric rule. (BxZNl-21)
	- Done: on input it reads O as zero and I or L as one, in either case. Output stays strict.
	- Done: this needed a general input-only alias mechanism on a base, which any base can now use.

- ✅ Allow any base to be prefaced with "base", "base-", or "base_", and still work. (github #8)

- ✅ `--show-symbols` should list with no delimiters. (Currently lists with newline in between each.) #1n4xq9d
	- Now concatenated with a single trailing newline. Added `--show-symbols-0` (NUL-separated) so scripts can still split multi-char symbols; fuzz harness uses it.

- ✅ Added a `--upper` flag, the opposite of `--lower`. Uppercases text output, and like `--lower` errors on a mixed-case output base (where changing case would collide two distinct digits). The two flags reject each other.

- ✅ Byte-mode re-encoding between text bases. Two power-of-2 text bases (e.g. hex and base-64) used to convert only as a positional number, which silently drops leading zeros and is not a byte re-encoding.
	- Now `--binary` (`--bin`, `-b`) re-encodes them as byte data the way `basenc` does, by routing through the raw-byte base; piped input streams.
	- `--number` (`--num`, `-N`) asserts the numeric reading.
	- With neither flag, a power-of-2 text-to-text conversion prints a note on stderr so the ambiguity is no longer silent.

- ✅ Renamed the 256-value raw-byte base to `bytes` and dropped its `binary`/`bin`/`raw` aliases, so the base name no longer collides with the new `--binary` mode flag (and "binary" no longer misleadingly names the byte base rather than base-2).

- ✅ Renamed the `--raw` output flag to `--no-newline` (`-n`), matching `echo -n`; its old name was unclear and overlapped the raw-byte base.

- ✅ Raw binary conversion now covers, besides the powers of two, the defined streaming binary-to-text codecs: base45, Ascii85, Z85, and base91, each implemented per its official spec.
	- Any other non-2^N base has no byte-exact mapping and is refused in binary mode.
	- `--list` shows which bases qualify (RAW column). (An earlier attempt to make every base work via whole-value base-x was reverted in favor of this, since a positional whole-value encoding isn't what a streaming codec means.)

- ✅ Screenshots retired. The README no longer shows them and the CICD stage is off by default; the generator is kept so they can be made again if wanted. Dropped the orphaned image files.

- ✅ Rigorous CICD testing. Raw round-trips now cover every base (not just powers of two) at lengths that force padding, with fixed base-x vectors pinning the leading-zero convention. Added a resource profile (peak memory and wall time) and a base-x timing guard, both skipped by `--quick`.

- ✅ Create a new base that covers all possible printable keyboard characters in a plain text document. (Including programming code, regular human writing, email addresses, newline, return, tab, etc.)
	- Without worrying about higher unicode alternatives (e.g. curly-quotes, mdash, etc.) - those would have to go through some separate conversion preprocessing in order to work with this base. I believe this should also covers Rich-Text format (which I believe has no special characters), MD, HTML, XML, JSON, embedded base64, etc., as-is.

- ✅ Create a base64 that's all emojis
	- Only emojis noted/suggested by unicode to print graphically.
	- Symbols in LANG=C order.
	- Use generic yellow emojis for skintone-based ones, not skin-tone variants.
	- Skip emojis that look too similar; use only the first one.

- ✅ Improve the performance of streaming binary-to-text conversion and vice-versa, to better approach existing linux utilities. Go should be able to get close.

- ✅ An optional padding scheme for custom bases (not necessarily `===`). The published big bases and the RFC base32/base64 bases already pad correctly; this is about letting user-defined bases opt into padding too.

- ✅ Update comments in code, help output, readme.md, and design.md to properly use "radix" and/or "base" in context, etc. But not the actual program interface, don't change that.

- ✅ Base64 (RFC 4648 s4) and base32 (RFC 4648 s6) binary output is now padded with `=` to the standard group boundary, matching the RFC test vectors. The URL and hex variants stay unpadded, and decoding accepts input with or without padding.

- ✅ Binary conversions to the big published bases (both base 2048's, 32768, 65536) round-trip at any input length and match the reference encoders byte-for-byte, using each one's own secondary alphabet for the final partial chunk. Odd-length tails no longer come back a byte long. Fixed vectors from the reference implementations guard the interop.

- ✅ Bases with '-' in the symbol set now use '~' as the negative marker instead of the en-dash. '~' was free in all four affected bases (45, 64u, 64h, 69prsh).

- ✅ Help: clarified the text for the index-related flags (`--get-index-count`, `--get-base-name`, `--show-symbols`, `--by-index`).

- ✅ `--list`: the NAME is no longer repeated in the ALIASES column.

### Deferred

### Canceled

- 🚫 Backwards compatible base '128v1compat' may have a subtly incorrect alphabet definition. (github #1)
	- Cause: the v1 base-128 definition is a "word-safe" version, which base 256 and 288 are not. Base 128 should have been a subset of 256. When writing v2, an incorrect assumption was made about the base-128 structure instead of copying v1 verbatim. Because 128 is a power of two, the difference could be as small as a single character in some binary encodings.
	- Verified: compared v2 against the bundled v1b for all 128 values. `128v1compat` and `128jc1` are byte-for-byte identical to v1b, and the v1 cross-check passes.
	- Note: cannot confirm any discrepancy without the original v1 (not v1b) alphabet, and changing it now would break the verified v1b compatibility.
