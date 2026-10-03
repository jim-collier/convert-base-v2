//	Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
//	Licensed under The MIT License (MIT). Full text at:
//		https://mit-license.org/
//	SPDX-License-Identifier: MIT

// Joins thin darwin Mach-O executables into one universal (fat) file, the
// way `lipo -create` does, for build hosts that have no lipo. Usage:
//
//	macho-fat -o OUT THIN...
//
// Slices go in unchanged, so each keeps its own code signature. The result is
// read back with debug/macho and every slice compared to its input before the
// file is written.
package main

import (
	"bytes"
	"debug/macho"
	"encoding/binary"
	"errors"
	"flag"
	"fmt"
	"os"
	"sort"
)

const fatMagic = 0xcafebabe

type slice struct {
	cpu    macho.Cpu
	subCpu uint32
	align  uint32 // log2
	offset uint32
	data   []byte
}

// Page size of the target, as log2. Same values lipo and llvm-lipo use.
func alignFor(cpu macho.Cpu) (uint32, error) {
	switch cpu {
	case macho.CpuAmd64:
		return 12, nil
	case macho.CpuArm64:
		return 14, nil
	}
	return 0, fmt.Errorf("unsupported cpu %v", cpu)
}

func alignUp(n, align uint64) uint64 { return (n + align - 1) &^ (align - 1) }

func makeFat(thins [][]byte) ([]byte, error) {
	if len(thins) < 2 {
		return nil, errors.New("need at least two thin files")
	}
	slices := make([]slice, 0, len(thins))
	seen := map[macho.Cpu]bool{}
	for i, data := range thins {
		f, err := macho.NewFile(bytes.NewReader(data))
		if err != nil {
			return nil, fmt.Errorf("input %d: %w", i+1, err)
		}
		if seen[f.Cpu] {
			return nil, fmt.Errorf("input %d: cpu %v given twice", i+1, f.Cpu)
		}
		seen[f.Cpu] = true
		align, err := alignFor(f.Cpu)
		if err != nil {
			return nil, fmt.Errorf("input %d: %w", i+1, err)
		}
		slices = append(slices, slice{cpu: f.Cpu, subCpu: f.SubCpu, align: align, data: data})
	}
	// Smaller alignment first wastes the least padding, and matches lipo's order.
	sort.SliceStable(slices, func(a, b int) bool { return slices[a].align < slices[b].align })

	end := uint64(8 + 20*len(slices))
	for i := range slices {
		off := alignUp(end, 1<<slices[i].align)
		end = off + uint64(len(slices[i].data))
		if end > 1<<32-1 {
			return nil, errors.New("too big for a 32-bit fat header")
		}
		slices[i].offset = uint32(off)
	}

	out := make([]byte, end)
	be := binary.BigEndian
	be.PutUint32(out[0:], fatMagic)
	be.PutUint32(out[4:], uint32(len(slices)))
	for i, s := range slices {
		h := out[8+20*i:]
		be.PutUint32(h[0:], uint32(s.cpu))
		be.PutUint32(h[4:], s.subCpu)
		be.PutUint32(h[8:], s.offset)
		be.PutUint32(h[12:], uint32(len(s.data)))
		be.PutUint32(h[16:], s.align)
		copy(out[s.offset:], s.data)
	}
	return out, nil
}

// Reads the result back with an independent parser.
func verify(fat []byte, thins [][]byte) error {
	ff, err := macho.NewFatFile(bytes.NewReader(fat))
	if err != nil {
		return err
	}
	if len(ff.Arches) != len(thins) {
		return fmt.Errorf("%d slices, want %d", len(ff.Arches), len(thins))
	}
	for _, arch := range ff.Arches {
		if arch.Offset%(1<<arch.Align) != 0 {
			return fmt.Errorf("%v slice at %#x is not aligned to 2^%d", arch.Cpu, arch.Offset, arch.Align)
		}
		got := fat[arch.Offset : arch.Offset+arch.Size]
		found := false
		for _, thin := range thins {
			if bytes.Equal(got, thin) {
				found = true
				break
			}
		}
		if !found {
			return fmt.Errorf("%v slice matches no input", arch.Cpu)
		}
	}
	return nil
}

func main() {
	outPath := flag.String("o", "", "output file")
	flag.Parse()
	if *outPath == "" || flag.NArg() < 2 {
		fmt.Fprintln(os.Stderr, "usage: macho-fat -o OUT THIN THIN...")
		os.Exit(2)
	}
	thins := make([][]byte, 0, flag.NArg())
	for _, path := range flag.Args() {
		data, err := os.ReadFile(path)
		if err != nil {
			fatal("%v", err)
		}
		thins = append(thins, data)
	}
	fat, err := makeFat(thins)
	if err != nil {
		fatal("%v", err)
	}
	if err := verify(fat, thins); err != nil {
		fatal("self-check: %v", err)
	}
	if err := os.WriteFile(*outPath, fat, 0o755); err != nil {
		fatal("%v", err)
	}
}

func fatal(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "macho-fat: "+format+"\n", args...)
	os.Exit(1)
}
