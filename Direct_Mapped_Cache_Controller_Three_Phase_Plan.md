# Direct Mapped Cache Controller Using Verilog HDL

## Three-Phase Project Development Plan

**Project type:** Five-member university engineering project\
**Primary HDL:** Verilog-2001\
**Simulation:** Icarus Verilog / VVP\
**Waveform inspection:** GTKWave\
**Project title:** Design and Implementation of a Direct Mapped Cache
Controller Using Verilog HDL

------------------------------------------------------------------------

## Project objective

Design, implement, verify, document, and prepare a complete
direct-mapped cache controller. The final project must include
synthesizable RTL where applicable, a behavioral main-memory model, a
self-checking testbench, reproducible simulation results, waveform
evidence, performance analysis, an IEEE-style report, a GitHub
repository, a five-minute prototype video plan, and interview
preparation.

This is an engineering project, not merely a code-generation exercise.
Every claim of correctness must be supported by compilation, simulation,
or other recorded evidence.

## Non-negotiable engineering rules

1.  Never claim that code works unless it has been compiled and tested.
2.  Never fabricate simulation results, performance metrics, waveforms,
    FPGA results, references, team contributions, or Git history.
3.  Do not silently ignore compiler or synthesis warnings. Explain and
    resolve or document each relevant warning.
4.  Keep synthesizable RTL separate from testbench-only and
    simulation-only code.
5.  Use modular, readable, commented Verilog-2001.
6.  Document module interfaces, clocking, reset polarity, request
    acceptance, response validity, and handshake timing.
7.  Check for stale data, race conditions, invalid cache states,
    duplicate writes, incorrect byte enables, and premature responses.
8.  Do not proceed to the next phase until the current phase's exit
    criteria have been met and reviewed.
9.  Maintain `DEVELOPMENT_LOG.md`, `PHASE_STATUS.md`,
    `REQUIREMENTS_TRACEABILITY.md`, and `TEST_RESULTS.md`.
10. Use task statuses consistently: `NOT STARTED`, `IN PROGRESS`,
    `BLOCKED`, `PASSED`, `FAILED`.
11. Do not overwrite unrelated files in an existing directory.
12. Use clearly marked placeholders for missing team names, enrollment
    numbers, repository URLs, and actual contributions.
13. Distinguish implemented, simulated, synthesized, and proposed
    functionality accurately.
14. Save commands, tool versions, test seeds, logs, and evidence so
    results can be reproduced.

------------------------------------------------------------------------

# Final Hardware Specification

  Parameter                                                 Specification
  ----------------------- -----------------------------------------------
  Address width                                                   16 bits
  Addressing                                             Byte-addressable
  Address space                                                    64 KiB
  Cache capacity                                                 64 bytes
  Number of cache lines                                                16
  Block size                                                      4 bytes
  Data width per block                                            32 bits
  Tag width                                                       10 bits
  Index width                                                      4 bits
  Offset width                                                     2 bits
  Mapping                                                   Direct mapped
  Replacement               Overwrite selected line on a conflicting miss
  Write policy                                              Write-through
  Write allocation                                         Write-allocate
  Controller                                         Finite State Machine
  HDL                                                        Verilog-2001

### Address decomposition

For a 16-bit byte address:

-   `tag = address[15:6]` (10 bits)
-   `index = address[5:2]` (4 bits)
-   `offset = address[1:0]` (2 bits)

The cache has 16 lines. Each line stores one valid bit, a 10-bit tag,
and a 32-bit data block.

-   Data capacity: `16 × 4 bytes = 64 bytes`
-   Data storage: `16 × 32 = 512 bits`
-   Tag and valid storage: `16 × 11 = 176 bits`
-   Total logical storage excluding control logic: `688 bits`

The full 16-bit byte-address space contains 65,536 bytes and 16,384
four-byte memory blocks. Do not incorrectly model it as only 256 blocks.

### Required functional behaviour

**Read hit** 1. Accept the CPU request according to the documented
handshake. 2. Decode tag, index, and offset. 3. Select the indexed cache
line. 4. Check the valid bit and compare tags. 5. Return the byte
selected by the offset. 6. Assert the response/ready signal according to
the documented protocol.

**Read miss** 1. Detect an invalid line or tag mismatch. 2. Request the
aligned four-byte block from main memory. 3. Wait for the memory
response. 4. Refill the selected cache line with the returned block and
requested tag. 5. Set the valid bit. 6. Return the requested byte. 7.
Ensure no stale data is returned and no response is asserted
prematurely.

**Write hit --- write-through** 1. Update the selected byte in the cache
block. 2. Write the same byte to main memory. 3. Preserve the other
three bytes. 4. Complete the CPU request only according to the defined
response protocol.

**Write miss --- write-allocate** 1. Fetch the existing four-byte memory
block. 2. Wait for the memory response. 3. Update the requested byte. 4.
Write the updated block/byte to main memory according to the selected
interface. 5. Allocate the updated block in the cache with the correct
tag and valid bit. 6. Prevent duplicate writes if the controller stalls.

Document byte ordering, block alignment, byte enables, memory latency,
reset behaviour, and back-to-back request handling.

------------------------------------------------------------------------

# PHASE 1 --- Architecture and Core RTL Implementation

## Objective

Design the architecture and implement the foundational cache hardware.
Establish a compiling simulation that demonstrates correct cold misses,
hits, refills, and conflict replacement.

## 1.1 Environment inspection

Check availability and record versions of:

-   Icarus Verilog (`iverilog`)
-   VVP (`vvp`)
-   GTKWave
-   Git
-   Python

If a tool is unavailable, document installation instructions. Do not
assume a tool ran if it was not available.

## 1.2 Architecture and design planning

Before implementing RTL:

1.  Explain direct mapping and its mapping formula.
2.  Derive tag, index, and offset widths.
3.  Calculate cache capacity and storage overhead.
4.  Draw the system block diagram.
5.  Define module interfaces and signal directions.
6.  Define CPU request/response handshaking.
7.  Define main-memory request/response handshaking and latency.
8.  Design and document the controller FSM.
9.  Explain tag comparison, valid-bit checking, refill, and replacement.
10. Document write-through and write-allocate behaviour.

Create:

``` text
docs/
  architecture.md
  address_decomposition.md
  fsm_design.md
  module_interfaces.md

diagrams/
  block_diagram.png
  fsm_diagram.png
```

Use clear Mermaid diagrams or clean vector diagrams where suitable.

## 1.3 Modular RTL implementation

Create these Verilog-2001 modules:

### `rtl/cache_memory.v`

Responsibilities:

-   16-entry data array, 32 bits per entry.
-   16-entry tag array, 10 bits per entry.
-   16 valid bits.
-   Indexed line access.
-   Byte selection.
-   Byte update while preserving other bytes.
-   Cache-line refill.
-   Reset/initialization behaviour.

### `rtl/main_memory.v`

Responsibilities:

-   Behavioral byte-addressable memory model.
-   Full 64 KiB address space, or a clearly justified equivalent
    representation that supports every 16-bit address.
-   Four-byte aligned block reads.
-   Byte-level writes and/or a documented write interface.
-   Deterministic initialization for reproducible tests.
-   Configurable or documented transaction latency.
-   Correct address alignment and byte ordering.

### `rtl/cache_controller.v`

Responsibilities:

-   CPU request acceptance.
-   Address decomposition.
-   Valid-bit and tag comparison.
-   Hit/miss detection.
-   FSM transitions.
-   Memory read/write requests.
-   Cache refill and update control.
-   CPU response signalling.
-   Correct handling of wait states and request stability.

### `rtl/cache_top.v`

Responsibilities:

-   Integrate the controller, cache, and main memory.
-   Expose the CPU-facing interface.
-   Connect all handshake and data signals.
-   Expose useful debug signals for the testbench and waveform.

## 1.4 FSM design

Start with these suggested states, adapting them if the implementation
requires additional states:

-   `IDLE`
-   `COMPARE_TAG`
-   `READ_HIT`
-   `READ_MISS`
-   `MEMORY_READ_WAIT`
-   `REFILL`
-   `WRITE_HIT`
-   `WRITE_MISS`
-   `MEMORY_WRITE_WAIT`
-   `RESPONSE`

For every state, document:

-   Purpose
-   Entry condition
-   Exit condition
-   Outputs/control signals
-   Data movement
-   Wait-state behaviour

Use a clear sequential/combinational coding style. Use non-blocking
assignments in clocked sequential logic.

## 1.5 Initial testbench

Create `testbench/cache_tb.v` and verify:

1.  Reset behaviour.
2.  First access to an empty cache produces a cold miss.
3.  Repeated access to the same address produces a hit.
4.  A different block can be loaded.
5.  Same-index conflicting addresses cause replacement.
6.  The returned byte is correct.
7.  No response occurs before the transaction completes.

Generate a VCD waveform and include the key CPU, cache, memory, and FSM
signals.

## 1.6 Phase 1 compile and review

Compile with Icarus Verilog, with warnings enabled. Run the testbench
using VVP.

Review:

-   Syntax and elaboration errors
-   Width mismatches
-   Inferred latches
-   Blocking/non-blocking assignment mistakes
-   FSM transitions
-   Memory addressing and block alignment
-   Request/response handshake correctness
-   Reset behaviour
-   Stale or premature data responses

### Phase 1 exit criteria

Do not mark Phase 1 complete until:

-   [ ] Architecture and address decomposition are documented.
-   [ ] Module interfaces are documented.
-   [ ] All required RTL modules exist.
-   [ ] Compilation succeeds.
-   [ ] The initial testbench executes.
-   [ ] Cold miss works.
-   [ ] Cache hit works.
-   [ ] Conflict replacement works.
-   [ ] Returned data is correct.
-   [ ] VCD waveform is generated.
-   [ ] Warnings are resolved or explained.
-   [ ] Actual logs and results are saved.

Save:

``` text
results/
  phase1_test_results.txt
  phase1_compile_log.txt
  phase1_waveform.vcd
```

At the end of Phase 1, provide a review containing implementation
summary, changed files, commands run, actual compiler output, tests and
outcomes, failures and fixes, limitations, exit-criteria status, and
remaining work.

**Stop and wait for explicit approval before Phase 2.**

------------------------------------------------------------------------

# PHASE 2 --- Comprehensive Verification, Performance, and Quality Assurance

## Objective

Turn the working prototype into a thoroughly tested and independently
checked cache controller. Verify functional correctness,
timing/handshake behaviour, write policy, edge cases, and
reproducibility.

## 2.1 Comprehensive directed tests

Build a self-checking testbench. Every test must record:

-   Test ID and description
-   Initial conditions
-   Stimulus
-   Expected result
-   Actual result
-   PASS/FAIL

### Cache functionality

1.  Cold cache miss.
2.  Repeated cache hit.
3.  Access to different memory blocks.
4.  Same-index conflict.
5.  Cache replacement.
6.  Re-access after replacement.
7.  Different offsets within the same block.
8.  All four byte positions.

### Read functionality

9.  Correct byte returned on hit.
10. Correct byte returned on miss.
11. Correct full-block refill.
12. Repeated reads.
13. Sequential requests.
14. Back-to-back requests, if supported by the interface.

### Write functionality

15. Write hit.
16. Write miss.
17. Write allocation.
18. Write-through verification.
19. Byte-level write.
20. Preservation of unaffected bytes.
21. Read-after-write consistency.
22. Main-memory consistency after cache replacement.

### Control and timing

23. Reset while idle.
24. Reset between transactions.
25. Delayed memory response.
26. Request held high.
27. Response handshake.
28. No duplicate writes.
29. No premature ready/response signal.
30. No stale response data.

## 2.2 Edge-case testing

Test:

-   `0x0000` and `0xFFFF`
-   Minimum and maximum tag values
-   Minimum and maximum cache indices
-   All four byte offsets
-   Multiple addresses mapping to the same cache line
-   Invalid cache entries
-   Repeated replacement
-   Different memory latency values
-   Reset behaviour

Check address arithmetic, block alignment, byte ordering, and boundary
conditions.

## 2.3 Independent Python reference model

Create a simple independent model in Python that represents:

-   Main memory
-   Cache lines
-   Valid bits
-   Tags
-   Read requests
-   Write requests
-   Hit/miss results
-   Replacement
-   Returned data

Run identical transaction sequences against the Verilog design and
Python model. Compare outputs and final memory/cache behaviour.

The Python model must independently implement the specification. Do not
copy internal RTL logic into the reference model.

Save reproducible input transactions, random seeds, expected outputs,
actual outputs, and failing cases.

## 2.4 Randomized testing

Generate reproducible random transactions covering:

-   Random read addresses
-   Random write addresses
-   Random byte offsets
-   Repeated addresses
-   Conflict-heavy addresses
-   Different memory latency values

Use fixed seeds and compare the Verilog output against the Python
reference model. Preserve any failing seed and transaction sequence for
debugging.

## 2.5 Waveform inspection

Generate VCD files and inspect them in GTKWave.

Include:

-   Clock and reset
-   CPU address, read/write, write data, read data, ready/response
-   Request acceptance
-   Cache hit and miss
-   Tag match
-   Cache index and tag
-   Valid bit
-   FSM state
-   Memory read/write enables
-   Memory address and data
-   Refill signal

Capture representative waveform screenshots for:

1.  Cold miss and refill
2.  Cache hit
3.  Conflict miss and replacement
4.  Write hit
5.  Write miss and write allocation
6.  Back-to-back requests, if supported

Save screenshots under `results/waveforms/`.

## 2.6 Performance measurement

Calculate metrics from actual test runs:

-   Total requests
-   Total reads
-   Total writes
-   Cache hits
-   Cache misses
-   Hit ratio
-   Miss ratio
-   Memory read transactions
-   Memory write transactions
-   Average transaction latency
-   Average memory access time (AMAT), with explicit assumptions

Formulas:

``` text
Hit Ratio  = Cache Hits / Total Cache Requests
Miss Ratio = Cache Misses / Total Cache Requests
AMAT       = Hit Time + (Miss Rate × Miss Penalty)
```

Clearly distinguish theoretical AMAT under stated assumptions from
measured simulation latency. Do not invent clock frequencies, FPGA
timing, or physical hardware performance.

## 2.7 Code quality and synthesis checks

Review:

-   Synthesizable RTL boundaries
-   Combinational/sequential separation
-   FSM coding style
-   Reset logic
-   Latch inference
-   Array indexing
-   Bit-width consistency
-   Memory initialization
-   Race conditions
-   Multiple drivers
-   Unused signals
-   Unreachable states
-   Dead code

If Yosys is installed, run synthesis checks and record warnings and
resource estimates. State clearly which parts are simulation-only. Do
not describe simulation results as FPGA measurements.

### Phase 2 exit criteria

-   [ ] All mandatory directed tests pass.
-   [ ] Edge cases pass.
-   [ ] Randomized tests pass.
-   [ ] Python reference-model comparisons pass.
-   [ ] Waveforms are captured and inspected.
-   [ ] Performance metrics are generated from actual results.
-   [ ] No unexplained critical warnings remain.
-   [ ] Known limitations are documented.
-   [ ] Regression simulation is reproducible.

Generate:

``` text
results/
  complete_test_results.txt
  coverage_summary.md
  performance_metrics.csv
  reference_model_results.txt
  synthesis_review.md
  waveforms/

docs/
  verification_strategy.md
```

At the end of Phase 2, provide a review with evidence and acceptance
status.

**Stop and wait for explicit approval before Phase 3.**

------------------------------------------------------------------------

# PHASE 3 --- Final Report, Repository, Demonstration, and Evaluation Preparation

## Objective

Prepare the complete university submission and make the project easy to
reproduce, inspect, and defend in a technical interview.

## 3.1 IEEE conference-style project report

Create a complete IEEE conference-style report with:

1.  Title
2.  Abstract
3.  Keywords
4.  Introduction
5.  Literature Review
6.  Problem Statement
7.  Objectives
8.  Proposed Solution
9.  System Architecture
10. Address Mapping Methodology
11. Cache Controller FSM
12. RTL Implementation
13. Verification Methodology
14. Results and Discussion
15. Performance Analysis
16. Individual Contributions
17. Limitations
18. Future Scope
19. Conclusion
20. References

Requirements:

-   IEEE two-column conference layout
-   Proper academic language and numbered sections
-   Numbered figures and tables
-   Equation numbering where appropriate
-   Correct citation format
-   Consistent technical terminology
-   Original architecture diagrams
-   Actual simulation results and waveform screenshots
-   No fabricated claims or references
-   Clear distinction between implemented, simulated, synthesized, and
    proposed features

Verify bibliographic details for every reference. Do not invent authors,
titles, publication years, DOIs, or URLs.

Create:

``` text
docs/
  IEEE_Project_Report.tex
  IEEE_Project_Report.pdf
```

Render and inspect the PDF for layout, missing figures, broken
references, overflow, and readability.

## 3.2 Individual contributions

Create a contribution table for all five members, using placeholders
until real details are provided:

-   Member 1: \[Name and actual contribution\]
-   Member 2: \[Name and actual contribution\]
-   Member 3: \[Name and actual contribution\]
-   Member 4: \[Name and actual contribution\]
-   Member 5: \[Name and actual contribution\]

Track actual work in:

-   Architecture
-   RTL implementation
-   Cache/memory implementation
-   Testbench
-   Verification
-   Documentation
-   Integration
-   Presentation

Do not invent contributions or claim that a member completed work
without evidence.

Create `docs/individual_contributions.md`.

## 3.3 Final GitHub repository

Use this structure:

``` text
direct-mapped-cache-controller/
├── README.md
├── LICENSE
├── .gitignore
├── rtl/
│   ├── cache_controller.v
│   ├── cache_memory.v
│   ├── main_memory.v
│   └── cache_top.v
├── testbench/
│   └── cache_tb.v
├── verification/
│   ├── reference_model.py
│   ├── randomized_tests.py
│   └── test_vectors/
├── docs/
│   ├── IEEE_Project_Report.tex
│   ├── IEEE_Project_Report.pdf
│   ├── architecture.md
│   ├── fsm_design.md
│   ├── verification_strategy.md
│   ├── individual_contributions.md
│   └── interview_questions.md
├── diagrams/
│   ├── block_diagram.png
│   └── fsm_diagram.png
├── results/
│   ├── phase1_test_results.txt
│   ├── complete_test_results.txt
│   ├── performance_metrics.csv
│   ├── synthesis_review.md
│   └── waveforms/
├── video/
│   ├── prototype_video_link.md
│   ├── demo_script.md
│   └── recording_checklist.md
├── DEVELOPMENT_LOG.md
├── PHASE_STATUS.md
├── REQUIREMENTS_TRACEABILITY.md
└── TEST_RESULTS.md
```

The README must explain:

-   Project overview and objectives
-   Architecture and specifications
-   Technology and tools
-   Installation
-   Compilation and simulation commands
-   Expected output
-   Actual test results
-   Performance metrics
-   Screenshots
-   Team members and contributions
-   Video link
-   Limitations and future scope

Provide exact commands that reproduce the simulation from a clean
checkout.

Do not commit unnecessary build files or enormous waveform files without
reason. Include useful waveform evidence.

## 3.4 Git and contribution audit

Provide guidance for meaningful commits under each member's own GitHub
account.

Never fabricate historical commits or commit under another person's
identity.

Verify:

-   Repository structure
-   Source files
-   README links
-   Report PDF
-   Video link placeholder or actual link
-   Reproducible build and simulation
-   Clean Git status
-   No passwords, API keys, tokens, or secrets
-   No unnecessary temporary files

Leave placeholders for repository URL and team details until supplied.

## 3.5 Five-minute prototype video

Prepare a demonstration script and recording checklist.

Suggested timing:

  -----------------------------------------------------------------------
  Time                                Content
  ----------------------------------- -----------------------------------
  0:00--0:30                          Project title, problem, and
                                      introduction of all five members

  0:30--1:15                          Architecture, direct mapping,
                                      tag/index/offset

  1:15--2:15                          Verilog modules and FSM

  2:15--4:15                          Live simulation: cold miss, hit,
                                      conflict miss, refill, and
                                      write-through

  4:15--5:00                          Actual results, limitations, and
                                      conclusion
  -----------------------------------------------------------------------

The video must not exceed five minutes. The team must record the actual
video; do not claim it exists until supplied.

Create:

``` text
video/
  demo_script.md
  recording_checklist.md
  prototype_video_link.md
```

## 3.6 Technical interview preparation

Prepare at least 35 meaningful questions and answers. Answers must
reflect the actual implementation.

Cover:

**Fundamentals** - What is cache memory? - Why do processors use
cache? - What is direct mapping? - What are hits and misses? - What is
spatial locality?

**Architecture** - Explain tag, index, and offset. - Why does this
design use 10 tag bits? - How does replacement work? - What is a
conflict miss? - What is a valid bit?

**RTL** - Explain each module. - Explain the FSM. - Why use non-blocking
assignments? - How is a memory block fetched? - How is a byte selected
and updated?

**Verification** - How do you verify a hit? - How did you test
replacement? - What is a reference model? - How did you test random
requests? - What does a waveform prove?

**Performance** - How is hit ratio calculated? - What is miss penalty? -
What is AMAT? - What trade-offs does direct mapping introduce?

**Design decisions** - Why write-through? - Why write-allocate? - What
are the limitations? - How could this be extended to set-associative
mapping? - How could it be implemented on an FPGA?

Create:

``` text
docs/
  interview_questions.md
  project_defense.md
```

## 3.7 Final independent project audit

Act as an external evaluator and review:

1.  Functional correctness
2.  RTL design quality
3.  Architecture clarity
4.  Test coverage
5.  Simulation reproducibility
6.  Performance analysis
7.  Documentation quality
8.  IEEE report formatting
9.  GitHub repository quality
10. Demonstration readiness
11. Individual contribution traceability
12. Technical interview readiness

Produce an evidence-based scorecard containing:

-   Evaluation category
-   Evidence
-   Identified issue
-   Severity
-   Recommended correction
-   Final status

Do not award full marks without evidence.

Run a final clean compilation and full regression after documentation is
complete.

### Phase 3 exit criteria

-   [ ] IEEE report exists and renders correctly.
-   [ ] All diagrams are included.
-   [ ] Actual test results are documented.
-   [ ] GitHub repository is organized.
-   [ ] Reproduction instructions work.
-   [ ] Actual team contributions are recorded.
-   [ ] Five-minute video script and checklist are ready.
-   [ ] Interview preparation is ready.
-   [ ] Final independent audit is complete.
-   [ ] Known limitations are disclosed.
-   [ ] Final regression passes.

------------------------------------------------------------------------

# Project Management and Status Files

Maintain these files throughout development.

### `DEVELOPMENT_LOG.md`

Record dated implementation decisions, files changed, commands executed,
errors, fixes, and test outcomes.

### `PHASE_STATUS.md`

Track every task and its status. Include phase exit criteria and
approval status.

### `REQUIREMENTS_TRACEABILITY.md`

Map every requirement to:

-   Requirement ID and description
-   RTL module or document
-   Test case
-   Actual verification result
-   Evidence file/path
-   Status

### `TEST_RESULTS.md`

Maintain a consolidated test register with test ID, description,
expected output, actual output, PASS/FAIL, and evidence.

## Required phase-end review

At the end of each phase, provide:

1.  What was implemented
2.  Files created or changed
3.  Commands executed
4.  Tool versions
5.  Compilation results
6.  Tests executed and actual outcomes
7.  Failures and fixes
8.  Warnings and their disposition
9.  Current limitations
10. Exit-criteria status
11. Remaining work
12. Recommendation for the next phase

If any acceptance criterion fails, fix it and rerun the relevant tests
before marking the phase complete.

------------------------------------------------------------------------

# Execution Instructions for Claude Code

1.  Inspect the current directory and development environment.
2.  Start **Phase 1 only**.
3.  Use the specifications in this document and sensible documented
    engineering defaults.
4.  Do not ask unnecessary questions. Use placeholders for missing team
    information.
5.  Implement, compile, simulate, debug, and verify Phase 1.
6.  Update all project-management files.
7.  Present the Phase 1 review with evidence.
8.  **Stop and wait for explicit user approval before starting Phase
    2.**
9.  After Phase 2, repeat the review and approval process before Phase
    3.
10. Do not claim the overall project is complete until all three phases'
    exit criteria are met.

**The priority is a correct, reproducible, demonstrable, and defensible
engineering project---not simply a large number of generated files.**

# BEGIN PHASE 1
