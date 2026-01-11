module apb2axi_fifo_async #(
    parameter int WIDTH = 32,
    parameter int DEPTH = 16      // DW ram_depth range: 4..1024
)(
    input  logic               wr_clk,
    input  logic               wr_resetn,
    input  logic               wr_vld,
    input  logic [WIDTH-1:0]   wr_data,
    output logic               wr_rdy,

    input  logic               rd_clk,
    input  logic               rd_resetn,
    output logic               rd_vld,
    output logic [WIDTH-1:0]   rd_data,
    input  logic               rd_rdy
);

    // DW uses active-low push/pop
    logic push_s_n, pop_d_n;
    logic full_s, empty_d;
    logic [WIDTH-1:0] data_d;

    assign wr_rdy  = ~full_s;
    assign rd_vld  = ~empty_d;
    assign rd_data = data_d;

    assign push_s_n = ~(wr_vld & wr_rdy);
    assign pop_d_n  = ~(rd_vld & rd_rdy);

    DW_fifo_2c_df #(
        .width      (WIDTH),
        .ram_depth  (DEPTH),
        .mem_mode   (3),   // decent default (prefetch/cache)
        .f_sync_type(2),
        .r_sync_type(2),
        .clk_ratio  (0),   // 0 = arbitrary clock relationship (safe)
        .rst_mode   (0),
        .err_mode   (0),
        .tst_mode   (0),
        .verif_en   (0),   // turn OFF random sampling-error injection in sim
        .clr_dual_domain(1),
        .arch_type  (0)
    ) u_fifo (
        // source/write domain
        .clk_s         (wr_clk),
        .rst_s_n       (wr_resetn),
        .init_s_n      (1'b1),
        .clr_s         (1'b0),
        .ae_level_s    ('0),
        .af_level_s    ('0),
        .push_s_n      (push_s_n),
        .data_s        (wr_data),

        // unused status outputs (ok to leave unconnected if you want)
        .clr_sync_s    (),
        .clr_in_prog_s (),
        .clr_cmplt_s   (),
        .fifo_word_cnt_s(),
        .word_cnt_s    (),
        .fifo_empty_s  (),
        .empty_s       (),
        .almost_empty_s(),
        .half_full_s   (),
        .almost_full_s (),
        .full_s        (full_s),
        .error_s       (),

        // dest/read domain
        .clk_d         (rd_clk),
        .rst_d_n       (rd_resetn),
        .init_d_n      (1'b1),
        .clr_d         (1'b0),
        .ae_level_d    ('0),
        .af_level_d    ('0),
        .pop_d_n       (pop_d_n),

        .clr_sync_d    (),
        .clr_in_prog_d (),
        .clr_cmplt_d   (),
        .data_d        (data_d),
        .word_cnt_d    (),
        .empty_d       (empty_d),
        .almost_empty_d(),
        .half_full_d   (),
        .almost_full_d (),
        .full_d        (),
        .error_d       (),

        .test          (1'b0)
    );

endmodule

// /*------------------------------------------------------------------------------
//  * Fully CDC-safe asynchronous FIFO
//  *  - Gray-coded pointers
//  *  - VALID/READY handshake on both sides
//  *  - Drop-in replacement for Nir's original async FIFO
//  *----------------------------------------------------------------------------*/

// module apb2axi_fifo_async #(
//     parameter int WIDTH = 32,
//     parameter int DEPTH = 16      // MUST BE POWER OF 2
// )(
//     // Write clock domain
//     input  logic               wr_clk,
//     input  logic               wr_resetn,
//     input  logic               wr_vld,
//     input  logic [WIDTH-1:0]   wr_data,
//     output logic               wr_rdy,

//     // Read clock domain
//     input  logic               rd_clk,
//     input  logic               rd_resetn,
//     output logic               rd_vld,
//     output logic [WIDTH-1:0]   rd_data,
//     input  logic               rd_rdy
// );

//     // ------------------------------------------------------------
//     // Local parameters / storage
//     // ------------------------------------------------------------
//     localparam int PTR_W = $clog2(DEPTH);

//     logic [WIDTH-1:0] mem [0:DEPTH-1];

//     // ------------------------------------------------------------
//     // Pointers (binary + Gray)
//     // ------------------------------------------------------------
//     logic [PTR_W:0] wptr_bin,  wptr_bin_next;
//     logic [PTR_W:0] rptr_bin,  rptr_bin_next;

//     logic [PTR_W:0] wptr_gray, wptr_gray_next;
//     logic [PTR_W:0] rptr_gray, rptr_gray_next;

//     // Synced pointers
//     logic [PTR_W:0] wptr_gray_rdclk_1, wptr_gray_rdclk_2;
//     logic [PTR_W:0] rptr_gray_wrclk_1, rptr_gray_wrclk_2;

//     // Status
//     logic           full;
//     logic           empty;
//     logic [PTR_W:0] wbin_sync;   // write pointer in read domain (binary)

//     // ------------------------------------------------------------
//     // Gray encode/decode
//     // ------------------------------------------------------------
//     function automatic logic [PTR_W:0] bin2gray(input logic [PTR_W:0] b);
//         return (b >> 1) ^ b;
//     endfunction

//     function automatic logic [PTR_W:0] gray2bin(input logic [PTR_W:0] g);
//         logic [PTR_W:0] b;
//         b[PTR_W] = g[PTR_W];
//         for (int i = PTR_W-1; i >= 0; i--) begin
//             b[i] = b[i+1] ^ g[i];
//         end
//         return b;
//     endfunction

//     // ------------------------------------------------------------
//     // FULL + EMPTY detection (pure combinational)
//     // ------------------------------------------------------------
//     always_comb begin
//         // Next write pointer
//         wptr_bin_next  = wptr_bin + 1;
//         wptr_gray_next = bin2gray(wptr_bin_next);

//         // FULL: classic async FIFO condition with extra MSB
//         full = (wptr_gray_next ==
//                 {~rptr_gray_wrclk_2[PTR_W:PTR_W-1],
//                   rptr_gray_wrclk_2[PTR_W-2:0]});

//         // EMPTY: compare synced write pointer with local read pointer
//         wbin_sync = gray2bin(wptr_gray_rdclk_2);
//         empty     = (wbin_sync == rptr_bin);
//     end

//     // ------------------------------------------------------------
//     // WRITE CLOCK DOMAIN
//     // ------------------------------------------------------------
//     always_ff @(posedge wr_clk or negedge wr_resetn) begin
//         if (!wr_resetn) begin
//             wptr_bin          <= '0;
//             wptr_gray         <= '0;
//             rptr_gray_wrclk_1 <= '0;
//             rptr_gray_wrclk_2 <= '0;
//             wr_rdy            <= 1'b1;
//         end
//         else begin
//             // sync read pointer into write domain
//             rptr_gray_wrclk_1 <= rptr_gray;
//             rptr_gray_wrclk_2 <= rptr_gray_wrclk_1;

//             // ready when not full
//             wr_rdy <= !full;

//             // PUSH
//             if (wr_vld && wr_rdy) begin
//                 mem[wptr_bin[PTR_W-1:0]] <= wr_data;
//                 wptr_bin  <= wptr_bin_next;
//                 wptr_gray <= wptr_gray_next;
//             end
//         end
//     end

//     // ------------------------------------------------------------
//     // READ CLOCK DOMAIN
//     // ------------------------------------------------------------
//     always_ff @(posedge rd_clk or negedge rd_resetn) begin
//         if (!rd_resetn) begin
//             rptr_bin          <= '0;
//             rptr_gray         <= '0;
//             wptr_gray_rdclk_1 <= '0;
//             wptr_gray_rdclk_2 <= '0;
//             rd_vld            <= 1'b0;
//             rd_data           <= '0;
//         end
//         else begin
//             // sync write pointer into read domain
//             wptr_gray_rdclk_1 <= wptr_gray;
//             wptr_gray_rdclk_2 <= wptr_gray_rdclk_1;

//             // valid whenever FIFO is non-empty
//             rd_vld <= !empty;

//             // POP only on valid & ready
//             if (!empty && rd_rdy) begin
//                 rd_data <= mem[rptr_bin[PTR_W-1:0]];
//                 rd_vld  <= '1;
//                 rptr_bin  <= rptr_bin + 1'b1;
//                 rptr_gray <= bin2gray(rptr_bin + 1'b1);
//             end
//         end
//     end

// endmodule