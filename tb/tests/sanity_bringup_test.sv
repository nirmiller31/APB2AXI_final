
class sanity_bringup_test extends uvm_test;
     `uvm_component_utils(sanity_bringup_test)

     apb2axi_env              env;

     function new(string name = "sanity_bringup_test", uvm_component parent = null);
          super.new(name, parent);
     endfunction

     function void build_phase(uvm_phase phase);
          super.build_phase(phase);
          uvm_root::get().set_timeout(50us, 1);
          env                 = apb2axi_env::type_id::create("env", this);
     endfunction

     task run_phase(uvm_phase phase);
          phase.raise_objection(this);
          `uvm_info("BASE_TEST", "UVM Environment bring-up test running...", apb2axi_verbosity)

          // wait some cycles to let components print activity
          #500ns;

          phase.drop_objection(this);
     endtask
endclass