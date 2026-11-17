//==============================================================================
// cache_tb.v  --  Phase 1 self-checking testbench (simulation only)
//------------------------------------------------------------------------------
// Verifies: reset, cold miss, hit, multi-block loading, same-index conflict
// replacement, returned data, refill contents/byte order, absence of premature
// responses, plus write-miss/write-hit smoke tests (full write verification is
// Phase 2).
//
// Three layers:
//   1. Protocol monitor  - watches every transaction on the CPU and memory
//                          buses (response without request, response before the
//                          memory finished, wrong number of memory operations,
//                          unaligned block reads, multi-cycle responses, latency
//                          against the documented formula).
//   2. Scoreboard        - `shadow` byte array = documented memory init pattern,
//                          updated on every write the testbench issues.
//   3. Directed tests    - P1-xx checks printed as [PASS]/[FAIL].
//
// Run from the repository root (VCD path is relative):  see Makefile.
// Plusargs: +novcd (skip waveform), +vcd=<file>.
//==============================================================================
`timescale 1ns/1ps

module cache_tb;

    parameter MEM_LATENCY = 4;

    // ------------------------------------------------------------------ DUT
    reg         clk;
    reg         rst;
    reg         cpu_req;
    reg         cpu_we;
    reg  [15:0] cpu_addr;
    reg  [7:0]  cpu_wdata;
    wire        cpu_ready;
    wire        cpu_resp_valid;
    wire [7:0]  cpu_rdata;

    wire        mem_req, mem_we, mem_done;
    wire [15:0] mem_addr;
    wire [7:0]  mem_wdata;
    wire [31:0] mem_rdata;

    wire [3:0]  dbg_state;
    wire        dbg_lookup, dbg_tag_match, dbg_hit, dbg_line_valid;
    wire [9:0]  dbg_tag;
    wire [3:0]  dbg_index;
    wire [1:0]  dbg_offset;
    wire        dbg_refill, dbg_byte_we;

    cache_top #(.MEM_LATENCY(MEM_LATENCY)) dut (
        .clk(clk), .rst(rst),
        .cpu_req(cpu_req), .cpu_we(cpu_we), .cpu_addr(cpu_addr),
        .cpu_wdata(cpu_wdata), .cpu_ready(cpu_ready),
        .cpu_resp_valid(cpu_resp_valid), .cpu_rdata(cpu_rdata),
        .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr),
        .mem_wdata(mem_wdata), .mem_done(mem_done), .mem_rdata(mem_rdata),
        .dbg_state(dbg_state), .dbg_lookup(dbg_lookup),
        .dbg_tag_match(dbg_tag_match), .dbg_hit(dbg_hit),
        .dbg_line_valid(dbg_line_valid), .dbg_tag(dbg_tag),
        .dbg_index(dbg_index), .dbg_offset(dbg_offset),
        .dbg_refill(dbg_refill), .dbg_byte_we(dbg_byte_we)
    );

    // ---------------------------------------------------------------- clock
    initial clk = 1'b0;
    always #5 clk = ~clk;                       // 10 ns simulated clock period

    integer cyc;                                // rising-edge counter (incremented
    initial cyc = 0;                            // only inside the monitor block below

    // ------------------------------------------------------------ waveform
    reg [8*128-1:0] vcd_name;
    initial begin
        if (!$test$plusargs("novcd")) begin
            if (!$value$plusargs("vcd=%s", vcd_name))
                vcd_name = "results/phase1_waveform.vcd";
            $dumpfile(vcd_name);
            $dumpvars(0, cache_tb);
        end
    end

    // --------------------------------------------------------- scoreboard
    // Independent restatement of the documented init pattern:
    //   mem[a] = (a[7:0] ^ a[15:8]) + 8'h5A
    reg [7:0] shadow [0:65535];
    integer   s;
    initial begin
        for (s = 0; s < 65536; s = s + 1)
            shadow[s] = (s[7:0] ^ s[15:8]) + 8'h5A;
    end

    function [31:0] shadow_block;
        input [15:0] a;
        reg   [15:0] b;
        begin
            b = {a[15:2], 2'b00};
            shadow_block = {shadow[b+16'd3], shadow[b+16'd2],
                            shadow[b+16'd1], shadow[b]};
        end
    endfunction

    // Documented transaction latency (accept edge -> edge that samples
    // cpu_resp_valid), see docs/fsm_design.md
    function integer exp_lat;
        input we;
        input hit;
        begin
            if (!we) exp_lat = hit ? 3 : (5 + MEM_LATENCY);
            else     exp_lat = hit ? (4 + MEM_LATENCY) : (6 + 2*MEM_LATENCY);
        end
    endfunction

    // ----------------------------------------------------- protocol monitor
    integer mon_errors;
    integer tot_req, tot_hit, tot_miss, tot_mem_rd, tot_mem_wr;
    integer lat_mismatch;
    reg     m_busy, m_acc_we, m_hit, prev_resp;
    integer m_rd_done, m_wr_done, acc_cyc;
    // results of the last completed transaction (read by directed tests)
    reg     last_hit;
    integer last_lat;
    integer last_rd_done, last_wr_done;

    initial begin
        mon_errors = 0; tot_req = 0; tot_hit = 0; tot_miss = 0;
        tot_mem_rd = 0; tot_mem_wr = 0; lat_mismatch = 0;
        m_busy = 0; m_acc_we = 0; m_hit = 0; prev_resp = 0;
        m_rd_done = 0; m_wr_done = 0; acc_cyc = 0;
        last_hit = 0; last_lat = 0; last_rd_done = 0; last_wr_done = 0;
    end

    task mon_err;
        input [8*60-1:0] msg;
        begin
            mon_errors = mon_errors + 1;
            $display("[MONITOR ERROR] t=%0t cyc=%0d : %0s", $time, cyc, msg);
        end
    endtask

    always @(posedge clk) begin
        cyc = cyc + 1;                          // single writer -> no race
        if (!rst) begin
            // hit/miss classification happens in COMPARE_TAG
            if (dbg_lookup) begin
                m_hit = dbg_hit;
                if (dbg_hit) tot_hit = tot_hit + 1; else tot_miss = tot_miss + 1;
            end
            // request acceptance
            if (cpu_req && cpu_ready) begin
                if (m_busy) mon_err("request accepted while busy");
                m_busy = 1; m_acc_we = cpu_we; m_rd_done = 0; m_wr_done = 0;
                acc_cyc = cyc; tot_req = tot_req + 1;
            end
            // memory bus checks
            if (mem_req && !m_busy)
                mon_err("memory request with no CPU request outstanding");
            if (mem_req && !mem_we && (mem_addr[1:0] != 2'b00))
                mon_err("unaligned block read address");
            if (mem_done) begin
                if (!mem_req) mon_err("mem_done without mem_req");
                if (mem_we) begin m_wr_done = m_wr_done + 1; tot_mem_wr = tot_mem_wr + 1; end
                else        begin m_rd_done = m_rd_done + 1; tot_mem_rd = tot_mem_rd + 1; end
            end
            // response checks
            if (cpu_resp_valid) begin
                if (!m_busy) mon_err("response with no request outstanding");
                else begin
                    if (m_rd_done != (m_hit ? 0 : 1) || m_wr_done != (m_acc_we ? 1 : 0))
                        mon_err("response before/without required memory operations");
                    if (cyc - acc_cyc != exp_lat(m_acc_we, m_hit)) begin
                        lat_mismatch = lat_mismatch + 1;
                        $display("[MONITOR] latency %0d != documented %0d (we=%0d hit=%0d)",
                                 cyc - acc_cyc, exp_lat(m_acc_we, m_hit), m_acc_we, m_hit);
                    end
                    last_hit = m_hit; last_lat = cyc - acc_cyc;
                    last_rd_done = m_rd_done; last_wr_done = m_wr_done;
                    m_busy = 0;
                end
                if (prev_resp)   mon_err("cpu_resp_valid high for more than one cycle");
                if (cpu_ready)   mon_err("cpu_ready high during response");
                if (mem_req)     mon_err("mem_req still high during response");
            end
            prev_resp = cpu_resp_valid;
        end
    end

    // ------------------------------------------------- check bookkeeping
    integer n_pass, n_fail;
    initial begin n_pass = 0; n_fail = 0; end

    task check_eq;
        input [8*10-1:0]  id;
        input [8*64-1:0]  desc;
        input [31:0]      expected;
        input [31:0]      actual;
        begin
            if (expected === actual) begin
                n_pass = n_pass + 1;
                $display("[PASS] %0s %0s | expected=0x%0h actual=0x%0h", id, desc, expected, actual);
            end else begin
                n_fail = n_fail + 1;
                $display("[FAIL] %0s %0s | expected=0x%0h actual=0x%0h", id, desc, expected, actual);
            end
        end
    endtask

    // ------------------------------------------------------- CPU driver
    // Drives on the falling edge, samples on the rising edge (race free).
    // After acceptance the request pins are scrambled to prove the controller
    // latched the request.
    reg [7:0] rd_result;
    integer   to;

    task cpu_access;
        input         we_i;
        input  [15:0] a;
        input  [7:0]  wd;
        reg           accepted, got;
        begin
            @(negedge clk);
            cpu_req = 1'b1; cpu_we = we_i; cpu_addr = a; cpu_wdata = wd;
            accepted = 1'b0; to = 0;
            while (!accepted) begin
                @(posedge clk);
                if (cpu_ready) accepted = 1'b1;
                to = to + 1;
                if (to > 100) begin
                    $display("[FAIL] TIMEOUT waiting for cpu_ready"); n_fail = n_fail + 1;
                    accepted = 1'b1;
                end
            end
            @(negedge clk);
            cpu_req = 1'b0; cpu_we = ~we_i; cpu_addr = ~a; cpu_wdata = ~wd;
            got = 1'b0; to = 0;
            while (!got) begin
                @(posedge clk);
                to = to + 1;
                if (cpu_resp_valid) begin
                    got = 1'b1; rd_result = cpu_rdata;
                end
                if (to > 200) begin
                    $display("[FAIL] TIMEOUT waiting for cpu_resp_valid (addr=0x%04h)", a);
                    n_fail = n_fail + 1; got = 1'b1;
                end
            end
            #1;                                   // let the monitor update
            if (we_i) shadow[a] = wd;
        end
    endtask

    task do_read;  input [15:0] a;               begin cpu_access(1'b0, a, 8'h00); end endtask
    task do_write; input [15:0] a; input [7:0] d; begin cpu_access(1'b1, a, d);    end endtask

    // ------------------------------------------------------ directed tests
    integer mr0, mw0, i;
    reg [15:0] aa;

    initial begin
        rst = 1'b1; cpu_req = 1'b0; cpu_we = 1'b0; cpu_addr = 16'h0; cpu_wdata = 8'h0;
        repeat (4) @(posedge clk);
        @(negedge clk); rst = 1'b0;
        @(negedge clk);

        $display("==== Phase 1 testbench start: MEM_LATENCY=%0d ====", MEM_LATENCY);

        // ---- P1-01 reset behaviour ------------------------------------
        check_eq("P1-01a", "cpu_ready high after reset",           1, cpu_ready);
        check_eq("P1-01b", "cpu_resp_valid low after reset",       0, cpu_resp_valid);
        check_eq("P1-01c", "mem_req low after reset",              0, mem_req);
        check_eq("P1-01d", "FSM in IDLE after reset",              0, dbg_state);
        check_eq("P1-01e", "all 16 valid bits cleared",            0, dut.u_cache.valid_array);

        // ---- P1-02 cold miss (0x0004: tag 0, index 1, offset 0) --------
        check_eq("P1-02a", "line 1 invalid before first access",   0, dut.u_cache.valid_array[1]);
        mr0 = tot_mem_rd; mw0 = tot_mem_wr;
        do_read(16'h0004);
        check_eq("P1-02b", "cold access classified as MISS",       0, last_hit);
        check_eq("P1-02c", "returned byte correct (0x0004)",       shadow[16'h0004], rd_result);
        check_eq("P1-02d", "one memory block read issued",         mr0+1, tot_mem_rd);
        check_eq("P1-02e", "no memory write issued",               mw0,   tot_mem_wr);
        check_eq("P1-02f", "line 1 valid after refill",            1, dut.u_cache.valid_array[1]);
        check_eq("P1-02g", "line 1 tag = 0x000",                   10'h000, dut.u_cache.tag_array[1]);
        check_eq("P1-02h", "line 1 holds full block 0x0004..07",   shadow_block(16'h0004), dut.u_cache.data_array[1]);

        // ---- P1-03 repeated access -> hit ------------------------------
        mr0 = tot_mem_rd;
        do_read(16'h0004);
        check_eq("P1-03a", "repeat access classified as HIT",      1, last_hit);
        check_eq("P1-03b", "returned byte correct",                shadow[16'h0004], rd_result);
        check_eq("P1-03c", "no memory read on hit",                mr0, tot_mem_rd);

        // ---- P1-04 other offsets of the same block hit -----------------
        for (i = 1; i < 4; i = i + 1) begin
            aa = 16'h0004 + i;
            mr0 = tot_mem_rd;
            do_read(aa);
            check_eq("P1-04a", "same-block offset is HIT",         1, last_hit);
            check_eq("P1-04b", "same-block offset byte correct",   shadow[aa], rd_result);
            check_eq("P1-04c", "no memory read",                   mr0, tot_mem_rd);
        end

        // ---- P1-05 a different block loads into its own line -----------
        do_read(16'h0008);                                 // tag 0, index 2
        check_eq("P1-05a", "second block cold MISS",               0, last_hit);
        check_eq("P1-05b", "second block byte correct",            shadow[16'h0008], rd_result);
        check_eq("P1-05c", "line 2 tag = 0x000",                   10'h000, dut.u_cache.tag_array[2]);
        do_read(16'h000A);
        check_eq("P1-05d", "second block offset 2 is HIT",         1, last_hit);
        check_eq("P1-05e", "second block offset 2 correct",        shadow[16'h000A], rd_result);

        // ---- P1-06 same-index conflict replaces the line ---------------
        // 0x0044 = tag 1, index 1, offset 0 : conflicts with 0x0004
        mr0 = tot_mem_rd;
        do_read(16'h0044);
        check_eq("P1-06a", "conflicting address is MISS",          0, last_hit);
        check_eq("P1-06b", "conflicting address byte correct",     shadow[16'h0044], rd_result);
        check_eq("P1-06c", "one block refill",                     mr0+1, tot_mem_rd);
        check_eq("P1-06d", "line 1 tag replaced by 0x001",         10'h001, dut.u_cache.tag_array[1]);
        check_eq("P1-06e", "line 1 holds new block 0x0044..47",    shadow_block(16'h0044), dut.u_cache.data_array[1]);
        do_read(16'h0045);
        check_eq("P1-06f", "new block offset 1 is HIT",            1, last_hit);
        check_eq("P1-06g", "new block offset 1 correct",           shadow[16'h0045], rd_result);

        // ---- P1-07 evicted block misses again --------------------------
        do_read(16'h0004);
        check_eq("P1-07a", "evicted block re-access is MISS",      0, last_hit);
        check_eq("P1-07b", "re-fetched byte correct",              shadow[16'h0004], rd_result);
        check_eq("P1-07c", "line 1 tag back to 0x000",             10'h000, dut.u_cache.tag_array[1]);

        // ---- P1-08 non-conflicting line unaffected ---------------------
        mr0 = tot_mem_rd;
        do_read(16'h0009);
        check_eq("P1-08a", "line 2 survived the line-1 conflict",  1, last_hit);
        check_eq("P1-08b", "line 2 byte correct",                  shadow[16'h0009], rd_result);
        check_eq("P1-08c", "no memory read",                       mr0, tot_mem_rd);

        // ---- P1-09 address-space extremes ------------------------------
        do_read(16'h0000);                                 // tag 0x000 idx 0 off 0
        check_eq("P1-09a", "0x0000 MISS",                          0, last_hit);
        check_eq("P1-09b", "0x0000 byte correct",                  shadow[16'h0000], rd_result);
        do_read(16'hFFFF);                                 // tag 0x3FF idx 15 off 3
        check_eq("P1-09c", "0xFFFF MISS",                          0, last_hit);
        check_eq("P1-09d", "0xFFFF byte correct",                  shadow[16'hFFFF], rd_result);
        check_eq("P1-09e", "line 15 tag = 0x3FF",                  10'h3FF, dut.u_cache.tag_array[15]);
        check_eq("P1-09f", "line 15 holds block 0xFFFC..FF",       shadow_block(16'hFFFC), dut.u_cache.data_array[15]);
        do_read(16'hFFFC);
        check_eq("P1-09g", "0xFFFC (offset 0) HIT",                1, last_hit);
        check_eq("P1-09h", "0xFFFC byte correct (byte order)",     shadow[16'hFFFC], rd_result);

        // ---- P1-10 write-miss / write-allocate smoke -------------------
        // 0x0102 = tag 4, index 0, offset 2 ; line 0 currently holds tag 0 (0x0000)
        mr0 = tot_mem_rd; mw0 = tot_mem_wr;
        do_write(16'h0102, 8'hA5);
        check_eq("P1-10a", "write to uncached block is MISS",      0, last_hit);
        check_eq("P1-10b", "write-allocate: one block fetch",      mr0+1, tot_mem_rd);
        check_eq("P1-10c", "write-through: one memory write",      mw0+1, tot_mem_wr);
        check_eq("P1-10d", "memory byte 0x0102 = 0xA5",            8'hA5, dut.u_mem.mem[16'h0102]);
        check_eq("P1-10e", "memory byte 0x0100 untouched",         shadow[16'h0100], dut.u_mem.mem[16'h0100]);
        check_eq("P1-10f", "memory byte 0x0101 untouched",         shadow[16'h0101], dut.u_mem.mem[16'h0101]);
        check_eq("P1-10g", "memory byte 0x0103 untouched",         shadow[16'h0103], dut.u_mem.mem[16'h0103]);
        check_eq("P1-10h", "line 0 tag = 0x004 (allocated)",       10'h004, dut.u_cache.tag_array[0]);
        check_eq("P1-10i", "line 0 block = merged",                shadow_block(16'h0100), dut.u_cache.data_array[0]);
        for (i = 0; i < 4; i = i + 1) begin
            aa = 16'h0100 + i;
            do_read(aa);
            check_eq("P1-10j", "read-after-write byte is HIT",     1, last_hit);
            check_eq("P1-10k", "read-after-write byte correct",    shadow[aa], rd_result);
        end

        // ---- P1-11 write-hit / write-through smoke ---------------------
        mr0 = tot_mem_rd; mw0 = tot_mem_wr;
        do_write(16'h0101, 8'h3C);
        check_eq("P1-11a", "write to cached block is HIT",         1, last_hit);
        check_eq("P1-11b", "no block fetch on write hit",          mr0, tot_mem_rd);
        check_eq("P1-11c", "exactly one memory write",             mw0+1, tot_mem_wr);
        check_eq("P1-11d", "memory byte 0x0101 = 0x3C",            8'h3C, dut.u_mem.mem[16'h0101]);
        check_eq("P1-11e", "cache line 0 block updated, others kept", shadow_block(16'h0100), dut.u_cache.data_array[0]);
        do_read(16'h0101);
        check_eq("P1-11f", "read-after-write returns 0x3C",        8'h3C, rd_result);

        // ---- P1-12 reset between transactions --------------------------
        @(negedge clk); rst = 1'b1;
        repeat (2) @(posedge clk);
        @(negedge clk); rst = 1'b0;
        @(negedge clk);
        check_eq("P1-12a", "valid bits cleared by reset",          0, dut.u_cache.valid_array);
        check_eq("P1-12b", "FSM back in IDLE",                     0, dbg_state);
        check_eq("P1-12c", "memory content survives reset",        8'h3C, dut.u_mem.mem[16'h0101]);
        do_read(16'h0101);
        check_eq("P1-12d", "post-reset access is MISS",            0, last_hit);
        check_eq("P1-12e", "post-reset data = written value",      8'h3C, rd_result);

        // ---- P1-13 tag-bit sensitivity: every one of the 10 tag bits matters --
        // Base 0x0020 = tag 0, index 8. For each tag bit b, the address that
        // differs ONLY in tag bit b maps to the same line and must MISS.
        do_read(16'h0020);
        for (i = 0; i < 10; i = i + 1) begin
            aa = 16'h0020 ^ (16'h0001 << (6 + i));
            mr0 = tot_mem_rd;
            do_read(aa);
            check_eq("P1-13a", "address differing in one tag bit is MISS",  0, last_hit);
            check_eq("P1-13b", "its byte is correct",                       shadow[aa], rd_result);
            check_eq("P1-13c", "its refill tag equals address tag",         aa[15:6], dut.u_cache.tag_array[8]);
            do_read(16'h0020);
            check_eq("P1-13d", "returning to base address is MISS (evicted)", 0, last_hit);
        end

        // ---- P1-14 protocol monitor summary ---------------------------
        repeat (5) @(posedge clk);
        check_eq("P1-14a", "monitor: protocol errors",             0, mon_errors);
        check_eq("P1-14b", "monitor: latency matches documented formula", 0, lat_mismatch);
        check_eq("P1-14c", "hit+miss count equals request count",  tot_req, tot_hit + tot_miss);

        $display("==== Statistics: requests=%0d hits=%0d misses=%0d mem_reads=%0d mem_writes=%0d ====",
                 tot_req, tot_hit, tot_miss, tot_mem_rd, tot_mem_wr);
        $display("==== SUMMARY (MEM_LATENCY=%0d): PASS=%0d FAIL=%0d ====", MEM_LATENCY, n_pass, n_fail);
        if (n_fail == 0 && mon_errors == 0) $display("RESULT: ALL TESTS PASSED");
        else                                $display("RESULT: FAILURES DETECTED");
        $finish;
    end

    // global watchdog
    initial begin
        #2000000;
        $display("[FAIL] global watchdog expired");
        $display("RESULT: FAILURES DETECTED");
        $finish;
    end

endmodule
