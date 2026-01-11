
package apb2axi_tb_pkg;

     import uvm_pkg::*;
     import apb2axi_pkg::*;
     import apb2axi_memory_pkg::*;

     int unsigned apb2axi_verbosity = UVM_DEBUG;
     
     `include "uvm_macros.svh"
     `include "defines.svh"

     function void apb2axi_configure_verbosity();
          if ($test$plusargs("APB2AXI_DEBUG")) begin
               apb2axi_verbosity = UVM_NONE;
               `uvm_info("APB2AXI_PKG", "APB2AXI_DEBUG flag detected → quiet mode (UVM_NONE)", UVM_NONE)
          end
          else begin
               apb2axi_verbosity = UVM_DEBUG;
               `uvm_info("APB2AXI_PKG", "Defaulting to verbose mode (UVM_DEBUG)", UVM_DEBUG)
          end
     endfunction

     // ======================================================
     //  Sequence items
     // ======================================================
     `include "tb/seq_item/apb_seq_item.sv"
     `include "tb/seq_item/axi_seq_item.sv"
     `include "tb/seq_item/virtual_seq_item.sv"

     // ======================================================
     //  Agents
     // ======================================================
     `include "tb/agent/apb_driver.sv"
     `include "tb/agent/apb_monitor.sv"
     `include "tb/agent/apb_sequencer.sv"
     `include "tb/agent/apb_agent.sv"

     `include "tb/agent/axi_driver.sv"
     `include "tb/agent/axi_monitor.sv"
     `include "tb/agent/axi_sequencer.sv"
     `include "tb/agent/axi_agent.sv"

     // ======================================================
     //  Enviorment
     // ======================================================
     // `include "tb/bfm/apb2axi_memory_pkg.sv"
     `include "tb/bfm/axi3_slave_bfm.sv"
     `include "tb/env/apb2axi_scoreboard.sv"
     `include "tb/env/apb2axi_env.sv"

     // ==========================================================
     //  Sequences
     // ==========================================================
     `include "tb/seq/apb2axi_base_seq.sv"
     `include "tb/seq/apb2axi_read_seq.sv"
     `include "tb/seq/apb2axi_write_seq.sv"
     `include "tb/seq/apb2axi_e2e_seq.sv"
     `include "tb/seq/apb2axi_read_error_seq.sv"
     `include "tb/seq/apb2axi_write_error_seq.sv"

     // ======================================================
     //  Tests
     // ======================================================
     `include "tb/tests/apb2axi_base_test.sv"
     `include "tb/tests/apb2axi_test.sv"

     // ======================================================
     //  Bringup
     // ======================================================
     // `include "tb/seq/bringup/apb2axi_bringup_seq.sv"
     // `include "tb/seq/bringup/apb2axi_read_bringup_seq.sv"
     // `include "tb/seq/bringup/apb2axi_multiple_beat_read_seq.sv"
     // `include "tb/seq/bringup/apb2axi_multiple_read_drain_seq.sv"
     // `include "tb/seq/bringup/apb2axi_reconsume_same_tag_seq.sv"
     // `include "tb/seq/bringup/apb2axi_read_drain_seq.sv"
     // `include "tb/seq/bringup/apb2axi_window_seq.sv"
     // `include "tb/seq/bringup/apb2axi_random_drain_seq.sv"
     // `include "tb/seq/bringup/apb2axi_stress_seq.sv"
     // `include "tb/seq/bringup/apb2axi_wr_sanity_seq.sv"
     // `include "tb/seq/bringup/apb2axi_mul_wr_seq.sv"
     // `include "tb/tests/sanity_bringup_test.sv"
     // `include "tb/tests/apb2axi_bringup_test.sv"

     // ======================================================
     //  Helper Functions
     // ======================================================

endpackage