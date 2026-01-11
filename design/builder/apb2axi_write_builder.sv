/*------------------------------------------------------------------------------
 * File          : apb2axi_write_builder.sv
 * Project       : APB2AXI
 * Author        : Nir Miller & Ido Oreg
 * Description   : - Pops write descriptors (CMD) to drive AXI AW and tracks beats per TAG
 *                 - Pops packed write-data beats (WD) and drives AXI W with per-TAG beat accounting
 *                 - Supports outstanding/interleaved writes by scheduling W beats only for active TAGs (ACLK domain)
 *------------------------------------------------------------------------------*/

import apb2axi_pkg::*;

module apb2axi_write_builder #(
     parameter int CMD_ENTRY_W  = CMD_ENTRY_W,
     parameter int DATA_ENTRY_W = DATA_ENTRY_W
)(
     input  logic                        aclk,
     input  logic                        aresetn,

     // ---------------- AXI AW ----------------
     output logic [AXI_ID_W-1:0]         awid,
     output logic [AXI_ADDR_W-1:0]       awaddr,
     output logic [3:0]                  awlen,
     output logic [2:0]                  awsize,
     output logic [1:0]                  awburst,
     output logic                        awlock,
     output logic [3:0]                  awcache,
     output logic [2:0]                  awprot,
     output logic                        awvalid,
     input  logic                        awready,

     // ---------------- AXI W -----------------
     output logic [AXI_ID_W-1:0]         wid,
     output logic [AXI_DATA_W-1:0]       wdata,
     output logic [(AXI_DATA_W/8)-1:0]   wstrb,
     output logic                        wlast,
     output logic                        wvalid,
     input  logic                        wready,

     // ---------------- CMD FIFO --------------
     input  logic                        wr_pop_vld,
     output logic                        wr_pop_rdy,
     input  logic [CMD_ENTRY_W-1:0]      wr_pop_data,

     // ---------------- DATA FIFO -------------
     input  logic                        wd_pop_vld,
     output logic                        wd_pop_rdy,
     input  logic [DATA_ENTRY_W-1:0]     wd_pop_data
);

     // ----------------------------------------------------------------
     // Decode FIFO payloads
     // ----------------------------------------------------------------
     directory_entry_t cmd;
     wr_entry_t        wd;

     assign cmd = wr_pop_data;
     assign wd  = wd_pop_data;

     // ----------------------------------------------------------------
     // Per-TAG state
     // ----------------------------------------------------------------
     logic [TAG_NUM-1:0] aw_active;
     logic [7:0]         beats_left [TAG_NUM];

     // ----------------------------------------------------------------
     // Defaults
     // ----------------------------------------------------------------
     assign awlock                      = 1'b0;
     assign awcache                     = 4'b0011;
     assign awprot                      = 3'b000;
     assign awburst                     = 2'b01; // INCR

     // ----------------------------------------------------------------
     // Reset
     // ----------------------------------------------------------------
     integer i;
     always_ff @(posedge aclk) begin
          if (!aresetn) begin
               awvalid                  <= 1'b0;
               wvalid                   <= 1'b0;
               wlast                    <= 1'b0;
               wr_pop_rdy               <= 1'b0;
               wd_pop_rdy               <= 1'b0;
               awid                     <= '0;
               awaddr                   <= '0;
               awlen                    <= '0;
               awsize                   <= '0;
               wid                      <= '0;
               wdata                    <= '0;
               wstrb                    <= '0;

               for (i = 0; i < TAG_NUM; i++) begin
                    aw_active[i]        <= 1'b0;
                    beats_left[i]       <= '0;
               end
          end else begin
               wr_pop_rdy               <= 1'b0;
               wd_pop_rdy               <= 1'b0;

               if (awvalid && awready) begin
                    awvalid             <= 1'b0;
               end
               if (wvalid  && wready) begin
                    wvalid              <= 1'b0;
                    wlast               <= 1'b0;
               end
               // -------------------------------------------------------
               // AW scheduler (independent)
               // -------------------------------------------------------
               if (!awvalid && wr_pop_vld) begin
                    wr_pop_rdy          <= 1'b1;

                    awid                <= cmd.tag;
                    awaddr              <= cmd.addr;
                    awlen               <= cmd.len;
                    awsize              <= cmd.size;
                    awvalid             <= 1'b1;

                    aw_active [cmd.tag] <= 1'b1;
                    beats_left[cmd.tag] <= cmd.len + 8'd1;
               end
               // -------------------------------------------------------
               // W scheduler (any-ready, greedy)
               // -------------------------------------------------------
               if (!wvalid && wd_pop_vld) begin
                    int w_tag;
                    w_tag               = wd.tag;

                    if (aw_active[w_tag] && beats_left[w_tag] != 0) begin
                         wd_pop_rdy     <= 1'b1;

                         wid            <= w_tag;
                         wdata          <= wd.data;
                         wstrb          <= '1;
                         wlast          <= (beats_left[w_tag] == 8'd1);
                         wvalid         <= 1'b1;
                    end
               end

               // -------------------------------------------------------
               // Beat accounting
               // -------------------------------------------------------
               if (wvalid && wready) begin
                    beats_left[wid]     <= beats_left[wid] - 8'd1;
                    if (beats_left[wid] == 8'd1) begin
                         aw_active[wid] <= 1'b0;
                    end
               end
          end
     end

endmodule