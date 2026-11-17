//==============================================================================
// cache_controller.v  --  FSM controller for the direct-mapped cache
//------------------------------------------------------------------------------
// Synthesizable Verilog-2001. Clock: posedge clk. Reset: synchronous, active
// high `rst`.
//
// CPU interface (single outstanding request, byte granularity)
//   cpu_req        request valid. A request is ACCEPTED on a rising clock edge
//                  at which (cpu_req && cpu_ready) is true. The address, we and
//                  wdata are latched on that edge, so the CPU may change or
//                  drop them afterwards.
//   cpu_ready      high only in IDLE: "I can accept a request this cycle".
//   cpu_resp_valid high for exactly ONE cycle (state RESPONSE) when the
//                  transaction is complete. For reads cpu_rdata holds the
//                  requested byte during that cycle. For writes cpu_rdata = 0.
//   cpu_rdata      result register; cleared when a request is accepted, so it
//                  can never show data from a previous transaction.
//   If cpu_req stays high, the controller simply accepts a new request in the
//   first IDLE cycle after each response (back-to-back, but not pipelined).
//
// Memory interface (see main_memory.v). mem_req/we/addr/wdata are held stable
// from the first cycle of a transaction until mem_done is seen.
//
// FSM (details in docs/fsm_design.md)
//   IDLE -> COMPARE_TAG -+-> READ_HIT  ----------------------------> RESPONSE
//                        +-> WRITE_HIT -> MEMORY_WRITE_WAIT --------> RESPONSE
//                        +-> READ_MISS  -+
//                        +-> WRITE_MISS -+-> MEMORY_READ_WAIT -> REFILL
//                                           -> (READ_HIT | WRITE_HIT) as above
//   After a refill the request is replayed as a HIT, so read data is always
//   taken from the cache array after the refill (never from a bypass path) and
//   a write-allocate write goes through exactly the same byte-update +
//   write-through path as a normal write hit.
//==============================================================================
`timescale 1ns/1ps

module cache_controller (
    input  wire        clk,
    input  wire        rst,

    // ---- CPU side ----
    input  wire        cpu_req,
    input  wire        cpu_we,
    input  wire [15:0] cpu_addr,
    input  wire [7:0]  cpu_wdata,
    output wire        cpu_ready,
    output wire        cpu_resp_valid,
    output wire [7:0]  cpu_rdata,

    // ---- cache array side ----
    output wire [3:0]  cache_index,
    output wire [1:0]  cache_offset,
    input  wire        cache_valid,
    input  wire [9:0]  cache_tag,
    input  wire [7:0]  cache_byte,
    output wire        cache_refill_en,
    output wire [9:0]  cache_refill_tag,
    output wire [31:0] cache_refill_data,
    output wire        cache_byte_we,
    output wire [7:0]  cache_byte_wdata,

    // ---- main memory side ----
    output wire        mem_req,
    output wire        mem_we,
    output wire [15:0] mem_addr,
    output wire [7:0]  mem_wdata,
    input  wire        mem_done,
    input  wire [31:0] mem_rdata,

    // ---- debug / observability ----
    output wire [3:0]  dbg_state,
    output wire        dbg_lookup,       // 1 in COMPARE_TAG: hit/tag_match valid
    output wire        dbg_tag_match,
    output wire        dbg_hit
);

    // ---- State encoding ------------------------------------------------------
    localparam [3:0] S_IDLE            = 4'd0,
                     S_COMPARE_TAG     = 4'd1,
                     S_READ_HIT        = 4'd2,
                     S_READ_MISS       = 4'd3,
                     S_MEMORY_READ_WAIT= 4'd4,
                     S_REFILL          = 4'd5,
                     S_WRITE_HIT       = 4'd6,
                     S_WRITE_MISS      = 4'd7,
                     S_MEMORY_WRITE_WAIT=4'd8,
                     S_RESPONSE        = 4'd9;

    reg [3:0] state, next_state;

    // ---- Latched request and datapath registers ------------------------------
    reg [15:0] req_addr;
    reg        req_we;
    reg [7:0]  req_wdata;
    reg [31:0] block_reg;       // block returned by memory, held until REFILL
    reg [7:0]  rdata_reg;       // byte returned to the CPU

    wire [9:0] req_tag    = req_addr[15:6];
    wire [3:0] req_index  = req_addr[5:2];
    wire [1:0] req_offset = req_addr[1:0];

    // ---- Hit detection (meaningful in COMPARE_TAG) ---------------------------
    wire tag_match = (cache_tag == req_tag);
    wire hit       = cache_valid && tag_match;

    // ---- State register ------------------------------------------------------
    always @(posedge clk) begin
        if (rst) state <= S_IDLE;
        else     state <= next_state;
    end

    // ---- Next-state logic ----------------------------------------------------
    always @(*) begin
        next_state = state;
        case (state)
            S_IDLE:
                if (cpu_req) next_state = S_COMPARE_TAG;

            S_COMPARE_TAG:
                if (hit) next_state = req_we ? S_WRITE_HIT  : S_READ_HIT;
                else     next_state = req_we ? S_WRITE_MISS : S_READ_MISS;

            S_READ_HIT:          next_state = S_RESPONSE;
            S_READ_MISS:         next_state = S_MEMORY_READ_WAIT;
            S_WRITE_MISS:        next_state = S_MEMORY_READ_WAIT;

            S_MEMORY_READ_WAIT:
                if (mem_done) next_state = S_REFILL;

            S_REFILL:            next_state = req_we ? S_WRITE_HIT : S_READ_HIT;

            S_WRITE_HIT:         next_state = S_MEMORY_WRITE_WAIT;

            S_MEMORY_WRITE_WAIT:
                if (mem_done) next_state = S_RESPONSE;

            S_RESPONSE:          next_state = S_IDLE;

            default:             next_state = S_IDLE;   // unused encodings
        endcase
    end

    // ---- Datapath registers (non-blocking, no reset needed for payload except
    //      the CPU-visible result register) ------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            req_addr  <= 16'd0;
            req_we    <= 1'b0;
            req_wdata <= 8'd0;
            block_reg <= 32'd0;
            rdata_reg <= 8'd0;
        end else begin
            if (state == S_IDLE && cpu_req) begin
                req_addr  <= cpu_addr;
                req_we    <= cpu_we;
                req_wdata <= cpu_wdata;
                rdata_reg <= 8'd0;                 // never show a stale result
            end
            if (state == S_MEMORY_READ_WAIT && mem_done)
                block_reg <= mem_rdata;
            if (state == S_READ_HIT)
                rdata_reg <= cache_byte;           // always read from the array
        end
    end

    // ---- Output logic (Moore) ------------------------------------------------
    assign cpu_ready      = (state == S_IDLE);
    assign cpu_resp_valid = (state == S_RESPONSE);
    assign cpu_rdata      = rdata_reg;

    assign cache_index       = req_index;
    assign cache_offset      = req_offset;
    assign cache_refill_en   = (state == S_REFILL);
    assign cache_refill_tag  = req_tag;
    assign cache_refill_data = block_reg;
    assign cache_byte_we     = (state == S_WRITE_HIT);   // 1 cycle -> 1 update
    assign cache_byte_wdata  = req_wdata;

    assign mem_we    = (state == S_MEMORY_WRITE_WAIT);
    assign mem_req   = (state == S_READ_MISS)  || (state == S_WRITE_MISS) ||
                       (state == S_MEMORY_READ_WAIT) ||
                       (state == S_MEMORY_WRITE_WAIT);
    assign mem_addr  = mem_we ? req_addr : {req_addr[15:2], 2'b00};
    assign mem_wdata = req_wdata;

    assign dbg_state     = state;
    assign dbg_lookup    = (state == S_COMPARE_TAG);
    assign dbg_tag_match = tag_match;
    assign dbg_hit       = hit;

endmodule
