//	Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
//	Licensed under The MIT License (MIT). Full text at:
//		https://mit-license.org/
//	SPDX-License-Identifier: MIT

package main

import (
	"bytes"
	"debug/macho"
	"encoding/binary"
	"os"
	"os/exec"
	"path/filepath"
	"testing"
)

const lcCodeSignature = 0x1d

// A 64-bit Mach-O header with no load commands, padded with a marker byte.
func thinStub(cpu macho.Cpu, size int, fill byte) []byte {
	b := bytes.Repeat([]byte{fill}, size)
	le := binary.LittleEndian
	le.PutUint32(b[0:], macho.Magic64)
	le.PutUint32(b[4:], uint32(cpu))
	le.PutUint32(b[8:], 0)
	le.PutUint32(b[12:], uint32(macho.TypeExec))
	le.PutUint32(b[16:], 0) // ncmds
	le.PutUint32(b[20:], 0) // sizeofcmds
	le.PutUint32(b[24:], 0)
	le.PutUint32(b[28:], 0)
	return b
}

type fatEntry struct{ cpu, subCpu, offset, size, align uint32 }

// Parses the header by hand, so the layout is not only checked by debug/macho.
func readHeader(t *testing.T, fat []byte) []fatEntry {
	t.Helper()
	be := binary.BigEndian
	if got := be.Uint32(fat[0:]); got != fatMagic {
		t.Fatalf("magic %#x", got)
	}
	n := int(be.Uint32(fat[4:]))
	entries := make([]fatEntry, n)
	for i := range entries {
		h := fat[8+20*i:]
		entries[i] = fatEntry{be.Uint32(h[0:]), be.Uint32(h[4:]), be.Uint32(h[8:]), be.Uint32(h[12:]), be.Uint32(h[16:])}
	}
	return entries
}

// Test ID: ErftBA9
func TestLayout(t *testing.T) {
	x86 := thinStub(macho.CpuAmd64, 5000, 0xaa)
	arm := thinStub(macho.CpuArm64, 7000, 0xbb)
	// arm64 given first, to show the order is by alignment and not by argument.
	fat, err := makeFat([][]byte{arm, x86})
	if err != nil {
		t.Fatal(err)
	}
	want := []fatEntry{
		{uint32(macho.CpuAmd64), 0, 0x1000, 5000, 12},
		{uint32(macho.CpuArm64), 0, 0x4000, 7000, 14},
	}
	got := readHeader(t, fat)
	if len(got) != len(want) {
		t.Fatalf("got %d entries, want %d", len(got), len(want))
	}
	for i := range want {
		if got[i] != want[i] {
			t.Errorf("entry %d: got %+v, want %+v", i, got[i], want[i])
		}
	}
	if len(fat) != 0x4000+7000 {
		t.Errorf("file size %d", len(fat))
	}
	if !bytes.Equal(fat[0x1000:0x1000+5000], x86) || !bytes.Equal(fat[0x4000:0x4000+7000], arm) {
		t.Error("slice bytes differ from input")
	}
	if !bytes.Equal(fat[48:0x1000], make([]byte, 0x1000-48)) {
		t.Error("padding is not zero")
	}
	if err := verify(fat, [][]byte{x86, arm}); err != nil {
		t.Error(err)
	}
}

// A first slice big enough that the second needs real padding to reach 2^14.
// Test ID: ErftBAA
func TestSecondSliceAlignment(t *testing.T) {
	fat, err := makeFat([][]byte{thinStub(macho.CpuAmd64, 0x5001, 1), thinStub(macho.CpuArm64, 64, 2)})
	if err != nil {
		t.Fatal(err)
	}
	if off := readHeader(t, fat)[1].offset; off != 0x8000 {
		t.Errorf("arm64 offset %#x, want 0x8000", off)
	}
}

// Test ID: ErftBAB
func TestRejects(t *testing.T) {
	x86 := thinStub(macho.CpuAmd64, 64, 0)
	cases := map[string][][]byte{
		"one input":   {x86},
		"same cpu":    {x86, thinStub(macho.CpuAmd64, 64, 1)},
		"other cpu":   {x86, thinStub(macho.CpuPpc64, 64, 0)},
		"not mach-o":  {x86, []byte("#!/bin/sh\necho hi\n")},
		"already fat": {x86, mustFat(t)},
	}
	for name, in := range cases {
		if _, err := makeFat(in); err == nil {
			t.Errorf("%s: no error", name)
		}
	}
}

// Test ID: ErftBAC
func TestVerifyCatchesChangedSlice(t *testing.T) {
	x86, arm := thinStub(macho.CpuAmd64, 64, 1), thinStub(macho.CpuArm64, 64, 2)
	fat := mustFat(t)
	fat[readHeader(t, fat)[1].offset+40] ^= 0xff
	if err := verify(fat, [][]byte{x86, arm}); err == nil {
		t.Error("changed slice not caught")
	}
}

func mustFat(t *testing.T) []byte {
	t.Helper()
	fat, err := makeFat([][]byte{thinStub(macho.CpuAmd64, 64, 1), thinStub(macho.CpuArm64, 64, 2)})
	if err != nil {
		t.Fatal(err)
	}
	return fat
}

// The real command, cross-built for both Macs. Go signs darwin/arm64 builds
// itself, and that signature has to come through the join intact.
// Test ID: ErftBAD
func TestRealCommand(t *testing.T) {
	if testing.Short() {
		t.Skip("cross-builds the command")
	}
	dir := t.TempDir()
	var thins [][]byte
	for _, arch := range []string{"amd64", "arm64"} {
		bin := filepath.Join(dir, arch)
		cmd := exec.Command("go", "build", "-trimpath", "-ldflags", "-s -w", "-o", bin, "./cmd/convert-base-v2")
		cmd.Dir = filepath.Join("..", "..", "..", "lib")
		cmd.Env = append(os.Environ(), "CGO_ENABLED=0", "GOOS=darwin", "GOARCH="+arch)
		if out, err := cmd.CombinedOutput(); err != nil {
			t.Fatalf("build %s: %v\n%s", arch, err, out)
		}
		data, err := os.ReadFile(bin)
		if err != nil {
			t.Fatal(err)
		}
		thins = append(thins, data)
	}
	fat, err := makeFat(thins)
	if err != nil {
		t.Fatal(err)
	}
	if err := verify(fat, thins); err != nil {
		t.Fatal(err)
	}
	ff, err := macho.NewFatFile(bytes.NewReader(fat))
	if err != nil {
		t.Fatal(err)
	}
	for _, arch := range ff.Arches {
		if arch.Type != macho.TypeExec {
			t.Errorf("%v slice type %v", arch.Cpu, arch.Type)
		}
		if arch.Cpu != macho.CpuArm64 {
			continue
		}
		signed := false
		for _, load := range arch.Loads {
			if raw := load.Raw(); len(raw) >= 4 && arch.ByteOrder.Uint32(raw) == lcCodeSignature {
				signed = true
			}
		}
		if !signed {
			t.Error("arm64 slice has no code signature")
		}
	}
}
