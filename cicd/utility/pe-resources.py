#!/usr/bin/env python3

##	Purpose: What a Windows .exe has in its resource section, as key=value lines:
##		the icon group count, the icon sizes, the fixed version numbers and flags,
##		and every string in the version info. Standard library only, so the
##		harness needs nothing installed to check the packaged exes.
##	Usage:
##		pe-resources.py FILE.exe
##		  Exit 1 when the file isn't a PE or its resources can't be read.
##	History: At bottom of script.

##	Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT


import struct
import sys

RT_ICON = 3
RT_GROUP_ICON = 14
RT_VERSION = 16


def u16(buf, off):
	return struct.unpack_from("<H", buf, off)[0]


def u32(buf, off):
	return struct.unpack_from("<I", buf, off)[0]


def rsrc_section(pe):
	if pe[:2] != b"MZ":
		raise ValueError("no MZ header")
	nt = u32(pe, 0x3C)
	if pe[nt : nt + 4] != b"PE\0\0":
		raise ValueError("no PE signature")
	coff = nt + 4
	sections = u16(pe, coff + 2)
	opt_size = u16(pe, coff + 16)
	opt = coff + 20
	magic = u16(pe, opt)
	## The data directories start later in PE32+ (64-bit) than in PE32.
	dirs = opt + (112 if magic == 0x20B else 96)
	rsrc_rva = u32(pe, dirs + 2 * 8)
	if rsrc_rva == 0:
		return None, None
	table = opt + opt_size
	for i in range(sections):
		sec = table + i * 40
		vsize, vaddr, rawsize, rawptr = struct.unpack_from("<IIII", pe, sec + 8)
		if vaddr <= rsrc_rva < vaddr + max(vsize, rawsize):
			return pe[rawptr : rawptr + rawsize], vaddr
	raise ValueError("resource directory is in no section")


## Leaves as (type, name, lang, bytes). Named entries are kept by their offset;
## nothing checked here uses them.
def resources(sec, base_rva):
	found = []

	def walk(off, path):
		named, ids = u16(sec, off + 12), u16(sec, off + 14)
		for i in range(named + ids):
			ent = off + 16 + i * 8
			name, target = u32(sec, ent), u32(sec, ent + 4)
			key = path + [name if name < 0x80000000 else ("named", name)]
			if target & 0x80000000:
				walk(target & 0x7FFFFFFF, key)
			else:
				rva, size = u32(sec, target), u32(sec, target + 4)
				start = rva - base_rva
				found.append((*key, sec[start : start + size]))

	walk(0, [])
	return found


## VS_VERSIONINFO is a tree of blocks: length, value length, type, a UTF-16 key,
## a value, then child blocks, each aligned to 4 bytes.
def version_blocks(buf, off, end):
	while off + 6 <= end:
		length, val_len, kind = struct.unpack_from("<HHH", buf, off)
		if length == 0:
			break
		block_end = off + length
		key_end = off + 6
		while buf[key_end : key_end + 2] != b"\0\0":
			key_end += 2
		key = buf[off + 6 : key_end].decode("utf-16-le")
		val_off = (key_end + 2 + 3) & ~3
		val_bytes = val_len * 2 if kind == 1 else val_len
		yield (
			key,
			kind,
			buf[val_off : val_off + val_bytes],
			(val_off + val_bytes + 3) & ~3,
			block_end,
		)
		off = (block_end + 3) & ~3


def version_info(blob):
	out = {}
	for key, _, value, child, end in version_blocks(blob, 0, len(blob)):
		if key != "VS_VERSION_INFO" or len(value) < 52:
			continue
		sig, _, fms, fls, pms, pls, _, flags = struct.unpack_from("<8I", value)
		if sig != 0xFEEF04BD:
			raise ValueError("bad VS_FIXEDFILEINFO signature")
		out["fixed_file_version"] = (
			f"{fms >> 16}.{fms & 0xFFFF}.{fls >> 16}.{fls & 0xFFFF}"
		)
		out["fixed_product_version"] = (
			f"{pms >> 16}.{pms & 0xFFFF}.{pls >> 16}.{pls & 0xFFFF}"
		)
		out["fixed_flags"] = f"0x{flags:x}"
		for skey, _, _, schild, send in version_blocks(blob, child, end):
			if skey != "StringFileInfo":
				continue
			for _, _, _, tchild, tend in version_blocks(blob, schild, send):
				for name, _, text, _, _ in version_blocks(blob, tchild, tend):
					out["string." + name] = text.decode("utf-16-le").rstrip("\0")
	return out


def main(argv):
	if len(argv) != 2:
		print("usage: pe-resources.py FILE.exe", file=sys.stderr)
		return 2
	try:
		with open(argv[1], "rb") as fh:
			pe = fh.read()
		sec, base = rsrc_section(pe)
		found = resources(sec, base) if sec is not None else []
		groups = [r for r in found if r[0] == RT_GROUP_ICON]
		info = {
			"icon_groups": str(len(groups)),
			"icons": str(sum(1 for r in found if r[0] == RT_ICON)),
		}
		if groups:
			## GRPICONDIR: 6 byte header, then 14 byte entries; a width of 0 means 256.
			blob = groups[0][3]
			sizes = [blob[6 + i * 14] or 256 for i in range(u16(blob, 4))]
			info["icon_sizes"] = ",".join(str(s) for s in sorted(sizes))
		versions = [r for r in found if r[0] == RT_VERSION]
		info["version_blocks"] = str(len(versions))
		if versions:
			info.update(version_info(versions[0][3]))
	except (OSError, ValueError, struct.error, IndexError, UnicodeDecodeError) as err:
		print(f"pe-resources: {argv[1]}: {err}", file=sys.stderr)
		return 1
	for key in sorted(info):
		print(f"{key}={info[key]}")
	return 0


if __name__ == "__main__":
	sys.exit(main(sys.argv))


##	History:
##		- 20261019 JC: Created, for the harness check on the packaged Windows exes.
