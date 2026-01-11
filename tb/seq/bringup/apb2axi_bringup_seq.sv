
//------------------------------------------------------------------------------
// File          : apb2axi_bringup_seq.sv
// Project       : APB2AXI
// Author        : Nir Miller & Ido Oreg
// Description   : Minimal directed APB sequence to trigger a single commit_pulse
//------------------------------------------------------------------------------

`ifndef APB2AXI_BRINGUP_SEQ_SV
`define APB2AXI_BRINGUP_SEQ_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
import apb2axi_tb_pkg::*;

class apb2axi_bringup_seq extends apb2axi_base_seq;

     `uvm_object_utils(apb2axi_bringup_seq)

     function new(string name = "apb2axi_bringup_seq");
          super.new(name);
     endfunction

     task body();
          axi_seq_item axi_got;

          `uvm_info("BRINGUP_SEQ", "Starting APB2AXI bringup sequence", UVM_LOW)

          // 1) Program addr_hi = 0
          apb_write(16'h0004, 32'h0000_0000);

          // 2) Program CMD    = read, len=1, size=0  (you can tweak later)
          apb_write(16'h0008, 32'h0000_0001);

          // 3) Program addr_lo and trigger commit_pulse
          apb_write(16'h0000, 32'h0000_1000);

          if (m_env == null)
               `uvm_fatal("BRINGUP_SEQ", "m_env is NULL – test must set it")

          // #200ns;

          // Block until AXI monitor reports one transaction
          m_env.axi_mon_fifo.get(axi_got);

          if ((axi_got.write != 0) || (axi_got.addr  != 64'h0000_0000_0000_1000)) begin
               `uvm_error("BRINGUP_SEQ", $sformatf("Unexpected AXI tx: %s", axi_got.convert2string()))
          end
          else begin
               `uvm_info("BRINGUP_SEQ", $sformatf("Matched AXI READ at 0x%0h OK", axi_got.addr), apb2axi_verbosity)
          end

     endtask

endclass

`endif