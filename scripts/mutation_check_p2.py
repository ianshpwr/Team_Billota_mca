#!/usr/bin/env python3
"""Phase 2 mutation check. Injects known bugs into COPIES of the RTL and runs
both the Phase 1 testbench and the Phase 2 directed testbench against each
mutant. A mutant that survives a testbench marks a coverage gap in it.
Usage: python3 -I scripts/mutation_check_p2.py [repo_root] [work_dir]
"""
import subprocess, shutil, os, sys

root = sys.argv[1] if len(sys.argv) > 1 else "."
work = sys.argv[2] if len(sys.argv) > 2 else "build/mutants_p2"

MUTS = [
 ("M01 byte order reversed on read",            "rtl/cache_memory.v",     "assign byte_o  = block_o[{offset, 3'b000} +: 8];", "assign byte_o  = block_o[{~offset, 3'b000} +: 8];"),
 ("M02 valid bit ignored in hit",               "rtl/cache_controller.v", "wire hit       = cache_valid && tag_match;", "wire hit       = tag_match;"),
 ("M03 tag compare drops bit 9",                "rtl/cache_controller.v", "wire tag_match = (cache_tag == req_tag);", "wire tag_match = (cache_tag[8:0] == req_tag[8:0]);"),
 ("M04 byte write clobbers whole word",         "rtl/cache_memory.v",     "data_array[index]  <= merge_byte(data_array[index], offset, byte_wdata);", "data_array[index]  <= {4{byte_wdata}};"),
 ("M05 read miss does not wait for memory",     "rtl/cache_controller.v", "if (mem_done) next_state = S_REFILL;", "next_state = S_REFILL;"),
 ("M06 refill tag not updated",                 "rtl/cache_memory.v",     "tag_array[index]   <= refill_tag;", "tag_array[index]   <= tag_array[index];"),
 ("M07 write-through skipped",                  "rtl/cache_controller.v", "S_WRITE_HIT:         next_state = S_MEMORY_WRITE_WAIT;", "S_WRITE_HIT:         next_state = S_RESPONSE;"),
 ("M08 block read address unaligned",           "rtl/cache_controller.v", "assign mem_addr  = mem_we ? req_addr : {req_addr[15:2], 2'b00};", "assign mem_addr  = req_addr;"),
 ("M09 memory big-endian block assembly",       "rtl/main_memory.v",      "{ mem[blk_base + 16'd3], mem[blk_base + 16'd2],\n                                 mem[blk_base + 16'd1], mem[blk_base] }", "{ mem[blk_base], mem[blk_base + 16'd1],\n                                 mem[blk_base + 16'd2], mem[blk_base + 16'd3] }"),
 ("M10 stale rdata (loaded too early)",         "rtl/cache_controller.v", "if (state == S_READ_HIT)\n                rdata_reg <= cache_byte;", "if (state == S_COMPARE_TAG)\n                rdata_reg <= cache_byte;"),
 ("M11 write-allocate skips refill",            "rtl/cache_controller.v", "S_WRITE_MISS:        next_state = S_MEMORY_READ_WAIT;", "S_WRITE_MISS:        next_state = S_WRITE_HIT;"),
 ("M12 reset does not clear valid bits",        "rtl/cache_memory.v",     "valid_array <= 16'd0;", "valid_array <= valid_array;"),
 ("M13 memory re-accepts request in DONE",      "rtl/main_memory.v",      "M_DONE:  mstate <= M_IDLE;", "M_DONE:  mstate <= req ? M_BUSY : M_IDLE;"),
 ("M14 memory commits write twice",             "rtl/main_memory.v",      "wire        fire     = (accept && (LAT == 1)) ||\n                           ((mstate == M_BUSY) && (cnt == 16'd1));", "wire        fire     = (accept && (LAT == 1)) ||\n                           ((mstate == M_BUSY) && (cnt == 16'd1)) || (mstate == M_DONE);"),
 ("M15 request re-latched every cycle",         "rtl/cache_controller.v", "if (state == S_IDLE && cpu_req) begin\n                req_addr  <= cpu_addr;", "if (cpu_req) begin\n                req_addr  <= cpu_addr;"),
 ("M16 memory FSM not reset",                   "rtl/main_memory.v",      "            mstate    <= M_IDLE;\n            cnt       <= 16'd0;", "            cnt       <= 16'd0;"),
 ("M17 write hit does not update cache",        "rtl/cache_controller.v", "assign cache_byte_we     = (state == S_WRITE_HIT);", "assign cache_byte_we     = 1'b0;"),
 ("M18 wrong index field",                      "rtl/cache_controller.v", "wire [3:0] req_index  = req_addr[5:2];", "wire [3:0] req_index  = req_addr[6:3];"),
 ("M19 memory writes block base not byte",      "rtl/main_memory.v",      "mem[op_addr] <= op_wdata;", "mem[blk_base] <= op_wdata;"),
 ("M20 response one cycle early",               "rtl/cache_controller.v", "assign cpu_resp_valid = (state == S_RESPONSE);", "assign cpu_resp_valid = (state == S_RESPONSE) || (state == S_READ_HIT);"),
 ("M21 tag compare drops bit 0",                "rtl/cache_controller.v", "wire tag_match = (cache_tag == req_tag);", "wire tag_match = (cache_tag[9:1] == req_tag[9:1]);"),
 ("M22 tag compare drops bit 5",                "rtl/cache_controller.v", "wire tag_match = (cache_tag == req_tag);", "wire tag_match = ({cache_tag[9:6], cache_tag[4:0]} == {req_tag[9:6], req_tag[4:0]});"),
 ("M23 memory latency one cycle too long",      "rtl/main_memory.v",      "localparam LAT = (LATENCY < 1) ? 1 : LATENCY;", "localparam LAT = ((LATENCY < 1) ? 1 : LATENCY) + 1;"),
 ("M24 RESPONSE skips IDLE (request not latched)", "rtl/cache_controller.v", "S_RESPONSE:          next_state = S_IDLE;", "S_RESPONSE:          next_state = cpu_req ? S_COMPARE_TAG : S_IDLE;"),
 ("M25 rdata not cleared on accept (stale)",    "rtl/cache_controller.v", "                rdata_reg <= 8'd0;                 // never show a stale result\n", ""),
 ("M26 refill writes block_reg of previous fill", "rtl/cache_controller.v", "if (state == S_MEMORY_READ_WAIT && mem_done)\n                block_reg <= mem_rdata;", "if (state == S_REFILL)\n                block_reg <= mem_rdata;"),
 ("M27 write miss data lost (no merge after refill)", "rtl/cache_controller.v", "S_REFILL:            next_state = req_we ? S_WRITE_HIT : S_READ_HIT;", "S_REFILL:            next_state = req_we ? S_MEMORY_WRITE_WAIT : S_READ_HIT;"),
 ("M28 cache reset skips data/tag clear (valid cleared)", "rtl/cache_memory.v", "                data_array[i] <= 32'd0;\n                tag_array[i]  <= 10'd0;\n", ""),
]

def build_run(d, tbfiles, defines, rtl, top, params, plusargs):
    out = os.path.join(d, top + ".vvp")
    cmd = ["iverilog", "-g2001", "-I", os.path.join(root, "testbench"), "-s", top, "-o", out] + defines + params + tbfiles + rtl
    c = subprocess.run(cmd, capture_output=True, text=True)
    if c.returncode: return None, "COMPILE ERROR: " + c.stderr[:300]
    r = subprocess.run(["vvp", out] + plusargs, capture_output=True, text=True, cwd=root, timeout=900)
    return r.stdout, ""

def verdict(out):
    if out is None: return "ERR"
    return "detected" if ("ALL TESTS PASSED" not in out) else "SURVIVED"

def stats(out):
    return (out.count("[FAIL]") + out.count("[QFAIL]"), out.count("[MONITOR ERROR]"))

only = sys.argv[3:] if len(sys.argv) > 3 else []
print("%-52s %-9s %-9s %-9s" % ("mutant", "Phase1 TB", "Phase2 TB", "Phase2 TB (variable latency)"))
survivors = 0
for name, f, old, new in MUTS:
    tag = name.split()[0]
    if only and tag not in only: continue
    d = os.path.join(work, tag); shutil.rmtree(d, ignore_errors=True)
    shutil.copytree(os.path.join(root, "rtl"), os.path.join(d, "rtl"))
    p = os.path.join(d, f); s = open(p).read()
    if old not in s:
        print("%-52s PATTERN NOT FOUND" % name); survivors += 1; continue
    open(p, "w").write(s.replace(old, new, 1))
    rtl = [os.path.join(d, "rtl", x) for x in ["main_memory.v", "cache_memory.v", "cache_controller.v", "cache_top.v"]]
    tb = lambda x: os.path.join(root, "testbench", x)
    o1, e1 = build_run(d, [tb("cache_tb.v")], [], rtl, "cache_tb", [], ["+novcd"])
    o2, e2 = build_run(d, [tb("cache_tb_directed.v")], [], rtl, "cache_tb_directed", [], [])
    rtl_vl = [os.path.join(d, "rtl", x) for x in ["cache_memory.v", "cache_controller.v"]]
    o3, e3 = build_run(d, [tb("cache_tb_directed.v"), tb("cache_top_varlat.v")], ["-DVARLAT"], rtl_vl, "cache_tb_directed",
                       ["-P", "cache_tb_directed.MEM_LATENCY=8"], []) if "main_memory.v" not in f else (None, "")
    v1, v2 = verdict(o1), verdict(o2)
    v3 = verdict(o3) if o3 is not None else "n/a (mem model)"
    f2 = stats(o2) if o2 else (0, 0)
    print("%-52s %-9s %-9s %-9s  [P2: fails=%d monitor=%d]" % (name, v1, v2, v3, f2[0], f2[1]))
    sys.stdout.flush()
    if v2 == "SURVIVED" or v2 == "ERR": survivors += 1
print("\nMutants not detected by the Phase 2 directed testbench: %d" % survivors)
