
//------------------------------------------------------------------------------
// File          : apb2axi_bringup_test.sv
// Project       : APB2AXI
// Description   : Minimal directed UVM test for bring-up
//------------------------------------------------------------------------------

class apb2axi_bringup_test extends apb2axi_base_test;
    `uvm_component_utils(apb2axi_bringup_test)

     function new(string name = "apb2axi_bringup_test",
                    uvm_component parent = null);
          super.new(name, parent);
     endfunction

     task run_phase(uvm_phase phase);
          string                             seq_sel;
          apb2axi_bringup_seq                bringup_seq;
          apb2axi_read_bringup_seq           rd_bringup_seq;
          apb2axi_multiple_beat_read_seq     mb_rd_bringup_seq;
          apb2axi_read_drain_seq             rd_drain_bringup_seq;
          apb2axi_multiple_read_drain_seq    multiple_rd_drain_bringup_seq;
          apb2axi_reconsume_same_tag_seq     reconsume_same_tag_seq;
          apb2axi_window_seq                 window_seq;
          apb2axi_random_drain_seq           random_drain_seq;
          apb2axi_stress_seq                 stress_seq;
          apb2axi_wr_sanity_seq              wr_sanity;
          apb2axi_mul_wr_seq                 mul_wr;

          phase.raise_objection(this);

          // Default = BRINGUP bringup if plusarg not given
          if (!$value$plusargs("APB2AXI_SEQ=%s", seq_sel)) seq_sel = "BRINGUP";

          `uvm_info("BRINGUP_TEST", $sformatf("Starting bring-up test, seq_sel=%s", seq_sel), apb2axi_verbosity)

          if (seq_sel.tolower() == "read") begin
               `uvm_info("BRINGUP_TEST", "Running READ bringup sequence", apb2axi_verbosity)
               rd_bringup_seq         = apb2axi_read_bringup_seq::type_id::create("rd_seq");
               rd_bringup_seq.m_env   = env;
               rd_bringup_seq.start(env.apb_ag.apb_seqr);
          end
          else if (seq_sel.tolower() == "mulread") begin
               `uvm_info("BRINGUP_TEST", "Running MULTIPLE BEAT READ bringup sequence", apb2axi_verbosity)
               mb_rd_bringup_seq         = apb2axi_multiple_beat_read_seq::type_id::create("mulread_seq");
               mb_rd_bringup_seq.m_env   = env;
               mb_rd_bringup_seq.start(env.apb_ag.apb_seqr);
          end
          else if (seq_sel.tolower() == "readdrain") begin
               `uvm_info("BRINGUP_TEST", "Running READ DRAIN bringup sequence", apb2axi_verbosity)
               rd_drain_bringup_seq         = apb2axi_read_drain_seq::type_id::create("read_drain_seq");
               rd_drain_bringup_seq.m_env   = env;
               rd_drain_bringup_seq.start(env.apb_ag.apb_seqr);
          end
          else if (seq_sel.tolower() == "mul_read_drain") begin
               `uvm_info("BRINGUP_TEST", "Running MULTIPLE READ DRAIN bringup sequence", apb2axi_verbosity)
               multiple_rd_drain_bringup_seq         = apb2axi_multiple_read_drain_seq::type_id::create("mul_read_drain_seq");
               multiple_rd_drain_bringup_seq.m_env   = env;
               multiple_rd_drain_bringup_seq.start(env.apb_ag.apb_seqr);
          end
          else if (seq_sel.tolower() == "recon") begin
               `uvm_info("BRINGUP_TEST", "Running CONSUME bringup sequence", apb2axi_verbosity)
               reconsume_same_tag_seq         = apb2axi_reconsume_same_tag_seq::type_id::create("reconsime_seq");
               reconsume_same_tag_seq.m_env   = env;
               reconsume_same_tag_seq.start(env.apb_ag.apb_seqr);
          end    
          else if (seq_sel.tolower() == "window") begin
               `uvm_info("BRINGUP_TEST", "Running WINDOW bringup sequence", apb2axi_verbosity)
               window_seq         = apb2axi_window_seq::type_id::create("window_seq");
               window_seq.m_env   = env;
               window_seq.start(env.apb_ag.apb_seqr);
          end       
          else if (seq_sel.tolower() == "random_drain") begin
               `uvm_info("BRINGUP_TEST", "Running RANDOM_DRAIN bringup sequence", apb2axi_verbosity)
               random_drain_seq         = apb2axi_random_drain_seq::type_id::create("random_drain_seq");
               random_drain_seq.m_env   = env;
               random_drain_seq.start(env.apb_ag.apb_seqr);
          end     
          else if (seq_sel.tolower() == "stress") begin
               `uvm_info("BRINGUP_TEST", "Running STRSS bringup sequence", apb2axi_verbosity)
               stress_seq         = apb2axi_stress_seq::type_id::create("stress_seq");
               stress_seq.m_env   = env;
               stress_seq.start(env.apb_ag.apb_seqr);
          end
          else if (seq_sel.tolower() == "write") begin
               `uvm_info("BRINGUP_TEST", "Running WRITE Sanity bringup sequence", apb2axi_verbosity)
               wr_sanity         = apb2axi_wr_sanity_seq::type_id::create("wr_sanity");
               wr_sanity.m_env   = env;
               wr_sanity.start(env.apb_ag.apb_seqr);
          end  
          else if (seq_sel.tolower() == "mul_wr") begin
               `uvm_info("BRINGUP_TEST", "Running MUL_WR Sanity bringup sequence", apb2axi_verbosity)
               mul_wr         = apb2axi_mul_wr_seq::type_id::create("mul_wr");
               mul_wr.m_env   = env;
               mul_wr.start(env.apb_ag.apb_seqr);
          end  
          else begin
               `uvm_info("BRINGUP_TEST", "Running (original) bringup sequence", apb2axi_verbosity)
               bringup_seq      = apb2axi_bringup_seq::type_id::create("wr_seq");
               bringup_seq.m_env = env;
               bringup_seq.start(env.apb_ag.apb_seqr);
          end

          `uvm_info("BRINGUP_TEST", "Bring-up sequence finished", apb2axi_verbosity)

          phase.drop_objection(this);
          
     endtask
endclass