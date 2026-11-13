from contextlib import redirect_stderr
import io
from pathlib import Path
import sys
import unittest

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
                       ["--latency", "-1"], ["--latency", "65536"], ["--profile", "unknown"]):
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
