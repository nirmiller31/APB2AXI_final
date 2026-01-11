class apb2axi_read_drain_seq extends apb2axi_base_seq;
     `uvm_object_utils(apb2axi_read_drain_seq)

     import apb2axi_memory_pkg::*;

     localparam int REG_ADDR_LO   = 'h00;
     localparam int REG_ADDR_HI   = 'h04;
     localparam int REG_CMD       = 'h08;
     localparam int REG_RD_STATUS = 'h0C;
     localparam int REG_RD_DATA   = 'h10;

     // Config
     rand bit [63:0]          cfg_addr;
     rand bit [7:0]           cfg_len;
     rand bit [2:0]           cfg_size;
     rand bit                 cfg_check;   // enable data checking

     bit [APB_DATA_W-1:0] data_q[$];

     function new(string name = "apb2axi_read_drain_seq");
          super.new(name);
          cfg_addr  = 64'h0000000000001680;
          cfg_len   = 8'd6;      // beats-1 (so 7 beats)
          cfg_size  = 3'd0;
          cfg_check = 1'b1;
     endfunction

     // Expected pattern – ADAPT to your BFM!
     function automatic bit [APB_DATA_W-1:0] expected_clc_data(int word_idx);
          const int WORDS_PER_BEAT = AXI_DATA_W / APB_DATA_W; // 2 for 64→32
          int unsigned base_idx;
          int unsigned axi_idx;
          int unsigned word_in_beat;
          mem_word_t   beat;

          // Same index computation as do_read()
          base_idx     = addr2idx(cfg_addr);
          axi_idx      = base_idx + (word_idx / WORDS_PER_BEAT);
          word_in_beat = word_idx % WORDS_PER_BEAT;

          if (axi_idx >= MEM_WORDS)
               return '0;

          beat = MEM[axi_idx];

          // Little-endian slicing, same as your handler:
          case (word_in_beat)
               0: return beat[31:0];     // first APB word
               1: return beat[63:32];    // second APB word
               default: return '0;
          endcase
     endfunction

     virtual task body();
          apb_seq_item req;
          bit [APB_DATA_W-1:0] status;
          bit         valid, err;
          bit [1:0]   resp;
          int unsigned num_beats;
          int unsigned tag;

          // 1) Program registers and commit
          // ADDR_HI
          req = apb_seq_item::type_id::create("wr_addr_hi");
          req.addr  = REG_ADDR_HI;
          req.write = 1;
          req.data  = cfg_addr[63:32];
          start_item(req); finish_item(req);

          // CMD
          req = apb_seq_item::type_id::create("wr_cmd");
          req.addr  = REG_CMD;
          req.write = 1;
          req.data  = {1'b0, 21'd0, cfg_size, cfg_len};
          start_item(req); finish_item(req);

          // ADDR_LO (commit)
          req = apb_seq_item::type_id::create("wr_addr_lo");
          req.addr  = REG_ADDR_LO;
          req.write = 1;
          req.data  = cfg_addr[31:0];
          start_item(req); finish_item(req);

          `uvm_info(get_type_name(),
                    $sformatf("Issued READ: addr=0x%016h len=%0d size=%0d",
                              cfg_addr, cfg_len, cfg_size),
                    apb2axi_verbosity)

          #1000ns;

          // set_tag_to_consume(0);

          // 2) Poll RD_STATUS until valid
          do begin
          // repeat (10) begin
               req = apb_seq_item::type_id::create("rd_status");
               req.addr  = REG_RD_STATUS;
               req.write = 0;
               start_item(req); 
               finish_item(req);
               status = req.data;

               // valid     = status[31];
               // err       = status[30];
               // resp      = status[29:28];
               // num_beats = status[27:20];
               // tag       = status[19:16];
               valid     = status[15];
               err       = status[14];
               resp      = status[13:12];
               num_beats = status[11:4];
               tag       = status[3:0];

               `uvm_info(get_type_name(),
                    $sformatf("I polled: valid=%b err=%0b resp=%0d tag=%0d beats=%0d",
                              valid, err, resp, tag, num_beats),
                    apb2axi_verbosity)
          // end
          end while (!valid);

          `uvm_info(get_type_name(),
                    $sformatf("RD_STATUS: valid=1 err=%0b resp=%0d tag=%0d beats=%0d",
                              err, resp, tag, num_beats),
                    apb2axi_verbosity)

          // 3) Drain RD_DATA + CHECK
          for (int i = 0; i < num_beats+1; i++) begin
               req = apb_seq_item::type_id::create($sformatf("rd_data_%0d", i));
               req.addr  = REG_RD_DATA;
               req.write = 0;
               start_item(req);
               finish_item(req);

               data_q.push_back(req.data);

               if (cfg_check) begin
               bit [APB_DATA_W-1:0] exp = expected_clc_data(i);
                    if (req.data !== exp) begin
                         `uvm_error(get_type_name(),
                                   $sformatf("DATA MISMATCH beat %0d: got 0x%08h expected 0x%08h",
                                             i, req.data, exp))
                    end else begin
                         `uvm_info(get_type_name(),
                                   $sformatf("Beat %0d OK: 0x%08h", i, req.data),
                                   UVM_LOW)
                    end
               end
          end

          // 4) ACK completion to directory
          req = apb_seq_item::type_id::create("rd_status_ack");
          req.addr  = REG_RD_STATUS;
          req.write = 1;
          req.data  = 'h1;
          start_item(req); 
          finish_item(req);
     endtask

endclass