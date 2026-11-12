# DEVELOPMENT_LOG.md

## 2026-11-15 - Phase 1

### Environment
* Found at start: `git 2.53.0`, `python3 3.14.5`, Homebrew. **Missing:** `iverilog`, `vvp`, `gtkwave`, `yosys`, `dot`, `pdflatex`.
* Working directory contained only `Direct_Mapped_Cache_Controller_Three_Phase_Plan.md` (identical copy also in `~/Downloads`). Left in place, untouched.
* Installed with Homebrew: `icarus-verilog` (13.0), `yosys` (0.71), `graphviz` (16.1.1).
  Homebrew also ran its routine cache cleanup during `brew install` (removed unrelated cached downloads; not project files).
* GTKWave: `brew install gtkwave` fails (migrated to a cask that no longer exists); `brew install --cask gtkwave` -> "No Cask with this name exists"; `brew tap homebrew/cask` refused. **Not installed.** Logged as limitation.
* `pdflatex` not installed - needed only in Phase 3; will be raised at that gate.

### Specification read

Spec file read in full (932 lines). Phase 1 scope executed only; Phases 2 and 3 not started.

### Design decisions (see `docs/architecture.md` D1-D11)
* Synchronous active-high reset; byte-granular CPU interface with 1-cycle `cpu_resp_valid`.
* Memory side: one request/`done` handshake, block read + byte write, configurable latency, registered 1-cycle `done`, memory ignores `req` while busy -> no duplicate writes.
* FSM has all 10 suggested states; refill replays the request as a hit (no bypass => no stale data; write-allocate reuses write-hit path).
* Little-endian block layout; deterministic memory init `(a[7:0]^a[15:8])+0x5A`.

### Files created
`rtl/{main_memory,cache_memory,cache_controller,cache_top}.v`, `testbench/cache_tb.v`, `Makefile`,
`scripts/{mutation_check.py,yosys_check.sh,vcd_trace.py,gen_test_register.py}`,
`docs/{architecture,address_decomposition,fsm_design,module_interfaces}.md`,
`diagrams/{block_diagram,fsm_diagram}.{dot,png}`, tracking files, `README.md`, `.gitignore`, `LICENSE`, `results/phase1_*`.

### Commands (all from repo root)
```
iverilog -g2001 -Wall -s cache_top -o /dev/null rtl/*.v         # RTL-only: clean, no output
make phase1          # compile (-g2001 -Wall) + simulate + VCD + logs
make lat-sweep       # MEM_LATENCY = 1 2 4 8
make mutation        # RTL bug-injection check of the testbench
make yosys           # generic synthesis / latch check
make trace           # text trace of the VCD
make phase1-all      # all of the above from a clean tree (exit code 0)
python3 -I scripts/gen_test_register.py                          # regenerates TEST_RESULTS.md
```

### Errors found and fixed
1. **Testbench race on cycle counter (testbench bug, not RTL).** First run: 81 PASS / 1 FAIL. Functional
   checks were all correct, but the latency monitor reported inconsistent latencies for identical
   operations (e.g. a read hit measured as 4, 3 and 2 cycles). Cause: `cyc` was incremented in one `always`
   block and read in another on the same clock edge (read/write race). Fix: single writer - the counter is
   now incremented at the top of the monitor block. After the fix every transaction matched the
   documented latency formulas at L = 1, 2, 4, 8.
2. **Coverage gap found by mutation testing (testbench weakness).** Mutant M3 (tag comparator ignoring tag
   bit 9) *survived* the original 82 checks because no two addresses differed only in tag bit 9.
   Fix: added `P1-13` (tag-bit sensitivity: each of the 10 tag bits flipped in turn must cause a miss at the
   same index). M3 is now detected; all 12 mutants detected.
3. No RTL defects were found by the testbench in Phase 1.

### Results (final Phase 1 run)
* Compile: exit 0, no warnings.
* Testbench: 122 checks, 0 failures, 0 monitor errors; identical output on repeated runs.
* Latency sweep L = 1, 2, 4, 8: 122/122 each.
* Mutation check: 12/12 mutants detected.
* Yosys: no latches, `check -assert` 0 problems; `cache_memory` = 688 flip-flops, `cache_controller` = 69.

### Not done / deliberately deferred
* No git commit: the kickoff authorised `git init` but not committing; commits should also carry the
  real author identity (Phase 3 contribution rules). Awaiting instruction.
* GTKWave screenshots (Phase 2.5).
* Python reference model, randomised tests, performance metrics (Phase 2).


## 2026-11-15 - Phase 2

Phase 1 approved by the user, with additional requirements (waveform viewer, git, licence, placeholders, extra
verification items). The user also authorised automatic continuation into Phase 3 after Phase 2.

### Waveform viewer
* `brew install gtkwave` / cask: unavailable (also `brew tap homebrew/cask` refused). GitHub `gtkwave/gtkwave` has no releases. **GTKWave not obtained.**
* `brew install surfer` -> Surfer 0.7.0 (native). Native window cannot be screen-captured from the automation session
  (`screencapture`: "could not create image from display"); Surfer has no screenshot command.
* Used Surfer's WebAssembly build driven through browser automation. First attempts (hosted app fetching `http://127.0.0.1`) failed
  (browser private-network blocking); fixed by serving the Surfer web files **and** the VCDs from one local origin
  (`scripts/fetch_surfer_web.sh`, `scripts/serve_waves.py`). Port 8765 was left stuck by a killed server; switched ports.
* Surfer's `startup_commands` URL parameter did not behave (single-line parse); keyboard command prompt used instead.
  `item_set_format ASCII` did not visibly apply, so the probe now emits one-hot state flags instead of an ASCII state name.
  A leftover CDP viewport override (1500x400) made later clicks miss the canvas; diagnosed and fixed (set 1500x520 explicitly).
* Result: six genuine Surfer screenshots; documented as Surfer, **not** GTKWave (`results/waveforms/README.md`).

### New files
`testbench/{tb_common.vh, cache_tb_directed.v, cache_tb_vec.v, wave_probe.v, cache_top_varlat.v}`,
`verification/{reference_model.py, randomized_tests.py, performance.py, test_vectors/*}`,
`scripts/{phase2_regression.sh, mutation_check_p2.py, gen_phase2_reports.py, synthesis_review.sh, serve_waves.py, fetch_surfer_web.sh}`,
`docs/verification_strategy.md`, `results/{complete_test_results.txt, coverage_summary.md, performance_metrics.csv, performance_summary.md,
phase2_latency_sweep.txt, phase2_mutation_results.txt, reference_model_results.txt, synthesis_review.md, synthesis_review_raw.txt, waveforms/*}`.
Installed with Homebrew: `surfer` 0.7.0, `verilator` 5.054. **RTL files were not modified.**

### Commands
```
make phase2                      # scripts/phase2_regression.sh + scripts/gen_phase2_reports.py
python3 -I verification/randomized_tests.py [--quick]
python3 -I scripts/mutation_check_p2.py . build/mutants_p2
sh scripts/synthesis_review.sh
```

### Test-development issues found and fixed (none were RTL bugs)
1. **E-08 check width.** `8'h40 + t[7:0]` was evaluated as a 32-bit expression inside `qcheck` (0x100 for t >= 192) -> 256 false failures. Fixed with `{24'h0, ...}`. (Testbench bug.)
2. **Write-wait length.** While writing D-25 I first assumed `MEMORY_WRITE_WAIT` lasts `L` cycles. Derivation showed `L+1` (request seen in the first cycle of the state) while `MEMORY_READ_WAIT` lasts `L`; checks and `docs/fsm_design.md` corrected before the first run. Same reasoning: at L=1 the read-wait self-loop is unreachable, so the coverage goal is 16 transitions there (17 otherwise).
3. **Variable-latency memory model:** a stray duplicate driver on the PRNG register found on review and removed.
4. **Comparison harness crash on X.** With a mutated RTL producing `x` in the log, the metrics step raised ValueError. Failing runs are now reported as failures and excluded from metrics.
5. **Mutation survivors.** The Phase 1 bench missed 6/28 new mutants (M14, M15, M16, M24, M25, M28) - expected, they target Phase 2 features. After adding D-24x, D-26, D-28 the Phase 2 bench detected all but M28 (not clearing the data/tag arrays at reset is functionally invisible). Resolved by test D-00 (no X after power-on reset), which enforces decision D10; M28 is now detected.
6. **Negative control** of the model harness: mutated RTL makes it fail (as intended). M15/M24 are invisible to the vector driver (never holds `cpu_req`); covered by the directed bench.

### Results
* Directed: 47 tests (313 check lines at L=4), all PASS; same at L = 0..16, 32, 64, 100, 255, 1000 and with random latency (max 2, 3, 8, 16, 40).
* Reference model: 357 runs, 714,666 fixed-latency transactions, 0 mismatches (transactions, final cache state, full memory image).
* Mutation: 28/28 detected by the Phase 2 bench (22/28 by the Phase 1 bench).
* Coverage (functional): 10/10 states, 17/17 legal transitions, 0 illegal, 16/16 indices, 4/4 offsets (reads and writes).
* Static: Verilator no warnings on synthesizable modules (1 explained unused-signal at top); Yosys `check -assert` 0 problems; iCE40 mapper estimate 757 FF + 778 LUT4 (not an implementation result).
* Reproducibility: a clean rerun reproduced every output byte-for-byte except generation timestamps/elapsed time.
* Phase 1 evidence preserved; Phase 1 testbench rerun output identical to `results/phase1_test_results.txt`.


## 2026-11-15 - Phase 3

### Toolchain
* `brew install tectonic` (0.17.0; self-contained LaTeX engine with IEEEtran) and `poppler` (pdfinfo); `.venv` with matplotlib 3.11.2 for plots.
* Attempt to use `fontspec`/Latin Modern Mono for monospace identifiers failed ("font cannot be found" in Tectonic) and was reverted;
  identifiers render in the serif face. Accepted (cosmetic).

### Report
* References were web-checked before use. Verified: Smith 1982 (ACM CSUR 14(3) 473-530, doi 10.1145/356887.356892), Hill 1988 (IEEE Computer 21(12) 25-40,
  doi 10.1109/2.16187), Jouppi 1990 (ISCA-17, pp. 364-373, Seattle), Wolf & Glaser 2013 (Austrochip, pp. 47-52; **my first draft had listed a wrong third author
  "Kepler" - that is the university's name; corrected**), Hennessy & Patterson 6th ed. (Morgan Kaufmann, 2017, ISBN 978-0-12-811905-1), IEEE Std 1364-2001. Tool
  citations use homepages reported by Homebrew. Unverified details (Icarus author name, publisher city) were removed rather than guessed.
* All statistics in the report come from `docs/report_numbers.tex`, generated from the saved logs.
* Layout issues fixed after rendering and inspecting the PDF: overfull spec table, unbreakable FSM path sentence (265 pt overfull -> list), two over-wide equations,
  fragile macro in captions (`\DeclareRobustCommand`), leftover "(Phase 1)" in diagram titles, overlapping chart labels, illegible full-width waveform screenshots.
* Waveform screenshots retaken at a 720 px viewport (Surfer text is fixed-size in CSS pixels, so narrow capture = legible print). A stale CDP viewport override made an earlier
  capture show only half the timeline; diagnosed (canvas wider than viewport) and fixed by clearing the override and using Playwright's own viewport.

### Audit
* `scripts/audit_checks.py` (21 checks) caught two problems in my own work: a stray log file I had left in the repo root, and a PDF page-count check that could not read a
  compressed PDF (now uses `pdfinfo`). Also fixed stale sentences in docs (Phase 2 "quantified later" notes) and made the Phase 1 register generator write to its own file
  so it cannot overwrite `TEST_RESULTS.md`.
* Independent reproduction in a clean copy (no `build/`, `.venv`, `.git`, browser scratch): see `docs/final_audit.md`.

### Not done (needs humans)
Team names/enrollment/contributions, AI-disclosure wording, git commits and publication, LICENSE holder, video recording and link.
