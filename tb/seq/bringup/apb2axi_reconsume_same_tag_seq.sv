// tb/seq/apb2axi_reconsume_same_tag_seq.sv

class apb2axi_reconsume_same_tag_seq extends apb2axi_base_seq;
     `uvm_object_utils(apb2axi_reconsume_same_tag_seq)

     // Must match your reg map
     localparam ADDR_LO_ADDR    = 32'h0000_0000;
     localparam ADDR_HI_ADDR    = 32'h0000_0004;
     localparam CMD_ADDR        = 32'h0000_0008;
     localparam RD_STATUS_ADDR  = 32'h0000_000C;
     localparam RD_DATA_ADDR    = 32'h0000_0010;
     localparam TAG_SEL_ADDR    = 32'h0000_0014;

     function new(string name = "apb2axi_reconsume_same_tag_seq");
          super.new(name);
     endfunction

     task body();
          bit [31:0] status, data;
          bit [7:0]  beats;
          bit [3:0]  tag;
          int total_words;
          const int WORDS_PER_BEAT = AXI_DATA_W / APB_DATA_W;

          `uvm_info(get_type_name(), "Starting re-consume-same-tag test", UVM_MEDIUM)

          //--------------------------------------------------
          // 1) Issue a single READ (same encoding as logs)
          //--------------------------------------------------
          // size=3 (8B), len=5 → 0x00000305
          apb_write(CMD_ADDR,     32'h0000_0305);
          apb_write(ADDR_HI_ADDR, 32'h0000_0000);
          apb_write(ADDR_LO_ADDR, 32'h0000_1480); // commit_pulse

          //--------------------------------------------------
          // 2) Wait for completion: RD_STATUS.valid==1
          //--------------------------------------------------
          do begin
          apb_read(RD_STATUS_ADDR, status);
          end while (!status[15]);

          tag   = status[3:0];
          beats = status[11:4];

          total_words = ((beats == 1) ? 1 : (beats + 1)) * WORDS_PER_BEAT;

          `uvm_info(get_type_name(),
                    $sformatf("First completion: tag=%0d beats=%0d status=0x%08x",
                              tag, beats, status),
                    UVM_MEDIUM)

          //--------------------------------------------------
          // 3) First legitimate drain of this TAG
          //--------------------------------------------------
          apb_write(TAG_SEL_ADDR, {28'h0, tag});      // TAG_TO_CONSUME
          apb_read (RD_STATUS_ADDR, status);          // arm REG FSM

          for (int i = 0; i < total_words; i++) begin
          apb_read(RD_DATA_ADDR, data);
          `uvm_info(get_type_name(),
                    $sformatf("First drain tag=%0d beat=%0d data=%08x",
                              tag, i, data),
                    UVM_MEDIUM)
          end

          //--------------------------------------------------
          // 4) Try to consume the SAME TAG again
          //--------------------------------------------------
          apb_write(TAG_SEL_ADDR, {28'h0, tag});
          apb_read (RD_STATUS_ADDR, status);

          `uvm_info(get_type_name(),
                    $sformatf("Second RD_STATUS for same tag=%0d : 0x%08x (beats=%0d, done=%0b)",
                              tag, status, status[11:4], status[15]),
                    UVM_MEDIUM)

          for (int i = 0; i < beats; i++) begin
          apb_read(RD_DATA_ADDR, data);
          `uvm_info(get_type_name(),
                    $sformatf("Second drain attempt tag=%0d beat=%0d data=%08x",
                              tag, i, data),
                    UVM_MEDIUM)
          end

          `uvm_info(get_type_name(), "Finished re-consume-same-tag test", UVM_MEDIUM)
     endtask

endclass