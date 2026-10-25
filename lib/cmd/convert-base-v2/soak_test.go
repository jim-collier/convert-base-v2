//	Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
//	Licensed under the GNU General Public License v2.0 or later. Full text at:
//		https://spdx.org/licenses/GPL-2.0-or-later.html
//	SPDX-License-Identifier: GPL-2.0-or-later

package main

import (
	"bytes"
	"encoding/hex"
	"fmt"
	"math/rand"
	"os"
	"path/filepath"
	"runtime"
	"runtime/pprof"
	"strings"
	"testing"
	"time"
)

// The soak test runs the command's main jobs over and over in one process, and
// the heap and goroutine count taken at round N must not have grown by round
// 2N. Rounds before N are the warm-up, which builds lazy tables and caches.
// It runs only when CICD_SOAK_OUT names a dir for its two heap profiles, as
// cicd.bash's leak checks do. `go tool pprof -base` on the pair shows what grew.
const (
	soakRounds = 100
	soakSlack  = 64 << 10 // heap noise allowed between the samples, in bytes
	soakGrowth = 0.05     // plus this share of the heap at round N
)

type soakSample struct {
	heapInuse  uint64
	goroutines int
}

// soakCheck compares the samples at round N and 2N.
func soakCheck(n, n2 soakSample) error {
	limit := n.heapInuse + soakSlack + uint64(float64(n.heapInuse)*soakGrowth)
	if n2.heapInuse > limit {
		return fmt.Errorf("heap in use grew from %d bytes at round N to %d at 2N, past the limit of %d", n.heapInuse, n2.heapInuse, limit)
	}
	if n2.goroutines > n.goroutines {
		return fmt.Errorf("%d goroutines at round N, %d at 2N", n.goroutines, n2.goroutines)
	}
	return nil
}

// Test ID: de54t
func TestSoakCheck(t *testing.T) {
	base := soakSample{heapInuse: 4 << 20, goroutines: 3}
	cases := []struct {
		name string
		n2   soakSample
		ok   bool
	}{
		{"same", base, true},
		{"shrank", soakSample{heapInuse: 3 << 20, goroutines: 2}, true},
		{"noise", soakSample{heapInuse: base.heapInuse + soakSlack, goroutines: 3}, true},
		{"heap grew", soakSample{heapInuse: 6 << 20, goroutines: 3}, false},
		{"one more goroutine", soakSample{heapInuse: base.heapInuse, goroutines: 4}, false},
	}
	for _, c := range cases {
		if err := soakCheck(base, c.n2); (err == nil) != c.ok {
			t.Errorf("%s: got %v", c.name, err)
		}
	}
}

// soakRig runs the command in this process, with its argv and standard
// streams swapped for files.
type soakRig struct {
	t   *testing.T
	dir string
}

func (r *soakRig) file(name string, data []byte) string {
	r.t.Helper()
	p := filepath.Join(r.dir, name)
	if err := os.WriteFile(p, data, 0o600); err != nil {
		r.t.Fatal(err)
	}
	return p
}

// run is one command line, reading stdinPath. It answers what went to stdout.
func (r *soakRig) run(stdinPath string, args ...string) []byte {
	r.t.Helper()
	in, err := os.Open(stdinPath)
	if err != nil {
		r.t.Fatal(err)
	}
	outPath, errPath := filepath.Join(r.dir, "stdout"), filepath.Join(r.dir, "stderr")
	out, err := os.Create(outPath)
	if err != nil {
		r.t.Fatal(err)
	}
	errOut, err := os.Create(errPath)
	if err != nil {
		r.t.Fatal(err)
	}

	savedArgs, savedIn, savedOut, savedErr := os.Args, os.Stdin, os.Stdout, os.Stderr
	os.Args = append([]string{"convert-base-v2"}, args...)
	os.Stdin, os.Stdout, os.Stderr = in, out, errOut
	runErr := run()
	os.Args, os.Stdin, os.Stdout, os.Stderr = savedArgs, savedIn, savedOut, savedErr

	for _, f := range []*os.File{in, out, errOut} {
		if err := f.Close(); err != nil {
			r.t.Fatal(err)
		}
	}
	if runErr != nil {
		msg, _ := os.ReadFile(errPath)
		r.t.Fatalf("%q: %v\n%s", args, runErr, msg)
	}
	got, err := os.ReadFile(outPath)
	if err != nil {
		r.t.Fatal(err)
	}
	return got
}

// roundTrip encodes raw into base and back, streamed from stdin.
func (r *soakRig) roundTrip(rawPath string, raw []byte, base string) {
	r.t.Helper()
	enc := r.file("enc", r.run(rawPath, "--from", "bytes", "--to", base))
	if got := r.run(enc, "--from", base, "--to", "bytes"); !bytes.Equal(got, raw) {
		r.t.Fatalf("bytes -> %s -> bytes changed the data (%d bytes in, %d out)", base, len(raw), len(got))
	}
}

func (r *soakRig) round(rawPath string, raw []byte, hexPath, hexText, number string) {
	r.t.Helper()
	got := strings.TrimSpace(string(r.run(os.DevNull, "--from", "10", "--to", "36", number)))
	if back := strings.TrimSpace(string(r.run(os.DevNull, "--from", "36", "--to", "10", got))); back != number {
		r.t.Fatalf("10 -> 36 -> 10 changed the number")
	}
	r.run(os.DevNull, "--from", "10", "--to", "16", "--precision", "12", "3.14159")
	// 10emoji comes from the default user config, so the config parser runs too.
	r.run(os.DevNull, "--from", "10", "--to", "10emoji", "8675309")

	for _, base := range []string{"64", "2048qntm", "ascii85", "z85", "base45"} {
		r.roundTrip(rawPath, raw, base)
	}
	// --binary between two text bases goes through the library's pipe goroutine.
	b32 := r.file("b32", r.run(hexPath, "--binary", "--from", "16", "--to", "32"))
	if back := strings.TrimSpace(string(r.run(b32, "--binary", "--from", "32", "--to", "16"))); !strings.EqualFold(back, hexText) {
		r.t.Fatalf("16 -> 32 -> 16 under --binary changed the data")
	}
	if up := strings.TrimSpace(string(r.run(rawPath, "--upper", "--from", "bytes", "--to", "16"))); up != strings.ToUpper(hexText) {
		r.t.Fatalf("--upper stream differs from the hex in upper case")
	}
	if list := r.run(os.DevNull, "--list"); len(list) == 0 {
		r.t.Fatalf("--list printed nothing")
	}
}

func soakTake(t *testing.T, outDir, name string) soakSample {
	t.Helper()
	runtime.GC()
	runtime.GC() // one pass can leave garbage that finalizers freed
	var ms runtime.MemStats
	runtime.ReadMemStats(&ms)
	s := soakSample{heapInuse: ms.HeapInuse, goroutines: runtime.NumGoroutine()}
	f, err := os.Create(filepath.Join(outDir, name))
	if err != nil {
		t.Fatal(err)
	}
	if err := pprof.Lookup("heap").WriteTo(f, 0); err != nil {
		t.Fatal(err)
	}
	if err := f.Close(); err != nil {
		t.Fatal(err)
	}
	return s
}

// Test ID: de54s
func TestSoak(t *testing.T) {
	outDir := os.Getenv("CICD_SOAK_OUT")
	if outDir == "" {
		t.Skip("set CICD_SOAK_OUT to a dir for the heap profiles; cicd.bash does in its leak checks")
	}
	if err := os.MkdirAll(outDir, 0o755); err != nil {
		t.Fatal(err)
	}
	dir := t.TempDir()
	t.Setenv("XDG_CONFIG_HOME", filepath.Join(dir, "xdg"))
	r := &soakRig{t: t, dir: dir}

	rng := rand.New(rand.NewSource(1))
	raw := make([]byte, 16<<10) // a multiple of 4, for z85
	rng.Read(raw)
	hexText := hex.EncodeToString(raw)
	digits := make([]byte, 400)
	for i := range digits {
		digits[i] = byte('0' + rng.Intn(10))
	}
	digits[0] = '7'
	rawPath, hexPath := r.file("raw", raw), r.file("hex", []byte(hexText))

	stamp := time.Now().Format("20060102-150405")
	var atN soakSample
	start := time.Now()
	for i := 1; i <= 2*soakRounds; i++ {
		r.round(rawPath, raw, hexPath, hexText, string(digits))
		switch i {
		case soakRounds:
			atN = soakTake(t, outDir, "heap-n_"+stamp+".pprof")
		case 2 * soakRounds:
			at2N := soakTake(t, outDir, "heap-2n_"+stamp+".pprof")
			t.Logf("%d rounds in %v. Heap in use %d -> %d bytes, goroutines %d -> %d", 2*soakRounds, time.Since(start).Round(time.Millisecond), atN.heapInuse, at2N.heapInuse, atN.goroutines, at2N.goroutines)
			if err := soakCheck(atN, at2N); err != nil {
				t.Errorf("%v. The heap profiles are in %s", err, outDir)
			}
		}
	}
}
