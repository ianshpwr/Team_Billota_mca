# Project Defence Guide

## 60-second summary (say this first)

We designed a direct-mapped cache controller in Verilog-2001: 16 lines x 4 bytes in front of a 64 KiB byte-addressable memory,
write-through with write-allocate, controlled by a 10-state FSM. We verified it in simulation with 47 directed and edge-case
tests, an always-on protocol monitor, an independent Python reference model compared on 714,666 transactions, and a mutation
study that detects 28 of 28 injected bugs. Latency follows 3 / 5+L / 4+L / 6+2L cycles at every memory latency we tried. We did
not run on an FPGA and make no timing claims.

## Demonstration order (matches the video)

1. `diagrams/block_diagram.png`, then address split with 0x0004 and 0x0044 (same index, different tag).
2. `make phase1` -> cold miss, hit, conflict replacement, write-through, `ALL TESTS PASSED`.
3. A waveform from `results/waveforms/` per concept.
4. Evidence: `TEST_RESULTS.md`, `results/reference_model_results.txt`, `results/phase2_mutation_results.txt`.

## Evidence map: "show me"

| Claim | Where to show it |
|---|---|
| Cold miss, hit, conflict replacement | `results/phase1_test_results.txt` (P1-02..P1-07), waveforms 1-3 |
| Write-through / write-allocate | tests D-15..D-22, waveforms 4-5, `docs/fsm_design.md` |
| No duplicate writes / no premature response | monitor in `testbench/tb_common.vh`, tests D-27..D-30, mutants M13, M14, M05, M20 |
| Each tag bit matters | test E-02, mutants M03, M21, M22 |
| Reset in the middle of a transaction | tests D-24R/W/A |
| Request held high | test D-26 |
| Latency formulas | `results/phase2_latency_sweep.txt` |
| Model agreement | `results/reference_model_results.txt` |
| Synthesizability | `results/synthesis_review.md` |
| Reproducibility | `make phase1-all`, `make phase2`; identical rerun |

## Hard questions to prepare for

* *"Is it tested on hardware?"* No. Simulation only; the iCE40 numbers are a mapper estimate and are labelled so.
* *"Did you use GTKWave?"* No, it could not be installed; the screenshots are from Surfer and are labelled.
* *"What is your code coverage?"* We measured functional coverage only (states, transitions, indices, offsets). No line coverage tool was run.
* *"Did you find bugs in the RTL?"* No RTL bugs were found; we found bugs in our own tests and a coverage gap, all logged in `DEVELOPMENT_LOG.md`.
* *"Who wrote what?"* Answer from `docs/individual_contributions.md` only, with evidence. Disclose AI assistance honestly per the university's policy.
* *"Why is the uniform-random hit ratio ~0?"* 64 B cache vs a 64 KiB address space: 0.1 % capacity, and random accesses have no locality.
* *"Why not write-back?"* Out of scope; write-through is simpler and keeps memory current. Listed as future work.
* *"Is the Python model really independent?"* It was written from the specification text and models only architectural state, no FSM or handshake; its latency column restates the documented timing contract, which the monitor verifies separately.

## Reproduce from scratch (for the examiner)

```sh
git clone [TODO: repository URL] && cd direct-mapped-cache-controller
brew install icarus-verilog            # or apt install iverilog
make phase1                            # ~2 s
make phase1-all                        # + sweep, mutation, Yosys (needs yosys, python3)
make phase2                            # full Phase 2 regression, about 3 minutes (needs verilator, yosys, python3)
```
Expected: `RESULT: ALL TESTS PASSED` and `RESULT: ALL COMPARISONS PASSED`.
