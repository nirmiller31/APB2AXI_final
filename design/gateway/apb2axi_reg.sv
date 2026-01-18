/*------------------------------------------------------------------------------
 * File          : apb2axi_reg.sv
 * Project       : APB2AXI
 * Author        : Nir Miller & Ido Oreg
 * Description   : - Implements the APB register file and address decode (ADDR/CMD/STATUS/DATA windows)
 *                 - Issues directory allocation on ADDR_LO write and supports per-TAG status/data access
 *                 - Streams RD_DATA via per-TAG ready/valid pop and exports WR_DATA words (tag+data) to the write packer
 *------------------------------------------------------------------------------*/

import apb2axi_pkg::*;

module apb2axi_reg #()(
     // APB Signals
     input  logic                  pclk,
     input  logic                  presetn,
     input  logic                  psel,
     input  logic                  penable,
     input  logic                  pwrite,
     input  logic [APB_ADDR_W-1:0] paddr,
     input  logic [APB_DATA_W-1:0] pwdata,
     output logic                  pready,
     output logic                  pslverr,
     output logic [APB_DATA_W-1:0] prdata,

     output logic                  reg_dir_alloc_vld,
     output directory_entry_t      reg_dir_alloc_entry,

     output logic [TAG_NUM-1:0]    reg_rd_dir_entry_consumed,
     output logic [TAG_NUM-1:0]    reg_wr_dir_entry_consumed,

     output logic [TAG_W-1:0]      reg_dir_tag_sel,
     input directory_entry_t       reg_dir_entry,
     input entry_state_e           reg_dir_entry_state,

     input logic [TAG_NUM-1:0]                      rdf_reg_data_vld,
     input logic [TAG_NUM-1:0][APB_DATA_W-1:0]      rdf_reg_data_out,
     input logic [TAG_NUM-1:0]                      rdf_reg_data_last,
     output logic [TAG_NUM-1:0]                     rdf_reg_data_rdy,

     output logic                  wr_word_valid,
     output logic [TAG_W-1:0]      wr_word_tag,
     output logic [APB_DATA_W-1:0] wr_word_data,

     output logic                  resp_policy_cfg
);

     logic [APB_REG_W-1:0]         addr_lo_rd_val;
     logic [APB_REG_W-1:0]         addr_hi_rd_val;
     logic [APB_REG_W-1:0]         cmd_rd_val;
     logic [APB_REG_W-1:0]         tag_to_consume_rd_val;
     logic [APB_REG_W-1:0]         sts_rd_val;
     logic [APB_REG_W-1:0]         data_rd_val;
     logic [APB_REG_W-1:0]         resp_policy_rd_val;

     logic                         sel_addr_lo, sel_addr_hi, sel_cmd, sel_rd_status, sel_rd_data, sel_tag_to_consume;
     logic                         addr_lo_we, addr_lo_we_d, addr_hi_we, cmd_we, tag_to_consume_we;

     localparam logic [APB_ADDR_W-1:0] RD_STATUS_BASE = REG_ADDR_RD_STATUS;
     localparam logic [APB_ADDR_W-1:0] RD_DATA_BASE   = REG_ADDR_RD_DATA;
     localparam logic [APB_ADDR_W-1:0] WR_DATA_BASE   = REG_ADDR_WR_DATA;

     logic [TAG_W-1:0]             st_tag;
     logic [TAG_W-1:0]             rd_tag;
     logic [TAG_W-1:0]             wr_tag;

     logic                         sel_rd_status_tag;
     logic                         sel_rd_data_tag;
     logic                         sel_wr_data_tag;
     logic                         sel_resp_policy_cfg;

     logic                         rd_status_re;
     logic                         rd_data_re;
     logic                         wr_data_we;
     logic                         resp_policy_we;

     assign sel_rd_status_tag      = (paddr >= RD_STATUS_BASE)   && (paddr <  (RD_STATUS_BASE + TAG_WINDOW_BYTES));
     assign sel_rd_data_tag        = (paddr >= RD_DATA_BASE)     && (paddr <  (RD_DATA_BASE + TAG_WINDOW_BYTES));
     assign sel_wr_data_tag        = (paddr >= WR_DATA_BASE)     && (paddr <  (WR_DATA_BASE + TAG_WINDOW_BYTES));

     assign st_tag                 = (paddr - RD_STATUS_BASE)    / TAG_STRIDE_BYTES;
     assign rd_tag                 = (paddr - RD_DATA_BASE)      / TAG_STRIDE_BYTES;
     assign wr_tag                 = (paddr - WR_DATA_BASE)      / TAG_STRIDE_BYTES;

     assign rd_status_re           = psel && penable && !pwrite && sel_rd_status_tag;
     assign rd_data_re             = psel && penable && !pwrite && sel_rd_data_tag;
     assign wr_data_we             = psel && penable &&  pwrite && sel_wr_data_tag;
     
     assign sel_addr_lo            = ({paddr[APB_ADDR_W-1:2], 2'b00} == REG_ADDR_ADDR_LO);
     assign sel_addr_hi            = ({paddr[APB_ADDR_W-1:2], 2'b00} == REG_ADDR_ADDR_HI);
     assign sel_cmd                = ({paddr[APB_ADDR_W-1:2], 2'b00} == REG_ADDR_CMD);
     assign sel_tag_to_consume     = ({paddr[APB_ADDR_W-1:2], 2'b00} == REG_ADDR_RD_TAG_SEL);
     assign sel_resp_policy_cfg    = ({paddr[APB_ADDR_W-1:2], 2'b00} == REG_RESP_POLICY);

     // Write enables for RW regs
     assign addr_lo_we             = psel & penable & pwrite & sel_addr_lo;
     assign addr_hi_we             = psel & penable & pwrite & sel_addr_hi;
     assign cmd_we                 = psel & penable & pwrite & sel_cmd;
     assign tag_to_consume_we      = psel & penable & pwrite & sel_tag_to_consume;
     assign resp_policy_we         = psel & penable & pwrite & sel_resp_policy_cfg;

     // ----------------------------------------------------------------
     // APB write mux
     // ----------------------------------------------------------------
     always_ff @(posedge pclk) begin
          if (!presetn) begin
               addr_lo_rd_val                                         <= '0;
               addr_hi_rd_val                                         <= '0;
               cmd_rd_val                                             <= '0;
               tag_to_consume_rd_val                                  <= '0;
               wr_word_valid                                          <= '0;
               wr_word_tag                                            <= '0;
               wr_word_data                                           <= '0;
               resp_policy_rd_val                                     <= '0;
          end 
          else begin
               if (addr_lo_we)               addr_lo_rd_val           <= pwdata;
               if (addr_hi_we)               addr_hi_rd_val           <= pwdata;
               if (cmd_we)                   cmd_rd_val               <= pwdata;
               if (tag_to_consume_we)        tag_to_consume_rd_val    <= pwdata;
               if (wr_data_we)               wr_word_data             <= pwdata;
               if (wr_data_we)               wr_word_tag              <= wr_tag;
               if (resp_policy_we)           resp_policy_rd_val       <= pwdata;
               wr_word_valid                                          <= wr_data_we;
          end
     end

     assign resp_policy_cfg = resp_policy_rd_val[0];

     // ----------------------------------------------------------------
     // APB read mux
     // ----------------------------------------------------------------
     always_comb begin
          prdata = '0;
          if (!pwrite && psel) begin
               unique case (1'b1)
                    sel_addr_lo:             prdata = addr_lo_rd_val;
                    sel_addr_hi:             prdata = addr_hi_rd_val;
                    sel_cmd:                 prdata = cmd_rd_val;
                    sel_rd_status_tag:       prdata = sts_rd_val;
                    sel_rd_data_tag:         prdata = data_rd_val;
                    sel_resp_policy_cfg:     prdata = resp_policy_rd_val;
                    default:                 prdata = '0;
               endcase
          end
     end

     // ----------------------------------------------------------------
     // Directory selection (optional: via TAG_TO_CONSUME)
     // ----------------------------------------------------------------
     // assign reg_dir_tag_sel = rd_status_re ? st_tag : tag_to_consume_rd_val[TAG_W-1:0];
     assign reg_dir_tag_sel = rd_tag;

     assign sts_rd_val = {
          8'b0,
          reg_dir_entry.err_beat_idx,               // [23:16]
          reg_dir_entry.state == DIR_ST_DONE,       // bit 15
          reg_dir_entry.state == DIR_ST_ERROR,      // bit 14
          reg_dir_entry.resp,                       // [13:12]
          reg_dir_entry.num_beats,                  // [11:4]
          reg_dir_entry.tag                         // [3:0]
     };

     // ----------------------------------------------------------------
     // RD_DATA streaming behavior:
     //  - If valid: return head data and pop (one-hot rdy)
     //  - If empty: return 0 and PSLVERR=1 (no pop)
     // ----------------------------------------------------------------
     always_comb begin
          rdf_reg_data_rdy = '0;
          pready           = 1'b1;
          pslverr          = 1'b0;

          if (rd_data_re) begin
               if (rdf_reg_data_vld[rd_tag]) begin
                    rdf_reg_data_rdy[rd_tag] = 1'b1;   // POP on this APB read
               end
               else begin
                    pslverr = 1'b1;                    // empty read -> error
               end
          end
     end

     // data returned
     assign data_rd_val = rdf_reg_data_vld[rd_tag] ? rdf_reg_data_out[rd_tag] : '0;

     // ----------------------------------------------------------------
     // reg_dir_entry_consumed pulse:
     //  - when SW successfully pops and that popped word is LAST for that tag
     // ----------------------------------------------------------------
     always_ff @(posedge pclk) begin
          if (!presetn) begin
               reg_wr_dir_entry_consumed <= 1'b0;
               reg_rd_dir_entry_consumed <= '0;
          end else begin
               reg_wr_dir_entry_consumed <= 1'b0;
               reg_rd_dir_entry_consumed <= '0;
               if (rd_data_re && rdf_reg_data_vld[rd_tag] && rdf_reg_data_rdy[rd_tag]) begin
                    if (rdf_reg_data_last[rd_tag]) begin
                         reg_rd_dir_entry_consumed[rd_tag] <= 1'b1;
                    end
               end
               if (rd_status_re && (reg_dir_entry.state inside {DIR_ST_DONE, DIR_ST_ERROR})) begin
                    reg_wr_dir_entry_consumed[rd_tag] <= 1'b1;
               end
          end
     end

     // ----------------------------------------------------------------
     // Outputs for Directory alloc entry
     // ----------------------------------------------------------------
     assign reg_dir_alloc_entry.is_write  = cmd_rd_val[DIR_ENTRY_ISWRITE_HI : DIR_ENTRY_ISWRITE_LO];
     assign reg_dir_alloc_entry.addr      = {addr_hi_rd_val, addr_lo_rd_val};
     assign reg_dir_alloc_entry.len       = cmd_rd_val[DIR_ENTRY_LEN_HI : DIR_ENTRY_LEN_LO];
     assign reg_dir_alloc_entry.size      = cmd_rd_val[DIR_ENTRY_SIZE_HI : DIR_ENTRY_SIZE_LO];
     assign reg_dir_alloc_entry.burst     = '0;
     assign reg_dir_alloc_entry.tag       = '0;
     assign reg_dir_alloc_entry.resp      = AXI_RESP_OKAY;
     assign reg_dir_alloc_entry.num_beats = '0;
     assign reg_dir_alloc_entry.err_beat_idx = '0;
     assign reg_dir_alloc_entry.state     = DIR_ST_EMPTY;

     // ----------------------------------------------------------------
     // Single-cycle reg_dir_alloc_vld on ADDR_LO write
     // ----------------------------------------------------------------
     always_ff @(posedge pclk) begin               
          if (!presetn) begin
               addr_lo_we_d <= 1'b0;
               reg_dir_alloc_vld <= 1'b0;
          end 
          else begin
               addr_lo_we_d <= addr_lo_we;
               reg_dir_alloc_vld <= addr_lo_we & ~addr_lo_we_d;
          end
     end
`ifndef SYNTHESIS
// ==========================================================================================================================
// =================================================== DEBUG infra ==========================================================
// ==========================================================================================================================

     bit reg_debug_en;

     initial begin
          reg_debug_en = $test$plusargs("APB2AXI_REG_DEBUG");
          if (reg_debug_en) begin
               $display("%t [DREG_DBG] Register File debug ENABLED (+APB2AXI_REG_DEBUG)", $time);
          end
     end

     always_ff @(posedge pclk) begin
          if (!presetn) begin
          end else if (reg_debug_en) begin
               if (addr_lo_we) begin
                    $display("REG_DBG %0t AddrLo WE asserted: paddr=0x%0h pwdata=0x%0h", $time, paddr, pwdata);
               end

               if (addr_lo_we || addr_hi_we || cmd_we) begin
                    $display("REGFILE %0t WRITE: addr=0x%0h data=0x%0h", $time, paddr, pwdata);
               end

               $display("REG_DIRSTAT %0t tag_sel=%0d dir_state=%0d entry.state=%0d resp=%0d beats=%0d tag=%0d",
                         $time,
                         reg_dir_tag_sel,
                         reg_dir_entry_state,
                         reg_dir_entry.state,
                         reg_dir_entry.resp,
                         reg_dir_entry.num_beats,
                         reg_dir_entry.tag);
          end
     end

// ==========================================================================================================================
// ==========================================================================================================================
// ==========================================================================================================================
`endif

endmodule