# REQUIREMENTS_TRACEABILITY.md

Status vocabulary: `NOT STARTED`, `IN PROGRESS`, `BLOCKED`, `PASSED`, `FAILED`.
Test IDs refer to `TEST_RESULTS.md`. Phase 1 evidence: `results/phase1_*`. Phase 2 evidence: `results/complete_test_results.txt`,
`results/phase2_*`, `results/reference_model_results.txt`, `results/coverage_summary.md`, `results/performance_metrics.csv`,
`results/synthesis_review.md`, `results/waveforms/`.
Last updated: 2026-11-15 (end of Phase 2).

## Hardware specification

| ID | Requirement | RTL / doc | Test case(s) | Actual verification result | Evidence | Status |
|---|---|---|---|---|---|---|
| HW-01 | 16-bit byte address, 64 KiB, all addresses valid | `main_memory.v` | P1-09, E-01, E-10 (full 64 KiB write+read sweep), D-18c | Every address written and read back correctly; memory image = scoreboard | `complete_test_results.txt` | PASSED |
| HW-02 | 64 B cache, 16 lines, 4 B block, 32-bit data | `cache_memory.v` | D-10, D-11, E-03 | All 16 lines refilled with full 32-bit blocks | same | PASSED |
| HW-03 | tag[15:6] 10 b, index[5:2] 4 b, offset[1:0] 2 b | `cache_controller.v`, `docs/address_decomposition.md` | E-02 (each tag bit, 3 indices x 4 base tags, reads+writes), E-03, E-04, P1-13; mutants M03, M18, M21, M22 | Every tag bit significant; index/offset fields correct; mutants detected | same, `phase2_mutation_results.txt` | PASSED |
| HW-04 | Direct mapped | RTL | D-04, D-05, D-06, E-05 (all 1024 tags on a line), E-07 | Conflicts replace the single candidate line; other lines untouched | same | PASSED |
| HW-05 | Replacement: overwrite selected line on conflicting miss | `cache_controller.v` REFILL | D-04..D-06, E-05, E-07, E-08 | Tag and block replaced; evicted block misses | same | PASSED |
| HW-06 | Write-through | RTL | D-15, D-18, D-22, D-28, E-08, E-09, E-10; Python model; M07 | Each store: memory updated, cache updated, exactly 1 memory write; lines always coherent with memory | same, `reference_model_results.txt` | PASSED |
| HW-07 | Write-allocate | RTL | D-16, D-17, D-20 (miss path), E-08; Python model; M11, M27 | Block fetched, merged, allocated with correct tag/valid | same | PASSED |
| HW-08 | FSM controller | `cache_controller.v`, `docs/fsm_design.md` | C-01 coverage, E-11 | 10/10 states, 17/17 transitions, 0 illegal; unused codes self-recover | `coverage_summary.md` | PASSED |
| HW-09 | Verilog-2001 | all RTL | compile `-g2001 -Wall`; Verilator lint | no warnings (RTL); 1 explained unused-signal at top | `build/compile_warnings.txt`, `synthesis_review.md` | PASSED |
| HW-10 | Storage 688 bits | `docs/address_decomposition.md` | Yosys | `cache_memory` = 688 flip-flops | `phase1_yosys_check.txt`, `synthesis_review.md` | PASSED |

## Functional behaviour (plan "Required functional behaviour")

| ID | Requirement | RTL / doc | Test case(s) | Actual result | Evidence | Status |
|---|---|---|---|---|---|---|
| FR-01 | Read hit: correct byte, no memory traffic | `cache_controller.v` | D-02, D-07, D-09, D-12 | correct, 0 memory reads | `complete_test_results.txt` | PASSED |
| FR-02 | Read miss: aligned block fetch, refill, valid, byte, no stale / premature response | RTL | D-01, D-03, D-10, D-11, D-29, D-30; M05, M10, M20, M25 | correct; monitor 0 errors; mutants detected | same | PASSED |
| FR-03 | Write hit: byte update, write-through, other bytes preserved | RTL | D-15, D-19, D-20, D-21 | correct | same | PASSED |
| FR-04 | Write miss: fetch, merge, write memory, allocate, no duplicate writes | RTL | D-16, D-17, D-18, D-28; M14 | exactly one array write per store (counted at the memory write port) | same | PASSED |
| FR-05a | Document byte order, alignment, byte enables, latency, reset, back-to-back | `docs/*.md` | D-14, D-23, D-24, D-26 | documentation matches verified behaviour (written wait-state lengths corrected) | `docs/` | PASSED |
| FR-05b | Stall / wait-state safety (request stable, no duplicate writes, no premature response) | RTL | D-25..D-30, monitor, variable-latency runs | 0 errors at 22 fixed + 5 random latencies | `phase2_latency_sweep.txt` | PASSED |
| FR-06 | Reset behaviour (idle, between transactions, mid-transaction) | RTL | D-23, D-24, D-24R, D-24W, D-24A, D-00; M12, M16 | clean recovery at every cycle offset; committed-or-original memory semantics | same | PASSED |
| FR-07 | Request held high (multiple cycles) | RTL | D-26; M15, M24 | each request accepted once, in order | same | PASSED |
| FR-08 | Latency formulas (3 / 5+L / 4+L / 6+2L) hold at all supported latencies | `docs/fsm_design.md` | L-01, monitor | PASSED at L = 0 (clamped), 1..16, 32, 64, 100, 255, 1000 | `phase2_latency_sweep.txt` | PASSED |

## Phase 2 deliverables (plan 2.1-2.7)

| ID | Requirement | Artifact | Result | Status |
|---|---|---|---|---|
| P2-01 | 30 directed tests with ID, init, stimulus, expected, actual, PASS/FAIL | `testbench/cache_tb_directed.v`, `TEST_RESULTS.md` | 47 tests, 47 PASS | PASSED |
| P2-02 | Edge cases | E-01..E-11 | PASS | PASSED |
| P2-03 | Independent Python reference model | `verification/reference_model.py` | agrees on 714,666 transactions | PASSED |
| P2-04 | Randomized, reproducible (fixed seeds), latency variety, failing cases preserved | `verification/randomized_tests.py` | 357/357 runs; no failing case | PASSED |
| P2-05 | Waveform inspection + 6 screenshots | `results/waveforms/` | genuine Surfer screenshots (GTKWave unobtainable) | PASSED (viewer deviation) |
| P2-06 | Performance metrics from actual runs; AMAT with assumptions | `results/performance_metrics.csv`, `performance_summary.md` | 309 rows; measured = predicted | PASSED |
| P2-07 | Code quality / synthesis checks | `results/synthesis_review.md` | no latches; 1 explained lint note | PASSED |
| P2-08 | `docs/verification_strategy.md` | docs | written | PASSED |
| P2-09 | Mutation check (extra) | `results/phase2_mutation_results.txt` | 28/28 detected | PASSED |

## Engineering rules (plan "non-negotiable")

| ID | Rule | How checked | Status |
|---|---|---|---|
| R-01 | No claim without compile + test | all results from saved logs; `scripts/gen_*` generate registers from logs | PASSED |
| R-02 | No fabricated results/metrics/FPGA/refs/contributions/git history | no FPGA numbers; no commits; placeholders for people | PASSED (ongoing) |
| R-03 | Warnings not silently ignored | warning dispositions in `PHASE_STATUS.md`, `synthesis_review.md` | PASSED |
| R-04 | Synthesizable RTL separate from simulation-only | `main_memory.v` model; testbench-only files in `testbench/` | PASSED |
| R-07 | Check stale data, races, duplicate writes, byte enables, premature responses | monitor + D-18..D-30 + mutants | PASSED |
| R-13 | Distinguish implemented / simulated / synthesized / proposed | wording in docs; synthesis = mapper estimate only | PASSED (re-audit in Phase 3) |
| R-14 | Reproducibility (commands, versions, seeds, logs) | `make phase1-all`, `make phase2`, fixed seeds, identical rerun | PASSED |

## Phase 3 deliverables

| ID | Requirement | Artifact | Actual verification result | Status |
|---|---|---|---|---|
| P3-01 | IEEE two-column report with 20 required sections, numbered figures/tables/equations, verified references | `docs/IEEE_Project_Report.tex`, `docs/IEEE_Project_Report.pdf` | builds (Tectonic), 6 pages, no overfull boxes; audit checks sections/figures/citations | PASSED |
| P3-02 | No fabricated claims/references; implemented vs simulated vs synthesized vs proposed distinguished | report, README | references web-verified; synthesis numbers labelled as mapper estimates; over-claim scan in audit | PASSED |
| P3-03 | Contribution table for five members, placeholders | `docs/individual_contributions.md` | template only, no invented names | PASSED (needs team input) |
| P3-04 | Repository structure per plan; README with commands, results, limitations | repo tree, `README.md` | structure and links checked by `scripts/audit_checks.py`; clean-copy reproduction | PASSED |
| P3-05 | Git guidance, no fabricated history | `docs/git_workflow.md` | no commits made by the assistant | PASSED |
| P3-06 | Five-minute video script, checklist, link placeholder; no claim video exists | `video/` | video not recorded; stated everywhere | PASSED (video OPEN) |
| P3-07 | >= 35 interview Q&A reflecting the implementation | `docs/interview_questions.md` | 46 Q&A, numbers cross-checked with results | PASSED |
| P3-08 | Final independent audit with evidence scorecard | `docs/final_audit.md`, `results/final_audit_checks.txt` | 21/21 automated checks; issues listed with severity | PASSED |
| P3-09 | Final clean compilation and regression | `make final` | exit 0; clean-copy run | PASSED |

All previous requirement tables above remain valid; the final regression regenerated `TEST_RESULTS.md` with identical content.
