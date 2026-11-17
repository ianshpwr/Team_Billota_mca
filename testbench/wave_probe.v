//==============================================================================
// wave_probe.v  --  TESTBENCH-ONLY signal collector for waveform screenshots
//------------------------------------------------------------------------------
// Pure observer: every port is an input. $dumpvars on this module (depth 1)
// produces a small VCD that contains only the signals worth reading, plus
// one-hot FSM state flags (st_*) and the decoded fields of the latched request.
//==============================================================================
`timescale 1ns/1ps

module wave_probe (
    input wire        clk,
    input wire        rst,
    input wire        cpu_req,
    input wire        cpu_we,
    input wire [15:0] cpu_addr,
    input wire [7:0]  cpu_wdata,
    input wire        cpu_ready,
    input wire        cpu_resp_valid,
    input wire [7:0]  cpu_rdata,
    input wire [3:0]  dbg_state,
    input wire [15:0] lat_addr,          // address latched by the controller
    input wire        dbg_lookup,
    input wire        dbg_tag_match,
    input wire        dbg_hit,
    input wire        dbg_line_valid,
    input wire [9:0]  dbg_tag,           // tag stored in the indexed line
    input wire        dbg_refill,
    input wire        dbg_byte_we,
    input wire        mem_req,
    input wire        mem_we,
    input wire [15:0] mem_addr,
    input wire [7:0]  mem_wdata,
    input wire        mem_done,
    input wire [31:0] mem_rdata
);
    // one-hot FSM state flags (idle, cmp=COMPARE_TAG, rhit=READ_HIT, rmiss=READ_MISS,
    // rwait=MEMORY_READ_WAIT, refill=REFILL, whit=WRITE_HIT, wmiss=WRITE_MISS,
    // wwait=MEMORY_WRITE_WAIT, resp=RESPONSE): readable in any waveform viewer without a
    // translation filter (dbg_state still carries the numeric encoding)
    wire st_idle            = (dbg_state == 4'd0);
    wire st_cmp          = (dbg_state == 4'd1);
    wire st_rhit           = (dbg_state == 4'd2);
    wire st_rmiss         = (dbg_state == 4'd3);
    wire st_rwait          = (dbg_state == 4'd4);
    wire st_refill         = (dbg_state == 4'd5);
    wire st_whit          = (dbg_state == 4'd6);
    wire st_wmiss        = (dbg_state == 4'd7);
    wire st_wwait         = (dbg_state == 4'd8);
    wire st_resp           = (dbg_state == 4'd9);
    wire [9:0] req_tag    = lat_addr[15:6];
    wire [3:0] req_index  = lat_addr[5:2];
    wire [1:0] req_offset = lat_addr[1:0];
endmodule
