
class apb2axi_base_test extends uvm_test;

    `uvm_component_utils(apb2axi_base_test)

    apb2axi_env                   env;

    function new(string name = "apb2axi_base_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        apb2axi_tb_pkg::apb2axi_configure_verbosity();
        uvm_top.set_timeout(10ms, 1);
        env                    = apb2axi_env::type_id::create("env", this);
        uvm_top.print_topology();
    endfunction

task run_phase(uvm_phase phase);
    
    apb2axi_base_seq main_seq;

    `uvm_info("BASE_TEST", $sformatf("Sequencer handle in test = %s", env.apb_ag.apb_seqr.get_full_name()), apb2axi_verbosity)

    if (env.apb_ag.apb_drv.seq_item_port != null)
        `uvm_info("BASE_TEST", "Driver seq_item_port handle is valid (UVM-1.2 safe check).", apb2axi_verbosity)
    else
        `uvm_error("BASE_TEST", "Driver seq_item_port handle is NULL!")

    phase.raise_objection(this);
    `uvm_info("BASE_TEST", "Starting APB2AXI main sequence...", apb2axi_verbosity)

    main_seq = apb2axi_base_seq::type_id::create("main_seq");
    main_seq.start(env.apb_ag.apb_seqr);

    `uvm_info("BASE_TEST", "Main sequence finished, dropping objection.", apb2axi_verbosity)
    phase.drop_objection(this);

endtask


endclass  