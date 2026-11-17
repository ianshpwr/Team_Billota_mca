# Module Interfaces and Handshake Protocols

Conventions: Verilog-2001. Single clock `clk`, rising-edge triggered.
Reset `rst` is **synchronous and active high**. All signals are sampled on the
rising edge of `clk`. "Cycle N" means the clock period before the Nth rising edge.

## Hierarchy

```
cache_top
├── u_ctrl  : cache_controller   (synthesizable)
├── u_cache : cache_memory       (synthesizable)
└── u_mem   : main_memory        (simulation model)
```

## 1. CPU-facing interface (`cache_top` / `cache_controller`)

| Signal | Dir | Width | Description |
|---|---|---|---|
| `clk` | in | 1 | Clock |
| `rst` | in | 1 | Synchronous reset, active high |
| `cpu_req` | in | 1 | Request valid |
| `cpu_we` | in | 1 | 1 = write one byte, 0 = read one byte |
| `cpu_addr` | in | 16 | Byte address |
| `cpu_wdata` | in | 8 | Byte to write (ignored for reads) |
| `cpu_ready` | out | 1 | High only in `IDLE`: a request can be accepted this cycle |
| `cpu_resp_valid` | out | 1 | One-cycle pulse: the transaction is complete |
| `cpu_rdata` | out | 8 | Read data (valid while `cpu_resp_valid` for reads); 0 for writes |

### CPU protocol

1. **Acceptance.** A request is accepted on a rising edge where
   `cpu_req && cpu_ready` are both 1. `cpu_addr`, `cpu_we`, `cpu_wdata` are
   latched at that edge. The CPU may change or drop them afterwards
   (the testbench deliberately scrambles them to prove this).
2. **Completion.** `cpu_resp_valid` is high for exactly one cycle when the
   operation is complete. For a read, `cpu_rdata` holds the byte in that cycle.
   For a write, memory has already been updated (write-through is synchronous).
3. **No premature response.** `cpu_resp_valid` is only asserted in the `RESPONSE`
   state, which is reached only after every required memory operation
   (read-refill and/or write-through) has signalled `mem_done`.
4. **No stale data.** `cpu_rdata` is cleared on acceptance and loaded only in
   `READ_HIT`, which always reads the cache array *after* any refill.
5. **Single outstanding request.** `cpu_ready` is low from acceptance until the
   cycle after `cpu_resp_valid`.
6. **Request held high.** If `cpu_req` stays high, the controller accepts a new
   request in the first `IDLE` cycle after each response. A held-high request is
   therefore executed repeatedly, once per transaction (no hang, no double
   execution within one transaction). Back-to-back requests are supported, one
   `IDLE` cycle apart; there is no pipelining.
   *Verification status: back-to-back requests (one idle cycle apart, test D-14) and
   `cpu_req` held high across multiple transactions while the next request is
   presented (test D-26: 12 mixed ops, 6 identical reads, 5 identical writes -> exactly
   5 memory writes) are verified in Phase 2.*
7. **Reset.** While `rst` is high the FSM returns to `IDLE`, all valid bits are
   cleared and any memory transaction in flight is aborted. Memory *contents*
   persist across reset; a write that had not yet committed is lost.
   *Verification status: reset while idle / between transactions (D-23, D-24) and reset
   asserted in the MIDDLE of a read miss, write hit and write miss at every cycle
   offset (D-24R/W/A, all L) are verified in Phase 2. A write that had committed
   before the reset edge persists; one that had not is lost; the controller always
   returns to a clean IDLE with all lines invalid and no spurious response.*

### Documented latency (clock cycles, accept edge → edge that samples `cpu_resp_valid`)

`L` = main-memory latency.

| Operation | Cycles | `L = 4` |
|---|---|---|
| Read hit | 3 | 3 |
| Read miss | 5 + L | 9 |
| Write hit | 4 + L | 8 |
| Write miss (allocate) | 6 + 2L | 14 |

These formulas are checked on **every** transaction by the testbench monitor
(Phase 1 `P1-14b` at `L = 1, 2, 4, 8`; Phase 2 monitor and test `L-01` at 22 fixed latencies from 0 to 1000 and with random per-transaction latency).

## 2. Controller ↔ cache array (`cache_controller` ↔ `cache_memory`)

| Signal | Dir (from controller) | Width | Description |
|---|---|---|---|
| `cache_index` | out | 4 | Line select = `req_addr[5:2]` |
| `cache_offset` | out | 2 | Byte select = `req_addr[1:0]` |
| `cache_valid` | in | 1 | Valid bit of the selected line (combinational) |
| `cache_tag` | in | 10 | Tag of the selected line (combinational) |
| `cache_byte` | in | 8 | Selected byte of the selected line (combinational) |
| `cache_refill_en` | out | 1 | Write whole line: data, tag, set valid |
| `cache_refill_tag` | out | 10 | Tag for the refill = `req_addr[15:6]` |
| `cache_refill_data` | out | 32 | Block for the refill (from memory) |
| `cache_byte_we` | out | 1 | Replace one byte, keep the other three |
| `cache_byte_wdata` | out | 8 | Byte to write |

`refill_en` has priority over `byte_we`; the controller never asserts both.
`cache_memory` additionally exposes `block_o[31:0]` (whole selected block) for
debug and tests.

## 3. Controller ↔ main memory (`cache_controller` ↔ `main_memory`)

| Signal | Dir (from controller) | Width | Description |
|---|---|---|---|
| `mem_req` | out | 1 | Transaction request, held until `mem_done` |
| `mem_we` | out | 1 | 1 = byte write, 0 = block read |
| `mem_addr` | out | 16 | Reads: block-aligned (`[1:0] = 00`). Writes: exact byte address |
| `mem_wdata` | out | 8 | Byte to write |
| `mem_done` | in | 1 | One-cycle completion pulse |
| `mem_rdata` | in | 32 | Aligned 4-byte block, valid with `mem_done` for reads |

`main_memory` parameter: `LATENCY` (default 4, values < 1 clamp to 1).

### Memory protocol

* Cycle 0 = first cycle in which `mem_req` is high and the memory is idle.
  `mem_done` is high in cycle `LATENCY`.
* `mem_req`, `mem_we`, `mem_addr`, `mem_wdata` stay stable until `mem_done`.
* A write is committed **exactly once**, on the edge that enters the memory's
  `DONE` state. The memory ignores `mem_req` while `BUSY`/`DONE`, so a request
  still being held in the `mem_done` cycle cannot be re-accepted.
  The controller leaves the wait state on `mem_done`, so `mem_req` is low in the
  following cycle.
* Reads return `{mem[A+3], mem[A+2], mem[A+1], mem[A]}`, `A = addr & ~3`.
* Write-through is **byte granular** (one byte per write transaction).

## 4. Observability ports (`cache_top`)

`mem_*` bus signals and `dbg_state[3:0]`, `dbg_lookup`, `dbg_tag_match`,
`dbg_hit`, `dbg_line_valid`, `dbg_tag[9:0]`, `dbg_index[3:0]`, `dbg_offset[1:0]`,
`dbg_refill`, `dbg_byte_we` are output-only observation points for the testbench
and waveform viewer. `dbg_hit` is only meaningful when `dbg_lookup = 1`
(`COMPARE_TAG`); outside that state it is a free-running combinational value.

## 5. `main_memory` initial contents

`mem[a] = (a[7:0] ^ a[15:8]) + 8'h5A` (mod 256). Deterministic; restated
independently in the testbench scoreboard (and, in Phase 2, in the Python model).
