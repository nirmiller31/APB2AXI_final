//------------------------------------------------------------------------------
// tb/seq/apb2axi_e2e_seq.sv
//
// FULL END-TO-END APB→AXI STRESS SEQUENCE
//
// 1) Program TAG_NUM write transactions (non-overlapping)
// 2) Interleaved outstanding W beats
// 3) Verify writes via AXI backdoor
// 4) Verify completions
// 5) Program TAG_NUM read transactions
// 6) Delayed, interleaved APB-word drain
// 7) Compare drained data to original writes
//
// Deterministic, no tag reuse, no BFM get(), no magic.
//------------------------------------------------------------------------------

class apb2axi_e2e_seq extends apb2axi_base_seq;
     `uvm_object_utils(apb2axi_e2e_seq)

     localparam int unsigned NUM_TXNS = TAG_NUM;

     typedef struct {
          bit [TAG_W-1:0]        tag;
          bit [AXI_ADDR_W-1:0]   addr;
          bit [AXI_LEN_W-1:0]    len;
          int unsigned           beats;
          bit [APB_DATA_W-1:0]   apb_words[];
     } txn_t;

     txn_t txns[NUM_TXNS];

     function new(string name="apb2axi_e2e_seq");
          super.new(name);
     endfunction

     // ------------------------------------------------------------
     // Expected read model (from written data)
     // ------------------------------------------------------------
     function automatic bit [APB_DATA_W-1:0]
     expected_word(txn_t t, int unsigned word_idx);
          return t.apb_words[word_idx];
     endfunction

     virtual task body();
          uvm_phase phase;
          int eligible[$];
          int pick;
          int step;
          bit done, error;
          bit [1:0] resp;
          bit [7:0] num_beats_hw;
          bit [APB_DATA_W-1:0] beat_words[APB_WORDS_PER_AXI_BEAT];
          bit [APB_DATA_W-1:0] got32, exp32;
          bit slverr;
          bit [AXI_ADDR_W-1:0]     addrs[NUM_TXNS];
          int unsigned             bytes[NUM_TXNS];
          int drained[NUM_TXNS] = '{default: 0};
          int sent_beats[NUM_TXNS] = '{default: 0};

          phase = get_starting_phase();
          if (phase != null) phase.raise_objection(this);

          `uvm_info("E2E", "===== APB→AXI FULL E2E SEQUENCE START =====", UVM_MEDIUM)

          // ---------------------------------------------------------
          // 1) PLAN TRANSACTIONS (FULL TAG COVERAGE)
          // ---------------------------------------------------------
          for (int i = 0; i < NUM_TXNS; i++) begin
               txns[i].tag   = i[TAG_W-1:0];
               txns[i].len   = $urandom_range(0, MAX_BEATS_NUM-2);
               txns[i].beats = axi_beats_from_len(txns[i].len);
               txns[i].addr  = pick_non_overlapping_addr(i, txns[i].len, addrs, bytes);

               txns[i].apb_words = new[txns[i].beats * APB_WORDS_PER_AXI_BEAT];

               foreach (txns[i].apb_words[j])
                    txns[i].apb_words[j] = 32'hCAFE_0000 ^ (i<<8) ^ j ^ $urandom();

               `uvm_info("E2E_PLAN",
                    $sformatf("TXN=%0d TAG=%0d ADDR=0x%0h LEN=%0d BEATS=%0d",
                              i, txns[i].tag, txns[i].addr,
                              txns[i].len, txns[i].beats),
                    UVM_NONE)
          end

          // ---------------------------------------------------------
          // 2) ISSUE ALL AW
          // ---------------------------------------------------------
          for (int i = 0; i < NUM_TXNS; i++) begin
               program_write_cmd(txns[i].len);
               program_addr(txns[i].addr);
          end

          #($urandom_range(0, 5000));

          // ---------------------------------------------------------
          // 3) INTERLEAVED W SEND (BEAT GRANULARITY)
          // ---------------------------------------------------------
          step = 0;
          while (1) begin
               eligible.delete();
               for (int i = 0; i < NUM_TXNS; i++)
                    if (sent_beats[i] < txns[i].beats)
                         eligible.push_back(i);

               if (eligible.size() == 0)
                    break;

               pick = eligible[$urandom_range(0, eligible.size()-1)];

               for (int k = 0; k < APB_WORDS_PER_AXI_BEAT; k++)
                    beat_words[k] =
                         txns[pick].apb_words[sent_beats[pick]*APB_WORDS_PER_AXI_BEAT + k];

               push_wr_beat(txns[pick].tag, beat_words);

               `uvm_info("E2E_W", $sformatf("STEP=%0d TXN=%0d TAG=%0d BEAT=%0d", step, pick, txns[pick].tag, sent_beats[pick]), UVM_NONE)

               sent_beats[pick]++;
               step++;
               #($urandom_range(10,120));
          end

          // ---------------------------------------------------------
          // 4) VERIFY WRITE COMPLETIONS
          // ---------------------------------------------------------
          for (int i = 0; i < NUM_TXNS; i++)
               wait_completion(txns[i].tag, 1000);

          // ---------------------------------------------------------
          // 5) BACKDOOR VERIFY WRITTEN MEMORY
          // ---------------------------------------------------------
          for (int i = 0; i < NUM_TXNS; i++) begin
               for (int b = 0; b < txns[i].beats; b++) begin
                    bit [AXI_DATA_W-1:0] got64, exp64;
                    bit ok;
                    exp64 = {
                         txns[i].apb_words[b*2+1],
                         txns[i].apb_words[b*2+0]
                    };
                    peek_axi_word64(txns[i].addr + b*(AXI_DATA_W/8),
                                    got64, ok);
                    if (!ok || got64 !== exp64)
                         `uvm_fatal("E2E_WR_CMP", $sformatf("WRITE MISMATCH TXN=%0d BEAT=%0d", i, b))
               end
          end

          // ---------------------------------------------------------
          // 6) ISSUE ALL AR
          // ---------------------------------------------------------
          for (int i = 0; i < NUM_TXNS; i++) begin
               program_read_cmd(txns[i].len);
               program_addr(txns[i].addr);
          end

          #(5000);   // allow all reads to complete

          // ---------------------------------------------------------
          // 7) INTERLEAVED APB-WORD DRAIN + COMPARE
          // ---------------------------------------------------------
          step = 0;

          while (1) begin
               eligible.delete();
               for (int i = 0; i < NUM_TXNS; i++)
                    if (drained[i] < txns[i].beats*APB_WORDS_PER_AXI_BEAT)
                         eligible.push_back(i);

               if (eligible.size() == 0)
                    break;

               pick = eligible[$urandom_range(0, eligible.size()-1)];

               pop_rd_apb_word(txns[pick].tag, got32, slverr);

               if(slverr) begin
                    #($urandom_range(10, 120));
                    continue;
               end

               exp32 = expected_word(txns[pick], drained[pick]);

               if (got32 !== exp32) `uvm_fatal("E2E_RD_CMP", $sformatf("READ MISMATCH TXN=%0d WORD=%0d", pick, drained[pick]))

               drained[pick]++;
               step++;
               #($urandom_range(10,120));
          end

          `uvm_info("E2E", "===== APB→AXI FULL E2E SEQUENCE PASSED =====", UVM_MEDIUM)

          if (phase != null) phase.drop_objection(this);
     endtask

endclass