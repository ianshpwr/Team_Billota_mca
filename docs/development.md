# Running checks while developing

Run commands from the repository root. Python checks use the standard library
only. HDL checks also need `iverilog` and `vvp` (install `icarus-verilog` with
Homebrew on macOS, or `iverilog` with apt on Ubuntu).

```sh
make test-python   # parser, model, metrics, runner and build failure checks
make smoke         # Python checks, RTL elaboration, directed RTL tests, random smoke
```

`make smoke` stores its logs in `build/`, including `smoke_directed.log` and
`rand/reference_model_results.txt`. It leaves committed results and representative
random vectors intact. Static waveform vectors are regenerated deterministically.
The GitHub Actions workflow runs the same command on pushes and pull requests,
using the official [checkout](https://github.com/actions/checkout) and
[setup-python](https://github.com/actions/setup-python) actions.

## Reproduce a specific workload

```sh
python3 -I verification/randomized_tests.py --quick --profile conflict --seed 17 --latency 0 --latency 4 --txns 75 --jobs 2
```

Repeat `--profile`, `--seed`, or `--latency` to select several values. The seven
static scenarios and variable memory latency comparisons still run. `--txns`
overrides the default even with `--quick`. Latency zero exercises the documented
clamp to one cycle. Invalid worker counts, transaction counts, latency values,
and timeouts fail before build outputs are changed.

Focused runs write their report under `build/rand/`; the unfiltered default run
writes the full reference report and performance CSV under `results/`. To refresh
all Phase 2 evidence, use `make phase2` as described in the main README.

## Investigate a failure

Each simulator run has a 120-second wall-clock timeout; change it with
`--timeout SECONDS`. A failed run returns a nonzero status and preserves its
vector, expected output, simulator log and any available DUT output/memory dump
under `verification/test_vectors/failing/`. Negative-control runs with
`--rtl-dir` keep those files in `build/rand/failing/` instead. Save evidence before
starting another regression, since `build/rand/` is recreated on each run.

Vector input must contain one eight-digit hexadecimal word per line. Blank lines,
`//` comments, `#` comments and inline comments are accepted by the Python model;
use `//` comments in vectors passed to Verilog's `$readmemh`. `ff000000` ends the
sequence. Invalid words and unsupported opcodes report their source file and line.

Build commands preserve failing tool exit codes even when output includes an
earlier PASS marker. `make phase1-all` completes cleanup before running checks;
`make final` runs its phases in sequence, including under parallel Make.
