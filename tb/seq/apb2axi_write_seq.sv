//------------------------------------------------------------------------------
// Outstanding AW issue + randomized interleaved W send (beat granularity)
//------------------------------------------------------------------------------

class apb2axi_write_seq extends apb2axi_base_seq;
     `uvm_object_utils(apb2axi_write_seq)

     localparam int unsigned NUM_TXNS_MAX = TAG_NUM;

     typedef struct {
          bit [TAG_W-1:0]        tag;
          bit [AXI_ADDR_W-1:0]   addr;
          bit [AXI_LEN_W-1:0]    len;               // beats-1
          int unsigned           beats;             // len+1
          int unsigned           total_apb_words;   // beats * APB_WORDS_PER_AXI_BEAT
          int unsigned           sent_beats;         // beats sent so far
          bit [APB_DATA_W-1:0]   apb_words[];        // [0 .. total_apb_words-1]
     } wr_txn_t;

     // Write-send order record
     typedef struct {
          int unsigned           step;
          int unsigned           txn;
          bit [TAG_W-1:0]        tag;
          int unsigned           beat;
          bit [APB_DATA_W-1:0]   w0;
          bit [APB_DATA_W-1:0]   w1;
     } wr_evt_t;

     function new(string name="apb2axi_write_seq");
          super.new(name);
     endfunction

     task automatic print_wr_order(wr_evt_t q[$]);
          `uvm_info("WR_ORDER", $sformatf("Write send-order summary: %0d beats", q.size()), UVM_LOW)
          foreach (q[i]) begin
               `uvm_info("WR_ORDER", $sformatf("step=%0d  txn=%0d  tag=%0d  beat=%0d  w0=0x%08x  w1=0x%08x", q[i].step, q[i].txn, q[i].tag, q[i].beat, q[i].w0, q[i].w1), UVM_LOW)
          end
     endtask

     task automatic compare_all_writes(wr_txn_t txns[], int unsigned num_txns);
          bit [AXI_DATA_W-1:0]     got_line;
          bit                      ok;

          bit [AXI_ADDR_W-1:0]     addr;
          bit [AXI_ADDR_W-1:0]     line_addr;

          bit mismatch;

          localparam int unsigned AXI_BYTES = (AXI_DATA_W/8);
          localparam int unsigned APB_BYTES = (APB_DATA_W/8);

          localparam int unsigned WRITE_SIZE_DEFAULT = 3;
          localparam int unsigned BYTES_PER_BEAT     = (1 << WRITE_SIZE_DEFAULT); // 8
          localparam int unsigned BITS_PER_BEAT      = BYTES_PER_BEAT * 8;        // 64

          for (int i = 0; i < num_txns; i++) begin
               // For SIZE=3 and APB=32b => 2 APB words per beat
               int unsigned apb_words_per_beat;
               apb_words_per_beat = (BYTES_PER_BEAT + APB_BYTES - 1) / APB_BYTES; // ceil (safe)

               for (int unsigned beat = 0; beat < txns[i].beats; beat++) begin
                    int unsigned byte_off;   // byte offset inside AXI line
                    int unsigned bit_off;    // bit offset inside AXI line

                    bit [BITS_PER_BEAT-1:0] exp_lane; // 64b
                    bit [BITS_PER_BEAT-1:0] got_lane; // 64b

                    addr = txns[i].addr + beat * BYTES_PER_BEAT;

                    line_addr = addr & ~(AXI_BYTES-1);

                    byte_off  = addr[$clog2(AXI_BYTES)-1:0];
                    bit_off   = byte_off * 8;

                    exp_lane = '0;
                    for (int unsigned b = 0; b < BYTES_PER_BEAT; b++) begin
                         int unsigned apb_word_idx;
                         int unsigned byte_in_apb;
                         bit [7:0]    byt;

                         apb_word_idx = beat * apb_words_per_beat + (b / APB_BYTES);
                         byte_in_apb  = b % APB_BYTES;

                         byt = txns[i].apb_words[apb_word_idx][8*byte_in_apb +: 8];
                         exp_lane[8*b +: 8] = byt;
                    end

                    peek_axi_word64(line_addr, got_line, ok);
                    if (!ok)
                         `uvm_fatal("WR_CMP", $sformatf("Backdoor peek failed line_addr=0x%0h (orig addr=0x%0h)", line_addr, addr))

                    got_lane = '0;
                    for (int unsigned b = 0; b < BYTES_PER_BEAT; b++) begin
                         got_lane[8*b +: 8] = got_line[bit_off + 8*b +: 8];
                    end

                    mismatch = 1'b0;
                    for (int unsigned b = 0; b < BYTES_PER_BEAT; b++) begin
                         if (got_lane[8*b +: 8] !== exp_lane[8*b +: 8])
                              mismatch = 1'b1;
                    end

                    if (mismatch) begin
                         `uvm_error("WR_CMP", $sformatf(
                              "MISMATCH TXN=%0d TAG=%0d BEAT=%0d addr=0x%0h line_addr=0x%0h byte_off=%0d exp=0x%016h got=0x%016h got_line=0x%0h",
                              i, txns[i].tag, beat, addr, line_addr, byte_off,
                              exp_lane, got_lane, got_line
                         ))
                    end else begin
                         `uvm_info("WR_CMP", $sformatf(
                              "MATCH TXN=%0d TAG=%0d BEAT=%0d addr=0x%0h lane=0x%016h (line_addr=0x%0h off=%0d)",
                              i, txns[i].tag, beat, addr, got_lane, line_addr, byte_off
                         ), UVM_NONE)
                    end
               end
          end
     endtask

     virtual task body();
          uvm_phase phase;

          int                      num_txns;
          wr_txn_t                 txns[NUM_TXNS_MAX];

          int                      eligible[$];
          int                      pick_i;

          int                      global_step;

          // completion/status locals (for early error visibility if you want)
          bit                      done, error;
          bit [1:0]                resp;
          bit [7:0]                num_beats_hw;

          // order log
          wr_evt_t                 wr_q[$];

          // per-beat send
          bit [APB_DATA_W-1:0]     beat_words[APB_WORDS_PER_AXI_BEAT];
          int                      wbase;

          bit [AXI_ADDR_W-1:0]     addrs[NUM_TXNS_MAX];
          int unsigned             bytes[NUM_TXNS_MAX];

          phase = get_starting_phase();
          if (phase != null) phase.raise_objection(this);

          num_txns    = $urandom_range(1, NUM_TXNS_MAX);
          global_step = 0;

          `uvm_info("WR_SEQ", $sformatf("Start WRITE outstanding+interleaved : num_txns=%0d", num_txns), UVM_NONE)

          // -----------------------------------------
          // 1) Plan txns (addr/len/data)
          // -----------------------------------------
          for (int i = 0; i < num_txns; i++) begin
               txns[i].tag            = i[TAG_W-1:0];
               txns[i].len            = $urandom_range(0, MAX_BEATS_NUM-2);
               txns[i].addr           = pick_non_overlapping_addr(i , txns[i].len, addrs, bytes);
               txns[i].beats          = axi_beats_from_len(txns[i].len);
               txns[i].total_apb_words= txns[i].beats * apb_words_per_axi_beat();
               txns[i].sent_beats     = 0;

               txns[i].apb_words      = new[txns[i].total_apb_words];

               foreach (txns[i].apb_words[j]) begin
                    txns[i].apb_words[j] = (32'hCAFE_0000 ^ (i << 8) ^ j) + $urandom();
                    // txns[i].apb_words[j] = 32'hFFFF_FFFF;
               end

               `uvm_info("WR_SEQ", $sformatf("PLAN: TXN=%0d TAG=%0d ADDR=0x%0h LEN=%0d (beats=%0d apb_words=%0d)", i, txns[i].tag, txns[i].addr, txns[i].len, txns[i].beats, txns[i].total_apb_words), UVM_NONE)
          end

          // -----------------------------------------
          // 2) Issue all AW first (no W yet)
          // -----------------------------------------
          for (int i = 0; i < num_txns; i++) begin
               `uvm_info("WR_AW", $sformatf("ISSUE_AW: TXN=%0d TAG=%0d ADDR=0x%0h LEN=%0d", i, txns[i].tag, txns[i].addr, txns[i].len), UVM_NONE)
               program_write_cmd(txns[i].len);
               program_addr(txns[i].addr);
          end

          // Let them queue
          #(200);

          // -----------------------------------------
          // 3) Randomized interleaved W send (BEAT granularity)
          // -----------------------------------------
          while (1) begin
               eligible.delete();

               for (int i = 0; i < num_txns; i++) begin
                    if (txns[i].sent_beats < txns[i].beats)
                         eligible.push_back(i);
               end

               if (eligible.size() == 0)
                    break;

               pick_i = eligible[$urandom_range(0, eligible.size()-1)];

               read_status(txns[pick_i].tag, done, error, resp, num_beats_hw);
               if (error) begin
                    print_wr_order(wr_q);
                    `uvm_fatal("WR_SEQ", $sformatf("TAG %0d ERROR while sending W resp=%0d", txns[pick_i].tag, resp))
               end

               wbase = txns[pick_i].sent_beats * APB_WORDS_PER_AXI_BEAT;
               for (int k = 0; k < APB_WORDS_PER_AXI_BEAT; k++) begin
                    beat_words[k] = txns[pick_i].apb_words[wbase + k];
               end

               // Log order (assumes AXI_DATA_W=64 so APB_WORDS_PER_AXI_BEAT=2)
               wr_q.push_back('{
                    step : global_step,
                    txn  : pick_i,
                    tag  : txns[pick_i].tag,
                    beat : txns[pick_i].sent_beats,
                    w0   : beat_words[0],
                    w1   : beat_words[1]
               });

               `uvm_info("WR_SEND", $sformatf("SEND_W step=%0d TXN=%0d TAG=%0d beat=%0d/%0d w0=0x%08x w1=0x%08x", global_step, pick_i, txns[pick_i].tag, txns[pick_i].sent_beats, txns[pick_i].beats-1, beat_words[0], beat_words[1]), UVM_NONE)

               // Send one beat to this TAG
               push_wr_beat(txns[pick_i].tag, beat_words);

               txns[pick_i].sent_beats++;
               global_step++;

               #($urandom_range(10, 120));
          end

          // Print order at end
          print_wr_order(wr_q);

          // -----------------------------------------
          // 4) Completion per tag
          // -----------------------------------------
          for (int i = 0; i < int'(num_txns); i++) begin
               wait_completion(txns[i].tag, 800);
               `uvm_info("WR_SEQ", $sformatf("TAG %0d completed OK (sent_beats=%0d/%0d)", txns[i].tag, txns[i].sent_beats, txns[i].beats), UVM_LOW)
          end

		// -----------------------------------------
		// 5) Compare (backdoor) after completion
		// -----------------------------------------
		compare_all_writes(txns, num_txns);          // FIXME last write takes place, track it somehow if we want

          `uvm_info("WR_SEQ", "Outstanding + interleaved WRITE test PASSED", UVM_MEDIUM)

          if (phase != null) phase.drop_objection(this);
     endtask

endclass