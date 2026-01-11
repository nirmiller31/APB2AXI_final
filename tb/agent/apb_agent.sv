
class apb_agent extends uvm_agent;

     `uvm_component_utils(apb_agent)

     apb_driver                         apb_drv;
     apb_monitor                        apb_mon;
     apb_sequencer                      apb_seqr;

     virtual apb_if                     vif;

     function new(string name = "apb_agent", uvm_component parent=null);
          super.new(name, parent);
     endfunction

     function void build_phase(uvm_phase phase);

          super.build_phase(phase);
          if (!uvm_config_db#(virtual apb_if)::get(this, "", "apb_vif", vif)) `uvm_fatal("APB_AGENT", "No virtual interface bound to apb_agent")

          apb_drv                        = apb_driver     ::type_id::create("apb_drv", this);
          apb_mon                        = apb_monitor    ::type_id::create("apb_mon", this);
          apb_seqr                       = apb_sequencer  ::type_id::create("apb_seqr", this);

          uvm_config_db#(virtual apb_if)::set(this, "apb_drv", "apb_vif", vif);
          uvm_config_db#(virtual apb_if)::set(this, "apb_mon", "apb_vif", vif);

          `uvm_info("APB_AGENT", $sformatf("Sequencer path = %s", apb_seqr.get_full_name()), apb2axi_verbosity)

     endfunction

     function void connect_phase(uvm_phase phase);

          super.connect_phase(phase);
          apb_drv.seq_item_port.connect(apb_seqr.seq_item_export);

     endfunction

endclass
