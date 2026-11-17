# Verification Strategy (Phase 2)

## 1. Goals and layers

| Layer | Artifact | What it establishes |
|---|---|---|
| L1 Directed, self-checking tests | `testbench/cache_tb_directed.v` (47 tests) | Each specified behaviour, edge case and handshake rule, with expected vs actual recorded |
| L2 Protocol monitor (always on) | `testbench/tb_common.vh` | Properties that must hold on *every* transaction of *every* test (below) |
| L3 Independent reference model | `verification/reference_model.py` + `testbench/cache_tb_vec.v` | Functional equivalence with an implementation written only from the specification, over 714,666 randomized/vector transactions |
| L4 Mutation check | `scripts/mutation_check_p2.py` | The testbenches would actually notice 28 classes of RTL bug (guards against vacuous tests) |
| L5 Waveform inspection | `results/waveforms/` | Cycle-level behaviour reviewed visually in a waveform viewer (Surfer) |
| L6 Static checks | Verilator lint, Yosys `check`, FSM/ice40 mapping | Synthesizability, latches, multiple drivers, width errors |
| L7 Phase 1 preserved | `testbench/cache_tb.v`, `results/phase1_*` | Unchanged; still passes (122 checks) |

The RTL was **not modified** in Phase 2: every Phase 2 test passed against the Phase 1 RTL. (Test-bench defects found
and fixed along the way are in `DEVELOPMENT_LOG.md`.)

## 2. Protocol monitor (checked every cycle)

* response only with an outstanding request; response lasts exactly one cycle; `cpu_ready` low while busy and during the response;
* response only after the exact number of memory operations (0 for a read hit, 1 read for a read miss, 1 write for a write hit, 1 read + 1 write for a write miss);
* **exactly one memory-array commit per store, none per load** (counted at the memory's write port, so a duplicate write is caught even though the data would be identical);
* latency = documented formula using the **measured** memory latency, and (fixed-latency mode) measured memory latency = configured `LATENCY`;
* `cpu_rdata` is 0 from acceptance to the response (no stale data) and 0 in a write response;
* `mem_req` only while a request is outstanding; `mem_req/we/addr/wdata` stable until `mem_done`; block reads aligned; `mem_done` only with `mem_req`;
* no illegal FSM transition (functional coverage, below); after reset no spurious response.

## 3. Directed test map (plan section 2.1 -> IDs)

| Plan # | Requirement | Test ID(s) |
|---|---|---|
| 1 | Cold miss | D-01 |
| 2 | Repeated hit | D-02 |
| 3 | Different blocks | D-03 |
| 4, 5 | Same-index conflict, replacement | D-04, D-05 |
| 6 | Re-access after replacement | D-06 |
| 7, 8 | Different offsets, all four byte positions | D-07, D-08 |
| 9, 10, 11 | Correct byte on hit / miss, full-block refill | D-09, D-10, D-11 |
| 12, 13, 14 | Repeated, sequential, back-to-back | D-12, D-13, D-14 |
| 15-17 | Write hit, write miss, write allocation | D-15, D-16, D-17 |
| 18 | Write-through verification (memory + cache + commit count + coherence + whole-memory scan) | D-18 |
| 19, 20, 21, 22 | Byte write, preservation, read-after-write, memory consistency after replacement | D-19, D-20, D-21, D-22 |
| 23, 24 | Reset while idle / between transactions | D-23, D-24 |
| (user req.) | **Reset during an active memory transaction**, every cycle offset, for read miss / write hit / write miss | D-24R, D-24W, D-24A |
| 25 | Delayed memory response | D-25 (+ all latency sweeps, variable-latency runs) |
| 26 | Request held high | D-26 (cpu_req stays high; next request presented while busy) |
| 27, 28, 29, 30 | Response handshake, no duplicate writes, no premature response, no stale data | D-27, D-28, D-29, D-30 |
| 2.2 | Edge cases | E-01 (0x0000/0xFFFF), E-02 (**each of the 10 tag bits independently**, min/max tags, reads *and* writes, 3 indices x 4 base tags), E-03 (min/max index), E-04 (offsets at corners), E-05 (all 1024 tags on one line), E-06 (invalid entries never hit, tag-0 aliasing), E-07/E-08 (repeated replacement, read and write), E-09 (write corners), E-10 (exhaustive 64 KiB write+read sweep), E-11 (illegal FSM state recovery) |
| - | Power-on initialisation (no X) | D-00 |
| user req. | Latency formulas across all supported latencies | L-01 and the monitor at L = 0..16, 32, 64, 100, 255, 1000 |
| - | Functional coverage goals | C-01 |

Every test prints its ID, description, initial conditions, stimulus, each check with *expected* and *actual*, and
`PASS`/`FAIL`. The consolidated register is generated into `TEST_RESULTS.md`.

### How the specific "additional verification requirements" are met

* **Ten tag bits independently** - E-02 flips exactly one tag bit (bit 0..9) of a base address at the same index and requires a MISS, the right data, the right stored tag, and eviction of the base; repeated for base tags 0x000, 0x3FF, 0x155, 0x2AA at indices 0, 7, 15, and for writes. Mutants dropping tag bit 0, 5 or 9 are all detected (M03, M21, M22).
* **Request held high over multiple cycles** - D-26 keeps `cpu_req` high continuously (> 40 cycles) while presenting the next request during the previous transaction; every request is accepted exactly once, in order, with correct data and exactly one memory write per store.
* **Reset during an active memory transaction** - D-24R/W/A abort the transaction at every cycle offset (every offset up to 12 + 2L; strided for large L), including the edge that commits the memory write; afterwards the valid bits, FSM, `cpu_ready`, `mem_req`, response are checked, the memory byte must equal "committed-or-original" (decided from the memory's own write port), and a recovery read must miss and return the correct byte.
* **Write-through and write-allocate checked independently against memory and cache** - D-18/D-20/D-22 compare the memory array, the cache line (via hierarchical references), the testbench scoreboard and an independently computed merged block; D-18 also asserts the write-through *invariant* (every valid line equals memory) and a full 64 KiB memory scan. The Python model separately predicts the final memory image and cache state.
* **Latency formulas across all supported latencies** - see `results/phase2_latency_sweep.txt`.

## 4. Independent reference model

`verification/reference_model.py` models only architectural state (64 KiB memory, 16 lines of `{valid, tag, 4 bytes}`) from the
written specification. It contains no FSM, wait state or handshake and was written without consulting RTL expressions.
It produces, per transaction: hit/miss, returned byte, memory reads/writes, and the *documented* latency; at the end the 16-line
cache state and the whole memory image. The same vector file is run on the RTL through `testbench/cache_tb_vec.v`; the
outputs are compared line by line, plus the memory dump byte-for-byte.

Reproducibility: vectors are generated with `random.Random(seed * 1000003 + sum(ord(c) for c in profile))` (fixed seeds 1-6). Profiles:
`uniform`, `hotset` (repeated addresses), `conflict` (3 indices x 6 tags), `sequential`, `write_heavy`, `mixed_reset` (resets and idles
in the stream), `corners`, `tagbits`. Latencies: fixed L = 1, 2, 3, 4, 8, 16, and a pseudo-random per-transaction latency in 1..8
(`testbench/cache_top_varlat.v`, latency column excluded from the comparison in that mode). Seed-1 vectors and expected outputs are
kept in `verification/test_vectors/`; any failing case would be preserved in `verification/test_vectors/failing/` (none occurred).

**Negative control for the harness itself.** Pointing the same harness at mutated RTL makes it fail (e.g. M01 55/55 runs fail, M18 55/55,
M04 52/55, M27 50/55, M12 31/55), so a clean pass is meaningful. M15 and M24 (request latching under held `cpu_req`) are invisible to
this driver by design (it never holds `cpu_req`); the directed bench D-26 detects them.

## 5. Mutation check

28 single-fault mutants of the RTL (byte order, valid ignored, each of three tag bits dropped, whole-word clobber, no wait for memory,
write-through skipped, unaligned block read, big-endian memory, stale `rdata`, write-allocate without refill, reset not clearing valid,
memory re-accept in DONE, double commit, request re-latched every cycle, memory FSM not reset, write hit not updating the cache, wrong
index, wrong byte lane write, early response, memory latency +1, request not latched on back-to-back, rdata not cleared, refill from
the previous block, write miss without merge, reset not clearing arrays).
Result (`results/phase2_mutation_results.txt`): **Phase 2 directed bench detects 28/28**; the Phase 1 bench detects 22/28
(it missed M14 double commit, M15 re-latch, M16 memory FSM not reset, M24 request not latched, M25 stale rdata, and M28 reset-without-array-clear -
exactly the areas Phase 2 added). The variable-latency configuration detects all 22 mutants it applies to (the other 6 modify the fixed-latency memory model).

## 6. Coverage

Functional coverage only (`results/coverage_summary.md`): 10/10 states, 17/17 legal transitions (16/16 reachable at L=1), 0 illegal
transitions, 16/16 indices and 4/4 offsets for both reads and writes. No line/branch/toggle coverage tool was run, so no such
percentage is claimed.

## 7. Static checks

Verilator `--lint-only -Wall`: no warnings for `cache_controller` and `cache_memory`; one `UNUSEDSIGNAL` for `cache_block` in `cache_top`
(unused debug output of `cache_memory`; intentional, harmless, left unchanged to avoid touching verified RTL). Yosys `proc; check -assert`:
0 problems, no latches, no multiple drivers. See `results/synthesis_review.md`.

## 8. Waveform inspection

Six scenarios (cold miss + refill, hit, conflict replacement, write hit, write miss + allocation, back-to-back) were rendered in
Surfer 0.7.0 and inspected: `results/waveforms/README.md`. GTKWave was not obtainable; this is stated wherever the screenshots are used.

## 9. Known limitations of the verification

* Simulation only (Icarus Verilog 13.0); no formal proof, no gate-level or FPGA timing simulation.
* Coverage is functional, not code coverage.
* Random-latency memory is a testbench model, not `rtl/main_memory.v`; `LATENCY` > 65535 is unsupported and untested.
* Hierarchical references into the DUT (cache arrays, memory array, commit strobe) are used for white-box checks and are simulation-only.
* The reference model's latency column restates the documented timing contract; timing is independently verified by the monitor.
* The scoreboard memory pattern is restated in the testbench and the model from the documented initialisation function; a mistake in that shared *documentation* would not be caught by comparison. The testbench shadow and the RTL memory are proven to agree (full 64 KiB scans D-18c/E-10a), but both restate the same documented pattern.
* Performance numbers use synthetic workloads and simulated cycles only.

## 10. How to reproduce

```sh
make phase2          # complete regression + generated reports (about 3 minutes)
python3 -I verification/randomized_tests.py --quick     # 55-run smoke subset
```
