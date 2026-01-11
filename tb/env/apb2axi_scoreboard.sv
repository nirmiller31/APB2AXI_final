
class apb2axi_scoreboard extends uvm_component;

     `uvm_component_utils(apb2axi_scoreboard)

     uvm_analysis_export #(apb_seq_item)     apb_export;
     uvm_analysis_export #(axi_seq_item)     axi_export;

     uvm_tlm_analysis_fifo #(apb_seq_item)   apb_fifo;
     uvm_tlm_analysis_fifo #(axi_seq_item)   axi_fifo;

     function new(string name = "apb2axi_scoreboard", uvm_component parent = null);

          super.new(name, parent);

          apb_export                         = new("apb_export", this);
          axi_export                         = new("axi_export", this);    

          apb_fifo                           = new("apb_fifo", this);
          axi_fifo                           = new("axi_fifo", this);

     endfunction

     function void connect_phase(uvm_phase phase);

          super.connect_phase(phase);

          apb_export.connect(apb_fifo.analysis_export);
          axi_export.connect(axi_fifo.analysis_export);

     endfunction

     task run_phase(uvm_phase phase);

          apb_seq_item                       apb_tr;
          axi_seq_item                       axi_tr;

          forever begin
          
               if(apb_fifo.try_get(apb_tr)) `uvm_info("SCOREBOARD", $sformatf("APB TXN captured: %s", apb_tr.convert2string()), apb2axi_verbosity)
               if(axi_fifo.try_get(axi_tr)) `uvm_info("SCOREBOARD", $sformatf("AXI TXN captured: %s", axi_tr.convert2string()), apb2axi_verbosity)
               #1ns;
          end
     endtask

endclass
