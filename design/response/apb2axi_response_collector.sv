/*------------------------------------------------------------------------------
 * File          : apb2axi_response_collector.sv
 * Project       : APB2AXI
 * Author        : Nir Miller & Ido Oreg
 * Description   : - Collects AXI read (R) and write (B) channel responses
 *                 - Pushes read data beats into the RDF with per-beat metadata
 *                 - Bundles completed transactions into the completion FIFO
 *------------------------------------------------------------------------------*/

import apb2axi_pkg::*;

module apb2axi_response_collector #(
)(
    input  logic                    aclk,
    input  logic                    aresetn,
    // AXI Read Data Channel (R)
    input  logic [TAG_W-1:0]        rid,
    input  logic [AXI_DATA_W-1:0]   rdata,
    input  logic [1:0]              rresp,
    input  logic                    rlast,
    input  logic                    rvalid,
    output logic                    rready,
    // AXI Write Response Channel (B)
    input  logic [TAG_W-1:0]        bid,
    input  logic [1:0]              bresp,
    input  logic                    bvalid,
    output logic                    bready,

    // RDF interface (AXI side)
    output logic                    rsp_rdf_push_vld,
    output rdf_entry_t              rsp_rdf_push_payload,
    input  logic                    rsp_rdf_push_rdy,
    // Completion FIFO IF (AXI side)
    output logic                    rsp_cq_push_vld,
    output logic [CPL_W-1:0]        rsp_cq_push_data,
    input  logic                    rsp_cq_push_rdy,

    input logic                     resp_policy_cfg             // 0=FIRST_ERROR, 1=WORST_ERROR
);

    completion_entry_t cpl_reg;

    logic                           reads_inflight [TAG_NUM];
    logic [7:0]                     beat_cnt       [TAG_NUM];

    logic                           err_seen       [TAG_NUM];
    axi_resp_e                      err_resp       [TAG_NUM];
    logic [7:0]                     err_beat_idx   [TAG_NUM];

    logic [TAG_W-1:0]               read_idx;

    assign rready                   = rsp_rdf_push_rdy;
    assign bready                   = 1'b1;

    function automatic int resp_severity(axi_resp_e r);
        case (r)
            AXI_RESP_OKAY:   return 0;
            AXI_RESP_EXOKAY: return 1;
            AXI_RESP_SLVERR: return 2;
            AXI_RESP_DECERR: return 3;
            default:         return 0;
        endcase
    endfunction

    function automatic string resp2s(logic [1:0] r);
        case (r)
            2'b00:      return "OKAY";
            2'b01:      return "EXOKAY";
            2'b10:      return "SLVERR";
            2'b11:      return "DECERR";
            default:    return "UNKN";
        endcase
    endfunction

    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            rsp_rdf_push_vld        <= 1'b0;
            rsp_rdf_push_payload    <= '0;

            rsp_cq_push_vld         <= 1'b0;
            rsp_cq_push_data        <= '0;

            for (int i = 0; i < TAG_NUM; i++) begin
                reads_inflight[i]   <= 1'b0;
                beat_cnt[i]         <= '0;
                err_seen[i]         <= 1'b0;
                err_resp[i]         <= AXI_RESP_OKAY;
                err_beat_idx[i]     <= '0;
            end
        end
        else begin
            rsp_rdf_push_vld        <= 1'b0;
            rsp_cq_push_vld         <= 1'b0;

            // ====================================================
            // READ DATA & COMPLETION HANDLING
            // ====================================================
            if (rvalid && rready) begin
                logic [7:0]         curr_beat_idx;
                axi_resp_e          rr;
                logic               eff_seen;
                axi_resp_e          eff_resp;
                logic [7:0]         eff_idx;

                read_idx            = rid;
                curr_beat_idx       = reads_inflight[read_idx] ? beat_cnt[read_idx] : 8'd0;
                rr                  = axi_resp_e'(rresp);

                eff_seen            = err_seen[read_idx];
                eff_resp            = err_resp[read_idx];
                eff_idx             = err_beat_idx[read_idx];

                // RDF push
                if (rsp_rdf_push_rdy) begin
                    rdf_entry_t     beat;
                    beat.tag        = rid;
                    beat.data       = rdata;
                    beat.last       = rlast;
                    beat.resp       = rr;

                    rsp_rdf_push_payload <= beat;
                    rsp_rdf_push_vld     <= 1'b1;
                end

                // Start-of-transaction init / beat counter
                if (!reads_inflight[read_idx]) begin
                    reads_inflight[read_idx] <= 1'b1;
                    beat_cnt[read_idx]       <= 8'd1;
                    // reset error tracking for new txn
                    err_seen[read_idx]       <= 1'b0;
                    err_resp[read_idx]       <= AXI_RESP_OKAY;
                    err_beat_idx[read_idx]   <= '0;
                    // also reset effective view
                    eff_seen = 1'b0;
                    eff_resp = AXI_RESP_OKAY;
                    eff_idx  = 8'h00;
                end
                else begin
                    beat_cnt[read_idx] <= beat_cnt[read_idx] + 1;
                end

                // ----------------------------
                // ERROR TRACKING (effective)
                // ----------------------------
                if (rr != AXI_RESP_OKAY) begin
                    if (!eff_seen) begin
                        eff_seen = 1'b1;
                        eff_resp = rr;
                        eff_idx  = curr_beat_idx;
                    end
                    else if (resp_policy_cfg != 0) begin
                        int old_sev, new_sev;
                        old_sev = resp_severity(eff_resp);
                        new_sev = resp_severity(rr);
                        if (new_sev > old_sev) begin
                            eff_resp = rr;
                            eff_idx  = curr_beat_idx;
                        end
                    end
                end
                err_seen[read_idx]     <= eff_seen;
                err_resp[read_idx]     <= eff_resp;
                err_beat_idx[read_idx] <= eff_idx;

                // ----------------------------
                // COMPLETION ON RLAST
                // ----------------------------
                if (rlast) begin
                    completion_entry_t cpl;
                    cpl.is_write     = 1'b0;
                    cpl.tag          = rid;
                    cpl.error        = eff_seen;
                    cpl.resp         = eff_seen ? eff_resp : AXI_RESP_OKAY;
                    cpl.num_beats    = curr_beat_idx + 1;
                    cpl.err_beat_idx = eff_seen ? eff_idx : 8'h00;
                    
                    reads_inflight[read_idx] <= 1'b0;

                    if (rsp_cq_push_rdy) begin
                        rsp_cq_push_data <= cpl;
                        rsp_cq_push_vld  <= 1'b1;
                    end
                end
            end

            // ====================================================
            // WRITE COMPLETION HANDLING
            // ====================================================
            if (bvalid && bready) begin
                completion_entry_t bw_cpl;
                bw_cpl.is_write     = 1'b1;
                bw_cpl.tag          = bid;
                bw_cpl.resp         = axi_resp_e'(bresp);
                bw_cpl.error        = (axi_resp_e'(bresp) != AXI_RESP_OKAY);
                bw_cpl.num_beats    = 8'd0;
                bw_cpl.err_beat_idx = 8'h00;

                if (rsp_cq_push_rdy) begin
                    rsp_cq_push_data <= bw_cpl;
                    rsp_cq_push_vld  <= 1'b1;
                end
            end
        end
    end

endmodule