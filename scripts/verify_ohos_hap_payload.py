#!/usr/bin/env python3
"""Verify the OHOS hap payload against the pinned tdjson manifest.

Checks the hap carries the required entries, that the packaged
arm64-v8a/libtdjson.so is byte-identical to the installed pinned library,
that its SHA-256/size match the pinned manifest member, and — the loader
gate — that the ELF's *dynamic symbol table* defines the four modern entry
points the Dart client binds (td_create_client_id/td_send/td_receive/
td_execute). A byte substring match (the old gate) can hit a string table
mention without the loader ever resolving the symbol; parsing .dynsym
cannot. A library exporting only the legacy td_json_client_* aliases must
fail: this client would still be unable to load it.
"""

import argparse
import hashlib
import json
import struct
import sys
import zipfile
from pathlib import Path

_REQUIRED_DYN_SYMBOLS = (
    "td_create_client_id",
    "td_send",
    "td_receive",
    "td_execute",
)


def defined_dynamic_functions(elf: bytes) -> set:
    """The STT_FUNC symbols the ELF defines (not imports) in .dynsym."""
    if (
        elf[:4] != b"\x7fELF"
        or elf[4] != 2  # ELFCLASS64
        or elf[5] != 1  # ELFDATA2LSB
        or elf[18] != 0xB7  # EM_AARCH64
    ):
        raise SystemExit("packaged libtdjson.so is not an arm64 ELF")
    e_shoff, = struct.unpack_from("<Q", elf, 0x28)
    e_shentsize, e_shnum, e_shstrndx = struct.unpack_from("<HHH", elf, 0x3A)
    sections = []
    for i in range(e_shnum):
        off = e_shoff + i * e_shentsize
        vals = struct.unpack_from("<IIQQQQIIQQ", elf, off)
        sections.append(vals)
    shstr_off = sections[e_shstrndx][4]

    def section_name(name_off: int) -> str:
        end = elf.index(b"\0", shstr_off + name_off)
        return elf[shstr_off + name_off:end].decode()

    dynsym = next(
        (s for s in sections if section_name(s[0]) == ".dynsym"), None
    )
    dynstr = next(
        (s for s in sections if section_name(s[0]) == ".dynstr"), None
    )
    if dynsym is None or dynstr is None:
        raise SystemExit("packaged libtdjson.so exposes no dynamic symbol table")
    _, _, _, _, sym_off, sym_size, _, _, _, entsize = dynsym
    str_off = dynstr[4]
    defined = set()
    for off in range(sym_off, sym_off + sym_size, entsize or 24):
        st_name, st_info, _st_other, st_shndx, _value, _size = (
            struct.unpack_from("<IBBHQQ", elf, off)
        )
        if st_shndx == 0:  # SHN_UNDEF: imported, not defined here
            continue
        if (st_info & 0xF) != 2:  # STT_FUNC
            continue
        end = elf.index(b"\0", str_off + st_name)
        defined.add(elf[str_off + st_name:end].decode())
    return defined


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("hap", type=Path)
    parser.add_argument(
        "--manifest", type=Path, default=Path("scripts/tdjson-manifest.json")
    )
    parser.add_argument(
        "--installed",
        type=Path,
        default=Path("ohos/entry/libs/arm64-v8a/libtdjson.so"),
    )
    args = parser.parse_args()

    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    asset = manifest["assets"]["tdjson-ohos-arm64.zip"]
    member = asset["members"]["arm64-v8a/libtdjson.so"]
    hap_member = "libs/arm64-v8a/libtdjson.so"

    with zipfile.ZipFile(args.hap) as bundle:
        names = bundle.namelist()
        for required in ("pack.info", "ets/modules.abc", hap_member):
            if required not in names:
                raise SystemExit(
                    f"hap payload is missing a required entry: {required} "
                    f"(have {sorted(names)[:20]})"
                )
        info = bundle.getinfo(hap_member)
        if info.file_size != member["size"]:
            raise SystemExit(
                f"{hap_member} size {info.file_size} does not match the "
                f"pinned {member['size']} bytes"
            )
        packaged = bundle.read(hap_member)

    digest = hashlib.sha256(packaged).hexdigest()
    if digest != member["sha256"]:
        raise SystemExit(
            f"{hap_member} does not match the pinned manifest digest"
        )
    if packaged != args.installed.read_bytes():
        raise SystemExit(
            "packaged libtdjson.so differs from the installed pinned bytes"
        )

    defined = defined_dynamic_functions(packaged)
    for symbol in _REQUIRED_DYN_SYMBOLS:
        if symbol not in defined:
            raise SystemExit(
                f"packaged libtdjson.so does not define the {symbol} "
                f"entry point in .dynsym"
            )
    print(
        f"hap payload verified ({len(names)} entries); {hap_member} matches "
        f"the pinned manifest entry from release "
        f"{asset.get('release_tag', manifest['release_tag'])}; dynsym defines "
        f"all {len(_REQUIRED_DYN_SYMBOLS)} modern tdjson entry points"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
