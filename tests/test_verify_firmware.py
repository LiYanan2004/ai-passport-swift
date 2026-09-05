#!/usr/bin/env python3
"""Host tests for the mini-program firmware compatibility parser."""

from __future__ import annotations

import hashlib
import importlib.util
import struct
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "verify_firmware", ROOT / "tools" / "verify_firmware.py"
)
assert SPEC and SPEC.loader
VERIFY = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = VERIFY
SPEC.loader.exec_module(VERIFY)


def sample_table() -> bytes:
    entries = (
        (1, 2, 0x9000, 0x6000, "nvs"),
        (1, 1, 0xF000, 0x1000, "phy_init"),
        (0, 0, 0x10000, 0x300000, "factory"),
        (1, 2, 0x356000, 0x4000, "cardid"),
        (0, 0x20, 0x700000, 0x100000, "recovery"),
    )
    raw = bytearray(b"\xff" * VERIFY.PARTITION_TABLE_SIZE)
    for index, (kind, subtype, offset, size, label) in enumerate(entries):
        VERIFY.ENTRY.pack_into(
            raw,
            index * VERIFY.ENTRY.size,
            0x50AA,
            kind,
            subtype,
            offset,
            size,
            label.encode().ljust(16, b"\0"),
            0,
        )
    marker = len(entries) * VERIFY.ENTRY.size
    struct.pack_into("<H", raw, marker, 0xEBEB)
    raw[marker + 16 : marker + 32] = hashlib.md5(raw[:marker]).digest()
    return bytes(raw)


class PartitionParserTest(unittest.TestCase):
    def test_parses_protected_layout_and_md5(self) -> None:
        partitions, found_md5 = VERIFY.parse_partition_table(sample_table())
        self.assertTrue(found_md5)
        self.assertEqual(partitions[-2].label, "cardid")
        self.assertEqual(partitions[-1].offset, VERIFY.RECOVERY_OFFSET)

    def test_rejects_bad_md5(self) -> None:
        raw = bytearray(sample_table())
        raw[28] ^= 1
        with self.assertRaisesRegex(ValueError, "MD5"):
            VERIFY.parse_partition_table(bytes(raw))

    def test_parses_swift_view_input_symbols_and_stack_frame(self) -> None:
        symbol = "$e15EmbeddedSwiftUI11_ViewInputsV14pushStableTypeABC"
        symbols = VERIFY.parse_nm_symbols(
            f"4201394e 000000b8 t {symbol}\n"
            "42014000 00000040 t unrelated\n",
            VERIFY.SWIFT_VIEW_INPUT_SYMBOL,
        )
        self.assertEqual(symbols, [(0x4201394E, 0xB8, symbol)])
        self.assertEqual(
            VERIFY.parse_riscv_stack_frame(
                "4201394e: 711d addi sp,sp,-96\n42013950: ce86 sw ra,92(sp)"
            ),
            96,
        )

    def test_rejects_regressed_swift_view_input_stack_frame(self) -> None:
        with self.assertRaisesRegex(ValueError, "448 bytes"):
            VERIFY.validate_swift_view_input_frames([96, 448])

    def test_rejects_missing_swift_view_input_stack_evidence(self) -> None:
        with self.assertRaisesRegex(ValueError, "evidence is missing"):
            VERIFY.validate_swift_view_input_frames([])


if __name__ == "__main__":
    unittest.main()
