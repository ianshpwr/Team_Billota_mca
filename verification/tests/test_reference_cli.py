from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "reference_model.py"


class ReferenceCliTests(unittest.TestCase):
    def test_bad_input_has_concise_file_and_line_diagnostic(self):
        with tempfile.TemporaryDirectory() as tmp:
            vec = Path(tmp) / "bad.vec"
            vec.write_text("// header\ninvalid\n")
            result = subprocess.run([sys.executable, "-I", str(SCRIPT), str(vec),
                                     str(Path(tmp) / "out.log"), str(Path(tmp) / "memory.hex")],
                                    text=True, capture_output=True)
            self.assertEqual(result.returncode, 2)
            self.assertIn("bad.vec:2:", result.stderr)
            self.assertNotIn("Traceback", result.stderr)
            self.assertFalse((Path(tmp) / "out.log").exists())

    def test_missing_input_has_concise_diagnostic(self):
        with tempfile.TemporaryDirectory() as tmp:
            result = subprocess.run([sys.executable, "-I", str(SCRIPT), str(Path(tmp) / "missing.vec"),
                                     str(Path(tmp) / "out.log"), str(Path(tmp) / "memory.hex")],
                                    text=True, capture_output=True)
            self.assertEqual(result.returncode, 2)
            self.assertIn("missing.vec", result.stderr)
            self.assertNotIn("Traceback", result.stderr)

    def test_help_describes_positional_arguments(self):
        result = subprocess.run([sys.executable, "-I", str(SCRIPT), "--help"], text=True, capture_output=True)
        self.assertEqual(result.returncode, 0)
        self.assertIn("latency", result.stdout)
