/*------------------------------------------------------------------------------
 * File          : apb2axi.sv
 * Project       : APB2AXI
 * Author        : Nir Miller & Ido Oreg
 * Creation date : Nov 2025
 * Description   : Top-level APB2AXI bridge.
 *------------------------------------------------------------------------------*/

import apb2axi_pkg::*;

module apb2axi #(
     parameter int APB_ADDR_W      = APB_ADDR_W,
     parameter int APB_DATA_W      = APB_DATA_W,
     parameter int AXI_ADDR_W      = AXI_ADDR_W,
     parameter int AXI_DATA_W      = AXI_DATA_W,
     parameter int AXI_ID_W        = AXI_ID_W
)(
     // -------------------------
     // APB Slave Interface
     // -------------------------
     input  logic                  PCLK,
     input  logic                  PRESETn,
     input  logic [APB_ADDR_W-1:0] PADDR,
     input  logic [APB_DATA_W-1:0] PWDATA,
     input  logic                  PWRITE,
     input  logic                  PSEL,
     input  logic                  PENABLE,
     output logic [APB_DATA_W-1:0] PRDATA,
     output logic                  PREADY,
     output logic                  PSLVERR,

     // -------------------------
     // AXI Master Interface (AXI3)
     // -------------------------
     input  logic                  ACLK,
     input  logic                  ARESETn,
     // Write Address Channel
     output logic [AXI_ID_W-1:0]   AWID,
     output logic [AXI_ADDR_W-1:0] AWADDR,
     output logic [3:0]            AWLEN,
     output logic [2:0]            AWSIZE,
     output logic [1:0]            AWBURST,
     output logic                  AWLOCK,
     output logic [3:0]            AWCACHE,
     output logic [2:0]            AWPROT,
     output logic                  AWVALID,
     input  logic                  AWREADY,
     // Write Data Channel
     output logic [AXI_ID_W-1:0]   WID,
     output logic [AXI_DATA_W-1:0] WDATA,
     output logic [AXI_DATA_W/8-1:0] WSTRB,
     output logic                  WLAST,
     output logic                  WVALID,
     input  logic                  WREADY,
     // Write Response Channel
     input  logic [3:0]            BID,
     input  logic [1:0]            BRESP,
     input  logic                  BVALID,
     output logic                  BREADY,
     // Read Address Channel
     output logic [3:0]            ARID,
     output logic [AXI_ADDR_W-1:0] ARADDR,
     output logic [3:0]            ARLEN,
     output logic [2:0]            ARSIZE,
     output logic [1:0]            ARBURST,
     output logic                  ARLOCK,
     output logic [3:0]            ARCACHE,
     output logic [2:0]            ARPROT,
     output logic                  ARVALID,
     input  logic                  ARREADY,
     // Read Data Channel
     input  logic [3:0]            RID,
     input  logic [AXI_DATA_W-1:0] RDATA,
     input  logic [1:0]            RRESP,
     input  logic                  RLAST,
     input  logic                  RVALID,
     output logic                  RREADY
);

     // =========================================================================
     // Reg File -> Response Collector
     // =========================================================================
     logic                    resp_policy_cfg;
     // =========================================================================
     // Register File <-> Directory
     // =========================================================================
     logic                    reg_dir_alloc_vld;
     directory_entry_t        reg_dir_alloc_entry;
     logic                    reg_dir_alloc_rdy;
     logic [TAG_NUM-1:0]      reg_rd_dir_entry_consumed;
     logic [TAG_NUM-1:0]      reg_wr_dir_entry_consumed;
     logic [TAG_WIDTH-1:0]    reg_dir_tag_sel;
     directory_entry_t        reg_dir_entry;
     entry_state_e            reg_dir_entry_state;
     // =========================================================================
     // Register File -> Write packer (APB per-word stream)
     // =========================================================================
     logic                    wr_word_valid;      // change
     logic [TAG_W-1:0]        wr_word_tag;        // change
     logic [APB_DATA_W-1:0]   wr_word_data;       // change
     // =========================================================================
     // Directory <-> Transaction Manager
     // =========================================================================
     logic                    dir_mgr_pop_vld;
     directory_entry_t        dir_mgr_pop_entry;     
     logic                    dir_mgr_pop_rdy;
     // =========================================================================
     // Response Handler <-> Directory
     // =========================================================================
     logic                    cq_dir_cpl_vld;
     completion_entry_t       cq_dir_cpl_entry;
     logic                    cq_dir_cpl_rdy;

     logic [TAG_NUM-1:0][2:0] dir_rsp_tag_size;
     // =========================================================================
     // Register File <-> Response Handler
     // =========================================================================
     logic [TAG_NUM-1:0]                     rdf_reg_data_vld;
     logic [TAG_NUM-1:0]                     rdf_reg_data_rdy;     
     logic [TAG_NUM-1:0][APB_DATA_W-1:0]     rdf_reg_data_out;
     logic [TAG_NUM-1:0]                     rdf_reg_data_last;
     // logic                    rdf_reg_data_req;
     // logic [TAG_W-1:0]        rdf_reg_data_req_tag;
     // =========================================================================
     // Transaction Manager <-> Write CMD FIFO
     // =========================================================================
     logic                    wr_push_vld;
     logic                    wr_push_rdy;
     logic [CMD_ENTRY_W-1:0]  wr_push_data;
     // =========================================================================
     // Transaction Manager <-> Write DATA FIFO
     // =========================================================================
     logic                    wdf_pop_vld;
     logic                    wdf_pop_rdy;
     logic [DATA_ENTRY_W-1:0] wdf_pop_payload;
     // =========================================================================
     // Write CMD FIFO <-> Write Builder
     // =========================================================================
     logic                    wr_pop_vld;
     logic                    wr_pop_rdy;
     logic [CMD_ENTRY_W-1:0]  wr_pop_data;
     // =========================================================================
     // Write DATA FIFO <-> Write Builder
     // =========================================================================
     logic                    wd_pop_vld;
     logic                    wd_pop_rdy;
     logic [DATA_ENTRY_W-1:0] wd_pop_data;
     // =========================================================================
     // Transaction Manager <-> Read FIFO
     // =========================================================================
     logic                    rd_push_vld;
     logic                    rd_push_rdy;
     logic [CMD_ENTRY_W-1:0]  rd_push_data;
     // =========================================================================
     // Read FIFO <-> Read Builder
     // =========================================================================
     logic                    rd_pop_vld;
     logic                    rd_pop_rdy;
     logic [CMD_ENTRY_W-1:0]  rd_pop_data;
     // =========================================================================
     // Response Collector <-> async_FIFO <-> RDF
     // =========================================================================
     logic                    rsp_rdf_push_vld;
     rdf_entry_t              rsp_rdf_push_payload;
     logic                    rsp_rdf_push_rdy;
     // -------------------------- ASYNC FIFO------------------------------------
     logic                    rsp_rdf_pop_vld;
     rdf_entry_t              rsp_rdf_pop_payload;
     logic                    rsp_rdf_pop_rdy;
     // =========================================================================
     // Response Collector <-> async_FIFO <-> Response Handler
     // =========================================================================
     logic                    rsp_cq_push_vld;
     logic                    rsp_cq_push_rdy;
     logic [CPL_W-1:0]        rsp_cq_push_data;
     // -------------------------- ASYNC FIFO------------------------------------
     logic                    rsp_cq_pop_vld;
     logic                    rsp_cq_pop_rdy;
     logic [CPL_W-1:0]        rsp_cq_pop_data;

     // =========================================================================
     // DIRECTORY
     // =========================================================================
     apb2axi_directory u_directory (
          .pclk(PCLK), 
          .presetn(PRESETn),

          .reg_dir_alloc_vld(reg_dir_alloc_vld),
          .reg_dir_alloc_entry(reg_dir_alloc_entry),
          .reg_dir_alloc_rdy(reg_dir_alloc_rdy),

          .reg_rd_dir_entry_consumed(reg_rd_dir_entry_consumed),
          .reg_wr_dir_entry_consumed(reg_wr_dir_entry_consumed),

          .reg_dir_tag_sel(reg_dir_tag_sel),
          .reg_dir_entry(reg_dir_entry),
          .reg_dir_entry_state(reg_dir_entry_state),

          .dir_mgr_pop_vld(dir_mgr_pop_vld),
          .dir_mgr_pop_entry(dir_mgr_pop_entry),
          .dir_mgr_pop_rdy(dir_mgr_pop_rdy),

          .cq_dir_cpl_vld(cq_dir_cpl_vld),
          .cq_dir_cpl_entry(cq_dir_cpl_entry),
          .cq_dir_cpl_rdy(cq_dir_cpl_rdy),

          .dir_rsp_tag_size(dir_rsp_tag_size)
     );
     // =========================================================================
     // REGISTER FILE
     // =========================================================================
     apb2axi_reg u_reg (
          .pclk(PCLK), 
          .presetn(PRESETn),
          .psel(PSEL), 
          .penable(PENABLE), 
          .pwrite(PWRITE),
          .paddr(PADDR), 
          .pwdata(PWDATA),
          .prdata(PRDATA), 
          .pready(PREADY), 
          .pslverr(PSLVERR),

          .reg_dir_alloc_vld(reg_dir_alloc_vld),
          .reg_dir_alloc_entry(reg_dir_alloc_entry),

          .rdf_reg_data_vld(rdf_reg_data_vld),
          .rdf_reg_data_rdy(rdf_reg_data_rdy),
          .rdf_reg_data_out(rdf_reg_data_out),
          .rdf_reg_data_last(rdf_reg_data_last),

          .reg_rd_dir_entry_consumed(reg_rd_dir_entry_consumed),
          .reg_wr_dir_entry_consumed(reg_wr_dir_entry_consumed),

          .reg_dir_tag_sel(reg_dir_tag_sel),
          .reg_dir_entry(reg_dir_entry),
          .reg_dir_entry_state(reg_dir_entry_state),

          .wr_word_valid(wr_word_valid),
          .wr_word_tag  (wr_word_tag),
          .wr_word_data (wr_word_data),

          .resp_policy_cfg(resp_policy_cfg)
     );
     // =========================================================================
     // WRITE PACKER
     // =========================================================================
     apb2axi_wr_packer u_wr_packer (
          .pclk        (PCLK),
          .presetn     (PRESETn),

          .wr_word_valid(wr_word_valid),
          .wr_word_tag  (wr_word_tag),
          .wr_word_data (wr_word_data),

          .wdf_pop_vld  (wdf_pop_vld),
          .wdf_pop_rdy  (wdf_pop_rdy),
          .wdf_pop_payload (wdf_pop_payload)
     );
     // =========================================================================
     // RESPONSE HANDLER
     // =========================================================================
     apb2axi_response_handler u_handler (
          .pclk(PCLK),
          .presetn(PRESETn),

          .rsp_rdf_pop_vld(rsp_rdf_pop_vld),
          .rsp_rdf_pop_payload(rsp_rdf_pop_payload),
          .rsp_rdf_pop_rdy(rsp_rdf_pop_rdy),

          .rsp_cq_pop_vld(rsp_cq_pop_vld),
          .rsp_cq_pop_data(rsp_cq_pop_data),
          .rsp_cq_pop_rdy(rsp_cq_pop_rdy),

          .rdf_reg_data_rdy(rdf_reg_data_rdy),
          .rdf_reg_data_vld(rdf_reg_data_vld),
          .rdf_reg_data_out(rdf_reg_data_out),
          .rdf_reg_data_last(rdf_reg_data_last),

          .cq_dir_cpl_vld(cq_dir_cpl_vld),
          .cq_dir_cpl_entry(cq_dir_cpl_entry),
          .cq_dir_cpl_rdy(cq_dir_cpl_rdy),

          .dir_rsp_tag_size(dir_rsp_tag_size)
     );
     // =========================================================================
     // RESPONSE COLLECTOR
     // =========================================================================
     apb2axi_response_collector #(
     ) u_resp_collector (
          .aclk(ACLK),
          .aresetn(ARESETn),

          .bid(BID),
          .bresp(BRESP),
          .bvalid(BVALID),
          .bready(BREADY),

          .rid(RID),
          .rdata(RDATA),
          .rresp(RRESP),
          .rlast(RLAST),
          .rvalid(RVALID),
          .rready(RREADY),

          .rsp_rdf_push_vld(rsp_rdf_push_vld),
          .rsp_rdf_push_payload(rsp_rdf_push_payload),
          .rsp_rdf_push_rdy(rsp_rdf_push_rdy),

          .rsp_cq_push_vld(rsp_cq_push_vld),
          .rsp_cq_push_rdy(rsp_cq_push_rdy),
          .rsp_cq_push_data(rsp_cq_push_data),

          .resp_policy_cfg(resp_policy_cfg)
     );
     // =========================================================================
     // TRANSACTION MANAGER
     // =========================================================================
     apb2axi_txn_mgr #(
     ) u_txn_mgr (
          .aclk(ACLK),
          .aresetn(ARESETn),

          .dir_mgr_pop_vld(dir_mgr_pop_vld),
          .dir_mgr_pop_entry(dir_mgr_pop_entry),
          .dir_mgr_pop_rdy(dir_mgr_pop_rdy),

          .wr_push_vld(wr_push_vld),
          .wr_push_rdy(wr_push_rdy),
          .wr_push_data (wr_push_data),

          .rd_push_vld(rd_push_vld),
          .rd_push_rdy(rd_push_rdy),
          .rd_push_data(rd_push_data)
     );
     // =========================================================================
     // WRITE BUILDER
     // =========================================================================
     apb2axi_write_builder #(
     ) u_wr_builder (
          .aclk(ACLK),
          .aresetn(ARESETn),

          .awid(AWID),
          .awaddr(AWADDR),
          .awlen(AWLEN),
          .awsize(AWSIZE),
          .awburst(AWBURST),
          .awlock(AWLOCK),
          .awcache(AWCACHE),
          .awprot(AWPROT),
          .awvalid(AWVALID),
          .awready(AWREADY),

          .wid(WID),
          .wdata(WDATA),
          .wstrb(WSTRB),
          .wlast(WLAST),
          .wvalid(WVALID),
          .wready(WREADY),

          .wr_pop_vld(wr_pop_vld),
          .wr_pop_rdy(wr_pop_rdy),
          .wr_pop_data(wr_pop_data),

          .wd_pop_vld(wd_pop_vld),
          .wd_pop_rdy(wd_pop_rdy),
          .wd_pop_data(wd_pop_data)
     );
     // =========================================================================
     // READ BUILDER
     // =========================================================================
     apb2axi_read_builder #(
          .FIFO_ENTRY_W(CMD_ENTRY_W)
     ) u_rd_builder (
          .aclk(ACLK),
          .aresetn(ARESETn),

          .arid(ARID),
          .araddr(ARADDR),
          .arlen(ARLEN),
          .arsize(ARSIZE),
          .arburst(ARBURST),
          .arlock(ARLOCK),
          .arcache(ARCACHE),
          .arprot(ARPROT),
          .arvalid(ARVALID),
          .arready(ARREADY),

          .rd_pop_vld(rd_pop_vld),
          .rd_pop_data(rd_pop_data),
          .rd_pop_rdy(rd_pop_rdy)
     );
     // ============================================================
     // Request FIFO's
     // ============================================================
     // ------------------------------------ FROM HERE THE OPTIONAL FIFO's ------------------------------------
     apb2axi_fifo #(               // FIFO used to absorve Writes' backpressure
          .ENTRY_WIDTH(CMD_ENTRY_W),
          .FIFO_DEPTH(FIFO_DEPTH)
     ) u_wr_cmd_apb2axi_fifo (
          .clk(ACLK),
          .resetn(ARESETn),

          .push_vld(wr_push_vld),
          .push_rdy(wr_push_rdy),
          .push_data(wr_push_data),

          .pop_vld(wr_pop_vld),
          .pop_rdy(wr_pop_rdy),
          .pop_data(wr_pop_data)
     );
     apb2axi_fifo #(               // FIFO used to absorve Writes' backpressure
          .ENTRY_WIDTH(DATA_ENTRY_W),
          .FIFO_DEPTH(FIFO_DEPTH)
     ) u_wr_data_apb2axi_fifo (
          .clk(ACLK),
          .resetn(ARESETn),

          .push_vld(wdf_pop_vld),
          .push_rdy(wdf_pop_rdy),
          .push_data(wdf_pop_payload),

          .pop_vld(wd_pop_vld),
          .pop_rdy(wd_pop_rdy),
          .pop_data(wd_pop_data)
     );
     apb2axi_fifo #(               // FIFO used to absorve Read' backpressure
          .ENTRY_WIDTH(CMD_ENTRY_W),
          .FIFO_DEPTH(FIFO_DEPTH)
     ) u_rd_apb2axi_fifo (
          .clk(ACLK),
          .resetn(ARESETn),

          .push_vld(rd_push_vld),
          .push_rdy(rd_push_rdy),
          .push_data(rd_push_data),

          .pop_vld(rd_pop_vld),
          .pop_rdy(rd_pop_rdy),
          .pop_data(rd_pop_data)
     );
     // ------------------------------------ UNTIL HERE THE OPTIONAL FIFO's ------------------------------------

     // =========================================================================
     // ASYNCHRONOUS FIFO's
     // =========================================================================
     apb2axi_fifo_async #(         // async FIFO used to pass completion entries
          .WIDTH(CPL_W)
     ) u_cq_fifo (
          .wr_clk(ACLK),
          .wr_resetn(ARESETn),
          .wr_vld(rsp_cq_push_vld),
          .wr_data(rsp_cq_push_data),
          .wr_rdy(rsp_cq_push_rdy),

          .rd_clk(PCLK),
          .rd_resetn(PRESETn),
          .rd_vld(rsp_cq_pop_vld),
          .rd_data(rsp_cq_pop_data),
          .rd_rdy(rsp_cq_pop_rdy)
     );
     apb2axi_fifo_async #(         // async FIFO used to pass axi DATA beats
          .WIDTH(RDF_W)
     ) u_rdf_fifo (
          .wr_clk   (ACLK),
          .wr_resetn(ARESETn),
          .wr_vld(rsp_rdf_push_vld),
          .wr_data(rsp_rdf_push_payload),
          .wr_rdy(rsp_rdf_push_rdy),

          .rd_clk(PCLK),
          .rd_resetn(PRESETn),
          .rd_vld(rsp_rdf_pop_vld),
          .rd_data(rsp_rdf_pop_payload),
          .rd_rdy(rsp_rdf_pop_rdy)
     );

     // // ------------------------------------ FROM HERE THE OPTIONAL ASYNC FIFO's ------------------------------------
     // apb2axi_fifo_async #(               // FIFO used to absorve Writes' backpressure
     //      .WIDTH(CMD_ENTRY_W)
     // ) u_wr_cmd_apb2axi_fifo (
     //      .wr_clk(PCLK),
     //      .wr_resetn(PRESETn),
     //      .wr_vld(wr_push_vld),
     //      .wr_data(wr_push_data),
     //      .wr_rdy(wr_push_rdy),

     //      .rd_clk(ACLK),
     //      .rd_resetn(ARESETn),
     //      .rd_vld(wr_pop_vld),
     //      .rd_data(wr_pop_data),
     //      .rd_rdy(wr_pop_rdy)
     // );
     // apb2axi_fifo_async #(               // FIFO used to absorve Writes' backpressure
     //      .WIDTH(DATA_ENTRY_W)
     // ) u_wr_data_apb2axi_fifo (
     //      .wr_clk(PCLK),
     //      .wr_resetn(PRESETn),
     //      .wr_vld(wdf_pop_vld),
     //      .wr_data(wdf_pop_payload),
     //      .wr_rdy(wdf_pop_rdy),

     //      .rd_clk(ACLK),
     //      .rd_resetn(ARESETn),
     //      .rd_vld(wd_pop_vld),
     //      .rd_data(wd_pop_data),
     //      .rd_rdy(wd_pop_rdy)
     // );
     // apb2axi_fifo_async #(               // FIFO used to absorve Read' backpressure
     //      .WIDTH(CMD_ENTRY_W)
     // ) u_rd_apb2axi_fifo (
     //      .wr_clk(PCLK),
     //      .wr_resetn(PRESETn),
     //      .wr_vld(rd_push_vld),
     //      .wr_data(rd_push_data),
     //      .wr_rdy(rd_push_rdy),

     //      .rd_clk(ACLK),
     //      .rd_resetn(ARESETn),
     //      .rd_vld(rd_pop_vld),
     //      .rd_data(rd_pop_data),
     //      .rd_rdy(rd_pop_rdy)
     // );
     // // ------------------------------------ UNTIL HERE THE OPTIONAL ASYNC FIFO's ------------------------------------

endmodule
