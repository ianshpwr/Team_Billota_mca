from contextlib import redirect_stderr
import io
from pathlib import Path
import sys
import subprocess
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import randomized_tests as regression


class RegressionOptionsTests(unittest.TestCase):
    def test_focused_run_options(self):
        args = regression.parse_args(["--quick", "--txns", "75", "--profile", "conflict",
                                      "--seed", "17", "--latency", "0", "--latency", "4"])
        self.assertEqual((args.txns, args.profile, args.seed, args.latency),
                         (75, ["conflict"], [17], [0, 4]))

    def test_invalid_options_fail_before_build(self):
        for option in (["--jobs", "0"], ["--txns", "0"], ["--txns", "262144"],
                       ["--latency", "-1"], ["--latency", "65536"], ["--profile", "unknown"],
                       ["--timeout", "0"], ["--timeout", "nan"], ["--timeout", "inf"]):
            with self.subTest(option=option), redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as caught:
                regression.parse_args(option)
            self.assertEqual(caught.exception.code, 2)

    def test_profile_generation_is_reproducible(self):
        for profile in regression.PROFILES:
            with self.subTest(profile=profile):
                first = regression.make_vectors(profile, 17, 75)
                self.assertEqual(first, regression.make_vectors(profile, 17, 75))
                self.assertNotEqual(first, regression.make_vectors(profile, 18, 75))
                self.assertEqual(len(first), 76)
                self.assertEqual(first[-1], "ff000000")


class SimulatorFailureTests(unittest.TestCase):
    def test_previous_outputs_cannot_make_a_new_run_pass(self):
        with tempfile.TemporaryDirectory() as tmp:
            vec = Path(tmp) / "input.vec"
            vec.write_text("00000400\nff000000\n")
            regression.ref.run(str(vec), str(Path(tmp) / "case.actual"), str(Path(tmp) / "case.mem"), 4)
            result = subprocess.CompletedProcess([], 0, "RESULT: ALL TESTS PASSED", "")
            with patch.object(regression, "BUILD", tmp), patch.object(regression.subprocess, "run", return_value=result):
                problems, actual, count, digest = regression.run_case("dut", str(vec), "case", 4, False)
            self.assertTrue(problems, "old simulator artifacts must not count as new output")
            self.assertIn("did not produce output", problems[0])
            self.assertFalse((Path(tmp) / "case.actual").exists())
            self.assertFalse((Path(tmp) / "case.mem").exists())

    def test_failures_preserve_evidence_without_missing_output_crash(self):
        cases = [
            (subprocess.CompletedProcess([], 7, "", "simulator failed"), "exited with code 7"),
            (subprocess.CompletedProcess([], 0, "", ""), "did not produce output"),
            (subprocess.TimeoutExpired("vvp", 0.1, output=b"partial output"), "timed out"),
        ]
        for outcome, message in cases:
            with self.subTest(message=message), tempfile.TemporaryDirectory() as tmp:
                vec = Path(tmp) / "input.vec"
                vec.write_text("00000400\nff000000\n")
                mock_kwargs = {"side_effect": outcome} if isinstance(outcome, Exception) else {"return_value": outcome}
                with patch.object(regression, "BUILD", tmp), patch.object(regression.subprocess, "run", **mock_kwargs):
                    problems, actual, count, digest = regression.run_case("dut", str(vec), "case", 4, False, 0.1)
                    self.assertIn(message, problems[0])
                    regression.preserve_failure({"tag": "case", "vec": str(vec)}, str(Path(tmp) / "failing"))
                evidence = Path(tmp) / "failing"
                self.assertEqual((evidence / "case.vec").read_text(), vec.read_text())
                self.assertTrue((evidence / "case.expected").is_file())
                self.assertTrue((evidence / "case.sim.log").is_file())
                self.assertFalse((evidence / "case.actual").exists())
