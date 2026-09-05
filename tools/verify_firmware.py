#!/usr/bin/env python3
"""Verify the merged ESP32-C3 firmware layout produced by idf.py merge-bin."""

from __future__ import annotations

import hashlib
import re
import shutil
import struct
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


EXPECTED_IMAGES = (
    (0x0000, "bootloader/bootloader.bin"),
    (0x8000, "partition_table/partition-table.bin"),
    (0x10000, "FoloToy-AI-Passport.bin"),
)

FLASH_SIZE = 8 * 1024 * 1024
PARTITION_TABLE_OFFSET = 0x8000
PARTITION_TABLE_SIZE = 0xC00
APP_MAX_SIZE = 0x300000
CARDID_OFFSET = 0x356000
CARDID_SIZE = 0x4000
RECOVERY_OFFSET = 0x700000
RECOVERY_SIZE = 0x100000
ENTRY = struct.Struct("<HBBII16sI")
RECOVERY_BOOT_MARKER = b"UP held: booting permanent recovery"
SWIFT_VIEW_INPUT_SYMBOL = "_ViewInputsV14pushStableType"
SWIFT_VIEW_INPUT_FRAME_LIMIT = 192


@dataclass(frozen=True)
class Partition:
    kind: int
    subtype: int
    offset: int
    size: int
    label: str

    @property
    def end(self) -> int:
        return self.offset + self.size


def parse_nm_symbols(raw: str, marker: str) -> list[tuple[int, int, str]]:
    """Return address, size, and name for defined ELF symbols containing marker."""
    symbols: list[tuple[int, int, str]] = []
    for line in raw.splitlines():
        fields = line.split(maxsplit=3)
        if len(fields) != 4 or marker not in fields[3]:
            continue
        try:
            symbols.append((int(fields[0], 16), int(fields[1], 16), fields[3]))
        except ValueError:
            continue
    return symbols


def parse_riscv_stack_frame(raw: str) -> int:
    """Read the entry basic block's `addi sp,sp,-N` frame allocation."""
    match = re.search(r"\baddi\s+sp,sp,-(\d+)\b", raw)
    return int(match.group(1)) if match else 0


def validate_swift_view_input_frames(frame_sizes: list[int]) -> int:
    if not frame_sizes:
        raise ValueError("Swift View input stack-frame evidence is missing")
    largest = max(frame_sizes)
    if largest > SWIFT_VIEW_INPUT_FRAME_LIMIT:
        raise ValueError(
            "Swift View input stack frame is "
            f"{largest} bytes; embedded limit is {SWIFT_VIEW_INPUT_FRAME_LIMIT}"
        )
    return largest


def verify_swift_view_input_frames(build_dir: Path) -> None:
    """Guard the ESP32-C3-specific stack adaptation using final RISC-V code.

    OpenSwiftUI graph inputs are cheap attribute-backed values. EmbeddedSwiftUI
    uses concrete inherited inputs, so firmware must keep their recursive helper
    frames bounded independently of host tests.
    """
    elf_path = build_dir / "FoloToy-AI-Passport.elf"
    nm = shutil.which("riscv32-esp-elf-nm")
    objdump = shutil.which("riscv32-esp-elf-objdump")
    if not elf_path.is_file() or nm is None or objdump is None:
        raise ValueError("RISC-V ELF stack-frame tools or application ELF are missing")

    nm_output = subprocess.run(
        [nm, "-S", "--defined-only", str(elf_path)],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    symbols = parse_nm_symbols(nm_output, SWIFT_VIEW_INPUT_SYMBOL)
    frame_sizes: list[int] = []
    for address, size, _ in symbols:
        disassembly = subprocess.run(
            [
                objdump,
                "-d",
                f"--start-address={address}",
                f"--stop-address={address + min(size, 64)}",
                str(elf_path),
            ],
            check=True,
            capture_output=True,
            text=True,
        ).stdout
        frame_sizes.append(parse_riscv_stack_frame(disassembly))

    largest = validate_swift_view_input_frames(frame_sizes)
    print(
        "Swift View input frame: PASS "
        f"({largest} / {SWIFT_VIEW_INPUT_FRAME_LIMIT} bytes, "
        f"{len(frame_sizes)} specialization(s))"
    )


def parse_partition_table(raw: bytes) -> tuple[list[Partition], bool]:
    """Parse an ESP-IDF table and verify its optional MD5 marker."""
    if len(raw) < PARTITION_TABLE_SIZE:
        raise ValueError("partition table is truncated")

    partitions: list[Partition] = []
    found_md5 = False
    for cursor in range(0, PARTITION_TABLE_SIZE, ENTRY.size):
        magic = int.from_bytes(raw[cursor : cursor + 2], "little")
        if magic == 0xFFFF:
            break
        if magic == 0xEBEB:
            expected = hashlib.md5(raw[:cursor]).digest()
            actual = raw[cursor + 16 : cursor + 32]
            if actual != expected:
                raise ValueError("partition table MD5 marker does not match")
            found_md5 = True
            break
        if magic != 0x50AA:
            raise ValueError(f"invalid partition entry at table offset 0x{cursor:x}")

        _, kind, subtype, offset, size, label_raw, _ = ENTRY.unpack_from(raw, cursor)
        label = label_raw.split(b"\0", 1)[0].decode("ascii", "strict")
        if not label or not size or offset < 0x9000 or offset + size > FLASH_SIZE:
            raise ValueError(f"invalid partition bounds for {label!r}")
        partitions.append(Partition(kind, subtype, offset, size, label))

    if not partitions:
        raise ValueError("partition table is empty")
    return partitions, found_md5


def verify_recovery_contract(merged: bytes, build_dir: Path) -> None:
    """Enforce the artifact/layout contract used by mini-program BLE install."""
    table = merged[
        PARTITION_TABLE_OFFSET : PARTITION_TABLE_OFFSET + PARTITION_TABLE_SIZE
    ]
    partitions, found_md5 = parse_partition_table(table)
    if not found_md5:
        raise ValueError("partition table has no MD5 marker")

    by_label = {item.label: item for item in partitions}
    expected = {
        "factory": Partition(0, 0, 0x10000, APP_MAX_SIZE, "factory"),
        "cardid": Partition(1, 2, CARDID_OFFSET, CARDID_SIZE, "cardid"),
        "recovery": Partition(0, 0x20, RECOVERY_OFFSET, RECOVERY_SIZE, "recovery"),
    }
    for label, wanted in expected.items():
        if by_label.get(label) != wanted:
            raise ValueError(f"partition {label!r} must remain {wanted}, got {by_label.get(label)}")

    ordered = sorted(partitions, key=lambda item: item.offset)
    for left, right in zip(ordered, ordered[1:]):
        if left.end > right.offset:
            raise ValueError(f"partitions {left.label!r} and {right.label!r} overlap")
    for item in partitions:
        if item.label != "cardid" and item.offset < CARDID_OFFSET + CARDID_SIZE and CARDID_OFFSET < item.end:
            raise ValueError(f"partition {item.label!r} overlaps protected cardid")
        if item.label != "recovery" and item.offset < RECOVERY_OFFSET + RECOVERY_SIZE and RECOVERY_OFFSET < item.end:
            raise ValueError(f"partition {item.label!r} overlaps permanent Recovery")

    app_path = build_dir / "FoloToy-AI-Passport.bin"
    app_size = app_path.stat().st_size
    if app_size > APP_MAX_SIZE:
        raise ValueError(f"application is {app_size} bytes; BLE limit is {APP_MAX_SIZE}")
    if len(merged) <= 0x10000 or merged[0x10000] != 0xE9:
        raise ValueError("merged artifact has no ESP application image at 0x10000")

    # A derivative may add resource partitions after cardid. The merged file is
    # still acceptable only if protected regions contain padding, never a real
    # device identity or a replacement Recovery payload.
    for label, offset, size in (
        ("cardid", CARDID_OFFSET, CARDID_SIZE),
        ("recovery", RECOVERY_OFFSET, RECOVERY_SIZE),
    ):
        payload = merged[offset : min(len(merged), offset + size)]
        if any(byte != 0xFF for byte in payload):
            raise ValueError(f"merged artifact contains forbidden {label} payload bytes")

    bootloader = (build_dir / "bootloader" / "bootloader.bin").read_bytes()
    if RECOVERY_BOOT_MARKER not in bootloader:
        raise ValueError("bootloader is missing the 5-second UP Recovery hook")

    print(f"Mini-program BLE contract: PASS (app {app_size} / {APP_MAX_SIZE} bytes)")


def main() -> int:
    build_dir = Path(sys.argv[1] if len(sys.argv) > 1 else "build").resolve()
    merged_path = build_dir / "FoloToy-AI-Passport-full.bin"
    flash_args_path = build_dir / "flash_args"

    if not merged_path.is_file() or not flash_args_path.is_file():
        print("ERROR: merged firmware or flash_args is missing", file=sys.stderr)
        return 1

    flash_args = flash_args_path.read_text(encoding="utf-8")
    if "--flash_size 8MB" not in flash_args:
        print("ERROR: flash_args does not select the required 8 MB flash size", file=sys.stderr)
        return 1

    merged = merged_path.read_bytes()
    for offset, relative_name in EXPECTED_IMAGES:
        image_path = build_dir / relative_name
        if not image_path.is_file():
            print(f"ERROR: missing image {image_path}", file=sys.stderr)
            return 1
        image = image_path.read_bytes()
        if merged[offset : offset + len(image)] != image:
            print(f"ERROR: {relative_name} differs at merged offset 0x{offset:x}", file=sys.stderr)
            return 1
        print(f"Verified {relative_name}: {len(image)} bytes at 0x{offset:x}")

    if len(merged) > FLASH_SIZE:
        print("ERROR: merged firmware exceeds 8 MB", file=sys.stderr)
        return 1

    try:
        verify_swift_view_input_frames(build_dir)
        verify_recovery_contract(merged, build_dir)
    except (
        OSError,
        subprocess.CalledProcessError,
        UnicodeDecodeError,
        ValueError,
    ) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1

    print(f"Merged firmware: PASS ({len(merged)} bytes, flash at 0x0)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
