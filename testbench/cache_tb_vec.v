//==============================================================================
// cache_tb_vec.v  --  vector-driven testbench for reference-model comparison
//------------------------------------------------------------------------------
// Replays a transaction file and logs the observed behaviour of the DUT in a
// line format that verification/reference_model.py reproduces independently.
//
// Plusargs: +vec=<file>   input vectors (hex words, one per line)
//           +out=<file>   result log   (transaction lines, final cache state)
//           +memdump=<f>  final 64 KiB memory image ($writememh format)
//           +vcd=<file>   optional waveform (curated signals via wave_probe)
// Vector word (32 bit, 8 hex digits):  {op[7:0], addr[15:0], wdata[7:0]}
//   op 00 = read addr                     op 01 = write wdata to addr
//   op 02 = reset (2 cycles)              op 03 = idle for `wdata` cycles
//   op FF = end of vectors
// Log lines:
//   T <n> <op> <addr hex4> <wdata hex2> <hit> <rdata hex2> <latency> <mem_rd> <mem_wr>
//   R <n>            reset performed        I <n> <cycles>   idle
//   C <line> <valid> <tag hex3> <data hex8> final cache state (16 lines)
//==============================================================================
`timescale 1ns/1ps

module cache_tb_vec;

    parameter MEM_LATENCY = 4;

    `include "tb_common.vh"

    reg [31:0] vecmem [0:262143];
    reg [8*256-1:0] vec_name, out_name, dump_name, vcd_name;
    integer fo, idx, ntxn, ii;
    reg [31:0] w;
    reg        done;
    integer    mr_before, mw_before;

    wave_probe wp (
        .clk(clk), .rst(rst), .cpu_req(cpu_req), .cpu_we(cpu_we), .cpu_addr(cpu_addr),
        .cpu_wdata(cpu_wdata), .cpu_ready(cpu_ready), .cpu_resp_valid(cpu_resp_valid),
        .cpu_rdata(cpu_rdata), .dbg_state(dbg_state), .lat_addr(dut.u_ctrl.req_addr),
        .dbg_lookup(dbg_lookup), .dbg_tag_match(dbg_tag_match), .dbg_hit(dbg_hit),
        .dbg_line_valid(dbg_line_valid), .dbg_tag(dbg_tag), .dbg_refill(dbg_refill),
        .dbg_byte_we(dbg_byte_we), .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr),
        .mem_wdata(mem_wdata), .mem_done(mem_done), .mem_rdata(mem_rdata)
    );

    initial begin
        if ($value$plusargs("vcd=%s", vcd_name)) begin
            $dumpfile(vcd_name);
            $dumpvars(1, wp);
        end
    end

    initial begin
        for (ii = 0; ii < 262144; ii = ii + 1) vecmem[ii] = 32'hFFFFFFFF;
        if (!$value$plusargs("vec=%s", vec_name)) begin
            $display("ERROR: +vec=<file> is required"); $finish;
        end
        if (!$value$plusargs("out=%s", out_name)) out_name = "build/vec_out.txt";
        $readmemh(vec_name, vecmem);
        fo = $fopen(out_name, "w");
        rst = 1'b1; cpu_req = 1'b0; cpu_we = 1'b0; cpu_addr = 16'h0; cpu_wdata = 8'h0;
        repeat (4) @(posedge clk);
        @(negedge clk); rst = 1'b0;
        @(negedge clk);

        idx = 0; ntxn = 0; done = 1'b0;
        while (!done) begin
            w = vecmem[idx];
            if ((^w === 1'bx) || (w[31:24] == 8'hFF)) done = 1'b1;
            else begin
                case (w[31:24])
                    8'h00: begin
                        do_read(w[23:8]);
                        $fdisplay(fo, "T %0d 0 %04h %02h %0d %02h %0d %0d %0d", idx, w[23:8], w[7:0],
                                  last_hit, rd_result, last_lat, last_rd_done, last_wr_done);
                    end
                    8'h01: begin
                        do_write(w[23:8], w[7:0]);
                        $fdisplay(fo, "T %0d 1 %04h %02h %0d %02h %0d %0d %0d", idx, w[23:8], w[7:0],
                                  last_hit, rd_result, last_lat, last_rd_done, last_wr_done);
                    end
                    8'h02: begin do_reset(2); $fdisplay(fo, "R %0d", idx); end
                    8'h03: begin repeat (w[7:0]) @(negedge clk); $fdisplay(fo, "I %0d %0d", idx, w[7:0]); end
                    default: begin $display("ERROR: bad op %0h at %0d", w[31:24], idx); done = 1'b1; end
                endcase
                idx = idx + 1;
            end
        end
        repeat (5) @(posedge clk);
        for (ii = 0; ii < 16; ii = ii + 1)
            $fdisplay(fo, "C %0d %0d %03h %08h", ii, cval(ii), ctag(ii), cblk(ii));
        $fclose(fo);
        if ($value$plusargs("memdump=%s", dump_name)) $writememh(dump_name, dut.u_mem.mem);
        $display("VEC_STATS file=%0s transactions=%0d cycles=%0d requests=%0d hits=%0d misses=%0d mem_reads=%0d mem_writes=%0d",
                 vec_name, idx, cyc, tot_req, tot_hit, tot_miss, tot_mem_rd, tot_mem_wr);
        $display("VEC_MONITOR errors=%0d latency_mismatches=%0d memory_latency_mismatches=%0d", mon_errors, lat_mismatch, memlat_mismatch);
        if (mon_errors == 0 && lat_mismatch == 0 && memlat_mismatch == 0) $display("RESULT: ALL TESTS PASSED");
        else $display("RESULT: FAILURES DETECTED");
        $finish;
    end

endmodule
