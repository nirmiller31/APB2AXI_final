/*------------------------------------------------------------------------------
 * File          : apb2axi_txn_mgr.sv
 * Project       : APB2AXI
 * Author        : Nir Miller & Ido Oreg
 * Description   : - Takes committed gateway entries
 *                 - Routes writes to WR FIFO, reads to RD FIFO
 *                 - All logic is in AXI clock domain
 *------------------------------------------------------------------------------*/

import apb2axi_pkg::*;

module apb2axi_txn_mgr #(
)(
     input  logic                       aclk,
     input  logic                       aresetn,
     // From Gateway (directory entry at commit time)
     input  logic                       dir_mgr_pop_vld,
     input  directory_entry_t           dir_mgr_pop_entry,
     output logic                       dir_mgr_pop_rdy,
     // To WRITE request FIFO
     output logic                       wr_push_vld,
     input  logic                       wr_push_rdy,
     output logic [CMD_ENTRY_W-1:0]     wr_push_data,
     // To READ request FIFO
     output logic                       rd_push_vld,
     input  logic                       rd_push_rdy,
     output logic [CMD_ENTRY_W-1:0]     rd_push_data
);
     logic [CMD_ENTRY_W-1:0]            entry_packed;
     assign entry_packed                = dir_mgr_pop_entry;

     always_comb begin
          dir_mgr_pop_rdy               = 1'b0;
          wr_push_vld                   = 1'b0;
          rd_push_vld                   = 1'b0;
          wr_push_data                  = '0;
          rd_push_data                  = '0;

          if (dir_mgr_pop_vld) begin
               if (dir_mgr_pop_entry.is_write) begin
                    if (wr_push_rdy) begin             // Write request -> WR FIFO
                         wr_push_vld         = 1'b1;
                         wr_push_data        = entry_packed;
                         dir_mgr_pop_rdy     = 1'b1;
                    end
               end else begin
                    if (rd_push_rdy) begin             // Read request -> RD FIFO
                         rd_push_vld         = 1'b1;
                         rd_push_data        = entry_packed;
                         dir_mgr_pop_rdy     = 1'b1;
                    end
               end
          end
     end

endmodule