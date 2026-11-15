"""Check orchestration exit codes using deliberately failing tool stand-ins."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class BuildFailureTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        for folder in ("bin", "results", "scripts"):
            (self.root / folder).mkdir()
        shutil.copy(ROOT / "Makefile", self.root)
        shutil.copy(ROOT / "scripts/phase2_regression.sh", self.root / "scripts")
        (self.root / "scripts/synthesis_review.sh").write_text("exit ${SYNTHESIS_EXIT:-0}\n")
        self.tool("iverilog", "exit 0")
        self.tool("python3", 'case "$*" in *"$FAIL_SCRIPT"*) echo "injected failure"; exit 23;; esac\nexit 0')
        self.tool("vvp", 'echo "SUMMARY TESTS=1 TESTS_FAILED=0 CHECKS_PASS=1 CHECKS_FAIL=0"\n'
                  'echo "LATENCY_CSV,L,3,9,8,14"\n'
                  'echo "MEMLAT_HIST,1,1"\n'
                  'echo "RESULT: ${SIM_RESULT:-ALL TESTS PASSED}"\nexit ${SIM_EXIT:-0}')
        self.env = dict(os.environ, PATH=str(self.root / "bin") + os.pathsep + os.environ["PATH"],
                        FAIL_SCRIPT="never-match-this-script")

    def tool(self, name, body):
        path = self.root / "bin" / name
        path.write_text("#!/bin/sh\n" + body + "\n")
        path.chmod(0o755)

    def run_command(self, command, **env):
        return subprocess.run(command, cwd=self.root, env=dict(self.env, **env),
                              capture_output=True, text=True, timeout=20)

    def test_make_propagates_python_failures(self):
        for target, script in (("audit", "audit_checks.py"), ("mutation", "mutation_check.py")):
            with self.subTest(target=target):
                result = self.run_command(["make", target], FAIL_SCRIPT=script)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("injected failure", result.stdout)

    def test_simulator_failure_cannot_be_hidden_by_pass_marker(self):
        result = self.run_command(["make", "phase1"], SIM_EXIT="23")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("RESULT: ALL TESTS PASSED", result.stdout)

    def test_sweep_checks_result_even_when_simulator_exits_zero(self):
        result = self.run_command(["make", "lat-sweep", "LATENCIES=1"], SIM_RESULT="FAILURES DETECTED")
        self.assertNotEqual(result.returncode, 0)

    def test_phase2_stops_on_failed_checks(self):
        for env in ({"FAIL_SCRIPT": "randomized_tests.py"},
                    {"FAIL_SCRIPT": "mutation_check_p2.py"}, {"SYNTHESIS_EXIT": "23"}):
            with self.subTest(env=env):
                result = self.run_command(["sh", "scripts/phase2_regression.sh"], **env)
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertNotIn("PHASE 2 REGRESSION COMPLETE", result.stdout)
