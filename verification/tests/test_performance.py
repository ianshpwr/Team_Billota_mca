from contextlib import redirect_stderr
import io
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import performance


class PerformanceTests(unittest.TestCase):
    def test_measured_metrics_for_all_four_request_classes(self):
        txns = performance.parse_log([
            "R 0", "T 1 0 0000 00 0 5a 9 1 0", "T 2 0 0000 00 1 5a 3 0 0",
            "T 3 1 0000 ab 1 00 8 0 1", "T 4 1 0040 cd 0 00 14 1 1", "C 0 1 001 000000cd"])
        result = performance.compute(txns, 4)
        for key, expected in {"total_requests": 4, "reads": 2, "writes": 2,
                              "hits": 2, "misses": 2, "hit_ratio": 0.5,
                              "mem_read_txns": 2, "mem_write_txns": 2,
                              "avg_latency_cycles": 8.5, "amat_class_weighted": 8.5,
                              "amat_read_formula": 6.0, "total_latency_cycles": 34}.items():
            self.assertEqual(result[key], expected, key)

    def test_malformed_records_fail_with_line_number(self):
        for row in ("T 0", "T 0 2 0000 00 0 00 9 1 0", "T 0 0 0000 00 0 00 0 1 0",
                    "T 0 0 0000 00 x 00 9 1 0"):
            with self.subTest(row=row), self.assertRaisesRegex(ValueError, "line 2:"):
                performance.parse_log(["header", row])

    def test_write_only_workload_has_no_read_amat(self):
        result = performance.compute(performance.parse_log(["T 0 1 0000 ab 0 00 14 1 1"]), 4)
        self.assertEqual(result["amat_read_formula"], "")

    def test_empty_log_cli_reports_error(self):
        with tempfile.TemporaryDirectory() as tmp:
            log = Path(tmp) / "empty.log"
            log.write_text("R 0\n")
            errors = io.StringIO()
            with redirect_stderr(errors), self.assertRaises(SystemExit) as caught:
                performance.main([str(log)])
            self.assertEqual(caught.exception.code, 2)
            self.assertIn("no transaction records", errors.getvalue())
