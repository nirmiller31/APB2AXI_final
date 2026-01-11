/*------------------------------------------------------------------------------
 * File          : apb2axi_directory.sv
 * Project       : APB2AXI
 * Author        : Nir Miller & Ido Oreg
 * Description   : - Maintains a per-TAG directory table and state machine for outstanding transactions
 *                 - Allocates the smallest free TAG, exposes per-TAG status/fields to APB, and pops oldest ALLOCATED to the manager
 *                 - Updates entries on completion and frees TAGs once APB confirms the transaction was fully consumed
 *------------------------------------------------------------------------------*/

import apb2axi_pkg::*;

module apb2axi_directory #()(
     input  logic                       pclk,
     input  logic                       presetn,

     input  logic                       reg_dir_alloc_vld,            // New descriptor available
     input  directory_entry_t           reg_dir_alloc_entry,          // Descriptor
     output logic                       reg_dir_alloc_rdy,            // Can accept?

     input  logic [TAG_NUM-1:0]         reg_rd_dir_entry_consumed,    // APB says: done with this TAG (consumed)
     input  logic [TAG_NUM-1:0]         reg_wr_dir_entry_consumed,    // APB says: done with this TAG (consumed)

     input  logic [TAG_W-1:0]           reg_dir_tag_sel,              // which TAG to inspect (status read)
     output directory_entry_t           reg_dir_entry,
     output entry_state_e               reg_dir_entry_state,

     output logic                       dir_mgr_pop_vld,              // We have an entry ready to FIFO'ed
     output directory_entry_t           dir_mgr_pop_entry,            // The ready entry
     input  logic                       dir_mgr_pop_rdy,              // FIFO can accept

     input  logic                       cq_dir_cpl_vld,               // Txn stored in handler, all beats recieved from AXI
     input  completion_entry_t          cq_dir_cpl_entry,             // The completion entry
     output logic                       cq_dir_cpl_rdy,

     output logic [TAG_NUM-1:0][2:0]    dir_rsp_tag_size   // NEW: size per tag (pclk)

);

     // =============================================================
     // Entry state machine
     // =============================================================

     entry_state_e                      state [DIR_ENTRIES];
     directory_entry_t                  entry [DIR_ENTRIES];

     logic [TAG_W-1:0]                  reg_dir_tag_sel_d;

     logic                              found_alloc;
     logic [TAG_W-1:0]                  oldest_tag;

     // -----------------------------------------------------------------
     // Free-entry allocation (smallest free TAG)
     // -----------------------------------------------------------------
     logic                              found_free;
     logic [TAG_W-1:0]                  free_tag;

     always_comb begin
          reg_dir_alloc_rdy             = found_free;                 // Free entry detection

          dir_mgr_pop_vld               = found_alloc;
          dir_mgr_pop_entry             = entry[oldest_tag];

          reg_dir_entry                 = entry[reg_dir_tag_sel];
          reg_dir_entry_state           = state[reg_dir_tag_sel];
     end

     // =============================================================
     // State Handling block
     // =============================================================
     always_ff @(posedge pclk) begin
          if (!presetn) begin
               cq_dir_cpl_rdy                               <= '1;
               for (int i = 0; i < DIR_ENTRIES; i++) begin
                    state[i]                                <= ST_EMPTY;
                    entry[i]                                <= '0;
               end
               reg_dir_tag_sel_d                            <= '0;
          end
          else begin
               reg_dir_tag_sel_d                            <= reg_dir_tag_sel;
               if (reg_dir_alloc_vld && reg_dir_alloc_rdy) begin
                    entry[free_tag]                         <= reg_dir_alloc_entry;
                    entry[free_tag].tag                     <= free_tag;
                    state[free_tag]                         <= ST_ALLOCATED;
               end
               if (dir_mgr_pop_vld && dir_mgr_pop_rdy) begin                         // ALLOCATED -> PENDING (once popped to FIFO)
                    state[oldest_tag]                       <= ST_PENDING;
               end
               if (cq_dir_cpl_vld && cq_dir_cpl_rdy) begin            // add semi-bytes support FIXME
                    state[cq_dir_cpl_entry.tag]             <= ST_COMPLETE;          // PENDING -> COMPLETE (after all data recieved)
                    entry[cq_dir_cpl_entry.tag].resp        <= cq_dir_cpl_entry.resp;
                    entry[cq_dir_cpl_entry.tag].num_beats   <= cq_dir_cpl_entry.num_beats;
                    entry[cq_dir_cpl_entry.tag].state       <= cq_dir_cpl_entry.error ? DIR_ST_ERROR : DIR_ST_DONE;
                    entry[cq_dir_cpl_entry.tag].err_beat_idx <= cq_dir_cpl_entry.err_beat_idx;
               end
               if (state[reg_dir_tag_sel_d] == ST_COMPLETE) begin                    // COMPLETE -> EMPTY (all consumed, can be cleared)
                    if(
                         (reg_rd_dir_entry_consumed[reg_dir_tag_sel_d] & ~entry[reg_dir_tag_sel_d].is_write) |
                         (reg_wr_dir_entry_consumed[reg_dir_tag_sel_d] &  entry[reg_dir_tag_sel_d].is_write)
                    ) begin
                         state[reg_dir_tag_sel_d]                  <= ST_EMPTY;
                         entry[reg_dir_tag_sel_d]                  <= '0;                         
                    end
               end
          end
     end

     // =============================================================
     // POP block (ALLOCATED -> PENDING)
     // Scan for oldest ALLOCATED entry
     // =============================================================
     always_comb begin
          found_alloc                   = 1'b0;
          oldest_tag                    = '0;
          for (int i = 0; i < DIR_ENTRIES; i++) begin       // Simple linear scan for now
               if (state[i] == ST_ALLOCATED && !found_alloc) begin
                    found_alloc         = 1'b1;
                    oldest_tag          = i;
               end
          end
     end

     // =============================================================
     // FREE block (EMPTY detection)
     // Scan for smallest EMPTY entry
     // =============================================================
     always_comb begin
          found_free                    = 1'b0;
          free_tag                      = '0;
          for (int i = 0; i < DIR_ENTRIES; i++) begin
               if (state[i] == ST_EMPTY && !found_free) begin
                    found_free          = 1'b1;
                    free_tag            = i[TAG_W-1:0];
               end
          end
     end

     // =============================================================
     // SIZE per-TAG
     // =============================================================
     genvar i;
     generate
          for (i = 0; i < TAG_NUM; i++) begin : GEN_DIR_SIZE
               assign dir_rsp_tag_size[i] = entry[i].size;
          end
     endgenerate


// ==========================================================================================================================
// =================================================== DEBUG infra ==========================================================
// ==========================================================================================================================

     bit dir_debug_en;

     initial begin
          dir_debug_en = $test$plusargs("APB2AXI_DIR_DEBUG");
          if (dir_debug_en)
               $display("%t [DIR_DBG] Directory debug ENABLED (+APB2AXI_DIR_DEBUG)", $time);
     end

     function automatic string state2str(entry_state_e s);
          case (s)
               ST_EMPTY:     return "EMPTY   ";
               ST_ALLOCATED: return "ALLOC   ";
               ST_PENDING:   return "PENDING ";
               ST_COMPLETE:  return "COMPLETE";
               default:      return "UNKNOWN ";
          endcase
     endfunction

     task automatic dir_dump(string reason = "");
          if (!dir_debug_en) return;

          $display("%t [DIR_DUMP] ---- Directory dump (%s) ----", $time, reason);
          for (int i = 0; i < DIR_ENTRIES; i++) begin
               $display("  idx=%0d state=%s tag=%0d addr=%h len=%0d size=%0d is_wr=%0b resp=%0d beats=%0d",
                        i,
                        state2str(state[i]),
                        entry[i].tag,
                        entry[i].addr,
                        entry[i].len,
                        entry[i].size,
                        entry[i].is_write,
                        entry[i].resp,
                        entry[i].num_beats);
          end
          $display("%t [DIR_DUMP] ---------------------------------", $time);
     endtask

     // =============================================================
     // PER-CYCLE DIRECTORY DUMP (when enabled)
     // =============================================================
     always_ff @(posedge pclk) begin
          if (dir_debug_en) begin
               if (!presetn)
                    dir_dump("RESET");
               else
                    dir_dump("CYCLE");
          end
     end

// ==========================================================================================================================
// ==========================================================================================================================
// ==========================================================================================================================



endmodule