class apb_driver extends uvm_driver #(apb_seq_item);

    `uvm_component_utils(apb_driver)

    virtual apb_if vif;

    function new(string name = "apb_drv", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);

        super.build_phase(phase);
        if (!uvm_config_db#(virtual apb_if)::get(this, "", "apb_vif", vif)) `uvm_fatal("APB_DRIVER", "No virtual interface bound to apb_driver")

    endfunction

    task run_phase(uvm_phase phase);
        apb_seq_item req;

        `uvm_info("APB_DRIVER","Entering run_phase() loop", apb2axi_verbosity)

        forever begin
            fork
                begin
                    seq_item_port.get_next_item(req);
                    `uvm_info("APB_DRIVER",
                            $sformatf("Got item addr=0x%0h", req.addr),
                            apb2axi_verbosity)
                    drive_apb(req);
                    seq_item_port.item_done();
                end

                // begin
                //     #100us; // sim-time watchdog
                //     `uvm_fatal("APB_DRIVER", "Timeout waiting on get_next_item / handshake");
                // end
            join_any
            disable fork;
        end
    endtask


    task drive_apb(apb_seq_item req);

        @(posedge vif.PCLK);
        wait (vif.PRESETn);

        req.slverr = 1'b0;
        
        // SETUP Phase
        vif.PSEL    <= 1;
        vif.PENABLE <= 0;
        vif.PADDR   <= req.addr;
        vif.PWRITE  <= req.write;
        vif.PWDATA  <= req.data;

        // ACCESS Phase
        @(posedge vif.PCLK);
        vif.PENABLE <= 1;

        // Wait for PREADY
        do @(posedge vif.PCLK); 
        while (!vif.PREADY);

        req.slverr = vif.PSLVERR;
        if (req.slverr) begin
            `uvm_info("APB_DRIVER", $sformatf("APB SLVERR @0x%0h (write=%0b)", req.addr, req.write), apb2axi_verbosity)
        end

        // READ: sample PRDATA IN THE SAME CYCLE
        if (!req.write) begin
            req.data = vif.PRDATA;
            `uvm_info("APB_DRIVER", $sformatf("APB READ @0x%0h = 0x%0h", req.addr, req.data), apb2axi_verbosity)
        end

        // IDLE Phase
        vif.PSEL    <= 0;
        vif.PENABLE <= 0;
        vif.PWRITE  <= 0;

        repeat($urandom_range(0,20)) @(posedge vif.PCLK);

    endtask

endclass
