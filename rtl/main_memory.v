//==============================================================================
// main_memory.v  --  Behavioral 64 KiB byte-addressable main-memory model
//------------------------------------------------------------------------------
// SIMULATION MODEL. The `initial` block that fills the array is simulation-only
// and is NOT intended for synthesis. The handshake logic itself is plain
// synchronous RTL.
//
// Capacity     : 65,536 bytes (every 16-bit byte address is valid).
// Byte order   : little-endian block view.
//                rdata = { mem[A+3], mem[A+2], mem[A+1], mem[A] }, A = addr & ~3
//                (byte at the aligned address occupies rdata[7:0]).
// Reads        : always return the full 4-byte block containing `addr`;
//                addr[1:0] is ignored (forced to 0).
// Writes       : single byte at the exact byte address `addr`; the other three
//                bytes of the block are never touched.
// Initial data : deterministic, mem[a] = (a[7:0] ^ a[15:8]) + 8'h5A  (mod 256).
//                Documented so the testbench and the Python model can
//                reproduce it independently.
//
// Handshake (single outstanding transaction)
//   * The master raises `req` (with we/addr/wdata) and HOLDS all of them stable
//     until it sees `done`.
//   * The slave accepts the request in the first cycle in which it is IDLE
//     and `req` is high (cycle 0). `LATENCY` = number of cycles from cycle 0
//     to the cycle in which `done` is high (LATENCY >= 1; smaller values are
//     clamped to 1).
//   * `done` is high for exactly ONE cycle (state DONE). For reads `rdata` is
//     valid during that cycle. For writes the byte is committed exactly once,
//     on the clock edge that enters the DONE state.
//   * The slave ignores `req` while BUSY or DONE, so a request that is still
//     held during the `done` cycle can never be re-accepted (no duplicate
//     write). The master must drop `req` in the cycle after `done`.
// Reset          : synchronous, active high. Aborts any transaction in flight
//                  (a write that has not yet committed is lost). Memory
//                  CONTENTS are preserved by reset (non-volatile behaviour).
//==============================================================================
`timescale 1ns/1ps

module main_memory #(
    parameter LATENCY = 4                  // cycles from request to `done`
) (
    input  wire        clk,
    input  wire        rst,                // synchronous, active high
    input  wire        req,                // request valid (held until done)
    input  wire        we,                 // 1 = byte write, 0 = block read
    input  wire [15:0] addr,               // byte address
    input  wire [7:0]  wdata,              // byte to write (when we = 1)
    output wire        done,               // 1-cycle completion pulse
    output wire [31:0] rdata               // aligned 4-byte block (reads)
);

    localparam LAT = (LATENCY < 1) ? 1 : LATENCY;

    localparam [1:0] M_IDLE = 2'd0,
                     M_BUSY = 2'd1,
                     M_DONE = 2'd2;

    reg [7:0]  mem [0:65535];              // byte array

    reg [1:0]  mstate;
    reg [15:0] cnt;                        // remaining BUSY cycles
    reg [15:0] lat_addr;
    reg        lat_we;
    reg [7:0]  lat_wdata;
    reg [31:0] rdata_q;

    // ---- Simulation-only deterministic initialisation ------------------------
    function [7:0] init_byte;
        input [15:0] a;
        begin
            init_byte = (a[7:0] ^ a[15:8]) + 8'h5A;
        end
    endfunction

    integer k;
    initial begin
        for (k = 0; k < 65536; k = k + 1)
            mem[k] = init_byte(k[15:0]);
    end

    // ---- Operation executed when the transaction completes -------------------
    // In the LAT==1 case the operation fires on the accept edge, so the live
    // inputs are used; otherwise the latched copies are used.
    wire        accept   = (mstate == M_IDLE) && req;
    wire        fire     = (accept && (LAT == 1)) ||
                           ((mstate == M_BUSY) && (cnt == 16'd1));
    wire [15:0] op_addr  = (mstate == M_IDLE) ? addr  : lat_addr;
    wire        op_we    = (mstate == M_IDLE) ? we    : lat_we;
    wire [7:0]  op_wdata = (mstate == M_IDLE) ? wdata : lat_wdata;
    wire [15:0] blk_base = {op_addr[15:2], 2'b00};

    always @(posedge clk) begin
        if (rst) begin
            mstate    <= M_IDLE;
            cnt       <= 16'd0;
            lat_addr  <= 16'd0;
            lat_we    <= 1'b0;
            lat_wdata <= 8'd0;
            rdata_q   <= 32'd0;
        end else begin
            case (mstate)
                M_IDLE: begin
                    if (req) begin
                        lat_addr  <= addr;
                        lat_we    <= we;
                        lat_wdata <= wdata;
                        if (LAT == 1) begin
                            mstate <= M_DONE;
                        end else begin
                            mstate <= M_BUSY;
                            cnt    <= LAT - 1;
                        end
                    end
                end
                M_BUSY: begin
                    if (cnt == 16'd1) mstate <= M_DONE;
                    else              cnt    <= cnt - 16'd1;
                end
                M_DONE:  mstate <= M_IDLE;
                default: mstate <= M_IDLE;
            endcase

            if (fire) begin
                if (op_we)
                    mem[op_addr] <= op_wdata;                  // exactly once
                else
                    rdata_q <= { mem[blk_base + 16'd3], mem[blk_base + 16'd2],
                                 mem[blk_base + 16'd1], mem[blk_base] };
            end
        end
    end

    assign done  = (mstate == M_DONE);
    assign rdata = rdata_q;

endmodule
