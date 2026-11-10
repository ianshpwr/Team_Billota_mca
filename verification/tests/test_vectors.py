"""Vector input checks; run with unittest discovery (no simulator needed)."""
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from reference_model import load_vectors


class VectorTests(unittest.TestCase):
    def load(self, text):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "input.vec"
            path.write_text(text)
            return load_vectors(path)

    def test_comments_blank_lines_and_end(self):
        self.assertEqual(self.load("# heading\n\n00000400 // read\n010005ab # write\n"
                                   "ff000000\ninvalid after end\n"), [0x00000400, 0x010005AB])

    def test_bad_words_include_line_number(self):
        for word in ("123", "000000000", "gg000000", "00000000 00000000", "-0000001"):
            with self.subTest(word=word), self.assertRaisesRegex(ValueError, r"input.vec:2:"):
                self.load("// header\n" + word)

    def test_unknown_opcode_rejected(self):
        with self.assertRaisesRegex(ValueError, "unsupported opcode 04"):
            self.load("04000000")

    def test_existing_vectors_remain_readable(self):
        root = Path(__file__).resolve().parents[1] / "test_vectors"
        for path in root.glob("*.vec"):
            with self.subTest(path=path.name):
                self.assertTrue(load_vectors(path))
