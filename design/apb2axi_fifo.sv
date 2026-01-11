/*------------------------------------------------------------------------------
 * File : design/fifo/apb2axi_fifo.sv
 * Desc : Wrapper FIFO used by APB2AXI.
 *        IMPLEMENTATION: Synopsys DesignWare DW_fifo_s1_sf
 *------------------------------------------------------------------------------*/

import apb2axi_pkg::*;

module apb2axi_fifo #(
    parameter int ENTRY_WIDTH = 32,
    parameter int FIFO_DEPTH  = 16
)(
    input  logic                   clk,
    input  logic                   resetn,

    // push side
    input  logic                   push_vld,
    output logic                   push_rdy,
    input  logic [ENTRY_WIDTH-1:0] push_data,

    // pop side
    output logic                   pop_vld,
    input  logic                   pop_rdy,
    output logic [ENTRY_WIDTH-1:0] pop_data
);

    // -----------------------------
    // DW wires
    // -----------------------------
    logic                   empty, almost_empty, half_full, almost_full, full, error;
    logic [ENTRY_WIDTH-1:0] data_out;

    logic push_req_n;
    logic pop_req_n;

    // ============================================================
    // ready/valid mapping
    // ============================================================
    assign push_rdy  = ~full;
    assign pop_vld   = ~empty;
    assign pop_data  = data_out;

    // ============================================================
    //   - push when (push_vld && push_rdy)
    //   - pop  when (pop_vld  && pop_rdy)
    // ============================================================
    assign push_req_n = ~(push_vld && push_rdy);
    assign pop_req_n  = ~(pop_vld  && pop_rdy);

    // ============================================================
    //   - rst_mode=0 => async reset (matches your resetn style)
    //   - diag_n tied high (disabled)
    // ============================================================
    DW_fifo_s1_sf #(
        .width     (ENTRY_WIDTH),
        .depth     (FIFO_DEPTH),
        .ae_level  (1),
        .af_level  (FIFO_DEPTH-1),
        .err_mode  (0),
        .rst_mode  (0)
    ) u_dw_fifo (
        .clk         (clk),
        .rst_n       (resetn),
        .push_req_n  (push_req_n),
        .pop_req_n   (pop_req_n),
        .diag_n      (1'b1),
        .data_in     (push_data),
        .empty       (empty),
        .almost_empty(almost_empty),
        .half_full   (half_full),
        .almost_full (almost_full),
        .full        (full),
        .error       (error),
        .data_out    (data_out)
    );

endmodule




// import apb2axi_pkg::*;

// module apb2axi_fifo #(
//     parameter int ENTRY_WIDTH   = 64,
//     parameter int FIFO_DEPTH    = 16
// )(
//     input  logic                   clk,
//     input  logic                   resetn,

//     // Push side (producer)
//     input  logic                   push_vld,
//     output logic                   push_rdy,
//     input  logic [ENTRY_WIDTH-1:0] push_data,

//     // Pop side (consumer)
//     output logic                   pop_vld,
//     input  logic                   pop_rdy,
//     output logic [ENTRY_WIDTH-1:0] pop_data
// );

//     localparam int PTR_W = (FIFO_DEPTH <= 1) ? 1 : $clog2(FIFO_DEPTH);

//     logic [ENTRY_WIDTH-1:0] mem [FIFO_DEPTH];
//     logic [PTR_W-1:0]       wptr, rptr;
//     logic [PTR_W:0]         count;    // can count up to FIFO_DEPTH

//     // status
//     wire full  = (count == FIFO_DEPTH);
//     wire empty = (count == 0);

//     assign push_rdy = !full;
//     assign pop_vld  = !empty;
//     assign pop_data   = mem[rptr];

//     wire do_push = push_vld && push_rdy;
//     wire do_pop  = pop_vld  && pop_rdy;

//     always_ff @(posedge clk or negedge resetn) begin
//         if (!resetn) begin
//             wptr  <= '0;
//             rptr  <= '0;
//             count <= '0;
//         end
//         else begin
//             // write
//             if (do_push) begin
//                 mem[wptr] <= push_data;
//                 wptr      <= (wptr + 1'b1);
//             end

//             // read
//             if (do_pop) begin
//                 rptr <= (rptr + 1'b1);
//             end

//             // update count
//             case ({do_push, do_pop})
//                 2'b10: count <= count + 1'b1; // push only
//                 2'b01: count <= count - 1'b1; // pop only
//                 default: ;                    // same or both (no net change)
//             endcase
//         end
//     end

// endmodule