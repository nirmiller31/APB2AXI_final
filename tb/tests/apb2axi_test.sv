
//------------------------------------------------------------------------------
// File          : apb2axi_test.sv
// Project       : APB2AXI
// Description   : Capability Test
//------------------------------------------------------------------------------

class apb2axi_test extends apb2axi_base_test;
    `uvm_component_utils(apb2axi_test)

     function new(string name = "apb2axi_test",
                    uvm_component parent = null);
          super.new(name, parent);
     endfunction

     task run_phase(uvm_phase phase);
          string                             seq_sel;

          apb2axi_read_seq                   rd_seq;
          apb2axi_write_seq                  wr_seq;
          apb2axi_e2e_seq                    e2e_seq;
          apb2axi_read_error_seq             rd_err_seq;
          apb2axi_write_error_seq            wr_err_seq;

          phase.raise_objection(this);

          // Default = READ read if plusarg not given
          if (!$value$plusargs("APB2AXI_SEQ=%s", seq_sel)) seq_sel = "READ";

          `uvm_info("APB2AXI_TEST", $sformatf("Starting test, seq_sel=%s", seq_sel), UVM_NONE)

          if (seq_sel.tolower() == "read") begin
               `uvm_info("APB2AXI_TEST", "Running [READ] sequence", UVM_NONE)
               rd_seq                   = apb2axi_read_seq::type_id::create("rd_seq");
               rd_seq.m_env             = env;
               rd_seq.start(env.apb_ag.apb_seqr);
          end
          else if (seq_sel.tolower() == "write") begin
               `uvm_info("APB2AXI_TEST", "Running [WRITE] sequence", UVM_NONE)
               wr_seq                   = apb2axi_write_seq::type_id::create("wr_seq");
               wr_seq.m_env             = env;
               wr_seq.start(env.apb_ag.apb_seqr);
          end
          else if (seq_sel.tolower() == "e2e") begin
               `uvm_info("APB2AXI_TEST", "Running [End-to-End] sequence", UVM_NONE)
               e2e_seq                  = apb2axi_e2e_seq::type_id::create("e2e_seq");
               e2e_seq.m_env            = env;
               e2e_seq.start(env.apb_ag.apb_seqr);
          end
          else if (seq_sel.tolower() == "read_error") begin
               `uvm_info("APB2AXI_TEST", "Running [READ ERROR] sequence", UVM_NONE)
               rd_err_seq               = apb2axi_read_error_seq::type_id::create("rd_err_seq");
               rd_err_seq.m_env         = env;
               rd_err_seq.start(env.apb_ag.apb_seqr);
          end
          else if (seq_sel.tolower() == "write_error") begin
               `uvm_info("APB2AXI_TEST", "Running [WRITE ERROR] sequence", UVM_NONE)
               wr_err_seq               = apb2axi_write_error_seq::type_id::create("wr_err_seq");
               wr_err_seq.m_env         = env;
               wr_err_seq.start(env.apb_ag.apb_seqr);
          end

          `uvm_info("APB2AXI_TEST", $sformatf("%s sequence finished", seq_sel), UVM_NONE)

          phase.drop_objection(this);
          
     endtask
endclass