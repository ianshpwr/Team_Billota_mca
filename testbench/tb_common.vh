//==============================================================================
// tb_common.vh  --  shared Phase 2 testbench infrastructure (simulation only)
//------------------------------------------------------------------------------
// `include`d INSIDE a testbench module, after `parameter MEM_LATENCY` is declared.
// Provides: clock, DUT instance (fixed-latency cache_top, or with -DVARLAT the
// variable-latency wrapper), protocol monitor, scoreboard (shadow memory),
// functional coverage counters, CPU driver tasks and check helpers.
//
// Monitor checks (every cycle, every transaction):
//   * response without an outstanding request / lasting > 1 cycle
//   * response before the required memory operations completed (exact count)
//   * array write commits in main memory == 1 per write, 0 per read (no duplicates)
//   * transaction latency == documented formula, using the MEASURED memory latency
//     (and, in fixed mode, measured memory latency == MEM_LATENCY)
//   * cpu_rdata is 0 from acceptance until the response (no stale data) and 0
//     in the response of a write
//   * cpu_ready low while busy; mem_req only while a request is outstanding;
//     mem_req/we/addr/wdata stable until mem_done; block reads are aligned
//   * after reset no spurious response appears
//==============================================================================

    localparam LATC = (MEM_LATENCY < 1) ? 1 : MEM_LATENCY;   // effective latency

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

`ifdef VARLAT
    cache_top_varlat #(.MAX_LAT(MEM_LATENCY)) dut (
`else
    cache_top #(.MEM_LATENCY(MEM_LATENCY)) dut (
`endif
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

    // Backdoor views (hierarchical, testbench only)
    wire        mem_fire_w = dut.u_mem.fire;
    wire        mem_opwe_w = dut.u_mem.op_we;

    // ---------------------------------------------------------------- clock
    initial clk = 1'b0;
    always #5 clk = ~clk;                       // 10 ns simulated period

    integer cyc;
    initial cyc = 0;

    // --------------------------------------------------------- scoreboard
    // Independent restatement of the documented init pattern.
    reg [7:0] shadow [0:65535];
    integer   s_i;
    initial begin
        for (s_i = 0; s_i < 65536; s_i = s_i + 1)
            shadow[s_i] = (s_i[7:0] ^ s_i[15:8]) + 8'h5A;
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

    // documented latency for FIXED memory latency (read hit 3, read miss 5+L,
    // write hit 4+L, write miss 6+2L)
    function integer exp_lat;
        input we;
        input hit;
        begin
            if (!we) exp_lat = hit ? 3 : (5 + LATC);
            else     exp_lat = hit ? (4 + LATC) : (6 + 2*LATC);
        end
    endfunction

    // ------------------------------------------------- cache array views
    function        cval;  input [3:0] i; begin cval  = dut.u_cache.valid_array[i]; end endfunction
    function [9:0]  ctag;  input [3:0] i; begin ctag  = dut.u_cache.tag_array[i];  end endfunction
    function [31:0] cblk;  input [3:0] i; begin cblk  = dut.u_cache.data_array[i]; end endfunction

    // ----------------------------------------------------- protocol monitor
    integer mon_errors;
    integer tot_req, tot_hit, tot_miss, tot_mem_rd, tot_mem_wr, tot_commits;
    integer tot_rd, tot_wr, tot_rd_hit, tot_rd_miss, tot_wr_hit, tot_wr_miss;
    integer lat_mismatch, memlat_mismatch;
    reg     m_busy, m_acc_we, m_hit, prev_resp, mreq_prev, mdone_prev;
    integer m_rd_done, m_wr_done, acc_cyc, m_commits0, m_memlat_sum, mem_start;
    integer last_resp_cyc;
    reg     [15:0] m_addr_prev; reg m_we_prev; reg [7:0] m_wd_prev;
    reg     last_hit;
    integer last_lat, last_gap, last_commits, last_memlat_sum;
    integer last_rd_done, last_wr_done;
    reg     [3:0] prev_state;
    // functional coverage
    integer cov_trans [0:255];
    integer cov_idx_rd [0:15];
    integer cov_idx_wr [0:15];
    integer cov_off_rd [0:3];
    integer cov_off_wr [0:3];
    integer cov_rd_hit, cov_rd_miss, cov_wr_hit, cov_wr_miss;
    integer cov_i;
    integer memlat_hist [0:63];
    integer cov_conflict, cov_cold;            // miss on valid line / on invalid line
    reg     m_line_was_valid;
    reg     cov_pause;                          // TB sets to 1 while it deliberately forces illegal states

    initial begin
        mon_errors = 0; tot_req = 0; tot_hit = 0; tot_miss = 0;
        tot_mem_rd = 0; tot_mem_wr = 0; tot_commits = 0;
        tot_rd = 0; tot_wr = 0; tot_rd_hit = 0; tot_rd_miss = 0; tot_wr_hit = 0; tot_wr_miss = 0;
        lat_mismatch = 0; memlat_mismatch = 0;
        m_busy = 0; m_acc_we = 0; m_hit = 0; prev_resp = 0; mreq_prev = 0; mdone_prev = 0;
        m_rd_done = 0; m_wr_done = 0; acc_cyc = 0; m_commits0 = 0; m_memlat_sum = 0; mem_start = 0;
        last_resp_cyc = -10; last_hit = 0; last_lat = 0; last_gap = 0; last_commits = 0;
        last_memlat_sum = 0; last_rd_done = 0; last_wr_done = 0; prev_state = 0;
        m_addr_prev = 0; m_we_prev = 0; m_wd_prev = 0; m_line_was_valid = 0; cov_pause = 0;
        for (cov_i = 0; cov_i < 256; cov_i = cov_i + 1) cov_trans[cov_i] = 0;
        for (cov_i = 0; cov_i < 16;  cov_i = cov_i + 1) begin cov_idx_rd[cov_i] = 0; cov_idx_wr[cov_i] = 0; end
        for (cov_i = 0; cov_i < 4;   cov_i = cov_i + 1) begin cov_off_rd[cov_i] = 0; cov_off_wr[cov_i] = 0; end
        for (cov_i = 0; cov_i < 64; cov_i = cov_i + 1) memlat_hist[cov_i] = 0;
        cov_rd_hit = 0; cov_rd_miss = 0; cov_wr_hit = 0; cov_wr_miss = 0; cov_conflict = 0; cov_cold = 0;
    end

    task mon_err;
        input [8*64-1:0] msg;
        begin
            mon_errors = mon_errors + 1;
            $display("[MONITOR ERROR] t=%0t cyc=%0d : %0s", $time, cyc, msg);
        end
    endtask

    always @(posedge clk) begin
        cyc = cyc + 1;                          // single writer -> no race
        if (rst) begin
            // reset aborts everything: forget the outstanding request
            m_busy = 0; prev_resp = 0; mreq_prev = 0; mdone_prev = 0;
            prev_state = 4'd0;
        end else begin
            // ---- FSM transition coverage -----------------------------------
            if (!cov_pause && (^dbg_state !== 1'bx)) begin
                cov_trans[{prev_state, dbg_state}] = cov_trans[{prev_state, dbg_state}] + 1;
                prev_state = dbg_state;
            end
            // ---- hit/miss classification (COMPARE_TAG) ----------------------
            if (dbg_lookup) begin
                m_hit = dbg_hit;
                m_line_was_valid = dbg_line_valid;
                if (dbg_hit) tot_hit = tot_hit + 1; else tot_miss = tot_miss + 1;
                if (m_acc_we) begin
                    if (dbg_hit) begin tot_wr_hit = tot_wr_hit + 1; cov_wr_hit = cov_wr_hit + 1; end
                    else         begin tot_wr_miss = tot_wr_miss + 1; cov_wr_miss = cov_wr_miss + 1; end
                end else begin
                    if (dbg_hit) begin tot_rd_hit = tot_rd_hit + 1; cov_rd_hit = cov_rd_hit + 1; end
                    else         begin tot_rd_miss = tot_rd_miss + 1; cov_rd_miss = cov_rd_miss + 1; end
                end
                if (!dbg_hit) begin
                    if (dbg_line_valid) cov_conflict = cov_conflict + 1;
                    else                cov_cold = cov_cold + 1;
                end
            end
            // ---- ready/busy --------------------------------------------------
            if (cpu_ready && m_busy) mon_err("cpu_ready high while a request is outstanding");
            // ---- acceptance --------------------------------------------------
            if (cpu_req && cpu_ready) begin
                m_busy = 1; m_acc_we = cpu_we; m_rd_done = 0; m_wr_done = 0;
                m_memlat_sum = 0; m_commits0 = tot_commits;
                acc_cyc = cyc; tot_req = tot_req + 1; last_gap = cyc - last_resp_cyc;
                if (cpu_we) begin tot_wr = tot_wr + 1; cov_idx_wr[cpu_addr[5:2]] = cov_idx_wr[cpu_addr[5:2]] + 1;
                                  cov_off_wr[cpu_addr[1:0]] = cov_off_wr[cpu_addr[1:0]] + 1; end
                else         begin tot_rd = tot_rd + 1; cov_idx_rd[cpu_addr[5:2]] = cov_idx_rd[cpu_addr[5:2]] + 1;
                                  cov_off_rd[cpu_addr[1:0]] = cov_off_rd[cpu_addr[1:0]] + 1; end
            end
            // ---- stale data: rdata must be 0 until the response -------------
            if (m_busy && !cpu_resp_valid && cpu_rdata !== 8'h00 && !(cpu_req && cpu_ready))
                mon_err("cpu_rdata non-zero before response (stale data)");
            // ---- memory bus --------------------------------------------------
            if (mem_req && !m_busy) mon_err("memory request with no CPU request outstanding");
            if (mem_req && !mem_we && (mem_addr[1:0] != 2'b00)) mon_err("unaligned block read address");
            if (mem_req && !mreq_prev) mem_start = cyc;
            if (mem_req && mreq_prev && !mdone_prev) begin
                if (mem_addr !== m_addr_prev || mem_we !== m_we_prev || mem_wdata !== m_wd_prev)
                    mon_err("memory request changed before mem_done");
            end
            if (mem_fire_w && mem_opwe_w) tot_commits = tot_commits + 1;   // array write happens at this edge
            if (mem_done) begin
                if (!mem_req) mon_err("mem_done without mem_req");
                m_memlat_sum = m_memlat_sum + (cyc - mem_start);
                if (cyc - mem_start < 63) memlat_hist[cyc - mem_start] = memlat_hist[cyc - mem_start] + 1;
                else memlat_hist[63] = memlat_hist[63] + 1;
`ifndef VARLAT
                if (cyc - mem_start != LATC) begin
                    memlat_mismatch = memlat_mismatch + 1;
                    $display("[MONITOR] memory latency %0d != configured %0d", cyc - mem_start, LATC);
                end
`endif
                if (mem_we) begin m_wr_done = m_wr_done + 1; tot_mem_wr = tot_mem_wr + 1; end
                else        begin m_rd_done = m_rd_done + 1; tot_mem_rd = tot_mem_rd + 1; end
            end
            m_addr_prev = mem_addr; m_we_prev = mem_we; m_wd_prev = mem_wdata;
            mreq_prev = mem_req; mdone_prev = mem_done;
            // ---- response ----------------------------------------------------
            if (cpu_resp_valid) begin
                if (!m_busy) mon_err("response with no request outstanding");
                else begin
                    if (m_rd_done != (m_hit ? 0 : 1) || m_wr_done != (m_acc_we ? 1 : 0))
                        mon_err("response before/without required memory operations");
                    if (tot_commits - m_commits0 != (m_acc_we ? 1 : 0))
                        mon_err("wrong number of memory array writes (duplicate/missing write)");
                    if (!m_acc_we && m_hit) begin
                        if (cyc - acc_cyc != 3) lat_mismatch = lat_mismatch + 1;
                    end else begin
                        if (cyc - acc_cyc != ((m_acc_we ? (m_hit ? 4 : 6) : 5) + m_memlat_sum)) begin
                            lat_mismatch = lat_mismatch + 1;
                            $display("[MONITOR] latency %0d != formula %0d (we=%0d hit=%0d memsum=%0d)",
                                cyc - acc_cyc, (m_acc_we ? (m_hit ? 4 : 6) : 5) + m_memlat_sum, m_acc_we, m_hit, m_memlat_sum);
                        end
                    end
                    if (m_acc_we && cpu_rdata !== 8'h00) mon_err("write response has non-zero cpu_rdata");
                    last_hit = m_hit; last_lat = cyc - acc_cyc;
                    last_rd_done = m_rd_done; last_wr_done = m_wr_done;
                    last_commits = tot_commits - m_commits0; last_memlat_sum = m_memlat_sum;
                    last_resp_cyc = cyc;
                    m_busy = 0;
                end
                if (prev_resp) mon_err("cpu_resp_valid high for more than one cycle");
                if (cpu_ready) mon_err("cpu_ready high during response");
                if (mem_req)   mon_err("mem_req still high during response");
            end
            prev_resp = cpu_resp_valid;
        end
    end

    // ------------------------------------------------- check bookkeeping
    integer n_pass, n_fail;
    integer t_pass, t_fail, tests_run, tests_failed;
    integer q_n, q_bad;                          // quiet (aggregated) checks
    reg [8*10-1:0]  cur_id;
    initial begin n_pass = 0; n_fail = 0; t_pass = 0; t_fail = 0; tests_run = 0; tests_failed = 0;
                  q_n = 0; q_bad = 0; end

    task begin_test;
        input [8*10-1:0]  id;
        input [8*160-1:0] desc;
        input [8*160-1:0] init;
        input [8*160-1:0] stim;
        begin
            cur_id = id; t_pass = 0; t_fail = 0; q_n = 0; q_bad = 0;
            $display("[TEST] %0s : %0s", id, desc);
            $display("       init: %0s", init);
            $display("       stim: %0s", stim);
        end
    endtask

    task end_test;
        begin
            tests_run = tests_run + 1;
            if (t_fail == 0) $display("[TEST-RESULT] %0s PASS (%0d checks)", cur_id, t_pass);
            else begin
                tests_failed = tests_failed + 1;
                $display("[TEST-RESULT] %0s FAIL (%0d failed of %0d checks)", cur_id, t_fail, t_pass + t_fail);
            end
        end
    endtask

    task check_eq;
        input [8*10-1:0]  id;
        input [8*72-1:0]  desc;
        input [31:0]      expected;
        input [31:0]      actual;
        begin
            if (expected === actual) begin
                n_pass = n_pass + 1; t_pass = t_pass + 1;
                $display("  [PASS] %0s %0s | expected=0x%0h actual=0x%0h", id, desc, expected, actual);
            end else begin
                n_fail = n_fail + 1; t_fail = t_fail + 1;
                $display("  [FAIL] %0s %0s | expected=0x%0h actual=0x%0h", id, desc, expected, actual);
            end
        end
    endtask

    // quiet check: counts silently, prints only failures; flushed as ONE check
    task qcheck;
        input [8*72-1:0]  what;
        input [31:0]      expected;
        input [31:0]      actual;
        begin
            q_n = q_n + 1;
            if (expected !== actual) begin
                q_bad = q_bad + 1;
                if (q_bad <= 20)
                    $display("  [QFAIL] %0s : %0s expected=0x%0h actual=0x%0h", cur_id, what, expected, actual);
            end
        end
    endtask

    task qflush;
        input [8*10-1:0]  id;
        input [8*72-1:0]  desc;
        begin
            if (q_bad == 0) begin
                n_pass = n_pass + 1; t_pass = t_pass + 1;
                $display("  [PASS] %0s %0s | %0d sub-checks, 0 mismatches", id, desc, q_n);
            end else begin
                n_fail = n_fail + 1; t_fail = t_fail + 1;
                $display("  [FAIL] %0s %0s | %0d sub-checks, %0d mismatches", id, desc, q_n, q_bad);
            end
            q_n = 0; q_bad = 0;
        end
    endtask

    // ------------------------------------------------------- CPU driver
    // Drives on the falling edge, samples on the rising edge (race free).
    // After acceptance the request pins are scrambled to prove the controller
    // latched the request.
    reg [7:0] rd_result;
    integer   to;
    integer   guard_to;
    integer   obs_s4, obs_s8;                    // cycles seen in MEMORY_READ_WAIT / MEMORY_WRITE_WAIT
    initial begin obs_s4 = 0; obs_s8 = 0; end

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
                    $display("[FAIL] TIMEOUT waiting for cpu_ready"); n_fail = n_fail + 1; t_fail = t_fail + 1;
                    accepted = 1'b1;
                end
            end
            @(negedge clk);
            cpu_req = 1'b0; cpu_we = ~we_i; cpu_addr = ~a; cpu_wdata = ~wd;
            got = 1'b0; to = 0; obs_s4 = 0; obs_s8 = 0;
            while (!got) begin
                @(posedge clk);
                to = to + 1;
                if (dbg_state === 4'd4) obs_s4 = obs_s4 + 1;
                if (dbg_state === 4'd8) obs_s8 = obs_s8 + 1;
                if (cpu_resp_valid) begin got = 1'b1; rd_result = cpu_rdata; end
                if (to > 200 + 4*LATC + 4*MEM_LATENCY) begin
                    $display("[FAIL] TIMEOUT waiting for cpu_resp_valid (addr=0x%04h)", a);
                    n_fail = n_fail + 1; t_fail = t_fail + 1; got = 1'b1;
                end
            end
            #1;                                   // let the monitor update
            if (we_i) shadow[a] = wd;
        end
    endtask

    task do_read;  input [15:0] a;                begin cpu_access(1'b0, a, 8'h00); end endtask
    task do_write; input [15:0] a; input [7:0] d; begin cpu_access(1'b1, a, d);    end endtask

    // Reset helper: assert for n rising edges, release, wait one idle cycle.
    task do_reset;
        input integer n;
        begin
            @(negedge clk); rst = 1'b1;
            repeat (n) @(posedge clk);
            @(negedge clk); rst = 1'b0;
            @(negedge clk);
        end
    endtask

    // Start a request, let it be accepted, wait `k` more rising edges, then
    // assert reset for two edges (mid-transaction). Updates the scoreboard only
    // if the memory array write really committed before the reset.
    reg     abort_committed;
    task cpu_access_abort;
        input         we_i;
        input  [15:0] a;
        input  [7:0]  wd;
        input integer k;
        integer       c0, j;
        reg           accepted;
        begin
            @(negedge clk);
            cpu_req = 1'b1; cpu_we = we_i; cpu_addr = a; cpu_wdata = wd;
            accepted = 1'b0; to = 0;
            while (!accepted) begin
                @(posedge clk);
                if (cpu_ready) accepted = 1'b1;
            end
            c0 = tot_commits;                    // monitor already counted up to this edge
            @(negedge clk);
            cpu_req = 1'b0; cpu_we = ~we_i; cpu_addr = ~a; cpu_wdata = ~wd;
            for (j = 0; j < k; j = j + 1) @(negedge clk);
            // reset takes effect at the NEXT rising edge
            rst = 1'b1;
            @(posedge clk); #1;
            abort_committed = (tot_commits > c0);   // commit at or before the edge before reset
            @(posedge clk);
            @(negedge clk); rst = 1'b0;
            @(negedge clk);
            if (we_i && abort_committed) shadow[a] = wd;
        end
    endtask

    // ------------------------------------------------------- helper checks
    // read + check hit/miss + returned byte
    task rd_chk;
        input [8*10-1:0]  id;
        input [8*72-1:0]  desc;
        input [15:0]      a;
        input             exp_hit;
        begin
            do_read(a);
            check_eq(id, desc, exp_hit, last_hit);
            check_eq(id, "  returned byte equals memory image", shadow[a], rd_result);
        end
    endtask

    // all valid cache lines must equal the memory image of their block (write-through invariant)
    integer coh_i, coh_bad;
    reg [15:0] coh_base;
    task coherence_scan;
        output integer bad;
        begin
            bad = 0;
            for (coh_i = 0; coh_i < 16; coh_i = coh_i + 1) begin
                if (cval(coh_i)) begin
                    coh_base = {ctag(coh_i), coh_i[3:0], 2'b00};
                    if (cblk(coh_i) !== shadow_block(coh_base)) bad = bad + 1;
                    if (cblk(coh_i) !== {dut.u_mem.mem[coh_base+16'd3], dut.u_mem.mem[coh_base+16'd2],
                                         dut.u_mem.mem[coh_base+16'd1], dut.u_mem.mem[coh_base]}) bad = bad + 1;
                end
            end
        end
    endtask

    // full-memory comparison against the scoreboard
    integer mm_i, mm_bad;
    task memory_scan;
        output integer bad;
        begin
            bad = 0;
            for (mm_i = 0; mm_i < 65536; mm_i = mm_i + 1)
                if (dut.u_mem.mem[mm_i] !== shadow[mm_i]) bad = bad + 1;
        end
    endtask

    function integer count_valid;
        input dummy;
        integer ci;
        begin
            count_valid = 0;
            for (ci = 0; ci < 16; ci = ci + 1) if (cval(ci)) count_valid = count_valid + 1;
        end
    endfunction

    // ------------------------------------------------ held-high request stream
    // The CPU presents the NEXT request immediately after the previous one was
    // accepted and keeps cpu_req high the whole time (even while the controller
    // is busy). Expected data for reads is taken from the scoreboard at the
    // moment of acceptance (in-order execution).
    reg        st_we  [0:127];
    reg [15:0] st_a   [0:127];
    reg [7:0]  st_d   [0:127];
    reg [7:0]  st_exp [0:127];
    integer    st_n, stream_acc, stream_resp, stream_bad, stream_cycles, stream_maxhigh;
    task stream_run;
        integer ia, ir, guard, hi;
        begin
            ia = 0; ir = 0; guard = 0; stream_bad = 0; hi = 0; stream_maxhigh = 0;
            @(negedge clk);
            cpu_req = 1'b1; cpu_we = st_we[0]; cpu_addr = st_a[0]; cpu_wdata = st_d[0];
            while (ir < st_n && guard < 20000 + st_n * (400 + 8 * MEM_LATENCY)) begin
                @(posedge clk);
                guard = guard + 1;
                if (cpu_req) hi = hi + 1; else hi = 0;
                if (hi > stream_maxhigh) stream_maxhigh = hi;
                if (cpu_req && cpu_ready && ia < st_n) begin
                    st_exp[ia] = shadow[st_a[ia]];
                    if (st_we[ia]) shadow[st_a[ia]] = st_d[ia];
                    ia = ia + 1;
                end
                if (cpu_resp_valid) begin
                    if (ir >= ia) stream_bad = stream_bad + 1;
                    else if (!st_we[ir] && cpu_rdata !== st_exp[ir]) stream_bad = stream_bad + 1;
                    ir = ir + 1;
                end
                @(negedge clk);
                if (ia < st_n) begin
                    cpu_req = 1'b1; cpu_we = st_we[ia]; cpu_addr = st_a[ia]; cpu_wdata = st_d[ia];
                end else begin
                    cpu_req = 1'b0; cpu_we = 1'b0; cpu_addr = 16'hDEAD; cpu_wdata = 8'hAD;
                end
            end
            stream_acc = ia; stream_resp = ir; stream_cycles = guard;
            #1;
        end
    endtask

    // legal FSM transitions {from,to}: used by the coverage report
    function legal_trans;
        input [7:0] t;
        begin
            case (t)
                {4'd0,4'd0}, {4'd0,4'd1}, {4'd1,4'd2}, {4'd1,4'd3}, {4'd1,4'd6}, {4'd1,4'd7},
                {4'd2,4'd9}, {4'd3,4'd4}, {4'd4,4'd4}, {4'd4,4'd5}, {4'd5,4'd2}, {4'd5,4'd6},
                {4'd6,4'd8}, {4'd7,4'd4}, {4'd8,4'd8}, {4'd8,4'd9}, {4'd9,4'd0}: legal_trans = 1'b1;
                default: legal_trans = 1'b0;
            endcase
        end
    endfunction

    // global watchdog (generous; the directed bench is bounded by construction)
    initial begin
        #4000000000;
        $display("[FAIL] global watchdog expired");
        $display("RESULT: FAILURES DETECTED");
        $finish;
    end
