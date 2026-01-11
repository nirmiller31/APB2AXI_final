/*------------------------------------------------------------------------------
 * File          : apb2axi_response_handler.sv
 * Project       : APB2AXI
 * Author        : Nir Miller & Ido Oreg
 * Description   : - Collects AXI read responses and completion records
 *                 - Buffers read beats per TAG and slices AXI data into APB words
 *                 - Drains read data to APB registers and signals directory completion
 *------------------------------------------------------------------------------*/
 
import apb2axi_pkg::*;

module apb2axi_response_handler #()(
    input  logic                                    pclk,
    input  logic                                    presetn,

    // RDF
    input  logic                                    rsp_rdf_pop_vld,
    input  rdf_entry_t                              rsp_rdf_pop_payload,
    output logic                                    rsp_rdf_pop_rdy,

    // Completion FIFO (consume completetions)
    input  logic                                    rsp_cq_pop_vld,
    input  completion_entry_t                       rsp_cq_pop_data,
    output logic                                    rsp_cq_pop_rdy,

    // APB Data drain
    output logic [TAG_NUM-1:0]                      rdf_reg_data_vld,
    output logic [TAG_NUM-1:0][APB_DATA_W-1:0]      rdf_reg_data_out,
    output logic [TAG_NUM-1:0]                      rdf_reg_data_last,
    input  logic [TAG_NUM-1:0]                      rdf_reg_data_rdy,

    // Directory completion
    output logic                                    cq_dir_cpl_vld,
    output completion_entry_t                       cq_dir_cpl_entry,
    input  logic                                    cq_dir_cpl_rdy,

    input logic [TAG_NUM-1:0][2:0]                  dir_rsp_tag_size

);

    // ======================================================================
    // Completion Indicator (for the Directory)
    // ======================================================================
    always_ff @(posedge pclk) begin
        if (!presetn) begin
            rsp_cq_pop_rdy                  <= 1'b0;
            cq_dir_cpl_vld                  <= 1'b0;
        end else begin
            completion_entry_t cq_cpl;
            cq_cpl                          = rsp_cq_pop_data;      // FIXME check if possible without delay
            rsp_cq_pop_rdy                  <= cq_dir_cpl_rdy;
            cq_dir_cpl_vld                  <= 1'b0;
            if (rsp_cq_pop_vld && rsp_cq_pop_rdy) begin
                cq_dir_cpl_vld              <= 1'b1;
                cq_dir_cpl_entry            <= cq_cpl;
            end      
        end
    end

    // ======================================================================
    // APB Storing & Slicing: read 32-bit words
    //  - Output buffer holds VALID until READY
    // ======================================================================

    rd_beat_t                               tag_mem[TAG_NUM][MAX_BEATS_NUM];

    logic [$clog2(MAX_BEATS_NUM)-1:0]       head [TAG_NUM];
    logic [$clog2(MAX_BEATS_NUM)-1:0]       tail [TAG_NUM];
    logic [$clog2(MAX_BEATS_NUM+1)-1:0]     count[TAG_NUM];

    logic [AXI_DATA_W-1:0]                  cur_data [TAG_NUM];
    logic                                   cur_last [TAG_NUM];
    logic                                   cur_valid[TAG_NUM];
    logic [$clog2(AXI_DATA_W):0]            cur_idx  [TAG_NUM];

    logic [2:0]                             rd_size [TAG_NUM];

    assign rsp_rdf_pop_rdy                  = (count[rsp_rdf_pop_payload.tag] < MAX_BEATS_NUM);    // stall when per-tag FIFO is full

    genvar gt;
    generate
        for (gt = 0; gt < TAG_NUM; gt++) begin : GEN_VLD
            assign rdf_reg_data_vld[gt] = cur_valid[gt] || (count[gt] != 0);
        end
    endgenerate

    // ======================================================================
    // "word head"
    // ======================================================================
    // generate
    //     for (gt = 0; gt < TAG_NUM; gt++) begin : GEN_PEEK
    //         always_comb begin
    //             rdf_reg_data_out[gt]                = '0;
    //             rdf_reg_data_last[gt]               = 1'b0;

    //             if (cur_valid[gt]) begin                // If mid-slice: peek current slice
    //                 rdf_reg_data_out[gt]            = cur_data[gt][cur_idx[gt] +: APB_DATA_W];
    //                 if (cur_last[gt] && (cur_idx[gt] + APB_DATA_W == AXI_DATA_W) && (count[gt] == 0)) begin
    //                     rdf_reg_data_last[gt]       = 1'b1;
    //                 end                                 // "last" is true only on the FINAL slice of FINAL beat for this tag
    //             end
    //             else if (count[gt] != 0) begin          // Else if FIFO has a beat: peek first slice of FIFO head
    //                 rdf_reg_data_out[gt]            = tag_mem[gt][head[gt]].data[0 +: APB_DATA_W];
    //                 if (AXI_DATA_W == APB_DATA_W) begin // If entire AXI beat fits in one APB word, last can be true right away
    //                     if (tag_mem[gt][head[gt]].last && (count[gt] == 1)) begin
    //                         rdf_reg_data_last[gt]   = 1'b1;
    //                     end
    //                 end
    //             end
    //         end
    //     end
    // endgenerate

    generate
        for (gt = 0; gt < TAG_NUM; gt++) begin : GEN_PEEK
            always_comb begin
                int unsigned            valid_bits;
                logic [APB_DATA_W-1:0]  slice;
                logic [APB_DATA_W-1:0]  mask;

                valid_bits = (1 << dir_rsp_tag_size[gt]) * 8;

                rdf_reg_data_out[gt]  = '0;
                rdf_reg_data_last[gt] = 1'b0;

                if (cur_valid[gt]) begin
                    // Mid-slice
                    if (cur_idx[gt] < valid_bits)
                        mask  = (valid_bits >= APB_DATA_W) ? {APB_DATA_W{1'b1}} : ((1 << valid_bits) - 1);
                        slice = cur_data[gt][cur_idx[gt] +: APB_DATA_W];
    
                        rdf_reg_data_out[gt] = slice & mask;
                    // LAST on final *valid* slice of final beat
                    if (cur_last[gt] && (cur_idx[gt] + APB_DATA_W >= valid_bits) && (count[gt] == 0)) begin
                        rdf_reg_data_last[gt] = 1'b1;
                    end
                end
                else if (count[gt] != 0) begin
                    // First slice of a new beat
                    if (valid_bits > 0)
                        mask  = (valid_bits >= APB_DATA_W) ? {APB_DATA_W{1'b1}} : ((1 << valid_bits) - 1);
                        slice = tag_mem[gt][head[gt]].data[0 +: APB_DATA_W];
    
                        rdf_reg_data_out[gt] = slice & mask;

                    // If only one valid slice in this beat
                    if (tag_mem[gt][head[gt]].last && (APB_DATA_W >= valid_bits) && (count[gt] == 1)) begin
                        rdf_reg_data_last[gt] = 1'b1;
                    end
                end
            end
        end
    endgenerate

    // ======================================================================
    // Enqueue AXI read beats into per-TAG FIFO
    // ======================================================================
    always_ff @(posedge pclk) begin
        if (!presetn) begin
            for (int t = 0; t < TAG_NUM; t++) begin
                head[t]                 <= '0;
                tail[t]                 <= '0;
                count[t]                <= '0;

                cur_valid[t]            <= 1'b0;
                cur_idx[t]              <= '0;
                cur_last[t]             <= 1'b0;
                cur_data[t]             <= '0;
            end
        end else begin
            logic [TAG_NUM-1:0] inc, dec;
            inc                         = '0;
            dec                         = '0;

            if (rsp_rdf_pop_vld && rsp_rdf_pop_rdy) begin
                int tg;
                tg                              = rsp_rdf_pop_payload.tag;
                inc[rsp_rdf_pop_payload.tag]    = 1'b1;
                tag_mem[tg][tail[tg]]           <= '{data : rsp_rdf_pop_payload.data, resp : rsp_rdf_pop_payload.resp, last : rsp_rdf_pop_payload.last};
                tail[tg]                        <= tail[tg] + 1'b1;
            end

            for (int t = 0; t < TAG_NUM; t++) begin
                if ((cur_valid[t] || (count[t] != 0)) && rdf_reg_data_rdy[t]) begin
                    int unsigned valid_bits;
                    valid_bits = (1 << dir_rsp_tag_size[t]) * 8;

                    if (!cur_valid[t])                  // Dequeue (only when we pop a NEW beat from FIFO)
                        dec[t]                  = 1'b1;
                    
                    if (cur_valid[t]) begin             // Slicing
                        if (cur_idx[t] + APB_DATA_W == valid_bits) begin
                            cur_valid[t]        <= 1'b0;
                            cur_idx[t]          <= '0;
                        end else begin
                            cur_idx[t]          <= cur_idx[t] + APB_DATA_W;
                        end
                    end
                    else begin                          // New beat
                        rd_beat_t beat;
                        
                        beat                    = tag_mem[t][head[t]];
                        head[t]                 <= head[t] + 1'b1;

                        if (valid_bits > APB_DATA_W) begin
                            cur_valid[t] <= 1'b1;
                            cur_idx[t]   <= APB_DATA_W;
                            cur_data[t]  <= beat.data;
                            cur_last[t]  <= beat.last;
                        end else begin
                            // Only one APB word is valid in this beat (e.g. SIZE=0/1/2)
                            cur_valid[t] <= 1'b0;
                            cur_idx[t]   <= '0;
                            cur_data[t]  <= '0;
                            cur_last[t]  <= 1'b0;
                        end
                    end
                end
            end

            for (int t = 0; t < TAG_NUM; t++) begin // Count update per TAG
                unique case ({inc[t], dec[t]})
                    2'b10: count[t]             <= count[t] + 1'b1;
                    2'b01: count[t]             <= count[t] - 1'b1;
                    2'b11: count[t]             <= count[t];
                    default: count[t]           <= count[t];
                endcase
            end
        end
    end


// ==========================================================================================================================
// =================================================== DEBUG infra (per-tag) ================================================
// ==========================================================================================================================

    // bit rh_debug_en;
    // int rh_debug_tag;

    // initial begin
    //     rh_debug_en  = $test$plusargs("APB2AXI_RH_DEBUG");
    //     rh_debug_tag = -1;

    //     // Read +APB2AXI_RH_DEBUG_TAG=<N>
    //     if (!$value$plusargs("APB2AXI_RH_DEBUG_TAG=%d", rh_debug_tag))
    //         rh_debug_tag = -1;

    //     if (rh_debug_en) begin
    //         if (rh_debug_tag < 0 || rh_debug_tag >= TAG_NUM) begin
    //             $display("%t [RH_DBG] ENABLED (+APB2AXI_RH_DEBUG) but missing/invalid +APB2AXI_RH_DEBUG_TAG=<0..%0d> (tag=%0d) -> dumps DISABLED",
    //                     $time, TAG_NUM-1, rh_debug_tag);
    //             rh_debug_en = 1'b0; // avoid accidental spam
    //         end else begin
    //             $display("%t [RH_DBG] ResponseHandler debug ENABLED (+APB2AXI_RH_DEBUG +APB2AXI_RH_DEBUG_TAG=%0d)", $time, rh_debug_tag);
    //         end
    //     end
    // end

    // function automatic string resp2str(logic [1:0] r);
    //     case (r)
    //         2'b00: return "OKAY  ";
    //         2'b01: return "EXOKAY";
    //         2'b10: return "SLVERR";
    //         2'b11: return "DECERR";
    //         default: return "UNKN  ";
    //     endcase
    // endfunction

    // task automatic rh_dump_tag(int t, string reason="");
    //     int idx;
    //     if (!rh_debug_en) return;

    //     $display("%t [RH_DUMP] ---- TAG=%0d (%s) ---- head=%0d tail=%0d count=%0d cur_valid=%0b cur_idx=%0d cur_last=%0b",
    //             $time, t, reason, head[t], tail[t], count[t], cur_valid[t], cur_idx[t], cur_last[t]);

    //     // ACTIVE window dump only: print "count" entries starting from head (wrap safe)
    //     idx = head[t];
    //     for (int k = 0; k < MAX_BEATS_NUM; k++) begin
    //         rd_beat_t b;
    //         b = tag_mem[t][idx];
    //         $display("  act[%0d] mem[%0d]= data=%h resp=%s last=%0b", k, idx, b.data, resp2str(b.resp), b.last);
    //         idx = (idx + 1) % MAX_BEATS_NUM;
    //     end

    //     $display("%t [RH_DUMP] ----------------------------", $time);
    // endtask

    // task automatic rh_dump_one(string reason="");
    //     if (!rh_debug_en) return;

    //     // Helpful one-line summaries to correlate with waveforms
    //     $display("%t [RH_DUMP] ===== RH dump (%s) tag=%0d =====", $time, reason, rh_debug_tag);
    //     $display("  APB_REQ: req=%0b tag=%0d ready=%0b  out_vld=%0b out_last=%0b out_data=%h",
    //             rdf_reg_data_req, rdf_reg_data_req_tag, rdf_reg_data_rdy,
    //             rdf_reg_data_vld, rdf_reg_data_last, rdf_reg_data_out);
    //     $display("  RDF_IN : pop_vld=%0b pop_rdy=%0b tag=%0d last=%0b resp=%s data=%h",
    //             rsp_rdf_pop_vld, rsp_rdf_pop_rdy,
    //             rsp_rdf_pop_payload.tag, rsp_rdf_pop_payload.last, resp2str(rsp_rdf_pop_payload.resp),
    //             rsp_rdf_pop_payload.data);
    //     $display("  CQ_IN  : pop_vld=%0b pop_rdy=%0b  dir_cpl_vld=%0b dir_cpl_rdy=%0b",
    //             rsp_cq_pop_vld, rsp_cq_pop_rdy, cq_dir_cpl_vld, cq_dir_cpl_rdy);

    //     rh_dump_tag(rh_debug_tag, reason);
    //     $display("%t [RH_DUMP] ================================", $time);
    // endtask

    // always_ff @(posedge pclk) begin
    //     if (rh_debug_en) begin
    //         if (!presetn)
    //             rh_dump_one("RESET");
    //         else
    //             rh_dump_one("CYCLE");
    //     end
    // end

// ==========================================================================================================================
// ==========================================================================================================================
// ==========================================================================================================================

endmodule