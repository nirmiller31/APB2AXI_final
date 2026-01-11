
class axi_driver extends uvm_driver #(axi_seq_item); // RSP defaults to REQ

     `uvm_component_utils(axi_driver)

     virtual axi_if vif;

     function new(string name = "axi_drv", uvm_component parent=null);
          super.new(name, parent);
     endfunction

     function void build_phase(uvm_phase phase); 
          super.build_phase(phase);
          if (!uvm_config_db#(virtual axi_if)::get(this, "", "axi_vif", vif)) `uvm_fatal("AXI_DRIVER", "No virtual interface bound to axi_driver")

     endfunction

     task run_phase(uvm_phase phase);
          
          axi_seq_item req;

          forever begin
               seq_item_port.get_next_item(req);
               if (req.write) begin
                    drive_write(req);
               end
               else begin
                    drive_read(req);
               end
               seq_item_port.item_done();
          end

     endtask

     task drive_write(axi_seq_item req);
          // --- Address phase ---
          vif.AWADDR          <= req.addr;
          vif.AWVALID         <= 1;
          vif.AWLEN           <= req.len;
          vif.AWBURST         <= req.burst;
          vif.AWSIZE          <= req.size;
          vif.AWID            <= req.id;
          @(posedge vif.ACLK iff vif.ARESETn);
          wait (vif.AWREADY);
          vif.AWVALID         <= 0;

          // --- Data phase ---
          vif.WDATA           <= req.data;
          vif.WSTRB           <= '1;
          vif.WLAST           <= 1;
          vif.WVALID          <= 1;
          @(posedge vif.ACLK iff vif.ARESETn);
          wait (vif.WREADY);
          vif.WVALID          <= 0;
          vif.WLAST           <= 0;

          // --- Response phase ---
          vif.BREADY          <= 1;
          wait (vif.BVALID);
          req.resp            = vif.BRESP;
          vif.BREADY          <= 0;

          `uvm_info("AXI_DRIVER", $sformatf("WRITE: addr=0x%08h data=0x%08h resp=%0d", req.addr, req.data, req.resp), apb2axi_verbosity)
     endtask

     task drive_read(axi_seq_item req);
          // --- Address phase ---
          vif.ARADDR          <= req.addr;
          vif.ARVALID         <= 1;
          vif.ARLEN           <= req.len;
          vif.ARBURST         <= req.burst;
          vif.ARSIZE          <= req.size;
          vif.ARID            <= req.id;
          @(posedge vif.ACLK iff vif.ARESETn);
          wait (vif.ARREADY);
          vif.ARVALID         <= 0;

          // --- Data phase ---
          vif.RREADY          <= 1;
          wait (vif.RVALID);
          req.data            = vif.RDATA;
          req.resp            = vif.RRESP;
          vif.RREADY          <= 0;

          `uvm_info("AXI_DRIVER", $sformatf("READ:  addr=0x%08h data=0x%08h resp=%0d", req.addr, req.data, req.resp), apb2axi_verbosity)
     endtask

endclass
