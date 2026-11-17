# PHASE_STATUS.md

Status vocabulary: `NOT STARTED`, `IN PROGRESS`, `BLOCKED`, `PASSED`, `FAILED`.

| Phase | Status | Approval |
|---|---|---|
| Phase 1 - Architecture and core RTL | **PASSED** | Approved by the user (2026-11-15) |
| Phase 2 - Verification and performance | **PASSED** (all exit criteria met, see below) | The user authorised automatic continuation into Phase 3 (2026-11-15) |
| Phase 3 - Final deliverables | **PASSED** (technical deliverables); human-input items open | n/a |

Last updated: 2026-11-15 (Phase 3 complete)

## Phase 1 (summary; evidence preserved unchanged in `results/phase1_*`)

All 12 exit criteria met; 122 checks, 12/12 mutants detected, compile clean. The RTL was **not modified** in Phase 2.

## Phase 2 tasks

| ID | Task | Status | Evidence |
|---|---|---|---|
| 2.0a | Obtain a waveform viewer | **PASSED with deviation** | GTKWave not obtainable; Surfer 0.7.0 used (`results/waveforms/README.md`) |
| 2.1 | Directed tests D-00..D-30 (all 30 plan tests + extras) | PASSED | `results/complete_test_results.txt`, `TEST_RESULTS.md` |
| 2.2 | Edge-case tests E-01..E-11 | PASSED | same |
| 2.2b | Latency formulas at all supported latencies (L = 0..16, 32, 64, 100, 255, 1000) | PASSED | `results/phase2_latency_sweep.txt` |
| 2.2c | Variable (random per-transaction) memory latency | PASSED | same |
| 2.3 | Independent Python reference model | PASSED | `verification/reference_model.py` |
| 2.4 | Randomized tests vs the model (8 profiles x 6 seeds x 6 latencies + variable latency) | PASSED | `results/reference_model_results.txt` (357/357 runs) |
| 2.4b | Negative control of the comparison harness | PASSED | `docs/verification_strategy.md` s.4 |
| 2.5 | Waveform capture and inspection (6 scenarios) | PASSED (Surfer, not GTKWave) | `results/waveforms/*.png`, `*.vcd` |
| 2.6 | Performance metrics from actual runs | PASSED | `results/performance_metrics.csv`, `performance_summary.md` |
| 2.7 | Synthesis / lint review | PASSED | `results/synthesis_review.md`, `synthesis_review_raw.txt` |
| 2.8 | Mutation check of the testbenches (28 mutants) | PASSED (28/28 by Phase 2 bench) | `results/phase2_mutation_results.txt` |
| 2.9 | Functional coverage summary | PASSED | `results/coverage_summary.md` |
| 2.10 | Reproducibility (clean rerun, byte-identical outputs except timestamps) | PASSED | verified 2026-11-15 |
| 2.11 | Docs: `docs/verification_strategy.md`, FSM/interface docs synced | PASSED | `docs/` |

## Phase 2 exit criteria

- [x] All mandatory directed tests pass. - 47/47 tests, 0 failed checks (L=4), and at 22 fixed + 5 variable latencies
- [x] Edge cases pass. - E-01..E-11
- [x] Randomized tests pass. - 357 runs, 714,666 fixed-latency transactions compared
- [x] Python reference-model comparisons pass. - same (transactions, final cache state, full memory image)
- [x] Waveforms are captured and inspected. - 6 scenarios in Surfer (not GTKWave)
- [x] Performance metrics are generated from actual results. - 309 rows
- [x] No unexplained critical warnings remain. - see Warnings
- [x] Known limitations are documented. - below and `docs/verification_strategy.md` s.9
- [x] Regression simulation is reproducible. - `make phase2`; clean rerun identical apart from timestamps

## User's additional Phase 2 requirements

| Requirement | Status | Where |
|---|---|---|
| Waveform viewer: practical attempt for GTKWave, else another viewer; genuine screenshots; document tool | PASSED (Surfer) | `results/waveforms/README.md` |
| Git: no commits under the user's identity; give commit commands | DONE | `docs/git_workflow.md` |
| License MIT provisional, holder marked | DONE | `LICENSE` (`[TODO: COPYRIGHT HOLDER(S)]`) |
| Team info stays placeholder | DONE | `README.md`, `docs/individual_contributions.md` |
| Each of the ten tag bits independently | PASSED | E-02 (+ P1-13) |
| CPU requests held high across multiple cycles | PASSED | D-26 |
| Reset during an active memory transaction | PASSED | D-24R/W/A |
| Write-through / write-allocate independently vs memory and cache | PASSED | D-15..D-22, D-18, Python model |
| Latency formulas across all supported latencies | PASSED | L-01 + sweep |
| Preserve Phase 1 evidence; do not modify RTL unnecessarily | DONE | RTL unchanged (file times predate the Phase 1 evidence; Phase 1 testbench output byte-identical on rerun) |

## Bugs found in Phase 2

* **RTL defects: none.** Every Phase 2 test passed on the unmodified Phase 1 RTL.
* **Testbench/tooling defects found and fixed** (details in `DEVELOPMENT_LOG.md`): width bug in an E-08 check; wrong expectation of the write-wait length (L+1, not L) found while deriving the D-25 checks and corrected before the first run (RTL was right); read-wait self-loop absent at L=1 (coverage goal adjusted); a stray duplicate driver in the variable-latency memory; crash of the comparison harness on X output (made a reported failure); mutant M28 initially survived (reset array-clear unobservable) -> test D-00 added.

## Warnings

| Source | Warning | Disposition |
|---|---|---|
| `iverilog -g2001 -Wall`, RTL and all 6 testbench configurations | none | n/a |
| Verilator `--lint-only -Wall` | `UNUSEDSIGNAL cache_block` in `cache_top` | Explained: unused debug output of `cache_memory`; harmless; RTL left unchanged |
| Yosys/ABC | "network is combinational" (benign) ; Yosys' own `abc9_map.v` lexer `bit` warning | Explained |
| Yosys `check -assert` | 0 problems | - |

## Known limitations (after Phase 2)

1. **GTKWave was not used** (not obtainable); Surfer 0.7.0 screenshots are genuine but of a different viewer.
2. Functional coverage only; **no line/branch/toggle coverage numbers** exist or are claimed.
3. Simulation only (Icarus 13.0): no formal verification, no gate-level or FPGA/ASIC timing; iCE40 figures are mapper estimates, not implementation results.
4. Single outstanding request, no pipelining, no write buffer; every write stalls for the full memory latency.
5. `LATENCY` > 65535 unsupported (16-bit counter), untested. Random-latency memory is a testbench model, not RTL.
6. Performance results use synthetic workloads and simulated cycles; no clock frequency is assumed.
7. Python model's latency column restates the documented timing contract (timing is verified independently by the monitor).
8. LICENSE copyright holder, team names, enrollment numbers, contributions, repository URL, video link are placeholders.
9. **No git commits exist**; commit commands are provided for the user.

## Placeholders requiring human input (not invented)

Team member names, enrollment numbers, per-member contributions; GitHub repository URL; LICENSE copyright holder;
prototype video link (video not recorded); university/course/guide details for the report title block.

## Phase 3 tasks

| ID | Task | Status | Evidence |
|---|---|---|---|
| 3.1 | IEEE conference-style report (LaTeX, 6-page PDF, 20 required sections, numbered figures/tables/equations, 10 verified references) | PASSED | `docs/IEEE_Project_Report.tex`, `docs/IEEE_Project_Report.pdf` (rendered and inspected page by page) |
| 3.1a | Reference verification (web-checked: authors, title, venue, year, pages, DOI/ISBN) | PASSED | web searches during Phase 3; one author-list error caught (Yosys paper) |
| 3.1b | Report numbers generated from logs (no hand-typed statistics) | PASSED | `docs/report_numbers.tex`, `scripts/gen_report_numbers.py` |
| 3.2 | Individual contributions (placeholders only) | PASSED as template - **needs team input** | `docs/individual_contributions.md` |
| 3.3 | Repository organised; professional README | PASSED | `README.md`, tree per plan |
| 3.4 | Git / contribution audit guidance; mechanical audit | PASSED (guidance + 21 automated checks) | `docs/git_workflow.md`, `scripts/audit_checks.py`, `results/final_audit_checks.txt` |
| 3.5 | Five-minute demo script, recording checklist, video-link placeholder | PASSED (materials ready); **video NOT recorded** | `video/` |
| 3.6 | 35+ technical interview Q&A (46 written) and project-defence guide | PASSED | `docs/interview_questions.md`, `docs/project_defense.md` |
| 3.7 | Final independent audit and scorecard | PASSED (issues disclosed) | `docs/final_audit.md` |
| 3.8 | Final clean compilation and full regression | PASSED | `make final` (exit 0) from a clean tree and from an independent clean copy |

## Phase 3 exit criteria

- [x] IEEE report exists and renders correctly. - 6 pages, no overfull boxes, figures present, references resolved
- [x] All diagrams are included. - block diagram, FSM, 2 waveforms, 3 plots
- [x] Actual test results are documented. - report Sec. XI/XII, `TEST_RESULTS.md`
- [x] GitHub repository is organized. - structure verified by `scripts/audit_checks.py` (not yet published)
- [x] Reproduction instructions work. - verified from a clean copy (`make phase1-all`, `make phase2`, audit)
- [~] Actual team contributions are recorded. - **template only; real names/contributions must come from the team**
- [x] Five-minute video script and checklist are ready. - `video/` (video itself not recorded)
- [x] Interview preparation is ready. - 46 Q&A + defence guide
- [x] Final independent audit is complete. - `docs/final_audit.md`
- [x] Known limitations are disclosed. - README, report Sec. XIV, audit
- [x] Final regression passes. - see above

Overall project: **technically complete; submission still requires human action** (team details, contributions and AI disclosure, git commits/publication,
video recording, LICENSE holder). See "Submission checklist" in `docs/final_audit.md`.
