# Final Independent Project Audit

Written from the viewpoint of an external evaluator. **Method:** (1) the mechanical checks in `scripts/audit_checks.py`
(output saved in `results/final_audit_checks.txt`: 21 checks, 0 failed); (2) an independent reproduction in a clean copy of the
repository with no `build/`, `.venv`, `.git` or browser scratch (`make phase1-all`, `make phase2`, audit: results in section 3);
(3) page-by-page inspection of the rendered report PDF; (4) reading the RTL and the key tests against the specification; (5) a hunt
for over-claims. The audit was done by the same assistant that produced the work, so it is *procedurally* independent only
(fresh checks, no reuse of earlier conclusions), **not organisationally independent**; the team's own review is still required.

Rating scale (evidence-based, no full marks without evidence): 5 = fully met and independently reproduced; 4 = met with minor
issues; 3 = met with notable gaps; 2 = partly met; 1 = weak/absent. **OPEN** = needs human action that cannot be done by the assistant.

## 1. Evidence-based scorecard

| # | Category | Evidence | Identified issue | Severity | Recommended correction | Rating / status |
|---|---|---|---|---|---|---|
| 1 | Functional correctness | 47 directed/edge tests pass at 22 fixed + 5 random latencies; 357/357 reference-model runs (714,666 transactions); exhaustive 64 KiB write+read sweep; 28/28 mutants detected | Simulation-only; no formal proof, no hardware run | Medium | State clearly (done); optionally add formal checks of the handshake properties | **4** PASSED |
| 2 | RTL design quality | Verilog-2001, `-Wall` clean, Verilator clean on synthesizable modules, Yosys `check -assert` 0 problems, no latches; modular; documented headers | `cache_block` unused at top; arrays are flip-flops with full reset (area-inefficient); `dbg_hit` is combinational outside COMPARE_TAG; 3-cycle hit latency is long for a "cache hit"; no parameters (sizes hard-coded per the spec) | Low | Documented as decisions D10/D11 and in synthesis review; parameterise only if the spec is extended | **4** PASSED |
| 3 | Architecture clarity | `docs/architecture.md`, `address_decomposition.md`, `fsm_design.md`, `module_interfaces.md`, two diagrams (inspected visually), decisions D1-D11 | Phase-1-era wording had to be synchronised after Phase 2 (done during this audit) | Low | Keep docs generated/checked with each RTL change | **5** PASSED |
| 4 | Test coverage | Functional coverage 10/10 states, 17/17 legal transitions, 16/16 indices, 4/4 offsets (R and W); protocol monitor on every transaction; mutation study | **No line/branch/toggle coverage measured** (Icarus has none); coverage percentage deliberately not claimed | Medium | Run Verilator `--coverage` on the RTL with the directed bench if a numeric code-coverage figure is required | **4** PASSED (gap disclosed) |
| 5 | Simulation reproducibility | `make phase1-all`, `make phase2`, `make final`; fixed seeds; identical rerun (only timestamps differ); clean-copy reproduction (section 3) | Verified only on macOS arm64 with Icarus 13.0 / Yosys 0.71 / Verilator 5.054 / Python 3.14; not tried on Linux or other tool versions. Waveform screenshots need network access once (to fetch the Surfer web build) | Medium | Run the regression on a Linux machine/CI (e.g. GitHub Actions with `iverilog`) before submission | **4** PASSED |
| 6 | Performance analysis | `results/performance_metrics.csv` (309 rows) + `performance_summary.md`; formulas verified on every transaction; AMAT defined with assumptions | Synthetic workloads only; no real traces; the class-weighted AMAT equals the measured average by construction (stated as a consistency check, not evidence); no hardware timing | Low | Add a trace-driven workload (e.g. a small program's address trace) if the course expects it | **4** PASSED |
| 7 | Documentation quality | README, 4 architecture docs, verification strategy, synthesis review, waveform README, development log, traceability matrix, generated registers | Large volume; risk of drift. Mitigated: registers, coverage, performance, report numbers are *generated from logs*; audit script cross-checks IDs and links | Low | Re-run `make final` after any change | **4** PASSED |
| 8 | IEEE report formatting | 6-page IEEEtran two-column PDF; 20 required sections; Tables I-III, Figs 1-6, equations (1)-(3); 10 references web-verified; inspected page by page | Identifiers use the serif face (monospace font unavailable in Tectonic); waveform screenshots are small (legible only when zoomed); only 5 of 10 references are scholarly sources (rest are the standard and tool pages); author block and contribution table are placeholders; Underfull-box warnings (cosmetic) | Low | Final typesetting with the university template/pdflatex if required; replace waveform figures with larger crops if space allows | **4** PASSED (placeholders OPEN) |
| 9 | GitHub repository quality | Structure matches plan 3.3 (checked mechanically), `.gitignore`, MIT licence (provisional), 22 markdown files with all local links resolving, no secrets, no files > 2 MB | **No commits and not published** (by instruction); LICENSE holder placeholder; extra files beyond the plan (scripts, extra testbenches) are documented | Medium | Follow `docs/git_workflow.md`; set repo URL; confirm licence | **3** OPEN (human action) |
| 10 | Demonstration readiness | `video/demo_script.md` (timed), `recording_checklist.md`; the live commands were executed during this audit (`make phase1`, vector-bench waveform regeneration) | **Video not recorded**; script not rehearsed by the team; relies on the six screenshots for visuals | High (for submission) | Team to rehearse with a stopwatch and record; keep <= 5:00 | **2** OPEN (human action) |
| 11 | Individual contribution traceability | `docs/individual_contributions.md` template with an evidence column; `docs/git_workflow.md` | **Names, enrollment numbers, contributions are all placeholders**; no per-member git history exists; the work was produced with an AI assistant and the disclosure text is for the team to write | High (for submission) | Team fills the table with real evidence; each member commits under their own account; write the AI-use disclosure per university policy | **1** OPEN (human action) |
| 12 | Technical interview readiness | 46 Q&A grounded in the implementation (numbers cross-checked), defence guide with evidence map and hard questions | Answers are only useful if the members understand and can explain them; no mock interview done | Medium | Each member reads RTL + FSM + one test; hold a mock defence | **3** PASSED (needs team preparation) |

## 2. Findings from the hunt for over-claims and inconsistencies

| Finding | Where | Resolution |
|---|---|---|
| Stray log file left in the repo root by the assistant | repo root | Caught by `scripts/audit_checks.py`, removed |
| PDF page-count check could not read compressed PDFs | `scripts/audit_checks.py` | Fixed (uses `pdfinfo`) |
| Stale "to be done in Phase 2" wording | `docs/architecture.md`, `docs/module_interfaces.md` | Corrected |
| Phase 1 register generator would have overwritten `TEST_RESULTS.md` | `scripts/gen_test_register.py` | Now writes `results/phase1_test_register.md` |
| Wrong third author for the Yosys paper in the first draft ("Kepler" is the university) | report references | Caught by web verification, corrected to Wolf and Glaser |
| Waveform screenshots initially illegible / half-timeline | `results/waveforms/*.png` | Retaken at 720 px viewport; viewer stated as Surfer, not GTKWave |
| Claims I looked for and did **not** find: FPGA runs, clock frequencies, timing closure, code-coverage percentages, "video recorded" | all docs, report | None present (audit check 19) |

## 3. Independent reproduction (clean copy)

A copy of the repository without `build/`, `.venv`, `.git`, `.playwright-mcp` and the compiled PDF was created in a fresh directory and
run with `make phase1-all`, then `make phase2`, then `python3 -I scripts/audit_checks.py`:

| Step (in the clean copy) | Result |
|---|---|
| `make phase1-all` (clean, Phase 1 test, latency sweep, mutation check, Yosys) | exit 0 |
| `make phase2` (full Phase 2 regression + generated reports) | exit 0; `RESULT: ALL TESTS PASSED` for every configuration; `ALL COMPARISONS PASSED` |
| `make report` (Tectonic; committed figure PNGs, no `.venv`) | exit 0, PDF rebuilt |
| Outputs vs the main repository | `phase2_latency_sweep.txt`, `performance_metrics.csv`, `phase2_mutation_results.txt`, `coverage_summary.md`, `TEST_RESULTS.md` byte-identical; `reference_model_results.txt` identical apart from the elapsed-time line |
| `scripts/audit_checks.py` in the clone | 19 of 21 checks pass. The 2 that fail are artefacts of how the clone was made, not project defects: my own `clone_*.log` files sit in that directory (the "stray files" check correctly flags them), and the `.gitignore` check needs a `.git` directory, which the clone intentionally lacks |

(The first audit run in the clone also flagged the missing PDF, because the PDF was deliberately excluded to test that it can be rebuilt; `make report` fixed that.)

## 4. Verdict

**Technically complete and reproducible; not yet submission-ready until the team supplies the human-input items below.**
Every technical claim in the README, report and results is backed by a saved log that was regenerated in this audit. Known gaps are
disclosed in the README, report (Sec. XIV) and `PHASE_STATUS.md`.

## 5. Submission checklist (for the team)

- [ ] Fill member names, enrollment numbers, **actual** contributions (`docs/individual_contributions.md`, README, report author block and Table III)
- [ ] Write the AI-assistance disclosure in the form the university requires
- [ ] Confirm the licence and set the copyright holder (`LICENSE`)
- [ ] Review the work (each member), then commit under your own accounts using `docs/git_workflow.md`; publish only with the team lead's approval; fill the repository URL
- [ ] Rehearse and record the <= 5:00 video; add the link (`video/prototype_video_link.md`, README, report)
- [ ] Run `make final` on the machine you will present from (and ideally on Linux) and confirm `AUDIT CHECKS: ... FAILED: 0`
- [ ] Rebuild the PDF after filling the author block (`make report`), re-read it once
- [ ] (Optional) install GTKWave and re-capture screenshots if the course insists on GTKWave
- [ ] (Optional) measure line coverage with Verilator if a numeric coverage figure is required
- [ ] Do **not** submit forms or upload on the team's behalf without the team's decision
