"""Architectural invariants and compatibility with saved reference outputs."""
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from reference_model import CacheModel, init_byte, run


class CacheModelTests(unittest.TestCase):
    def setUp(self):
        self.cache = CacheModel()

    def test_refill_fetches_all_four_bytes(self):
        for offset in range(4):
            self.assertEqual(self.cache.read(0x1200 + offset),
                             (offset != 0, init_byte(0x1200 + offset), int(offset == 0), 0))

    def test_conflict_replaces_only_selected_line(self):
        self.cache.read(0x0004)
        self.cache.read(0x0008)
        self.assertFalse(self.cache.read(0x0044)[0])
        self.assertTrue(self.cache.read(0x0008)[0])
        self.assertFalse(self.cache.read(0x0004)[0])

    def test_write_allocate_through_and_reset_persistence(self):
        self.assertEqual(self.cache.write(0xFFFF, 0xA5), (False, 0, 1, 1))
        self.assertEqual(self.cache.mem[0xFFFF], 0xA5)
        self.assertEqual(self.cache.read(0xFFFF), (True, 0xA5, 0, 0))
        self.assertEqual(self.cache.write(0xFFFF, 0x3C), (True, 0, 0, 1))
        self.cache.reset()
        self.assertFalse(any(self.cache.valid))
        self.assertEqual(self.cache.read(0xFFFF), (False, 0x3C, 1, 0))

    def test_every_address_round_trips_through_fields(self):
        for address in range(65536):
            tag, index, offset = self.cache.fields(address)
            self.assertEqual((tag << 6) | (index << 2) | offset, address)

    def test_latency_contract_including_zero_clamp(self):
        for latency in (0, 1, 4, 16):
            model = CacheModel(latency)
            L = max(1, latency)
            self.assertEqual([model.latency(write, hit)
                              for write, hit in ((False, True), (False, False),
                                                 (True, True), (True, False))],
                             [3, 5 + L, 4 + L, 6 + 2 * L])

    def test_saved_random_reference_outputs_unchanged(self):
        vectors = Path(__file__).resolve().parents[1] / "test_vectors"
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp) / "actual.log"
            for expected in vectors.glob("*.L4.expected"):
                with self.subTest(profile=expected.stem):
                    run(expected.with_name(expected.name.replace(".L4.expected", ".vec")),
                        output, None, 4)
                    self.assertEqual(output.read_text(), expected.read_text())
