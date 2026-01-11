
//------------------------------------------------------------------------------
// apb2axi_read_bringup_seq.sv
// Simple READ bring-up: program one read via APB,
// then check AXI AR/R via axi_mon_fifo and BFM memory pattern.
//------------------------------------------------------------------------------

`ifndef APB2AXI_READ_BRINGUP_SEQ_SV
`define APB2AXI_READ_BRINGUP_SEQ_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
import apb2axi_tb_pkg::*;
import apb2axi_pkg::*;

class apb2axi_read_bringup_seq extends apb2axi_base_seq;

    `uvm_object_utils(apb2axi_read_bringup_seq)

    function new(string name = "apb2axi_read_bringup_seq");
        super.new(name);
    endfunction

    task body();
        axi_seq_item axi_got;
        bit [31:0]  base_addr;
        int unsigned expected_idx;

        `uvm_info("READ_BRINGUP_SEQ",
                  "Starting APB2AXI READ bringup sequence",
                  UVM_LOW)

        // Choose some non-zero aligned address
        base_addr    = 32'h0000_0010;   // word index = 4 (for 32-bit data)
        expected_idx = base_addr >> $clog2(AXI_DATA_W/8);  // matches BFM: mem[idx][31:0] = idx

        // 1) addr_hi = 0
        apb_write(16'h0004, 32'h0000_0000);

        // 2) CMD = read, len=1, size=0   (same encoding as your first bringup)
        apb_write(16'h000f, 32'h0000_0001);

        // 3) addr_lo = base_addr → commit_pulse
        apb_write(16'h0000, base_addr);

        if (m_env == null) `uvm_fatal("READ_BRINGUP_SEQ", "m_env is NULL – test must set it before starting sequence")

        // Give some time for AR + R to happen
        #200ns;

        // Block until AXI monitor reports the READ transaction
        m_env.axi_mon_fifo.get(axi_got);

        // ---------------- Checks ----------------
        if (axi_got.write) begin
            `uvm_error("READ_BRINGUP_SEQ", $sformatf("Expected READ, got WRITE: %s", axi_got.convert2string()))
        end

        if (axi_got.addr[31:0] != base_addr) begin
            `uvm_error("READ_BRINGUP_SEQ", $sformatf("Unexpected AXI addr. Got 0x%0h, expected 0x%0h", axi_got.addr, 64'(base_addr)))
        end

        // BFM memory pattern: mem[idx][31:0] = idx
        if (axi_got.data[31:0] != expected_idx) begin
            `uvm_error("READ_BRINGUP_SEQ", $sformatf("Unexpected read data. Got 0x%0h, expected 0x%0h", axi_got.data[31:0], expected_idx))
        end
        else begin
            `uvm_info("READ_BRINGUP_SEQ", $sformatf("READ OK: addr=0x%0h data=0x%0h (idx=%0d)", base_addr, axi_got.data[31:0], expected_idx), apb2axi_verbosity)
        end

    endtask

endclass

`endif