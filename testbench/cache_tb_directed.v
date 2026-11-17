//==============================================================================
// cache_tb_directed.v  --  Phase 2 directed, self-checking testbench (sim only)
//------------------------------------------------------------------------------
// D-01..D-30 : the 30 mandatory directed tests of the plan (section 2.1)
// E-01..E-12 : edge cases (section 2.2)
// L-01       : latency formulas, X-01: illegal-state recovery
// Every test prints: ID + description, initial conditions, stimulus, then each
// check with expected / actual / PASS-FAIL, then a [TEST-RESULT] line.
//
// Parameters : MEM_LATENCY (memory latency, cycles; with -DVARLAT it is the MAX
//              of a pseudo-random per-transaction latency),
//              EXHAUSTIVE (1 = full 64 KiB write sweep + read sweep, else a
//              strided subset).
// Plusargs   : +vcd=<file> writes a waveform.
//==============================================================================
`timescale 1ns/1ps

module cache_tb_directed;

    parameter MEM_LATENCY = 4;
    parameter EXHAUSTIVE  = 0;

    `include "tb_common.vh"

    integer c0;
    integer i, j, k, t, b, bad, mr0, mw0, mc0, me0, nh0, nm0, ia;
    integer kmax, stride, idx_v, bit_v, errs;
    reg [15:0] aa, a2, base_a;
    reg [9:0]  tg, tg2;
    reg [3:0]  ix;
    reg [7:0]  dd;
    reg [31:0] blk, expb;
    reg        hit_exp;
    integer    first_lat;

    reg [8*128-1:0] vcd_name;
    initial begin
        if ($value$plusargs("vcd=%s", vcd_name)) begin
            $dumpfile(vcd_name);
            $dumpvars(0, cache_tb_directed);
        end
    end

    // expected block after replacing byte `off` of `blk0` with `v` (independent of the RTL function)
    function [31:0] merged;
        input [31:0] blk0;
        input [1:0]  off;
        input [7:0]  v;
        reg   [31:0] mask;
        begin
            mask   = 32'hFF << (8 * off);
            merged = (blk0 & ~mask) | ({24'h0, v} << (8 * off));
        end
    endfunction

    function [31:0] mem_block;      // block as stored in the DUT's main memory
        input [15:0] a;
        reg   [15:0] bb;
        begin
            bb = {a[15:2], 2'b00};
            mem_block = {dut.u_mem.mem[bb+16'd3], dut.u_mem.mem[bb+16'd2],
                         dut.u_mem.mem[bb+16'd1], dut.u_mem.mem[bb]};
        end
    endfunction

    // --------------------------------------------------------------------
    // Reset-in-flight sweep: op 0 = read miss, 1 = write hit, 2 = write miss
    // --------------------------------------------------------------------
    task reset_sweep;
        input integer op;
        reg [15:0] A;
        integer kk, kmx, strd, nsteps;
        begin
            kmx  = 12 + 2 * MEM_LATENCY;
            strd = (kmx > 60) ? (kmx / 30) : 1;
            nsteps = 0;
            for (kk = 0; kk <= kmx; kk = kk + strd) begin
                A  = 16'h0A00 + (((kk % 16) * 4) + (kk % 4)) + ((kk / 16) * 16'h0040);
                dd = 8'hC0 + kk[5:0];
                do_reset(2);
                if (op == 1) do_read(A);                       // line cached -> the write is a hit
                cpu_access_abort((op != 0), A, dd, kk);
                qcheck("valid bits cleared by reset",              0, dut.u_cache.valid_array);
                qcheck("FSM back in IDLE",                         0, dbg_state);
                qcheck("cpu_ready high after reset",               1, cpu_ready);
                qcheck("no response pending after reset",          0, cpu_resp_valid);
                qcheck("mem_req low after reset",                  0, mem_req);
                qcheck("memory byte = committed-or-original",      shadow[A], dut.u_mem.mem[A]);
                do_read(A);
                qcheck("post-reset access is a MISS",              0, last_hit);
                qcheck("post-reset data equals memory image",      shadow[A], rd_result);
                nsteps = nsteps + 1;
            end
        end
    endtask

    initial begin
        rst = 1'b1; cpu_req = 1'b0; cpu_we = 1'b0; cpu_addr = 16'h0; cpu_wdata = 8'h0;
        repeat (4) @(posedge clk);
        @(negedge clk); rst = 1'b0;
        @(negedge clk);

        $display("==== Phase 2 directed testbench start: MEM_LATENCY=%0d (effective %0d) EXHAUSTIVE=%0d ====",
                 MEM_LATENCY, LATC, EXHAUSTIVE);

        begin_test("D-00", "Power-on reset initialises all storage (no X values)", "first reset after simulation start; nothing accessed yet", "inspect valid/tag/data arrays and visible outputs");
        check_eq("D-00a", "valid bits all 0",                           0, dut.u_cache.valid_array);
        for (i = 0; i < 16; i = i + 1) begin
            qcheck("line has no X bits in tag/data", 0, (^{cblk(i), ctag(i)} === 1'bx));
        end
        qflush("D-00b", "all 16 tag/data entries are X-free after reset");
        check_eq("D-00c", "CPU/memory outputs are known (no X)",        0, (^{cpu_ready, cpu_resp_valid, cpu_rdata, mem_req, mem_we, dbg_state} === 1'bx));
        end_test;

        // ================================================================
        // CACHE FUNCTIONALITY (spec tests 1-8)
        // ================================================================
        begin_test("D-01", "Cold cache miss", "after reset, all 16 lines invalid", "read 0x0004 (tag 0, index 1, offset 0)");
        do_reset(2);
        check_eq("D-01a", "line 1 invalid before the access",           0, cval(1));
        mr0 = tot_mem_rd; mw0 = tot_mem_wr;
        do_read(16'h0004);
        check_eq("D-01b", "access classified as MISS",                  0, last_hit);
        check_eq("D-01c", "returned byte equals memory image",          shadow[16'h0004], rd_result);
        check_eq("D-01d", "exactly one block read from memory",         mr0 + 1, tot_mem_rd);
        check_eq("D-01e", "no memory write",                            mw0, tot_mem_wr);
        check_eq("D-01f", "line 1 valid after refill",                  1, cval(1));
        check_eq("D-01g", "line 1 tag = 0x000",                         10'h000, ctag(1));
        check_eq("D-01h", "line 1 block = full 4-byte memory block",    shadow_block(16'h0004), cblk(1));
        end_test;

        begin_test("D-02", "Repeated cache hit", "line 1 holds block 0x0004..07 (from D-01)", "read 0x0004 three times");
        for (i = 0; i < 3; i = i + 1) begin
            mr0 = tot_mem_rd;
            do_read(16'h0004);
            check_eq("D-02a", "repeat access is HIT",                   1, last_hit);
            check_eq("D-02b", "returned byte correct",                  shadow[16'h0004], rd_result);
            check_eq("D-02c", "no memory read on hit",                  mr0, tot_mem_rd);
        end
        end_test;

        begin_test("D-03", "Access to different memory blocks", "line 1 valid; lines 2,3,4 invalid", "read 0x0008, 0x000C, 0x0010 then re-read all");
        rd_chk("D-03a", "0x0008 (index 2) cold MISS",                   16'h0008, 1'b0);
        rd_chk("D-03b", "0x000C (index 3) cold MISS",                   16'h000C, 1'b0);
        rd_chk("D-03c", "0x0010 (index 4) cold MISS",                   16'h0010, 1'b0);
        rd_chk("D-03d", "0x0004 still HIT (different line)",            16'h0004, 1'b1);
        rd_chk("D-03e", "0x0008 still HIT",                             16'h0008, 1'b1);
        rd_chk("D-03f", "0x0010 still HIT",                             16'h0010, 1'b1);
        check_eq("D-03g", "four lines valid",                           4, count_valid(0));
        end_test;

        begin_test("D-04", "Same-index conflict", "line 1 holds tag 0x000; lines 2-4 valid", "read 0x0044 (tag 1, index 1) which collides with 0x0004");
        mr0 = tot_mem_rd;
        do_read(16'h0044);
        check_eq("D-04a", "conflicting address is MISS",                0, last_hit);
        check_eq("D-04b", "miss happened on a VALID line (conflict)",   1, m_line_was_valid);
        check_eq("D-04c", "returned byte correct",                      shadow[16'h0044], rd_result);
        check_eq("D-04d", "one block refill",                           mr0 + 1, tot_mem_rd);
        end_test;

        begin_test("D-05", "Cache replacement", "after D-04", "inspect line 1 and the neighbouring lines");
        check_eq("D-05a", "line 1 tag replaced by 0x001",               10'h001, ctag(1));
        check_eq("D-05b", "line 1 data replaced by block 0x0044..47",   shadow_block(16'h0044), cblk(1));
        check_eq("D-05c", "line 1 still valid",                         1, cval(1));
        check_eq("D-05d", "line 2 untouched",                           shadow_block(16'h0008), cblk(2));
        check_eq("D-05e", "line 3 untouched",                           shadow_block(16'h000C), cblk(3));
        check_eq("D-05f", "line 4 untouched",                           shadow_block(16'h0010), cblk(4));
        check_eq("D-05g", "valid-line count unchanged",                 4, count_valid(0));
        end_test;

        begin_test("D-06", "Re-access after replacement", "line 1 holds tag 0x001", "read 0x0004 (evicted), 0x0044 (now evicted), 0x0004 again");
        rd_chk("D-06a", "evicted block 0x0004 -> MISS",                 16'h0004, 1'b0);
        check_eq("D-06b", "line 1 tag back to 0x000",                   10'h000, ctag(1));
        rd_chk("D-06c", "0x0044 evicted in turn -> MISS",               16'h0044, 1'b0);
        rd_chk("D-06d", "0x0044 now HIT",                               16'h0044, 1'b1);
        rd_chk("D-06e", "0x0004 -> MISS again",                         16'h0004, 1'b0);
        end_test;

        begin_test("D-07", "Different offsets within the same block", "reset", "read offset 0..3 of 0x0020 and offset 3..0 of 0x0030");
        do_reset(2);
        rd_chk("D-07a", "0x0020 (offset 0) cold MISS",                  16'h0020, 1'b0);
        rd_chk("D-07b", "0x0021 (offset 1) HIT",                        16'h0021, 1'b1);
        rd_chk("D-07c", "0x0022 (offset 2) HIT",                        16'h0022, 1'b1);
        rd_chk("D-07d", "0x0023 (offset 3) HIT",                        16'h0023, 1'b1);
        rd_chk("D-07e", "0x0033 (offset 3 first) cold MISS",            16'h0033, 1'b0);
        rd_chk("D-07f", "0x0032 (offset 2) HIT",                        16'h0032, 1'b1);
        rd_chk("D-07g", "0x0031 (offset 1) HIT",                        16'h0031, 1'b1);
        rd_chk("D-07h", "0x0030 (offset 0) HIT",                        16'h0030, 1'b1);
        end_test;

        begin_test("D-08", "All four byte positions map to the right block lane", "reset", "first-miss at each offset 0..3 in separate blocks; compare to block bits");
        do_reset(2);
        for (i = 0; i < 4; i = i + 1) begin
            aa = 16'h0100 + (i * 4) + i;                // block 0x0100+4i, offset i
            ix = aa[5:2];
            do_read(aa);
            qcheck("byte equals memory image",                        shadow[aa], rd_result);
            qcheck("byte equals cache block lane (offset*8+:8)",      cblk(ix) >> (8 * i) & 32'hFF, {24'h0, rd_result});
            qcheck("miss on first touch",                             0, last_hit);
        end
        qflush("D-08a", "offsets 0..3 select bits [7:0],[15:8],[23:16],[31:24]");
        end_test;

        // ================================================================
        // READ FUNCTIONALITY (9-14)
        // ================================================================
        begin_test("D-09", "Correct byte returned on hit", "reset; fill all 16 lines (tag 8)", "read all 64 bytes of the cached 64-byte window");
        do_reset(2);
        for (i = 0; i < 16; i = i + 1) do_read(16'h0200 + 4 * i);
        nh0 = tot_hit;
        for (i = 0; i < 64; i = i + 1) begin
            do_read(16'h0200 + i);
            qcheck("hit", 1, last_hit);
            qcheck("hit byte correct", shadow[16'h0200 + i], rd_result);
        end
        qflush("D-09a", "64 hit reads return the correct byte");
        check_eq("D-09b", "64 additional hits counted",                 nh0 + 64, tot_hit);
        end_test;

        begin_test("D-10", "Correct byte returned on miss", "reset", "one cold miss in each of the 16 lines (offset varies)");
        do_reset(2);
        for (i = 0; i < 16; i = i + 1) begin
            aa = 16'h0340 + 4 * i + (i % 4);
            do_read(aa);
            qcheck("miss", 0, last_hit);
            qcheck("miss byte correct", shadow[aa], rd_result);
        end
        qflush("D-10a", "16 cold misses return the correct byte");
        end_test;

        begin_test("D-11", "Correct full-block refill", "after D-10", "compare every line (valid, tag, 32-bit data) with memory");
        for (i = 0; i < 16; i = i + 1) begin
            aa = 16'h0340 + 4 * i;
            qcheck("line valid",      1, cval(i));
            qcheck("line tag 0x00D",  aa[15:6], ctag(i));
            qcheck("line data",       shadow_block(aa), cblk(i));
        end
        qflush("D-11a", "all 16 lines refilled with the full memory block");
        check_eq("D-11b", "16 valid lines",                             16, count_valid(0));
        end_test;

        begin_test("D-12", "Repeated reads", "reset", "read 0x0124 twenty times");
        do_reset(2);
        mr0 = tot_mem_rd; nh0 = tot_hit; nm0 = tot_miss;
        for (i = 0; i < 20; i = i + 1) begin
            do_read(16'h0124);
            qcheck("byte correct", shadow[16'h0124], rd_result);
        end
        qflush("D-12a", "20 reads all return the correct byte");
        check_eq("D-12b", "exactly one miss",                           nm0 + 1, tot_miss);
        check_eq("D-12c", "19 hits",                                    nh0 + 19, tot_hit);
        check_eq("D-12d", "exactly one memory read",                    mr0 + 1, tot_mem_rd);
        end_test;

        begin_test("D-13", "Sequential requests", "reset", "read 0x0000..0x007F byte by byte (two tags over 16 lines)");
        do_reset(2);
        nh0 = tot_hit; nm0 = tot_miss; mr0 = tot_mem_rd;
        for (i = 0; i < 128; i = i + 1) begin
            do_read(i);
            qcheck("sequential byte correct", shadow[i], rd_result);
            qcheck("miss only on the first byte of each block", (i % 4 == 0) ? 0 : 1, last_hit);
        end
        qflush("D-13a", "128 sequential reads: correct data, 1 miss per block");
        check_eq("D-13b", "32 misses",                                  nm0 + 32, tot_miss);
        check_eq("D-13c", "96 hits",                                    nh0 + 96, tot_hit);
        check_eq("D-13d", "32 memory block reads",                      mr0 + 32, tot_mem_rd);
        end_test;

        begin_test("D-14", "Back-to-back requests", "reset", "8 reads issued as soon as the controller is ready again");
        do_reset(2);
        for (i = 0; i < 8; i = i + 1) begin
            do_read(16'h0050 + 4 * i);
            if (i > 0) qcheck("accept edge is 1 cycle after previous response edge", 1, last_gap);
            qcheck("data correct", shadow[16'h0050 + 4 * i], rd_result);
        end
        qflush("D-14a", "8 back-to-back reads, one idle cycle between transactions");
        end_test;

        // ================================================================
        // WRITE FUNCTIONALITY (15-22)
        // ================================================================
        begin_test("D-15", "Write hit", "reset; block 0x0104 cached", "write 0x0105 = 0xA1");
        do_reset(2);
        do_read(16'h0104);
        mr0 = tot_mem_rd; mw0 = tot_mem_wr;
        blk = shadow_block(16'h0104);
        do_write(16'h0105, 8'hA1);
        check_eq("D-15a", "write classified as HIT",                    1, last_hit);
        check_eq("D-15b", "no block fetch",                             mr0, tot_mem_rd);
        check_eq("D-15c", "one memory write",                           mw0 + 1, tot_mem_wr);
        check_eq("D-15d", "cache block updated at offset 1 only",       merged(blk, 2'd1, 8'hA1), cblk(1));
        check_eq("D-15e", "memory byte 0x0105 = 0xA1",                  8'hA1, dut.u_mem.mem[16'h0105]);
        check_eq("D-15f", "write response carries cpu_rdata = 0",       0, rd_result);
        end_test;

        begin_test("D-16", "Write miss", "reset; nothing cached", "write 0x0208 = 0x55 (tag 8, index 2)");
        do_reset(2);
        mr0 = tot_mem_rd; mw0 = tot_mem_wr;
        do_write(16'h0208, 8'h55);
        check_eq("D-16a", "write classified as MISS",                   0, last_hit);
        check_eq("D-16b", "block fetched (write-allocate)",             mr0 + 1, tot_mem_rd);
        check_eq("D-16c", "byte written through to memory",             mw0 + 1, tot_mem_wr);
        check_eq("D-16d", "memory byte 0x0208 = 0x55",                  8'h55, dut.u_mem.mem[16'h0208]);
        end_test;

        begin_test("D-17", "Write allocation", "after D-16", "inspect line 2; read the other bytes of the block");
        check_eq("D-17a", "line 2 allocated (valid)",                   1, cval(2));
        check_eq("D-17b", "line 2 tag = 0x008",                         10'h008, ctag(2));
        check_eq("D-17c", "line 2 = fetched block with byte 0 replaced", shadow_block(16'h0208), cblk(2));
        mr0 = tot_mem_rd;
        rd_chk("D-17d", "0x0208 (written byte) HIT",                    16'h0208, 1'b1);
        rd_chk("D-17e", "0x0209 (fetched, unwritten) HIT",              16'h0209, 1'b1);
        rd_chk("D-17f", "0x020A HIT",                                   16'h020A, 1'b1);
        rd_chk("D-17g", "0x020B HIT",                                   16'h020B, 1'b1);
        check_eq("D-17h", "no further memory reads",                    mr0, tot_mem_rd);
        end_test;

        begin_test("D-18", "Write-through verification (cache vs main memory)", "reset", "mixed write hits/misses; after each write compare memory, cache, commit count");
        do_reset(2);
        c0 = tot_commits;
        for (i = 0; i < 24; i = i + 1) begin
            aa = 16'h0600 + (i * 5) + ((i % 3) * 16'h0040);       // spreads over index/offset/tag
            if (i % 2) do_read({aa[15:2], 2'b00});                // cache the line -> write hit
            dd = 8'h80 + i;
            do_write(aa, dd);
            qcheck("main memory holds the written byte at response time",   dd, dut.u_mem.mem[aa]);
            qcheck("exactly one array write committed for this store",      1, last_commits);
            qcheck("cache line holds the same byte",                        dd, (cblk(aa[5:2]) >> (8 * aa[1:0])) & 32'hFF);
            qcheck("cache tag matches the address",                         aa[15:6], ctag(aa[5:2]));
        end
        qflush("D-18a", "write-through: memory, cache and commit count agree");
        coherence_scan(bad);
        check_eq("D-18b", "every valid line equals memory block (coherence)", 0, bad);
        memory_scan(bad);
        check_eq("D-18c", "whole 64 KiB memory equals scoreboard",       0, bad);
        check_eq("D-18d", "24 stores -> 24 memory array writes",         c0 + 24, tot_commits);
        end_test;

        begin_test("D-19", "Byte-level write", "reset; block 0x0300 cached", "write 0x11,0x22,0x33,0x44 to offsets 0..3, one at a time");
        do_reset(2);
        do_read(16'h0300);
        blk = shadow_block(16'h0300);
        for (i = 0; i < 4; i = i + 1) begin
            dd  = 8'h11 * (i + 1);
            blk = merged(blk, i[1:0], dd);
            do_write(16'h0300 + i, dd);
            qcheck("write was a hit", 1, last_hit);
            qcheck("cache block equals expected after this byte", blk, cblk(0));
            qcheck("memory block equals expected after this byte", blk, mem_block(16'h0300));
        end
        qflush("D-19a", "four single-byte writes build the expected block");
        check_eq("D-19b", "final block = 0x44332211",                   32'h44332211, cblk(0));
        end_test;

        begin_test("D-20", "Preservation of unaffected bytes", "reset", "one byte written to each offset, on a HIT and on a MISS");
        do_reset(2);
        for (i = 0; i < 4; i = i + 1) begin
            // write HIT: block cached first
            aa = 16'h0400 + 4 * i;                            // distinct blocks, idx = i
            do_read(aa);
            blk  = shadow_block(aa);
            expb = merged(blk, i[1:0], 8'hEE);
            do_write(aa + i, 8'hEE);
            qcheck("hit path: other three cache bytes preserved", expb, cblk(aa[5:2]));
            qcheck("hit path: other three memory bytes preserved", expb, mem_block(aa));
            // write MISS (write-allocate): fresh block
            a2   = 16'h0500 + 4 * (i + 4);                    // idx = 4+i, never read before
            blk  = shadow_block(a2);
            expb = merged(blk, i[1:0], 8'h6D);
            do_write(a2 + i, 8'h6D);
            qcheck("miss path: was a miss", 0, last_hit);
            qcheck("miss path: other three cache bytes preserved", expb, cblk(a2[5:2]));
            qcheck("miss path: other three memory bytes preserved", expb, mem_block(a2));
        end
        qflush("D-20a", "unaffected bytes preserved for all offsets, hit and miss");
        end_test;

        begin_test("D-21", "Read-after-write consistency", "reset", "write then read same/other bytes via hit and miss paths");
        do_reset(2);
        do_write(16'h0700, 8'hAB);                            // write miss
        rd_chk("D-21a", "read back written byte (HIT)",         16'h0700, 1'b1);
        check_eq("D-21b", "value is 0xAB",                      8'hAB, rd_result);
        rd_chk("D-21c", "neighbour byte unchanged (HIT)",       16'h0701, 1'b1);
        do_write(16'h0701, 8'hCD);                            // write hit
        rd_chk("D-21d", "read back second written byte",        16'h0701, 1'b1);
        check_eq("D-21e", "value is 0xCD",                      8'hCD, rd_result);
        rd_chk("D-21f", "first written byte still 0xAB",        16'h0700, 1'b1);
        check_eq("D-21g", "value is 0xAB",                      8'hAB, rd_result);
        do_reset(2);                                          // cache emptied: reads now come from memory
        rd_chk("D-21h", "after reset read comes from memory (MISS)", 16'h0701, 1'b0);
        check_eq("D-21i", "memory returns 0xCD",                8'hCD, rd_result);
        end_test;

        begin_test("D-22", "Main-memory consistency after cache replacement", "reset", "write 0x0404/0x0406, evict by conflict read, re-read");
        do_reset(2);
        do_write(16'h0404, 8'h9C);                            // write miss, line 1, tag 0x010
        do_write(16'h0406, 8'h7E);                            // write hit
        check_eq("D-22a", "line 1 tag = 0x010",                 10'h010, ctag(1));
        rd_chk("D-22b", "conflicting read 0x0004 evicts line -> MISS", 16'h0004, 1'b0);
        check_eq("D-22c", "memory kept 0x9C (no write-back needed)", 8'h9C, dut.u_mem.mem[16'h0404]);
        check_eq("D-22d", "memory kept 0x7E",                   8'h7E, dut.u_mem.mem[16'h0406]);
        rd_chk("D-22e", "re-read 0x0404 -> MISS (evicted)",     16'h0404, 1'b0);
        check_eq("D-22f", "refetched value 0x9C",               8'h9C, rd_result);
        rd_chk("D-22g", "0x0406 -> HIT",                        16'h0406, 1'b1);
        check_eq("D-22h", "refetched value 0x7E",               8'h7E, rd_result);
        check_eq("D-22i", "refilled block equals memory block", mem_block(16'h0404), cblk(1));
        end_test;

        // ================================================================
        // CONTROL AND TIMING (23-30)
        // ================================================================
        begin_test("D-23", "Reset while idle", "cache full of valid lines, controller idle", "assert rst for 1 cycle");
        do_reset(2);
        for (i = 0; i < 16; i = i + 1) do_read(16'h0800 + 4 * i);
        check_eq("D-23a", "16 valid lines before reset",        16, count_valid(0));
        do_reset(1);
        check_eq("D-23b", "valid bits cleared",                 0, dut.u_cache.valid_array);
        check_eq("D-23c", "FSM in IDLE",                        0, dbg_state);
        check_eq("D-23d", "cpu_ready high",                     1, cpu_ready);
        check_eq("D-23e", "no response",                        0, cpu_resp_valid);
        check_eq("D-23f", "mem_req low",                        0, mem_req);
        memory_scan(bad);
        check_eq("D-23g", "memory contents untouched by reset", 0, bad);
        rd_chk("D-23h", "previously cached address now MISS",   16'h0800, 1'b0);
        end_test;

        begin_test("D-24", "Reset between transactions", "idle between requests", "read A; reset; read A; write B; reset; read B");
        do_reset(2);
        rd_chk("D-24a", "read 0x0900 MISS",                     16'h0900, 1'b0);
        do_reset(2);
        rd_chk("D-24b", "read 0x0900 after reset -> MISS again", 16'h0900, 1'b0);
        do_write(16'h0A01, 8'h42);
        do_reset(1);
        check_eq("D-24c", "valid bits cleared again",           0, dut.u_cache.valid_array);
        rd_chk("D-24d", "read written address after reset -> MISS", 16'h0A01, 1'b0);
        check_eq("D-24e", "write-through survived the reset",   8'h42, rd_result);
        end_test;

        begin_test("D-24R", "Reset during an ACTIVE memory transaction (read miss)", "reset each iteration", "reset k cycles after acceptance for every k in 0..12+2L (read miss)");
        reset_sweep(0);
        qflush("D-24Ra", "read-miss aborted at every phase: clean recovery");
        check_eq("D-24Rb", "no monitor errors / spurious responses",   0, mon_errors);
        end_test;

        begin_test("D-24W", "Reset during an ACTIVE memory transaction (write hit)", "line cached, then write", "reset k cycles after acceptance for every k (write hit / write-through)");
        reset_sweep(1);
        qflush("D-24Wa", "write-hit aborted at every phase: memory = committed-or-original");
        check_eq("D-24Wb", "no monitor errors / spurious responses",   0, mon_errors);
        end_test;

        begin_test("D-24A", "Reset during an ACTIVE memory transaction (write miss)", "cache empty, then write", "reset k cycles after acceptance for every k (write-allocate)");
        reset_sweep(2);
        qflush("D-24Aa", "write-miss aborted at every phase: memory = committed-or-original");
        check_eq("D-24Ab", "no monitor errors / spurious responses",   0, mon_errors);
        end_test;

        begin_test("D-25", "Delayed memory response", "reset", "observe wait states during read miss, write hit, write miss");
        do_reset(2);
        me0 = mon_errors;
        do_read(16'h0C04);                                     // cold read miss
        check_eq("D-25a", "MEMORY_READ_WAIT lasted exactly the measured memory latency", last_memlat_sum, obs_s4);
        check_eq("D-25b", "no MEMORY_WRITE_WAIT on a read",     0, obs_s8);
        do_write(16'h0C05, 8'h31);                             // write hit
        check_eq("D-25c", "MEMORY_WRITE_WAIT = measured latency + 1 (request starts in this state)", last_memlat_sum + 1, obs_s8);
        check_eq("D-25d", "no read wait on write hit",          0, obs_s4);
        do_write(16'h0D04, 8'h32);                             // write miss (other line, cold)
        check_eq("D-25e", "write miss: read wait + write wait = total measured latency + 1", last_memlat_sum + 1, obs_s4 + obs_s8);
        check_eq("D-25f", "no response before the memory finished (monitor)", 0, mon_errors - me0);
`ifndef VARLAT
        check_eq("D-25g", "wait length equals configured MEM_LATENCY", LATC, obs_s4);
`endif
        end_test;

        begin_test("D-26", "Request held high across multiple cycles", "reset", "cpu_req stays 1 while the next request is presented; 12 mixed ops, 6 identical reads, 5 identical writes");
        do_reset(2);
        c0 = tot_commits; me0 = mon_errors;
        st_n = 12;
        for (i = 0; i < 12; i = i + 1) begin
            st_we[i] = (i % 3 == 2);
            st_a[i]  = 16'h0E00 + 4 * (i % 5) + (i % 4) + ((i / 6) * 16'h0040);
            st_d[i]  = 8'h10 + i;
        end
        stream_run;
        check_eq("D-26a", "all 12 requests accepted exactly once",   12, stream_acc);
        check_eq("D-26b", "all 12 responses received",               12, stream_resp);
        check_eq("D-26c", "read data / ordering correct",            0, stream_bad);
        check_eq("D-26d", "cpu_req was held high for > 40 cycles",   1, (stream_maxhigh > 40));
        check_eq("D-26e", "4 stores -> 4 memory writes (no duplicates)", c0 + 4, tot_commits);
        st_n = 6;
        for (i = 0; i < 6; i = i + 1) begin st_we[i] = 0; st_a[i] = 16'h0F11; st_d[i] = 0; end
        mr0 = tot_mem_rd;
        stream_run;
        check_eq("D-26f", "6 identical held reads: 6 accepted",      6, stream_acc);
        check_eq("D-26g", "6 responses, data correct",               0, stream_bad);
        check_eq("D-26h", "at most one refill for the identical reads", 1, (tot_mem_rd - mr0) <= 1);
        st_n = 5; c0 = tot_commits;
        for (i = 0; i < 5; i = i + 1) begin st_we[i] = 1; st_a[i] = 16'h0F12; st_d[i] = 8'h77; end
        stream_run;
        check_eq("D-26i", "5 identical held writes: 5 accepted",     5, stream_acc);
        check_eq("D-26j", "5 responses",                             5, stream_resp);
        check_eq("D-26k", "5 requests -> exactly 5 memory writes",   c0 + 5, tot_commits);
        check_eq("D-26l", "memory byte = 0x77",                      8'h77, dut.u_mem.mem[16'h0F12]);
        check_eq("D-26m", "no monitor errors",                       0, mon_errors - me0);
        end_test;

        begin_test("D-27", "Response handshake", "reset", "check resp pulse width, ready low while busy, ready high the cycle after response");
        do_reset(2);
        me0 = mon_errors;
        do_read(16'h1004);                                     // miss
        @(posedge clk);                                        // the cycle right after the response edge
        check_eq("D-27a", "cpu_ready high in the cycle after the response", 1, cpu_ready);
        check_eq("D-27b", "cpu_resp_valid low in the cycle after the response", 0, cpu_resp_valid);
        do_read(16'h1005);                                     // hit
        @(posedge clk);
        check_eq("D-27c", "same for a hit response: ready high",  1, cpu_ready);
        check_eq("D-27d", "same for a hit response: resp low",    0, cpu_resp_valid);
        check_eq("D-27e", "monitor: 1-cycle pulse, ready low during busy/response", 0, mon_errors - me0);
        end_test;

        begin_test("D-28", "No duplicate writes", "reset", "30 stores (hit/miss mix) + held-high stream; count array commits");
        do_reset(2);
        c0 = tot_commits; mw0 = tot_mem_wr; me0 = mon_errors;
        for (i = 0; i < 30; i = i + 1) begin
            aa = 16'h1100 + (i * 7) + ((i % 4) * 16'h0040);
            if (i % 3 == 0) do_read(aa);
            do_write(aa, 8'h20 + i);
            qcheck("one commit per store", 1, last_commits);
        end
        qflush("D-28a", "each store caused exactly one memory array write");
        check_eq("D-28b", "30 stores -> 30 array commits",       c0 + 30, tot_commits);
        check_eq("D-28c", "30 stores -> 30 mem_done(write) pulses", mw0 + 30, tot_mem_wr);
        st_n = 8; c0 = tot_commits;
        for (i = 0; i < 8; i = i + 1) begin st_we[i] = 1; st_a[i] = 16'h1200 + i; st_d[i] = 8'h50 + i; end
        stream_run;
        check_eq("D-28d", "held-high 8-store stream: 8 commits", c0 + 8, tot_commits);
        check_eq("D-28e", "no monitor errors",                   0, mon_errors - me0);
        end_test;

        begin_test("D-29", "No premature ready/response", "reset", "all four transaction types; compare response time with required memory completion");
        do_reset(2);
        me0 = mon_errors;
        do_read(16'h1304);   check_eq("D-29a", "read miss: 1 memory read done before response",  1, last_rd_done);
        do_read(16'h1304);   check_eq("D-29b", "read hit: no memory op",                          0, last_rd_done + last_wr_done);
        do_write(16'h1304, 8'h01); check_eq("D-29c", "write hit: 1 memory write done before response", 1, last_wr_done);
        check_eq("D-29d", "write hit: no memory read",           0, last_rd_done);
        do_write(16'h1404, 8'h02); check_eq("D-29e", "write miss: 1 read + 1 write before response", 2, last_rd_done + last_wr_done);
        check_eq("D-29f", "monitor: no response before memory completion", 0, mon_errors - me0);
        check_eq("D-29g", "latency matches formula on every transaction",  0, lat_mismatch);
        end_test;

        begin_test("D-30", "No stale response data", "reset", "rdata cleared on write; refill data comes from memory not the old line; backdoor memory change visible on miss");
        do_reset(2);
        me0 = mon_errors;
        do_read(16'h1504);                                     // rdata = value
        do_write(16'h1508, 8'h99);                             // write response must NOT repeat old read data
        check_eq("D-30a", "write response rdata = 0 (not the previous read data)", 0, rd_result);
        do_read(16'h0004);                                     // line 1 <- tag 0
        dd = shadow[16'h0004];
        dut.u_mem.mem[16'h0044] = 8'hEE;                       // backdoor change of the conflicting block
        shadow[16'h0044]        = 8'hEE;
        do_read(16'h0044);                                     // conflict miss
        check_eq("D-30b", "miss returned the NEW memory value, not the evicted line's byte", 8'hEE, rd_result);
        check_eq("D-30c", "...which differs from the old cached byte", 1, (rd_result != dd));
        do_read(16'h0044);
        check_eq("D-30d", "subsequent hit returns the refilled value", 8'hEE, rd_result);
        check_eq("D-30e", "monitor: cpu_rdata was 0 on every busy cycle (no stale data)", 0, mon_errors - me0);
        end_test;

        // ================================================================
        // EDGE CASES (plan section 2.2)
        // ================================================================
        begin_test("E-01", "Address extremes 0x0000 and 0xFFFF", "reset", "read and write all 4 bytes of the blocks at 0x0000 and 0xFFFC");
        do_reset(2);
        for (i = 0; i < 4; i = i + 1) begin
            rd_chk("E-01a", "0x0000+i read",                    16'h0000 + i, (i == 0) ? 1'b0 : 1'b1);
            rd_chk("E-01b", "0xFFFC+i read",                    16'hFFFC + i, (i == 0) ? 1'b0 : 1'b1);
        end
        do_write(16'hFFFF, 8'hC3);  check_eq("E-01c", "write 0xFFFF HIT",   1, last_hit);
        do_write(16'h0000, 8'h3C);  check_eq("E-01d", "write 0x0000 HIT",   1, last_hit);
        check_eq("E-01e", "memory[0xFFFF] = 0xC3",              8'hC3, dut.u_mem.mem[16'hFFFF]);
        check_eq("E-01f", "memory[0x0000] = 0x3C",              8'h3C, dut.u_mem.mem[16'h0000]);
        do_reset(2);
        do_write(16'hFFFE, 8'h5A);  check_eq("E-01g", "write miss 0xFFFE",  0, last_hit);
        check_eq("E-01h", "line 15 tag = 0x3FF after allocate", 10'h3FF, ctag(15));
        check_eq("E-01i", "line 15 block = memory block",       mem_block(16'hFFFC), cblk(15));
        end_test;

        begin_test("E-02", "Each of the 10 tag bits independently, min/max tags (reads and writes)", "reset", "address differing from a base in exactly one tag bit must MISS; then offset/index flips");
        do_reset(2);
        // explicit, visible per-bit checks (index 0, base tag 0x000)
        for (b = 0; b < 10; b = b + 1) begin
            do_read(16'h0000);
            aa = 16'h0000 ^ (16'h0001 << (6 + b));
            do_read(aa);
            check_eq("E-02a", "read: address differing in ONE tag bit is MISS",      0, last_hit);
            check_eq("E-02b", "  ...and returns the correct byte",                    shadow[aa], rd_result);
            check_eq("E-02c", "  ...and stores that tag in the line",                 aa[15:6], ctag(0));
        end
        for (b = 0; b < 10; b = b + 1) begin           // write variant, index 3, base tag 0x155
            aa = {10'h155, 4'd3, 2'b00};
            do_read(aa);
            a2 = aa ^ (16'h0001 << (6 + b));
            do_write(a2, 8'hB0 + b);
            check_eq("E-02d", "write: address differing in ONE tag bit is MISS",     0, last_hit);
            check_eq("E-02e", "  ...write-through reached memory",                    8'hB0 + b, dut.u_mem.mem[a2]);
        end
        // systematic sweep: indices {0,7,15} x base tags {0x000,0x3FF,0x155,0x2AA} x 10 bits
        for (j = 0; j < 3; j = j + 1) begin
            ix = (j == 0) ? 4'd0 : (j == 1) ? 4'd7 : 4'd15;
            for (k = 0; k < 4; k = k + 1) begin
                tg = (k == 0) ? 10'h000 : (k == 1) ? 10'h3FF : (k == 2) ? 10'h155 : 10'h2AA;
                for (b = 0; b < 10; b = b + 1) begin
                    base_a = {tg, ix, 2'b10};
                    aa     = {tg ^ (10'h001 << b), ix, 2'b10};
                    do_read(base_a);
                    do_read(aa);
                    qcheck("single tag-bit flip is a MISS", 0, last_hit);
                    qcheck("data correct",                  shadow[aa], rd_result);
                    qcheck("line stores flipped tag",       aa[15:6], ctag(ix));
                    do_read(base_a);
                    qcheck("base address now evicted -> MISS", 0, last_hit);
                    qcheck("base data correct",             shadow[base_a], rd_result);
                end
            end
        end
        qflush("E-02f", "tag-bit sweep: 3 indices x 4 base tags x 10 bits");
        // non-tag bits must NOT cause a miss
        do_read(16'h1234);
        for (b = 0; b < 2; b = b + 1) begin
            do_read(16'h1234 ^ (16'h0001 << b));
            qcheck("offset-bit flip stays in the block -> HIT", 1, last_hit);
        end
        qflush("E-02g", "offset bits do not affect hit detection");
        end_test;

        begin_test("E-03", "Minimum and maximum cache indices", "reset", "read byte 0 of every line with tag 0x000 and with tag 0x3FF");
        do_reset(2);
        for (i = 0; i < 16; i = i + 1) begin
            do_read({10'h000, i[3:0], 2'b00});
            qcheck("tag 0 line miss", 0, last_hit);
            qcheck("tag 0 data", shadow[{10'h000, i[3:0], 2'b00}], rd_result);
            do_read({10'h3FF, i[3:0], 2'b00});
            qcheck("tag 0x3FF replaces: miss", 0, last_hit);
            qcheck("tag 0x3FF data", shadow[{10'h3FF, i[3:0], 2'b00}], rd_result);
            qcheck("line holds 0x3FF", 10'h3FF, ctag(i));
        end
        qflush("E-03a", "all 16 indices work with minimum and maximum tag");
        end_test;

        begin_test("E-04", "All four offsets at every address corner", "reset", "first touch at each offset of 4 corner blocks");
        do_reset(2);
        for (j = 0; j < 4; j = j + 1) begin
            base_a = (j == 0) ? 16'h0000 : (j == 1) ? 16'hFFFC : (j == 2) ? 16'h003C : 16'hFFC0;
            for (i = 0; i < 4; i = i + 1) begin
                aa = base_a + ((i + j) % 4);
                do_read(aa);
                qcheck("byte at corner", shadow[aa], rd_result);
                qcheck("block lane", (cblk(aa[5:2]) >> (8 * aa[1:0])) & 32'hFF, {24'h0, rd_result});
            end
        end
        qflush("E-04a", "corner-block offsets return the right byte lane");
        end_test;

        begin_test("E-05", "Multiple addresses mapping to the same line (all 1024 tags at index 5)", "reset", "read every tag 0..1023 at index 5, twice");
        do_reset(2);
        mr0 = tot_mem_rd;
        for (t = 0; t < 1024; t = t + 1) begin
            aa = {t[9:0], 4'd5, 2'b01};
            do_read(aa);
            qcheck("each new tag evicts: MISS", 0, last_hit);
            qcheck("data", shadow[aa], rd_result);
            qcheck("tag stored", t[9:0], ctag(5));
            do_read(aa);
            qcheck("immediate re-read HIT", 1, last_hit);
        end
        qflush("E-05a", "1024 blocks sharing one line replace each other correctly");
        check_eq("E-05b", "1024 refills",                         mr0 + 1024, tot_mem_rd);
        end_test;

        begin_test("E-06", "Invalid cache entries never hit (tag-0 aliasing after reset)", "reset (tag arrays = 0, valid = 0)", "read a tag-0 address of every line; fill; reset; repeat");
        do_reset(2);
        for (i = 0; i < 16; i = i + 1) begin
            do_read({10'h000, i[3:0], 2'b11});
            qcheck("tag 0 matches reset tag but valid=0 -> MISS", 0, last_hit);
        end
        qflush("E-06a", "16 invalid lines all miss although stored tag == 0");
        do_reset(2);
        for (i = 0; i < 16; i = i + 1) do_read({10'h000, i[3:0], 2'b11});
        do_reset(2);
        for (i = 0; i < 16; i = i + 1) begin
            do_read({10'h000, i[3:0], 2'b11});
            qcheck("after refill+reset the same addresses MISS", 0, last_hit);
        end
        qflush("E-06b", "reset invalidates previously valid lines");
        end_test;

        begin_test("E-07", "Repeated replacement (ping-pong)", "reset", "alternate 0x0008 / 0x0048 (same index) 50 times each");
        do_reset(2);
        mr0 = tot_mem_rd;
        for (i = 0; i < 50; i = i + 1) begin
            do_read(16'h0008);  qcheck("A miss", 0, last_hit);  qcheck("A data", shadow[16'h0008], rd_result);
            do_read(16'h0048);  qcheck("B miss", 0, last_hit);  qcheck("B data", shadow[16'h0048], rd_result);
        end
        qflush("E-07a", "100 consecutive conflict misses, all data correct");
        check_eq("E-07b", "100 refills",                          mr0 + 100, tot_mem_rd);
        end_test;

        begin_test("E-08", "Write replacement and write-allocate over a valid conflicting line", "reset", "256 tags written at index 5, then read back");
        do_reset(2);
        for (t = 0; t < 256; t = t + 1) begin
            aa = {t[9:0] ^ 10'h2A5, 4'd5, 2'b10};
            do_write(aa, 8'h40 + t[7:0]);
            qcheck("write miss over valid line", (t == 0) ? 0 : 0, last_hit);
            qcheck("memory updated", {24'h0, 8'h40 + t[7:0]}, dut.u_mem.mem[aa]);
            qcheck("line tag", aa[15:6], ctag(5));
        end
        qflush("E-08a", "256 write-allocates replace each other, memory always updated");
        for (t = 0; t < 256; t = t + 1) begin
            aa = {t[9:0] ^ 10'h2A5, 4'd5, 2'b10};
            do_read(aa);
            qcheck("read back after replacement (from memory)", {24'h0, 8'h40 + t[7:0]}, rd_result);
        end
        qflush("E-08b", "all 256 written bytes read back correctly");
        end_test;

        begin_test("E-09", "Write corners", "reset", "write all 4 bytes of 0x0000 and 0xFFFC blocks on hit and miss");
        do_reset(2);
        for (i = 0; i < 4; i = i + 1) begin
            do_write(16'hFFFC + i, 8'hF0 + i);        qcheck("0xFFFC+i write", 8'hF0 + i, dut.u_mem.mem[16'hFFFC + i]);
            do_write(16'h0000 + i, 8'h0F - i);        qcheck("0x0000+i write", 8'h0F - i, dut.u_mem.mem[16'h0000 + i]);
        end
        qflush("E-09a", "corner writes reach memory");
        check_eq("E-09b", "block 0xFFFC in cache = F3F2F1F0",     32'hF3F2F1F0, cblk(15));
        check_eq("E-09c", "block 0x0000 in cache = 0C0D0E0F",     32'h0C0D0E0F, cblk(0));
        coherence_scan(bad);
        check_eq("E-09d", "coherence",                            0, bad);
        end_test;

        begin_test("E-10", "Large-address-space sweep (write then read)", "reset", "stores then loads over the 64 KiB space (EXHAUSTIVE=1: every address)");
        do_reset(2);
        // stride 1 (exhaustive) or a coprime stride that still touches every index/offset/tag combination
        for (i = 0; i < 65536; i = i + ((EXHAUSTIVE != 0) ? 1 : 37)) begin
            aa = i;
            do_write(aa, (aa[7:0] * 8'd5) + aa[15:8] + 8'd1);
        end
        memory_scan(bad);
        check_eq("E-10a", "memory image equals scoreboard after write sweep", 0, bad);
        coherence_scan(bad);
        check_eq("E-10b", "cache lines coherent with memory",     0, bad);
        for (i = 0; i < 65536; i = i + ((EXHAUSTIVE != 0) ? 1 : 37)) begin
            aa = i;
            do_read(aa);
            qcheck("sweep read data", shadow[aa], rd_result);
        end
        qflush("E-10c", "read sweep returns the stored byte at every visited address");
        check_eq("E-10d", "monitor errors over the whole sweep",  0, mon_errors);
        end_test;

        begin_test("E-11", "Illegal FSM state recovery", "idle", "force state register to unused codes 10..15; check outputs quiet and recovery to IDLE");
        cov_pause = 1'b1;
        for (i = 10; i < 16; i = i + 1) begin
            @(negedge clk);
            dut.u_ctrl.state = i[3:0];
            #1;
            qcheck("cpu_ready low in illegal state", 0, cpu_ready);
            qcheck("cpu_resp_valid low",             0, cpu_resp_valid);
            qcheck("mem_req low",                    0, mem_req);
            qcheck("no refill strobe",               0, dbg_refill);
            qcheck("no byte-write strobe",           0, dbg_byte_we);
            @(negedge clk);
            qcheck("recovered to IDLE after one clock", 0, dbg_state);
        end
        qflush("E-11a", "all 6 unused state encodings are quiet and self-recover");
        cov_pause = 1'b0; prev_state = 4'd0;
        rd_chk("E-11b", "controller works normally afterwards",   16'h1600, 1'b0);
        end_test;

        // ================================================================
        // LATENCY FORMULAS (checked for the current memory latency)
        // ================================================================
        begin_test("L-01", "Latency formulas: read hit 3, read miss 5+L, write hit 4+L, write miss 6+2L", "reset", "one transaction of each type; measured accept->response cycles");
        do_reset(2);
        do_read(16'h1700);   first_lat = last_lat;
        begin : lat_blk
            integer l_rm, l_rh, l_wh, l_wm;
            l_rm = last_lat;
            do_read(16'h1700);  l_rh = last_lat;
            do_write(16'h1701, 8'h11); l_wh = last_lat;
            do_write(16'h1800, 8'h22); l_wm = last_lat;
`ifndef VARLAT
            check_eq("L-01a", "read hit latency = 3",             3,              l_rh);
            check_eq("L-01b", "read miss latency = 5+L",          5 + LATC,       l_rm);
            check_eq("L-01c", "write hit latency = 4+L",          4 + LATC,       l_wh);
            check_eq("L-01d", "write miss latency = 6+2L",        6 + 2 * LATC,   l_wm);
`endif
            check_eq("L-01e", "monitor: every transaction matched the formula (measured L)", 0, lat_mismatch);
            check_eq("L-01f", "monitor: memory latency equals configured",                  0, memlat_mismatch);
            $display("LATENCY_CSV,%0d,%0d,%0d,%0d,%0d", LATC, l_rh, l_rm, l_wh, l_wm);
        end
        end_test;

        // ================================================================
        // Summary and coverage
        // ================================================================
        repeat (5) @(posedge clk);
        begin : cov_blk
            integer st_seen, legal_seen, legal_total, illegal_seen, ii, idx_rd_ok, idx_wr_ok, off_rd_ok, off_wr_ok;
            st_seen = 0; legal_seen = 0; legal_total = 17; illegal_seen = 0;
`ifndef VARLAT
            if (LATC == 1) legal_total = 16;          // MEMORY_READ_WAIT lasts 1 cycle: no 4->4 self-loop at L=1
`endif
            for (ii = 0; ii < 16; ii = ii + 1) begin : stloop
                integer jj, vis;
                vis = 0;
                for (jj = 0; jj < 16; jj = jj + 1) vis = vis + cov_trans[{ii[3:0], jj[3:0]}];
                if (vis > 0) st_seen = st_seen + 1;
            end
            for (ii = 0; ii < 256; ii = ii + 1) begin
                if (cov_trans[ii] > 0) begin
                    if (legal_trans(ii[7:0])) legal_seen = legal_seen + 1;
                    else begin illegal_seen = illegal_seen + 1; $display("[COVERAGE] ILLEGAL transition %0d -> %0d seen %0d times", ii[7:4], ii[3:0], cov_trans[ii]); end
                end
            end
            idx_rd_ok = 0; idx_wr_ok = 0; off_rd_ok = 0; off_wr_ok = 0;
            for (ii = 0; ii < 16; ii = ii + 1) begin if (cov_idx_rd[ii] > 0) idx_rd_ok = idx_rd_ok + 1; if (cov_idx_wr[ii] > 0) idx_wr_ok = idx_wr_ok + 1; end
            for (ii = 0; ii < 4;  ii = ii + 1) begin if (cov_off_rd[ii] > 0) off_rd_ok = off_rd_ok + 1; if (cov_off_wr[ii] > 0) off_wr_ok = off_wr_ok + 1; end
            $display("COVERAGE,states_visited,%0d,10", st_seen);
            $display("COVERAGE,legal_transitions_visited,%0d,%0d", legal_seen, legal_total);
            $display("COVERAGE,illegal_transitions_visited,%0d,0", illegal_seen);
            $display("COVERAGE,index_read,%0d,16", idx_rd_ok);
            $display("COVERAGE,index_write,%0d,16", idx_wr_ok);
            $display("COVERAGE,offset_read,%0d,4", off_rd_ok);
            $display("COVERAGE,offset_write,%0d,4", off_wr_ok);
            $display("COVERAGE,read_hit,%0d,", cov_rd_hit);
            $display("COVERAGE,read_miss,%0d,", cov_rd_miss);
            $display("COVERAGE,write_hit,%0d,", cov_wr_hit);
            $display("COVERAGE,write_miss,%0d,", cov_wr_miss);
            $display("COVERAGE,cold_misses_invalid_line,%0d,", cov_cold);
            $display("COVERAGE,conflict_misses_valid_line,%0d,", cov_conflict);
            begin_test("C-01", "Functional coverage goals (state/transition/index/offset)", "end of regression", "evaluate monitor coverage counters");
            check_eq("C-01a", "all 10 FSM states visited",             10, st_seen);
            check_eq("C-01b", "all legal transitions visited (17; 16 when L=1)",      legal_total, legal_seen);
            check_eq("C-01c", "no illegal transition observed",        0, illegal_seen);
            check_eq("C-01d", "all 16 indices read",                   16, idx_rd_ok);
            check_eq("C-01e", "all 16 indices written",                16, idx_wr_ok);
            check_eq("C-01f", "all 4 offsets read",                    4, off_rd_ok);
            check_eq("C-01g", "all 4 offsets written",                 4, off_wr_ok);
            end_test;
        end

        for (i = 0; i < 64; i = i + 1)
            if (memlat_hist[i] > 0) $display("MEMLAT_HIST,%0d,%0d", i, memlat_hist[i]);
        $display("==== Statistics: requests=%0d (reads=%0d writes=%0d) hits=%0d misses=%0d mem_reads=%0d mem_writes=%0d array_commits=%0d ====",
                 tot_req, tot_rd, tot_wr, tot_hit, tot_miss, tot_mem_rd, tot_mem_wr, tot_commits);
        $display("==== Protocol monitor: errors=%0d latency_mismatches=%0d memory_latency_mismatches=%0d ====",
                 mon_errors, lat_mismatch, memlat_mismatch);
        $display("==== SUMMARY (MEM_LATENCY=%0d): TESTS=%0d TESTS_FAILED=%0d CHECKS_PASS=%0d CHECKS_FAIL=%0d ====",
                 MEM_LATENCY, tests_run, tests_failed, n_pass, n_fail);
        if (n_fail == 0 && mon_errors == 0 && lat_mismatch == 0 && memlat_mismatch == 0 && tests_failed == 0)
            $display("RESULT: ALL TESTS PASSED");
        else
            $display("RESULT: FAILURES DETECTED");
        $finish;
    end

endmodule
