

class apb2axi_env extends uvm_env;

     `uvm_component_utils(apb2axi_env)

     uvm_tlm_analysis_fifo #(axi_seq_item) axi_mon_fifo;

     apb_agent                apb_ag;
     axi_agent                axi_ag;
     axi3_slave_bfm           axi_bfm;
     apb2axi_scoreboard       sb;

     virtual apb_if apb_vif;
     virtual axi_if axi_vif;

     function new(string name = "apb2axi_env", uvm_component parent = null);
          super.new(name, parent);
     endfunction

     function void build_phase(uvm_phase phase);
          super.build_phase(phase);

          axi_mon_fifo = new("axi_mon_fifo", this);

          // Get interfaces
          if (!uvm_config_db#(virtual apb_if)::get(this, "", "apb_vif", apb_vif)) `uvm_fatal("ENV", "No apb_vif found in config_db")
          if (!uvm_config_db#(virtual axi_if)::get(this, "", "axi_vif", axi_vif)) `uvm_fatal("ENV", "No axi_vif found in config_db")

          // Ensure agent is active
          uvm_config_db#(uvm_active_passive_enum)::set(this, "apb_ag", "is_active", UVM_ACTIVE);

          // Create components
          apb_ag    = apb_agent         ::type_id::create("apb_ag", this);
          axi_ag    = axi_agent         ::type_id::create("axi_ag", this);
          axi_bfm   = axi3_slave_bfm    ::type_id::create("axi_bfm", this);
          sb        = apb2axi_scoreboard::type_id::create("sb", this);

          // Propagate virtual interfaces
          uvm_config_db#(virtual apb_if)::set(this, "apb_ag",  "apb_vif", apb_vif);
          uvm_config_db#(virtual axi_if)::set(this, "axi_ag",  "axi_vif", axi_vif);
          uvm_config_db#(virtual axi_if)::set(this, "axi_bfm", "axi_vif", axi_vif);
          uvm_config_db#(axi3_slave_bfm)::set(uvm_root::get(), "*", "axi_bfm_h", axi_bfm);

          `uvm_info("ENV", "APB2AXI Environment built successfully.", apb2axi_verbosity)

     endfunction

     function void connect_phase(uvm_phase phase);

          super.connect_phase(phase);

          // Connect monitors to scoreboard
          apb_ag.apb_mon.ap.connect(sb.apb_export);
          axi_ag.axi_mon.ap.connect(sb.axi_export);

          axi_ag.axi_mon.ap.connect(axi_mon_fifo.analysis_export);

          `uvm_info("ENV", "Scoreboard connections established.", apb2axi_verbosity)

     endfunction

endclass
