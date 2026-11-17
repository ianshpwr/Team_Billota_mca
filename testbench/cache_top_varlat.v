//==============================================================================
// cache_top_varlat.v  --  TESTBENCH-ONLY variant of cache_top (simulation only)
//------------------------------------------------------------------------------
// Same ports and instance names as rtl/cache_top.v (u_ctrl, u_cache, u_mem), but
// main memory is `tb_mem_varlat`: each transaction gets a pseudo-random latency
// in [1, MAX_LAT] (deterministic xorshift generator, fixed seed). The RTL under
// test (cache_controller, cache_memory) is the unmodified rtl/ source.
// Purpose: exercise irregular memory delays (spec tests 25 / latency variety).
// Handshake semantics are identical to rtl/main_memory.v.
//==============================================================================
`timescale 1ns/1ps

module tb_mem_varlat #(
    parameter MAX_LAT = 8,
    parameter [31:0] SEED = 32'h1BADB002
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        req,
    input  wire        we,
    input  wire [15:0] addr,
    input  wire [7:0]  wdata,
    output wire        done,
    output wire [31:0] rdata
);
    localparam [1:0] M_IDLE = 2'd0, M_BUSY = 2'd1, M_DONE = 2'd2;
    localparam MAXL = (MAX_LAT < 1) ? 1 : MAX_LAT;

    reg [7:0]  mem [0:65535];
    reg [1:0]  mstate;
    reg [15:0] cnt;
    reg [15:0] lat_addr;
    reg        lat_we;
    reg [7:0]  lat_wdata;
    reg [31:0] rdata_q;
    reg [31:0] rnd;                         // free-running xorshift32

    function [7:0] init_byte; input [15:0] a; begin init_byte = (a[7:0] ^ a[15:8]) + 8'h5A; end endfunction
    integer k;
    initial begin
        for (k = 0; k < 65536; k = k + 1) mem[k] = init_byte(k[15:0]);
        rnd = SEED;
    end
    reg [31:0] r1, r2;
    always @(posedge clk) begin   // full xorshift32 step using temporaries
        r1 = rnd ^ (rnd << 13);
        r2 = r1 ^ (r1 >> 17);
        rnd <= r2 ^ (r2 << 5);
    end

    wire [15:0] lat_new = 16'd1 + (rnd[23:8] % MAXL);

    wire        accept   = (mstate == M_IDLE) && req;
    wire        fire     = (accept && (lat_new == 16'd1)) || ((mstate == M_BUSY) && (cnt == 16'd1));
    wire [15:0] op_addr  = (mstate == M_IDLE) ? addr  : lat_addr;
    wire        op_we    = (mstate == M_IDLE) ? we    : lat_we;
    wire [7:0]  op_wdata = (mstate == M_IDLE) ? wdata : lat_wdata;
    wire [15:0] blk_base = {op_addr[15:2], 2'b00};

    always @(posedge clk) begin
        if (rst) begin
            mstate <= M_IDLE; cnt <= 16'd0; lat_addr <= 16'd0; lat_we <= 1'b0;
            lat_wdata <= 8'd0; rdata_q <= 32'd0;
        end else begin
            case (mstate)
                M_IDLE: if (req) begin
                    lat_addr <= addr; lat_we <= we; lat_wdata <= wdata;
                    if (lat_new == 16'd1) mstate <= M_DONE;
                    else begin mstate <= M_BUSY; cnt <= lat_new - 16'd1; end
                end
                M_BUSY: if (cnt == 16'd1) mstate <= M_DONE; else cnt <= cnt - 16'd1;
                M_DONE:  mstate <= M_IDLE;
                default: mstate <= M_IDLE;
            endcase
            if (fire) begin
                if (op_we) mem[op_addr] <= op_wdata;
                else rdata_q <= { mem[blk_base + 16'd3], mem[blk_base + 16'd2],
                                  mem[blk_base + 16'd1], mem[blk_base] };
            end
        end
    end
    assign done  = (mstate == M_DONE);
    assign rdata = rdata_q;
endmodule

module cache_top_varlat #(
    parameter MAX_LAT = 8
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        cpu_req,
    input  wire        cpu_we,
    input  wire [15:0] cpu_addr,
    input  wire [7:0]  cpu_wdata,
    output wire        cpu_ready,
    output wire        cpu_resp_valid,
    output wire [7:0]  cpu_rdata,
    output wire        mem_req,
    output wire        mem_we,
    output wire [15:0] mem_addr,
    output wire [7:0]  mem_wdata,
    output wire        mem_done,
    output wire [31:0] mem_rdata,
    output wire [3:0]  dbg_state,
    output wire        dbg_lookup,
    output wire        dbg_tag_match,
    output wire        dbg_hit,
    output wire        dbg_line_valid,
    output wire [9:0]  dbg_tag,
    output wire [3:0]  dbg_index,
    output wire [1:0]  dbg_offset,
    output wire        dbg_refill,
    output wire        dbg_byte_we
);
    wire [3:0]  cache_index;  wire [1:0] cache_offset;  wire cache_valid;
    wire [9:0]  cache_tag;    wire [31:0] cache_block;  wire [7:0] cache_byte;
    wire        cache_refill_en;  wire [9:0] cache_refill_tag;  wire [31:0] cache_refill_data;
    wire        cache_byte_we;    wire [7:0] cache_byte_wdata;

    cache_controller u_ctrl (
        .clk(clk), .rst(rst), .cpu_req(cpu_req), .cpu_we(cpu_we), .cpu_addr(cpu_addr),
        .cpu_wdata(cpu_wdata), .cpu_ready(cpu_ready), .cpu_resp_valid(cpu_resp_valid),
        .cpu_rdata(cpu_rdata), .cache_index(cache_index), .cache_offset(cache_offset),
        .cache_valid(cache_valid), .cache_tag(cache_tag), .cache_byte(cache_byte),
        .cache_refill_en(cache_refill_en), .cache_refill_tag(cache_refill_tag),
        .cache_refill_data(cache_refill_data), .cache_byte_we(cache_byte_we),
        .cache_byte_wdata(cache_byte_wdata), .mem_req(mem_req), .mem_we(mem_we),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_done(mem_done), .mem_rdata(mem_rdata),
        .dbg_state(dbg_state), .dbg_lookup(dbg_lookup), .dbg_tag_match(dbg_tag_match), .dbg_hit(dbg_hit));

    cache_memory u_cache (
        .clk(clk), .rst(rst), .index(cache_index), .offset(cache_offset),
        .valid_o(cache_valid), .tag_o(cache_tag), .block_o(cache_block), .byte_o(cache_byte),
        .refill_en(cache_refill_en), .refill_tag(cache_refill_tag), .refill_data(cache_refill_data),
        .byte_we(cache_byte_we), .byte_wdata(cache_byte_wdata));

    tb_mem_varlat #(.MAX_LAT(MAX_LAT)) u_mem (
        .clk(clk), .rst(rst), .req(mem_req), .we(mem_we), .addr(mem_addr),
        .wdata(mem_wdata), .done(mem_done), .rdata(mem_rdata));

    assign dbg_line_valid = cache_valid;
    assign dbg_tag        = cache_tag;
    assign dbg_index      = cache_index;
    assign dbg_offset     = cache_offset;
    assign dbg_refill     = cache_refill_en;
    assign dbg_byte_we    = cache_byte_we;
endmodule
