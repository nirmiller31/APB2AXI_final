//------------------------------------------------------------------------------
// File : tb/seq/apb2axi_write_error_seq.sv
// Desc : Write error injection verification
//        Single BRESP per tag (policy-independent)
//------------------------------------------------------------------------------

import uvm_pkg::*;
`include "uvm_macros.svh"
import apb2axi_pkg::*;

class apb2axi_write_error_seq extends apb2axi_base_seq;
     `uvm_object_utils(apb2axi_write_error_seq)

     function new(string name="apb2axi_write_error_seq");
          super.new(name);
     endfunction

     // ------------------------------------------------------------
     // Read status (write path uses same packing)
     // ------------------------------------------------------------
     task automatic read_status_simple(
          input  bit [TAG_W-1:0] tag,
          output bit             done,
          output bit             error,
          output bit [1:0]       resp,
          output bit [7:0]       num_beats
     );
          bit [APB_REG_W-1:0] sts;
          bit slverr;

          apb_read(tag_win_addr(REG_ADDR_RD_STATUS, tag), sts, slverr);

          done      = sts[15];
          error     = sts[14];
          resp      = sts[13:12];
          num_beats = sts[7:0];

     endtask

     // ------------------------------------------------------------
     // Wait for completion WITHOUT fatal on error
     // ------------------------------------------------------------
     task automatic wait_completion_no_fatal(
          input  bit [TAG_W-1:0] tag,
          output bit             done,
          output bit             error,
          output bit [1:0]       resp,
          output bit [7:0]       num_beats,
          input  int             timeout = 500
     );
          done = 0; error = 0; resp = 0; num_beats = 0;

          repeat (timeout) begin
               read_status_simple(tag, done, error, resp, num_beats);
               if (done || error) return;
               #50;
          end

          `uvm_fatal(get_name(), $sformatf("TAG %0d TIMEOUT waiting for completion", tag))
     endtask

     // ------------------------------------------------------------
     // Main test
     // ------------------------------------------------------------
     task body();
          bit [AXI_ADDR_W-1:0] addr;

          bit done, error;
          bit [1:0] resp;
          bit [7:0] num_beats;

          axi_resp_e exp_resp;
          bit         exp_error;

          bit [TAG_W-1:0] tag   = '0;
          int unsigned    beats = 1;   // single-beat write

          `uvm_info(get_name(), "Starting apb2axi_write_error_seq", UVM_NONE)

          // -------------------------------------------------
          // CASE: DECERR on B channel
          // -------------------------------------------------
          addr = rand_addr_in_range_aligned();

          // Program write command (len=0 => 1 beat)
          program_write_cmd(0);
          // Inject B-channel error
          m_env.axi_bfm.inject_write_error(tag, AXI_RESP_DECERR);
          program_addr(addr);

          // Push full AXI beat (64b = 2 APB words)
          push_wr_apb_word(tag, 32'hDEAD_BEEF);
          push_wr_apb_word(tag, 32'hCAFEBABE);

          // Wait for completion (expect error)
          wait_completion_no_fatal(tag, done, error, resp, num_beats);

          // -------------------------------------------------
          // Expected outcome
          // -------------------------------------------------
          exp_resp  = AXI_RESP_DECERR;
          exp_error = 1'b1;

          // -------------------------------------------------
          // Check
          // -------------------------------------------------
          if (resp != exp_resp[1:0] || error != exp_error)
               `uvm_fatal(get_name(),
                    $sformatf("WRITE ERROR mismatch: got(err=%0b resp=%0d) exp(err=%0b resp=%0d)", error, resp, exp_error, exp_resp))

          `uvm_info(get_name(), "apb2axi_write_error_seq PASSED", UVM_NONE)
     endtask

endclass