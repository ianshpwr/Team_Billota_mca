# Technical Interview Preparation (46 questions)

Answers describe **this** implementation and cite the repository. Numbers come from the saved results (`results/`, `TEST_RESULTS.md`).
Be ready to open the file named in each answer. If you do not know something, say so; never quote a number that is not in the repository.

## A. Fundamentals

**1. What is cache memory?**
A small, fast memory between the processor and main memory that keeps copies of recently used blocks. Here: 16 lines x 4 bytes = 64 B in front of a 64 KiB memory (`rtl/cache_memory.v`).

**2. Why do processors use a cache?**
Main memory is much slower than the CPU. Programs show temporal and spatial locality, so a small fast buffer satisfies most accesses quickly. In our simulation a hit takes 3 cycles while a read miss takes 5+L (9 cycles at L=4).

**3. What is direct mapping?**
Each memory block can be stored in exactly one cache line, chosen by `index = (address/4) mod 16 = address[5:2]`. A lookup needs one tag comparison and one valid-bit check (`docs/address_decomposition.md`).

**4. What are a hit and a miss?**
Hit: the indexed line is valid and its tag equals `address[15:6]`. Miss: otherwise. In `cache_controller.v`: `hit = cache_valid && (cache_tag == req_tag)`. Cold miss = the line was invalid; conflict miss = the line was valid but held a different tag.

**5. What is spatial locality and how does this design exploit it?**
Nearby addresses are used together. A miss fetches the whole 4-byte block, so the other three bytes hit (test D-07, and the sequential workload reaches the highest hit ratio, 0.589 at L=4).

**6. Temporal locality?**
Recently used data is reused soon. Repeated reads of the same address hit (D-02, D-12); the hot-set workload's hit ratio is 0.379 at L=4.

## B. Architecture

**7. Explain tag, index and offset.**
For a 16-bit byte address: offset = bits [1:0] selects the byte in a 4-byte block; index = [5:2] selects one of 16 lines; tag = [15:6] identifies which of the competing blocks is stored.

**8. Why 10 tag bits?**
16 - 4 (index) - 2 (offset) = 10. The 64 KiB space has 16,384 blocks; each line is shared by 1,024 blocks, and 2^10 = 1,024. We verified that each of the 10 bits matters (test E-02; mutants that drop tag bit 0, 5 or 9 are detected).

**9. How does replacement work?**
Direct mapped means no choice: a conflicting miss overwrites the selected line in the REFILL state. Because the cache is write-through, memory is always current, so no write-back is needed.

**10. What is a conflict miss? Give an example.**
A miss caused by two active blocks mapping to the same line. 0x0004 (tag 0) and 0x0044 (tag 1) both use index 1, so alternating them misses every time (test E-07: 100 consecutive conflict misses).

**11. What is a valid bit and why is it needed?**
It says whether a line holds real data. After reset the stored tag is 0, so without the valid bit an address with tag 0 would falsely hit. Test E-06 checks this; the mutant that ignores the valid bit is detected.

**12. What is the storage overhead?**
Per line 32 data + 10 tag + 1 valid = 43 bits; 16 lines = 688 bits, of which 176 (34.4 % of the data bits) are tag/valid overhead. Yosys maps `cache_memory` to exactly 688 flip-flops.

**13. Block size and byte order?**
4 bytes, little-endian: offset 0 = bits [7:0] of the 32-bit block. Reversing it is detected by mutants M01 and M09.

## C. RTL

**14. Describe each module.**
`cache_memory`: arrays, combinational read, byte select, byte merge, whole-line refill. `cache_controller`: request latch, tag compare, FSM, memory/cache strobes, response. `main_memory`: behavioural 64 KiB model with configurable latency (simulation only). `cache_top`: wiring plus debug ports.

**15. Explain the FSM.**
10 states: IDLE, COMPARE_TAG, READ_HIT, READ_MISS, MEMORY_READ_WAIT, REFILL, WRITE_HIT, WRITE_MISS, MEMORY_WRITE_WAIT, RESPONSE (`docs/fsm_design.md`, `diagrams/fsm_diagram.png`). Hit path: IDLE -> COMPARE_TAG -> READ_HIT -> RESPONSE. Miss path: ... -> READ_MISS -> MEMORY_READ_WAIT -> REFILL -> READ_HIT -> RESPONSE.

**16. Why use non-blocking assignments in sequential logic?**
All registers update simultaneously from pre-edge values, avoiding simulation races and matching synchronous hardware. Combinational blocks use blocking assignments with a default value to avoid latches. Yosys reports no latches.

**17. How is a memory block fetched?**
READ_MISS/WRITE_MISS raise `mem_req` with the block-aligned address `{addr[15:2], 2'b00}` and hold it until the one-cycle `mem_done`. The 32-bit block is registered in `block_reg`, then written into the line in REFILL.

**18. How is a byte selected and updated?**
Select: `block[{offset,3'b000} +: 8]`. Update: `merge_byte()` replaces one byte and keeps the other three; the byte-write strobe lasts exactly one cycle (WRITE_HIT), so there is exactly one cache update.

**19. Why "replay as hit" after the refill?**
After REFILL the request goes to READ_HIT or WRITE_HIT. Reads therefore always come from the cache array (no bypass path, so no stale data) and write-allocate reuses the write-hit logic (less code, fewer bugs).

**20. How do you prevent duplicate writes during wait states?**
The cache update lasts one cycle; the memory commits a write once when it enters DONE and ignores `req` while BUSY/DONE; the monitor counts array commits (exactly 1 per store). Mutants M13 (re-accept in DONE) and M14 (double commit) are detected.

**21. How does reset work and what survives it?**
Synchronous, active high. Controller returns to IDLE, valid bits and arrays clear, memory FSM aborts. Memory contents survive; a write that committed before the reset edge persists, one that had not is lost (tests D-24R/W/A, every cycle offset).

**22. What happens if `cpu_req` stays high?**
The request is latched at acceptance; the next request is accepted in the first IDLE cycle after each response, once per transaction (test D-26: 5 held writes -> exactly 5 memory writes).

**23. What is synthesizable and what is not?**
`cache_controller` and `cache_memory` are synthesizable; `main_memory` (initial-block fill, 64 KiB array) and all testbenches are simulation-only (`results/synthesis_review.md`).

## D. Verification

**24. How do you verify a hit?**
Read the same address twice: the second must be classified HIT (the monitor samples `dbg_hit` in COMPARE_TAG), return the correct byte, and cause no memory read (D-02).

**25. How did you test replacement?**
Same-index, different-tag addresses (D-04..D-06), all 1,024 tags on one line (E-05), ping-pong (E-07); we compare tag, data and valid bits of the line after each refill.

**26. What is a reference model and why is yours independent?**
A separate implementation of the specification used as the expected result. `verification/reference_model.py` models only architectural state (memory + 16 lines) from the spec, with no FSM or handshakes, written without reusing RTL expressions. 357 runs / 714,666 transactions agree exactly.

**27. How did you test random requests?**
Eight generator profiles (uniform, hot-set, conflict, sequential, write-heavy, resets, corners, tag patterns), fixed seeds 1-6, latencies 1,2,3,4,8,16 and a random latency. Failing cases would be saved in `verification/test_vectors/failing/` (none occurred).

**28. What does a waveform prove?**
It shows cycle-by-cycle behaviour (handshake ordering, one-cycle pulses, state sequence) for the specific scenario. It does not prove correctness in general; that is why we also use self-checking tests and the model.

**29. What is mutation testing and what did it show?**
Inject a known bug and check that the tests fail. 28 mutants: the Phase 2 bench detects 28; the earlier bench detected 22, missing duplicate-commit, re-latch, memory-reset and stale-rdata faults. One mutant (reset not clearing arrays) is functionally invisible and was caught by the power-on X-check.

**30. How did you check the timing/latency?**
The monitor compares every transaction's latency with 3, 5+L, 4+L, 6+2L using the measured memory latency; the suite ran at 22 fixed latencies (0..1000) and 5 random-latency configurations, all passing.

**31. What coverage do you have?**
Functional only: 10/10 FSM states, 17/17 legal transitions (16/16 reachable at L=1), 16/16 indices and 4/4 offsets for reads and writes. We did **not** measure line/branch coverage and do not claim a percentage.

**32. What bugs did verification find?**
No RTL bugs. We found bugs in our own tests (width error, wrong wait-length expectation, duplicate driver in a test model, harness crash on X) and one coverage gap (tag-bit-9 mutant survived the first suite, fixed by the tag-bit sweep).

## E. Performance

**33. How is hit ratio calculated?**
Hits / total requests (a write hit means its block was cached). Computed from the DUT's actual transaction log by `verification/performance.py`.

**34. What is miss penalty here?**
Extra cycles of a miss compared with a hit: for reads (5+L) - 3 = 2+L (6 cycles at L=4).

**35. What is AMAT?**
Hit time + miss rate x miss penalty. For reads: 3 + MR x (2+L). Writes always pay the write-through latency, so mixed traffic uses a class-weighted average, which equals the measured average latency in our runs.

**36. What trade-offs does direct mapping introduce?**
Pros: single comparator, simple control, short hit path. Cons: conflict misses (conflict workload hit ratio 0.163 vs 0.379 for the hot set at L=4). Set-associativity or a victim cache reduces conflicts at cost of complexity.

**37. Why is the write-heavy workload slower?**
Write-through without a write buffer stalls the CPU for the full memory write (4+L even on a hit): 11.54 cycles average at L=4 versus 8.46 for the hot-set workload.

## F. Design decisions

**38. Why write-through?**
Simplicity and safety: memory is always current, so replacement needs no write-back or dirty bit and a reset never loses data already acknowledged. The cost is write latency.

**39. Why write-allocate?**
After a write the block will likely be used again; fetching it lets the cache keep the whole block valid. It also reuses the existing miss/refill path.

**40. Why byte-granular CPU interface and byte writes to memory?**
The specification returns "the byte selected by the offset" and requires preserving the other bytes. A block read plus a byte write is the simplest consistent memory interface.

**41. What are the limitations?**
Simulation only; no FPGA/timing claim; one outstanding request; no pipelining or write buffer; memory model behavioural with a 16-bit latency counter; functional coverage only; synthetic workloads; viewer was Surfer, not GTKWave.

**42. How would you extend this to set-associative mapping?**
Keep N tag/valid/data sets, compare N tags in parallel, select the hit way, and add a replacement policy (e.g., LRU bits or pseudo-LRU). The index shrinks by log2 N bits and the tag grows accordingly; the FSM largely stays, with a way-select on refill.

**43. How could this be implemented on an FPGA?**
Synthesize `cache_controller` and `cache_memory` (Yosys mapped them to 757 flip-flops and 778 LUT4 on iCE40 as an estimate only), replace the behavioural memory with a real memory/controller, remove the array reset to infer block RAM, add constraints and run place-and-route to get real timing. None of that has been done.

**44. Why does the write wait last L+1 cycles but the read wait L?**
For reads the request starts one state earlier (READ_MISS asserts `mem_req`); for writes the request first appears in MEMORY_WRITE_WAIT. We found this while writing test D-25 and documented it in `docs/fsm_design.md`.

**45. What happens on an illegal FSM state?**
Unused codes 10-15 take the `default` branch to IDLE; test E-11 forces each code, checks the outputs are quiet and the controller recovers in one clock.

**46. Which tools did you use and why?**
Icarus Verilog (simulation, free, Verilog-2001), Yosys (synthesis checks), Verilator (lint), Python (reference model, random vectors, metrics), Surfer (waveform viewer; GTKWave could not be installed), Graphviz (diagrams), Tectonic/LaTeX (report).
