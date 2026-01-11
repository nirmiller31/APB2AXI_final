
class apb_monitor extends uvm_monitor;

     `uvm_component_utils(apb_monitor)

     // Observes transactions for:
     uvm_analysis_port #(apb_seq_item)     ap;

     virtual apb_if                        vif;

     function new(string name = "apb_monitor", uvm_component parent=null);
          super.new(name, parent);
          ap                                = new("ap", this);
     endfunction

     function void build_phase(uvm_phase phase);
          
          super.build_phase(phase);
          if (!uvm_config_db#(virtual apb_if)::get(this, "", "apb_vif", vif)) `uvm_fatal("APB_MONITOR", "No virtual interface bound to apb_monitor")

     endfunction

     task run_phase(uvm_phase phase);

          apb_seq_item                       tr;

          // Wait for reset release
          wait (vif.PRESETn === 1'b1);
          @(posedge vif.PCLK);

          forever begin
               @(posedge vif.PCLK);
               // Check for valid access phase
               if (vif.PSEL && vif.PENABLE && vif.PREADY) begin
                    `uvm_info("APB_MONITOR", $sformatf("%t [APB_MON] WRITE addr=%0h write=%0b data=%0h", $time, vif.PADDR, vif.PWRITE, vif.PWRITE ? vif.PWDATA : vif.PRDATA), apb2axi_verbosity)
                    tr                       = apb_seq_item::type_id::create("tr", this);
                    tr.addr                  = vif.PADDR;
                    tr.write                 = vif.PWRITE;
                    tr.data                  = vif.PWRITE ? vif.PWDATA : vif.PRDATA;
                    tr.slverr                = vif.PSLVERR;
                    `uvm_info("APB_MONITOR", $sformatf("Observed %s", tr.convert2string()), apb2axi_verbosity)
                    ap.write(tr);
               end
          end
     endtask


endclass
