from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[2] / "scripts" / "vcd_trace.py"


class VcdTraceTests(unittest.TestCase):
    def trace(self, scope="cache_tb", address="1010"):
        text = f'''$scope module {scope} $end
$var wire 1 ! clk $end
$var wire 16 " cpu_addr [15:0] $end
$upscope $end
$enddefinitions $end
#0
0!
b{address} "
#5000
1!
#10000
0!
#15000
1!
'''
        with tempfile.TemporaryDirectory() as tmp:
            vcd = Path(tmp) / "trace.vcd"
            vcd.write_text(text)
            return subprocess.run([sys.executable, "-I", str(SCRIPT), str(vcd)], text=True, capture_output=True)

    def test_high_impedance_signals_do_not_crash_trace(self):
        for value in ("z", "Z", "10z1", "x"):
            with self.subTest(value=value):
                result = self.trace(address=value)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("x", result.stdout)
