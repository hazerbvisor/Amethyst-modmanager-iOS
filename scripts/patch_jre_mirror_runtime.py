#!/usr/bin/env python3
"""Enable debugger-backed mirror mappings in the pinned JRE 17 and 21 builds.

Both bundled runtimes already contain Amethyst's MirrorMappedCodeCache support,
but their DeviceRequiresTXMWorkaround implementations predate the iOS 26.6
Preboot permission change. JRE 17 returns false and skips the debugger mapping;
JRE 21 dereferences the failed opendir result. The launcher only enables the
option after it has established the Universal JIT protocol, so the detector is
replaced with an unconditional true return.

The detector is located through the Mach-O symbol table so routine upstream JRE
rebuilds do not invalidate a hard-coded file offset. Its complete expected
prologue is still verified before writing, so an incompatible implementation is
rejected rather than patched heuristically.
"""

from __future__ import annotations

import argparse
import os
import struct
import sys
from pathlib import Path


MH_MAGIC_64 = 0xFEEDFACF
CPU_TYPE_ARM64 = 0x0100000C
LC_SEGMENT_64 = 0x19
LC_SYMTAB = 0x2
DETECTOR_SYMBOLS = (
    b"__Z27DeviceRequiresTXMWorkaroundb",
    b"__Z27DeviceRequiresTXMWorkaroundv",
)
LEGACY_PREFIX = bytes.fromhex(
    "fc6fbda9"  # stp x28, x27, [sp, #-0x30]!
    "f44f01a9"  # stp x20, x19, [sp, #0x10]
    "fd7b02a9"  # stp x29, x30, [sp, #0x20]
    "fd830091"  # add x29, sp, #0x20
)
CURRENT_PREFIX = bytes.fromhex(
    "fd7bbfa9"  # stp x29, x30, [sp, #-0x10]!
    "fd030091"  # mov x29, sp
)
MAX_PREFIX_SIZE = max(len(LEGACY_PREFIX), len(CURRENT_PREFIX))
RETURN_TRUE = bytes.fromhex(
    "20008052"  # mov w0, #1
    "c0035fd6"  # ret
)
MARKER_NAME = ".amethyst-mirror-mapping"
MARKER_CONTENT = "amethyst-mirror-mapping-v1\n"
SUPPORTED_RUNTIMES = (17, 21)


class PatchError(RuntimeError):
    pass


def _cstring(data: bytes, offset: int, limit: int) -> bytes:
    if offset < 0 or offset >= limit:
        raise PatchError(f"invalid Mach-O string offset: {offset}")
    end = data.find(b"\0", offset, limit)
    if end < 0:
        raise PatchError("unterminated Mach-O symbol name")
    return data[offset:end]


def _symbol_file_offset(data: bytes, symbol: bytes) -> int:
    if len(data) < 32:
        raise PatchError("file is too small to be a 64-bit Mach-O")

    magic, cpu_type, _, _, ncmds, sizeofcmds, _, _ = struct.unpack_from(
        "<IiiIIIII", data, 0
    )
    if magic != MH_MAGIC_64 or cpu_type != CPU_TYPE_ARM64:
        raise PatchError("expected an arm64 64-bit Mach-O")
    if 32 + sizeofcmds > len(data):
        raise PatchError("truncated Mach-O load commands")

    segments: list[tuple[int, int, int]] = []
    symtab: tuple[int, int, int, int] | None = None
    command_offset = 32
    for _ in range(ncmds):
        if command_offset + 8 > len(data):
            raise PatchError("truncated Mach-O load command")
        command, command_size = struct.unpack_from("<II", data, command_offset)
        if command_size < 8 or command_offset + command_size > len(data):
            raise PatchError("invalid Mach-O load command size")
        if command == LC_SEGMENT_64:
            if command_size < 72:
                raise PatchError("truncated LC_SEGMENT_64 command")
            vm_address, _, file_offset, file_size = struct.unpack_from(
                "<QQQQ", data, command_offset + 24
            )
            segments.append((vm_address, file_offset, file_size))
        elif command == LC_SYMTAB:
            if command_size < 24:
                raise PatchError("truncated LC_SYMTAB command")
            symtab = struct.unpack_from("<IIII", data, command_offset + 8)
        command_offset += command_size

    if symtab is None:
        raise PatchError("Mach-O has no symbol table")
    symbols_offset, symbol_count, strings_offset, strings_size = symtab
    symbols_end = symbols_offset + symbol_count * 16
    strings_end = strings_offset + strings_size
    if symbols_end > len(data) or strings_end > len(data):
        raise PatchError("truncated Mach-O symbol or string table")

    symbol_address = None
    for index in range(symbol_count):
        entry_offset = symbols_offset + index * 16
        string_index, _, _, _, value = struct.unpack_from(
            "<IBBHQ", data, entry_offset
        )
        if string_index and _cstring(
            data, strings_offset + string_index, strings_end
        ) == symbol:
            symbol_address = value
            break
    if symbol_address is None:
        raise PatchError(f"required symbol not found: {symbol.decode()}")

    for vm_address, file_offset, file_size in segments:
        if vm_address <= symbol_address < vm_address + file_size:
            result = file_offset + symbol_address - vm_address
            if result + MAX_PREFIX_SIZE > len(data):
                raise PatchError("symbol points outside the Mach-O file")
            return result
    raise PatchError("symbol is not backed by a file segment")


def _detector_location(data: bytes) -> tuple[int, bytes]:
    for symbol in DETECTOR_SYMBOLS:
        try:
            return _symbol_file_offset(data, symbol), symbol
        except PatchError as error:
            if not str(error).startswith("required symbol not found:"):
                raise
    names = ", ".join(symbol.decode() for symbol in DETECTOR_SYMBOLS)
    raise PatchError(f"required detector symbol not found (tried {names})")


def _marker_path(libjvm: Path) -> Path:
    try:
        return libjvm.parents[2] / MARKER_NAME
    except IndexError as error:
        raise PatchError("libjvm path is not inside a Java runtime") from error


def patch_runtime(
    runtime_version: int,
    libjvm: Path,
    check_only: bool = False,
) -> str:
    data = libjvm.read_bytes()
    detector_offset, detector_symbol = _detector_location(data)
    marker = _marker_path(libjvm)
    detector = data[detector_offset:detector_offset + MAX_PREFIX_SIZE]

    if detector.startswith(RETURN_TRUE):
        if check_only and marker.read_text(errors="replace") != MARKER_CONTENT:
            raise PatchError(f"runtime marker is missing or invalid: {marker}")
        if not check_only:
            marker.write_text(MARKER_CONTENT)
        return "already patched"

    expected_prefix = (
        CURRENT_PREFIX if detector_symbol.endswith(b"b") else LEGACY_PREFIX
    )
    if not detector.startswith(expected_prefix):
        raise PatchError(
            "unsupported DeviceRequiresTXMWorkaround prologue at "
            f"0x{detector_offset:x}: "
            f"{detector[:len(expected_prefix)].hex()}"
        )
    if check_only:
        raise PatchError("runtime still needs the mirror-mapping detector fix")

    with libjvm.open("r+b") as stream:
        stream.seek(detector_offset)
        stream.write(RETURN_TRUE)
        stream.flush()
        os.fsync(stream.fileno())
    patched = libjvm.read_bytes()
    if patched[detector_offset:detector_offset + len(RETURN_TRUE)] != RETURN_TRUE:
        raise PatchError("patched detector instructions did not persist")
    marker.write_text(MARKER_CONTENT)
    return "applied detector fix"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--check",
        action="store_true",
        help="verify the runtime and marker without modifying them",
    )
    parser.add_argument("runtime_version", type=int, choices=SUPPORTED_RUNTIMES)
    parser.add_argument("libjvm", type=Path)
    args = parser.parse_args()

    try:
        result = patch_runtime(
            args.runtime_version,
            args.libjvm,
            args.check,
        )
    except (OSError, PatchError) as error:
        print(f"[jre-mirror-patch] ERROR: {error}", file=sys.stderr)
        return 1

    print(
        f"[jre-mirror-patch] JRE {args.runtime_version}: "
        f"{result}: {args.libjvm}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
