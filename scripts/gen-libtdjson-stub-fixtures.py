#!/usr/bin/env python3
"""Regenerate the minimal aarch64 ELF stub fixtures used by
test/verify_ohos_hap_payload_test.dart (see that file for the contract).

The verifier (scripts/verify_ohos_hap_payload.py) parses real ELF structure:
header class/data/machine, section headers, .dynsym entries and their
STT_FUNC/defined status. These fixtures are generated to that contract —
they are not loadable libraries, they are parser inputs.

Usage: python3 gen_stub.py <out.so> modern|legacy-only|both-sets
"""
import struct
import sys


def build(path, symbols):
    EH = 64  # x86_64 header size; same for aarch64
    ehs = 64  # Elf64_Ehdr size
    shs = 64  # Elf64_Shdr size

    # sections: [null, .dynsym, .dynstr, .text]
    text = b"\x1f\x20\x03\xd5" * 2  # nop
    dynsym = bytearray(24)  # null symbol
    dynstr = bytearray(b"\x00")
    for name in symbols:
        name_off = len(dynstr)
        dynstr += name.encode() + b"\x00"
        # Elf64_Sym: name(4) info(1) other(1) shndx(2) value(8) size(8)
        dynsym += struct.pack(
            "<IBBHQQ", name_off, 0x12, 0, 3, 0, 4
        )  # GLOBAL|FUNC, defined in section 3 (.text)

    # layout
    off = ehs
    dynsym_off = off
    off += len(dynsym)
    # align dynstr to 8
    pad = (-off) % 8
    off += pad
    dynstr_off = off
    off += len(dynstr)
    text_off = off
    off += len(text)
    # shstrtab follows .text; section headers last

    # Elf64_Ehdr
    ehdr = bytearray(ehs)
    ehdr[0:4] = b"\x7fELF"
    ehdr[4] = 2  # ELFCLASS64
    ehdr[5] = 1  # ELFDATA2LSB
    ehdr[6] = 1  # EV_CURRENT
    ehdr[7] = 0  # System V
    struct.pack_into(
        "<HHIQQQIHHHHHH", ehdr, 16,
        3,   # e_type = ET_DYN
        0xB7,  # e_machine = EM_AARCH64
        1,   # e_version
        0, 0,  # e_entry, e_phoff
        0,  # e_shoff patched below
        0,  # e_flags
        EH, 0, 0, 0, 0, 0,  # ehsize; phentsize/phnum/shentsize/shnum/shstrndx patched below
    )
    # We point e_shstrndx at .dynstr? No: verifier only follows sh_name for
    # finding .dynsym/.dynstr by name. Provide a real .shstrtab instead:
    # simpler: extend sections to [null, .dynsym, .dynstr, .text, .shstrtab]
    shstrtab = bytearray(b"\x00")
    names = [b".dynsym", b".dynstr", b".text", b".shstrtab"]
    name_offs = []
    for n in names:
        name_offs.append(len(shstrtab))
        shstrtab += n + b"\x00"
    shnum = 5
    # recompute offsets with shstrtab after .text
    shstrtab_off = text_off + len(text)
    pad2 = (-(shstrtab_off + len(shstrtab))) % 8
    shoff = shstrtab_off + len(shstrtab) + pad2

    struct.pack_into("<Q", ehdr, 0x28, shoff)  # e_shoff

    def shdr(name_off, s_type, flags, addr, offset, size, link, info,
             align, entsize):
        return struct.pack(
            "<IIQQQQIIQQ", name_off, s_type, flags, addr, offset, size,
            link, info, align, entsize,
        )

    shdrs = b"".join([
        shdr(0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
        shdr(name_offs[0], 11, 2, 0, dynsym_off, len(dynsym), 2, 0, 8, 24),
        shdr(name_offs[1], 3, 2, 0, dynstr_off, len(dynstr), 0, 0, 1, 0),
        shdr(name_offs[2], 1, 6, 0, text_off, len(text), 0, 0, 4, 0),
        shdr(name_offs[3], 3, 0, 0, shstrtab_off, len(shstrtab), 0, 0, 1, 0),
    ])
    e_shstrndx = 4
    out = bytearray(ehdr)
    out += dynsym
    out += b"\x00" * pad
    out += dynstr
    out += text
    assert len(out) == shstrtab_off, (len(out), shstrtab_off)
    out += shstrtab
    out += b"\x00" * pad2
    assert len(out) == shoff
    out += shdrs
    struct.pack_into("<H", ehdr, 0x36, 0)  # e_phentsize
    struct.pack_into("<H", ehdr, 0x38, 0)  # e_phnum
    struct.pack_into("<Q", ehdr, 0x28, shoff)  # e_shoff
    struct.pack_into("<H", ehdr, 0x3A, shs)  # e_shentsize
    struct.pack_into("<H", ehdr, 0x3C, shnum)  # e_shnum
    struct.pack_into("<H", ehdr, 0x3E, e_shstrndx)  # e_shstrndx
    out[0:ehs] = ehdr
    with open(path, "wb") as f:
        f.write(bytes(out))
    print(f"wrote {path} ({len(out)} bytes, {len(symbols)} dynsym)")


MODERN = ["td_create_client_id", "td_send", "td_receive", "td_execute"]
LEGACY = [
    "td_json_client_create", "td_json_client_send", "td_json_client_receive",
    "td_json_client_execute", "td_json_client_destroy",
]

if __name__ == "__main__":
    which = sys.argv[2]
    if which == "modern":
        build(sys.argv[1], MODERN + LEGACY)
    elif which == "legacy-only":
        build(sys.argv[1], LEGACY)
    else:
        raise SystemExit("modern|legacy-only")
