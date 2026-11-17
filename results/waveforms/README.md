# Waveform evidence (Phase 2.5)

## Viewer used (be precise about this)

**Surfer 0.7.0 (WebAssembly build served locally), not GTKWave.** GTKWave could not be
installed in the development environment (Homebrew no longer ships it; no usable macOS
distribution was available). Surfer is a waveform viewer that opens VCD files natively
(`brew install surfer` also gives the native app, version 0.7.0). Because the native window
could not be screen-captured from the automation session, the screenshots were taken from
Surfer's web build (`scripts/fetch_surfer_web.sh`), served from the same local origin as the
VCD files (`scripts/serve_waves.py`) and driven with browser automation. The PNGs are
genuine screenshots of the Surfer viewer displaying the simulator's VCD output.
They are **not** Python-rendered traces and are **not** GTKWave screenshots.
The text trace in `results/phase1_waveform_trace.txt` (Phase 1) remains a script
rendering and is labelled as such.

## How each image was produced

1. `vvp build/vec4.vvp +vec=verification/test_vectors/<scenario>.vec +vcd=results/waveforms/<scenario>.vcd`
   (`testbench/cache_tb_vec.v`, memory latency L = 4; only the curated `wave_probe` signals are dumped).
2. Surfer opens the VCD in a 720 x 520 px browser viewport; commands `scope_add cache_tb_vec.wp`, `toggle_side_panel`, `zoom_fit` are typed into Surfer's command prompt; the screenshot (720 x 470 px) is the waveform area. A narrow viewport is used on purpose: Surfer's text has a fixed size in CSS pixels, so a narrow capture keeps it legible when the image is printed at page width.
3. Time axis is in ps; the clock period is 10 000 ps (10 ns simulated).

## Signals shown (spec 2.5)

`clk`, `rst`, `cpu_req`, `cpu_we`, `cpu_addr`, `cpu_wdata`, `cpu_rdata`, `cpu_ready`, `cpu_resp_valid` (request
acceptance = `cpu_req & cpu_ready`), `dbg_lookup`, `dbg_hit`, `dbg_tag_match`, `dbg_line_valid`, `dbg_tag` (tag stored in
the indexed line), `lat_addr` / `req_tag` / `req_index` / `req_offset` (latched request), `dbg_refill`, `dbg_byte_we`,
`mem_req`, `mem_we`, `mem_addr`, `mem_wdata`, `mem_done`, `mem_rdata`, `dbg_state` (numeric) and one-hot state flags.

State legend: `dbg_state` 0 IDLE, 1 COMPARE_TAG, 2 READ_HIT, 3 READ_MISS, 4 MEMORY_READ_WAIT, 5 REFILL, 6 WRITE_HIT,
7 WRITE_MISS, 8 MEMORY_WRITE_WAIT, 9 RESPONSE. One-hot flags: `st_idle`, `st_cmp` (COMPARE_TAG), `st_rhit`, `st_rmiss`,
`st_rwait`, `st_refill`, `st_whit`, `st_wmiss`, `st_wwait`, `st_resp`.
(Registers show `x` only before the first clock edge / reset, which is expected.)

## Screenshots and what was inspected

| Scenario | Image / VCD | Transactions (from `verification/test_vectors/*.vec`, DUT log) | Observations confirmed in the waveform |
|---|---|---|---|
| 1. Cold miss and refill | `wave_cold_miss_refill.png/.vcd` | read 0x0004: miss, 9 cycles, byte 0x5E | After reset release `cpu_req` rises while `cpu_ready=1`; `dbg_lookup` pulses with `dbg_hit=0`, `dbg_line_valid=0`; FSM 1 -> 3 -> 4 (4 wait cycles) -> 5 -> 2 -> 9 -> 0; `mem_req` high from READ_MISS until `mem_done`, `mem_addr=0004`; `mem_rdata=61605F5E` is returned with `mem_done`; `dbg_refill` pulses one cycle; the stored tag then reads 000 and `dbg_line_valid=1`; `cpu_resp_valid` pulses once carrying `cpu_rdata=5E`; `cpu_wdata`/`cpu_addr` change after acceptance without affecting the result (request latched) |
| 2. Cache hit | `wave_cache_hit.png/.vcd` | read 0x0004 miss (9), read 0x0004 hit (3), read 0x0005 hit (3) | The two hits go IDLE -> COMPARE_TAG -> READ_HIT -> RESPONSE with `dbg_hit=1`, no `mem_req`, no `dbg_refill`; response 3 cycles after acceptance |
| 3. Conflict miss and replacement | `wave_conflict_replace.png/.vcd` | 0x0004 miss, 0x0044 miss (same index 1, tag 000 -> 001), 0x0004 miss again | At the second access `dbg_lookup` shows `dbg_line_valid=1` but `dbg_hit=0` (tag mismatch); a full refill follows; `dbg_tag` changes 000 -> 001 -> 000; `mem_rdata` = `A1A09F9E` (block 0x0044) then `61605F5E` again |
| 4. Write hit | `wave_write_hit.png/.vcd` | read 0x0104 (miss), write 0x0105=0xA1 (hit, 8 cycles), read 0x0105 (hit, A1) | On the write: `dbg_hit=1`; `dbg_byte_we` pulses for ONE cycle in WRITE_HIT, followed by MEMORY_WRITE_WAIT with `mem_req=1`, `mem_we=1`, `mem_addr=0105`, `mem_wdata=A1` held until `mem_done`; no block read; response only after `mem_done` |
| 5. Write miss and write allocation | `wave_write_miss_alloc.png/.vcd` | write 0x0208=0x55 (miss, 14 cycles), read 0x0209 (hit, 0x65), read 0x0208 (hit, 0x55) | `dbg_hit=0` -> WRITE_MISS -> MEMORY_READ_WAIT (read request, `mem_we=0`) -> REFILL (tag 008 allocated, valid=1) -> WRITE_HIT (`dbg_byte_we`) -> MEMORY_WRITE_WAIT (`mem_we=1`, `mem_wdata=55`) -> RESPONSE; the following reads hit and return the preserved byte 0x65 and the written 0x55 |
| 6. Back-to-back requests | `wave_back_to_back.png/.vcd` | 7 requests: 3 misses, 2 hits, 1 write hit, 1 read hit | Next request accepted in the first IDLE cycle after each response (one idle cycle between transactions); `cpu_ready` low from acceptance until after the response; no overlap/pipelining |

Each VCD is reproducible with `make phase2` (the regression regenerates the VCDs; screenshots are regenerated
manually with the steps above).
