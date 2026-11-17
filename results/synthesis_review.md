# Synthesis and Lint Review (Phase 2.7)

Raw output: `results/synthesis_review_raw.txt` (regenerate with `sh scripts/synthesis_review.sh`).
Tools: Yosys 0.71, Verilator 5.054, Icarus Verilog 13.0.

**Scope and honesty note.** Everything below is the result of running synthesis/lint *tools* on the RTL.
It is **not** an FPGA or ASIC implementation: no place-and-route, no timing analysis, no clock-frequency figure, no power.
The iCE40 numbers are the technology-mapper's LUT4/flip-flop count only. `rtl/main_memory.v` is a **simulation model**
and is excluded from synthesis (blackboxed at top level).

## Simulation-only versus synthesizable parts

| File | Synthesizable? | Notes |
|---|---|---|
| `rtl/cache_controller.v` | Yes | Three-block FSM, non-blocking sequential assignments, `default:` branch, sync reset |
| `rtl/cache_memory.v` | Yes | 16-entry flop-based arrays, `for` loop with constant bounds in reset, function-based byte merge |
| `rtl/cache_top.v` | Yes (wiring) | Instantiates `main_memory`, so the *whole* top is a simulation top |
| `rtl/main_memory.v` | **No (model)** | 64 KiB array, `initial` fill loop, behavioural latency counter |
| `testbench/*` | No | Hierarchical references, `$display`, `force`-free pokes, file I/O |

## Results

| Check | Result |
|---|---|
| Verilator lint `-Wall`, `cache_controller` | no warnings |
| Verilator lint `-Wall`, `cache_memory` | no warnings |
| Verilator lint `-Wall`, `cache_top` (+ memory model) | 1 warning: `UNUSEDSIGNAL cache_block` (see below) |
| Yosys `proc; opt_clean; check -assert`, each module and `cache_top` (memory blackboxed) | 0 problems; no latches, no multiple drivers, no combinational loops |
| Yosys FSM detection | `state` not re-encoded: *"Register is connected to module port"* (it drives `dbg_state`); no recoding benefit claimed |
| iCE40 LUT4 mapping (mapper estimate only) | `cache_controller`: 69 `SB_DFFESR` + 42 `SB_LUT4`; `cache_memory`: 688 `SB_DFFESR` + 736 `SB_LUT4` (sum 757 flip-flops + 778 LUT4, the synthesizable part of the design) |
| Generic gate-level synthesis | `cache_controller` 143 cells (69 flops); `cache_memory` 1963 cells (688 flops, 531 `$_MUX_`) |
| Yosys warnings | `ABC: Warning: The network is combinational` (37x, benign: ABC prints it when optimising purely combinational cones); `Lexer warning: SystemVerilog keyword 'bit'` (2x, from Yosys' own `abc9_map.v` library file, not the project) |

## Review checklist (plan 2.7)

| Item | Finding |
|---|---|
| Synthesizable RTL boundaries | Clear; only `main_memory.v` is a model (documented in its header) |
| Combinational / sequential separation | State register, next-state logic, datapath registers and Moore outputs are separate blocks/assigns |
| FSM coding style | Binary encoding, default-to-IDLE recovery for codes 10-15 (tested by E-11); no unreachable *reachable-state* issues: all 10 states and 17 transitions are exercised |
| Reset logic | Synchronous, active high; controller state, request registers, cache valid/tag/data and the memory FSM are reset; memory array is not (by design) |
| Latch inference | None (Yosys `check -assert`, PROC_DLATCH reported "No latch inferred") |
| Array indexing | All indices are 4-bit (`index`) or 16-bit address slices; no out-of-range access possible; `byte_o` uses `[{offset,3'b000} +: 8]` |
| Bit-width consistency | Verilator `-Wall` (WIDTH checks enabled) reports none for the synthesizable modules |
| Memory initialisation | Cache arrays cleared by reset (no X after reset, test D-00); main memory filled by the `initial` block (simulation only) |
| Race conditions | Sequential logic uses non-blocking assignments only; testbench drives on the falling edge and samples on the rising edge |
| Multiple drivers | None (Yosys `check`) |
| Unused signals | `cache_block` wire in `cache_top` (the `block_o` debug output of `cache_memory`); `dbg_tag_match`/other `dbg_*` are outputs for observation. Left as is: removing it would change verified RTL for no functional benefit |
| Unreachable states | Codes 10-15 are unreachable in normal operation and recover to IDLE (E-11); all encoded states 0-9 reachable (C-01) |
| Dead code | None identified. `READ_MISS`/`WRITE_MISS` are intentionally distinct 1-cycle states with identical outputs (kept for waveform/statistics clarity, documented in `docs/fsm_design.md`) |

## Warning dispositions

| Warning | Disposition |
|---|---|
| Verilator `UNUSEDSIGNAL cache_block` | Explained: intentionally unconnected debug output; no functional effect |
| Yosys/ABC "network is combinational" | Explained: benign tool message |
| Yosys lexer `bit` keyword | Explained: originates in Yosys' own library file |
| Icarus Verilog `-Wall` | No warnings for RTL or any testbench (`build/compile_warnings.txt` empty) |

## Resource-estimate context

The 688 flip-flops in `cache_memory` equal the specified logical storage (16 x (32 data + 10 tag + 1 valid)); the 736 LUT4 are
dominated by the 16:1 read muxes (data) and the per-entry write/reset steering. Storing the arrays as flops (with
synchronous reset of every entry, decision D10) is simple but not area-efficient; a block-RAM implementation would need
the reset-to-zero removed and valid bits kept in flops. This is a design observation, not a measured result.
