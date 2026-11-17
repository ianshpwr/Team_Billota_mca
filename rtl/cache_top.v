//==============================================================================
// cache_top.v  --  Top level: CPU-facing cache + behavioral main memory
//------------------------------------------------------------------------------
// Integrates cache_controller, cache_memory and main_memory.
// Synthesizable parts : cache_controller, cache_memory.
// Simulation model    : main_memory (initial-block memory fill).
//
// CPU-facing interface and protocol: see cache_controller.v / docs/module_interfaces.md
// The mem_* and dbg_* ports are observability outputs for the testbench and
// waveform viewer; a real CPU would leave them unconnected.
//==============================================================================
`timescale 1ns/1ps

module cache_top #(
    parameter MEM_LATENCY = 4              // main-memory latency in clock cycles
) (
    input  wire        clk,
    input  wire        rst,                // synchronous, active high

    // ---- CPU interface ----
    input  wire        cpu_req,
    input  wire        cpu_we,
    input  wire [15:0] cpu_addr,
    input  wire [7:0]  cpu_wdata,
    output wire        cpu_ready,
    output wire        cpu_resp_valid,
    output wire [7:0]  cpu_rdata,

    // ---- observability: memory bus ----
    output wire        mem_req,
    output wire        mem_we,
    output wire [15:0] mem_addr,
    output wire [7:0]  mem_wdata,
    output wire        mem_done,
    output wire [31:0] mem_rdata,

    // ---- observability: controller / cache ----
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

    // controller <-> cache array
    wire [3:0]  cache_index;
    wire [1:0]  cache_offset;
    wire        cache_valid;
    wire [9:0]  cache_tag;
    wire [31:0] cache_block;
    wire [7:0]  cache_byte;
    wire        cache_refill_en;
    wire [9:0]  cache_refill_tag;
    wire [31:0] cache_refill_data;
    wire        cache_byte_we;
    wire [7:0]  cache_byte_wdata;

    cache_controller u_ctrl (
        .clk              (clk),
        .rst              (rst),
        .cpu_req          (cpu_req),
        .cpu_we           (cpu_we),
        .cpu_addr         (cpu_addr),
        .cpu_wdata        (cpu_wdata),
        .cpu_ready        (cpu_ready),
        .cpu_resp_valid   (cpu_resp_valid),
        .cpu_rdata        (cpu_rdata),
        .cache_index      (cache_index),
        .cache_offset     (cache_offset),
        .cache_valid      (cache_valid),
        .cache_tag        (cache_tag),
        .cache_byte       (cache_byte),
        .cache_refill_en  (cache_refill_en),
        .cache_refill_tag (cache_refill_tag),
        .cache_refill_data(cache_refill_data),
        .cache_byte_we    (cache_byte_we),
        .cache_byte_wdata (cache_byte_wdata),
        .mem_req          (mem_req),
        .mem_we           (mem_we),
        .mem_addr         (mem_addr),
        .mem_wdata        (mem_wdata),
        .mem_done         (mem_done),
        .mem_rdata        (mem_rdata),
        .dbg_state        (dbg_state),
        .dbg_lookup       (dbg_lookup),
        .dbg_tag_match    (dbg_tag_match),
        .dbg_hit          (dbg_hit)
    );

    cache_memory u_cache (
        .clk         (clk),
        .rst         (rst),
        .index       (cache_index),
        .offset      (cache_offset),
        .valid_o     (cache_valid),
        .tag_o       (cache_tag),
        .block_o     (cache_block),
        .byte_o      (cache_byte),
        .refill_en   (cache_refill_en),
        .refill_tag  (cache_refill_tag),
        .refill_data (cache_refill_data),
        .byte_we     (cache_byte_we),
        .byte_wdata  (cache_byte_wdata)
    );

    main_memory #(.LATENCY(MEM_LATENCY)) u_mem (
        .clk   (clk),
        .rst   (rst),
        .req   (mem_req),
        .we    (mem_we),
        .addr  (mem_addr),
        .wdata (mem_wdata),
        .done  (mem_done),
        .rdata (mem_rdata)
    );

    assign dbg_line_valid = cache_valid;
    assign dbg_tag        = cache_tag;
    assign dbg_index      = cache_index;
    assign dbg_offset     = cache_offset;
    assign dbg_refill     = cache_refill_en;
    assign dbg_byte_we    = cache_byte_we;

endmodule
