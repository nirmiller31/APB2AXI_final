
class axi_monitor extends uvm_monitor;

     `uvm_component_utils(axi_monitor)

     // Observes transactions for:
     uvm_analysis_port #(axi_seq_item)     ap;

     virtual axi_if                        vif;

     function new(string name = "axi_mon", uvm_component parent=null);
          super.new(name, parent);
          ap                                = new("ap", this);
     endfunction

     function void build_phase(uvm_phase phase);
          
          super.build_phase(phase);
          if (!uvm_config_db#(virtual axi_if)::get(this, "", "axi_vif", vif)) `uvm_fatal("AXI_MONITOR", "No virtual interface bound to axi_monitor")

     endfunction

     task run_phase(uvm_phase phase);

          wait (vif.ARESETn === 1'b1);
          @(posedge vif.ACLK);

          forever begin
               @(posedge vif.ACLK);
               // --- Detect Write Address handshake ---
               if (vif.AWVALID && vif.AWREADY) begin
                    axi_seq_item tr     = axi_seq_item::type_id::create("axi_wr_tr", this);
                    tr.write            = 1;
                    tr.addr             = vif.AWADDR;
                    tr.id               = vif.AWID;
                    tr.len              = vif.AWLEN;
                    tr.size             = vif.AWSIZE;
                    tr.burst            = vif.AWBURST;

                    // Capture data once WVALID/WREADY handshake completes
                    `uvm_info("AXI_MONITOR", $sformatf("AW handshake: id=%0d addr=0x%0h len=%0d size=%0d burst=%0d", tr.id, tr.addr, tr.len, tr.size, tr.burst), apb2axi_verbosity)
                    fork
                         automatic axi_seq_item wr_tr = tr;
                         begin
                              handle_write_transaction(wr_tr);
                         end
                    join_none
               end

               // --- Detect Read Address handshake ---
               else if (vif.ARVALID && vif.ARREADY) begin
                    axi_seq_item tr     = axi_seq_item::type_id::create("axi_rd_tr", this);
                    tr.write            = 0;
                    tr.addr             = vif.ARADDR;
                    tr.id               = vif.ARID;
                    tr.len              = vif.ARLEN;
                    tr.size             = vif.ARSIZE;
                    tr.burst            = vif.ARBURST;

                    `uvm_info("AXI_MONITOR", $sformatf("AR handshake: id=%0d addr=0x%0h len=%0d size=%0d burst=%0d", tr.id, tr.addr, tr.len, tr.size, tr.burst), apb2axi_verbosity)

                    // Wait for data return
                    fork
                         automatic axi_seq_item rd_tr = tr;
                         begin
                              handle_read_transaction(rd_tr);
                         end
                    join_none
               end
          end
     endtask
     // =========================================================
     // Private helpers
     // =========================================================

     // For now: assume single-beat write.
     // Later we can extend this to capture full bursts.
     task automatic handle_write_transaction(axi_seq_item tr);

          // Wait for at least one W beat
          @(posedge vif.ACLK);
          wait (vif.WVALID && vif.WREADY);
          tr.data = vif.WDATA;

          `uvm_info("AXI_MONITOR", $sformatf("WRITE data beat: id=%0d data=0x%0h last=%0b", tr.id, tr.data, vif.WLAST), apb2axi_verbosity)

          // FIXME in future: loop until WLAST == 1

          // Wait for response
          wait (vif.BVALID && vif.BREADY);
          tr.resp = vif.BRESP;

          `uvm_info("AXI_MONITOR", $sformatf("WRITE resp: id=%0d resp=%0d", tr.id, tr.resp), apb2axi_verbosity)

          // Transaction is now complete
          ap.write(tr);

     endtask : handle_write_transaction

     // For now: assume single-beat read.
     // Later we can extend this to consume a full R burst.
     task automatic handle_read_transaction(axi_seq_item tr);

          // Wait for first data beat
          @(posedge vif.ACLK);
          wait (vif.RVALID && vif.RREADY);
          tr.data = vif.RDATA;
          tr.resp = vif.RRESP;

          `uvm_info("AXI_MONITOR", $sformatf("READ data beat: id=%0d data=0x%0h resp=%0d last=%0b", tr.id, tr.data, tr.resp, vif.RLAST), apb2axi_verbosity)

          // FIXME in future: enforce RLAST==1 for single-beat,
          // or loop over beats until RLAST.

          ap.write(tr);

     endtask : handle_read_transaction

endclass
