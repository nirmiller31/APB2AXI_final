
class apb2axi_multiple_beat_read_seq extends apb2axi_base_seq;
     `uvm_object_utils(apb2axi_multiple_beat_read_seq)

     rand bit [31:0] addr_lo = 32'h0000_1000;
     rand byte       len     = 3;       // 3 → 4 beats
     rand bit [2:0]  size    = 3'b011;  // 8 bytes/beat

     function new(string name="apb2axi_multiple_beat_read_seq"); super.new(name); endfunction

     task body();
          // 1) ADDR_HI
          apb_write(32'h04, 32'h0000_0000);

          // 2) CMD (read)
          apb_write(32'h08, pack_cmd(1'b0, size, len));

          // 3) ADDR_LO → fires commit_pulse
          apb_write(32'h00, addr_lo);

          `uvm_info("MB_SEQ", $sformatf("Issued read: addr=%h len=%0d (beats=%0d) size=%0d", addr_lo, len, len+1, size), UVM_MEDIUM)

          // Optionally store expected len in config_db for scoreboard
          uvm_config_db#(byte)::set(null, "*", "exp_len", len);
     endtask

     task apb_write(bit [31:0] addr, bit [31:0] data);
          apb_seq_item req = apb_seq_item::type_id::create("req");
          req.write = 1;
          req.addr  = addr;
          req.data  = data;
          start_item(req); 
          finish_item(req);
     endtask

     function bit [31:0] pack_cmd(bit is_write, bit [2:0] size, byte len);
          pack_cmd = {20'h0, len[7:0], size[2:0], is_write};
     endfunction

endclass