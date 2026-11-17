//==============================================================================
// cache_memory.v  --  Direct-mapped cache storage (16 lines x 4 bytes)
//------------------------------------------------------------------------------
// Synthesizable. Holds the data, tag and valid arrays only; ALL hit/miss
// decisions are made by cache_controller.
//
// Organisation : 16 lines. Per line: 1 valid bit, 10-bit tag, 32-bit block.
// Byte order   : little-endian within a block. Offset 0 -> block[7:0],
//                offset 1 -> block[15:8], offset 2 -> block[23:16],
//                offset 3 -> block[31:24].
// Read port    : asynchronous (combinational) read of the line selected by
//                `index`; `byte_o` additionally selects one byte by `offset`.
// Write ports  : synchronous, both address the line selected by `index`.
//                  refill_en : replace the WHOLE line (data + tag), set valid.
//                  byte_we   : replace ONE byte (selected by `offset`) and
//                              preserve the other three bytes. Tag/valid are
//                              unchanged.
//                If both are asserted, refill_en has priority (the controller
//                never asserts both). The controller only asserts byte_we for
//                a line that is already valid.
// Reset        : synchronous, active high. Clears valid bits and also zeroes
//                the data/tag arrays so simulation never shows X values.
//==============================================================================
`timescale 1ns/1ps

module cache_memory (
    input  wire        clk,
    input  wire        rst,            // synchronous, active high

    input  wire [3:0]  index,          // line select (address[5:2])
    input  wire [1:0]  offset,         // byte select (address[1:0])

    // read side (combinational)
    output wire        valid_o,        // valid bit of the selected line
    output wire [9:0]  tag_o,          // tag of the selected line
    output wire [31:0] block_o,        // 4-byte block of the selected line
    output wire [7:0]  byte_o,         // selected byte of the selected line

    // whole-line refill
    input  wire        refill_en,
    input  wire [9:0]  refill_tag,
    input  wire [31:0] refill_data,

    // single-byte update
    input  wire        byte_we,
    input  wire [7:0]  byte_wdata
);

    reg [31:0] data_array [0:15];
    reg [9:0]  tag_array  [0:15];
    reg [15:0] valid_array;

    integer i;

    // ---- Read path -----------------------------------------------------------
    assign valid_o = valid_array[index];
    assign tag_o   = tag_array[index];
    assign block_o = data_array[index];
    assign byte_o  = block_o[{offset, 3'b000} +: 8];

    // ---- Byte merge: replace one byte of a block, keep the other three -------
    function [31:0] merge_byte;
        input [31:0] blk;
        input [1:0]  off;
        input [7:0]  b;
        begin
            case (off)
                2'd0:    merge_byte = {blk[31:8],  b};
                2'd1:    merge_byte = {blk[31:16], b, blk[7:0]};
                2'd2:    merge_byte = {blk[31:24], b, blk[15:0]};
                default: merge_byte = {b, blk[23:0]};
            endcase
        end
    endfunction

    // ---- Write path ----------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            valid_array <= 16'd0;
            for (i = 0; i < 16; i = i + 1) begin
                data_array[i] <= 32'd0;
                tag_array[i]  <= 10'd0;
            end
        end else if (refill_en) begin
            data_array[index]  <= refill_data;
            tag_array[index]   <= refill_tag;
            valid_array[index] <= 1'b1;
        end else if (byte_we) begin
            data_array[index]  <= merge_byte(data_array[index], offset, byte_wdata);
        end
    end

endmodule
