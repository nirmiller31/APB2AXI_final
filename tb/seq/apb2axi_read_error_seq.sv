//------------------------------------------------------------------------------
// File : tb/seq/apb2axi_read_error_seq.sv
// Desc : Read error injection verification (policy-aware) + err_beat_idx
//        Policy comes from +RESP_POLICY=<0|1> (default 0)
//------------------------------------------------------------------------------

import uvm_pkg::*;
`include "uvm_macros.svh"
import apb2axi_pkg::*;

class apb2axi_read_error_seq extends apb2axi_base_seq;
     `uvm_object_utils(apb2axi_read_error_seq)

     // 0 = FIRST_ERROR, 1 = WORST_ERROR
     int unsigned policy = 0;

     function new(string name="apb2axi_read_error_seq");
          super.new(name);
     endfunction

     // ------------------------------------------------------------
     // Helpers
     // ------------------------------------------------------------

     function automatic axi_resp_e resp_worst(axi_resp_e a, axi_resp_e b);
          // Priority: DECERR > SLVERR > EXOKAY > OKAY
          if (a == AXI_RESP_DECERR || b == AXI_RESP_DECERR) return AXI_RESP_DECERR;
          if (a == AXI_RESP_SLVERR || b == AXI_RESP_SLVERR) return AXI_RESP_SLVERR;
          if (a == AXI_RESP_EXOKAY || b == AXI_RESP_EXOKAY) return AXI_RESP_EXOKAY;
          return AXI_RESP_OKAY;
     endfunction

     // Read full status including err_beat_idx (matches your apb2axi_reg.sv packing)
     task automatic read_status_full(
          input  bit [TAG_W-1:0] tag,
          output bit             done,
          output bit             error,
          output bit [1:0]       resp,
          output bit [7:0]       num_beats,
          output bit [7:0]       err_beat_idx
     );
          bit [APB_REG_W-1:0] sts;
          bit slverr;

          apb_read(tag_win_addr(REG_ADDR_RD_STATUS, tag), sts, slverr);

          err_beat_idx = sts[23:16];
          done         = sts[15];
          error        = sts[14];
          resp         = sts[13:12];
          num_beats    = sts[11:4];
     endtask

     // Wait for completion but DO NOT fatal on error (this is an error test)
     task automatic wait_completion_no_fatal(
          input  bit [TAG_W-1:0] tag,
          output bit             done,
          output bit             error,
          output bit [1:0]       resp,
          output bit [7:0]       num_beats,
          output bit [7:0]       err_beat_idx,
          input  int             timeout = 500
     );
          done = 0; error = 0; resp = 0; num_beats = 0; err_beat_idx = 0;

          repeat (timeout) begin
               read_status_full(tag, done, error, resp, num_beats, err_beat_idx);
               if (done || error) return;
               #50;
          end

          `uvm_fatal(get_name(), $sformatf("TAG %0d TIMEOUT waiting for completion", tag))
     endtask

     // Drain RD_DATA so directory frees the TAG (pop all APB words)
     task automatic drain_rd_data(
          input bit [TAG_W-1:0] tag,
          input int unsigned    beats
     );
          bit [APB_DATA_W-1:0] d;
          bit slverr;

          for (int unsigned b = 0; b < beats; b++) begin
               for (int unsigned w = 0; w < APB_WORDS_PER_AXI_BEAT; w++) begin
                    pop_rd_apb_word(tag, d, slverr);
                    if (slverr) begin
                         `uvm_fatal(get_name(),
                              $sformatf("RD_DATA underflow while draining tag=%0d (beat=%0d word=%0d)", tag, b, w))
                    end
               end
          end
     endtask

     // Clear read error injection for a tag (prevents leftovers leaking)
     task automatic clear_read_injection(input bit [TAG_W-1:0] tag);
          // relies on your BFM exposing these as non-local
          m_env.axi_bfm.rerr_map_valid[tag] = 1'b0;
          for (int i = 0; i < 256; i++) begin
               m_env.axi_bfm.rerr_map[tag][i] = AXI_RESP_OKAY;
          end
     endtask

     // Compute expected outcome according to policy
     task automatic compute_expected(
          input  axi_resp_e     inj_resp0, input int unsigned inj_idx0, input bit inj_v0,
          input  axi_resp_e     inj_resp1, input int unsigned inj_idx1, input bit inj_v1,
          output axi_resp_e     exp_resp,
          output bit [7:0]      exp_err_idx,
          output bit            exp_error
     );
          // Defaults: no error
          exp_resp    = AXI_RESP_OKAY;
          exp_err_idx = 8'h00;
          exp_error   = 1'b0;

          if (!inj_v0 && !inj_v1) return;

          if (policy == 0) begin
               // FIRST_ERROR -> earliest beat index wins
               if (inj_v0 && (!inj_v1 || (inj_idx0 <= inj_idx1))) begin
                    exp_resp    = inj_resp0;
                    exp_err_idx = inj_idx0[7:0];
               end
               else begin
                    exp_resp    = inj_resp1;
                    exp_err_idx = inj_idx1[7:0];
               end
          end
          else begin
               // WORST_ERROR -> highest severity wins.
               // If tie on severity (e.g., SLVERR then SLVERR) keep earliest index.
               axi_resp_e best_resp;
               int unsigned best_idx;

               // Seed with one valid injection
               if (inj_v0) begin
                    best_resp = inj_resp0;
                    best_idx  = inj_idx0;
               end
               else begin
                    best_resp = inj_resp1;
                    best_idx  = inj_idx1;
               end

               // Consider the other injection (if exists)
               if (inj_v0 && inj_v1) begin
                    axi_resp_e combined;

                    // If we seeded from v0, compare v1; if seeded from v1, compare v0.
                    // Compare in time order so "same severity" keeps the earlier index.
                    if (inj_idx0 <= inj_idx1) begin
                         // best is inj0 (maybe), then check inj1
                         combined = resp_worst(best_resp, inj_resp1);
                         if (combined != best_resp) begin
                              best_resp = combined;
                              best_idx  = inj_idx1; // severity increased at inj1
                         end
                    end
                    else begin
                         // earliest is inj1, then inj0
                         best_resp = inj_resp1;
                         best_idx  = inj_idx1;

                         combined = resp_worst(best_resp, inj_resp0);
                         if (combined != best_resp) begin
                              best_resp = combined;
                              best_idx  = inj_idx0; // severity increased at inj0
                         end
                    end
               end

               exp_resp    = best_resp;
               exp_err_idx = best_idx[7:0];
          end

          exp_error = (exp_resp != AXI_RESP_OKAY);
     endtask

     // ------------------------------------------------------------
     // Main test
     // ------------------------------------------------------------
     task body();
          bit [AXI_ADDR_W-1:0]  addr;

          bit done, error;
          bit [1:0] resp;
          bit [7:0] num_beats;
          bit [7:0] err_idx;

          axi_resp_e exp_resp;
          bit [7:0]  exp_err_idx;
          bit        exp_error;

          bit [TAG_W-1:0] tag = '0;
          int unsigned beats = 4;   // len=3

          if ($test$plusargs("RESP_POLICY_WORST")) begin
               policy = 1;
               program_resp_policy_worst();
          end
          `uvm_info(get_name(), $sformatf("Starting read-error seq (policy=%0d; 0=FIRST,1=WORST)", policy), UVM_NONE)

          clear_read_injection(tag);

          // -------------------------------------------------
          // CASE 1: single SLVERR on beat 2
          // -------------------------------------------------
          `uvm_info(get_name(), "CASE 1: single SLVERR @ beat 2", UVM_NONE)

          addr = rand_addr_in_range_aligned();
          program_read_cmd(beats-1);

          m_env.axi_bfm.inject_read_error(tag, 2, AXI_RESP_SLVERR);

          program_addr(addr);

          wait_completion_no_fatal(tag, done, error, resp, num_beats, err_idx);

          compute_expected(AXI_RESP_SLVERR, 2, 1'b1, AXI_RESP_OKAY,   0, 1'b0, exp_resp, exp_err_idx, exp_error);

          if (num_beats != beats[7:0])
               `uvm_fatal(get_name(), $sformatf("CASE1 num_beats mismatch: got=%0d exp=%0d", num_beats, beats))
          if (resp != exp_resp[1:0] || error != exp_error || err_idx != exp_err_idx)
               `uvm_fatal(get_name(), $sformatf("CASE1 status mismatch: got(err=%0b resp=%0d err_idx=%0d) exp(err=%0b resp=%0d err_idx=%0d)", error, resp, err_idx, exp_error, exp_resp, exp_err_idx))

          drain_rd_data(tag, beats);
          clear_read_injection(tag);

          // -------------------------------------------------
          // CASE 2: SLVERR then DECERR later
          // -------------------------------------------------
          `uvm_info(get_name(), "CASE 2: SLVERR @1 then DECERR @3", UVM_NONE)

          addr = rand_addr_in_range_aligned();
          program_read_cmd(beats-1);
          
          m_env.axi_bfm.inject_read_error(tag, 1, AXI_RESP_SLVERR);
          m_env.axi_bfm.inject_read_error(tag, 3, AXI_RESP_DECERR);

          program_addr(addr);

          wait_completion_no_fatal(tag, done, error, resp, num_beats, err_idx);

          compute_expected(AXI_RESP_SLVERR, 1, 1'b1, AXI_RESP_DECERR, 3, 1'b1, exp_resp, exp_err_idx, exp_error);

          if (num_beats != beats[7:0])
               `uvm_fatal(get_name(), $sformatf("CASE2 num_beats mismatch: got=%0d exp=%0d", num_beats, beats))
          if (resp != exp_resp[1:0] || error != exp_error || err_idx != exp_err_idx)
               `uvm_fatal(get_name(), $sformatf("CASE2 status mismatch: got(err=%0b resp=%0d err_idx=%0d) exp(err=%0b resp=%0d err_idx=%0d)", error, resp, err_idx, exp_error, exp_resp, exp_err_idx))

          drain_rd_data(tag, beats);
          clear_read_injection(tag);

          // -------------------------------------------------
          // CASE 3: two errors, same severity (SLVERR then SLVERR)
          // -------------------------------------------------
          `uvm_info(get_name(), "CASE 3: SLVERR @0 then SLVERR @2", UVM_NONE)

          addr = rand_addr_in_range_aligned();
          program_read_cmd(beats-1);

          m_env.axi_bfm.inject_read_error(tag, 0, AXI_RESP_SLVERR);
          m_env.axi_bfm.inject_read_error(tag, 2, AXI_RESP_SLVERR);

          program_addr(addr);

          wait_completion_no_fatal(tag, done, error, resp, num_beats, err_idx);

          compute_expected(AXI_RESP_SLVERR, 0, 1'b1, AXI_RESP_SLVERR, 2, 1'b1, exp_resp, exp_err_idx, exp_error);

          if (num_beats != beats[7:0])
               `uvm_fatal(get_name(), $sformatf("CASE3 num_beats mismatch: got=%0d exp=%0d", num_beats, beats))
          if (resp != exp_resp[1:0] || error != exp_error || err_idx != exp_err_idx)
               `uvm_fatal(get_name(), $sformatf("CASE3 status mismatch: got(err=%0b resp=%0d err_idx=%0d) exp(err=%0b resp=%0d err_idx=%0d)", error, resp, err_idx, exp_error, exp_resp, exp_err_idx))

          drain_rd_data(tag, beats);
          clear_read_injection(tag);

          `uvm_info(get_name(), "apb2axi_read_error_seq PASSED", UVM_NONE)
     endtask

endclass