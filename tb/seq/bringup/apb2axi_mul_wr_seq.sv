// tb/seq/apb2axi_mul_wr_seq.sv
// NOTE: This file is `included by apb2axi_tb_pkg.sv.
// Do NOT import apb2axi_tb_pkg::* here (it causes "package importing itself").
// Do NOT re-import uvm_pkg::* if your tb_pkg already does it.

class apb2axi_mul_wr_seq extends apb2axi_base_seq;
  `uvm_object_utils(apb2axi_mul_wr_seq)

  // ------------------------------------------------
  // Re-declare regs locally (do NOT rely on base localparams)
  // ------------------------------------------------
  localparam int REG_ADDR_LO        = 'h00;
  localparam int REG_ADDR_HI        = 'h04;
  localparam int REG_CMD            = 'h08;

  // Per-tag status window base (your design uses 0x0100..)
  localparam int REG_RD_STATUS_B    = 'h0100;

  // Write data window base
  localparam int REG_WR_DATA_BASE   = 'h0300;

  // -------------------------------
  // Configuration knobs
  // -------------------------------
  localparam int NUM_TXNS = 3;
  localparam int AXI_LEN  = 3;                  // LEN=3 => 4 beats
  localparam int BEATS    = AXI_LEN + 1;

  localparam int APB_PER_BEAT = (AXI_DATA_W / APB_DATA_W);

  typedef struct {
    bit [63:0]      addr;
    bit [TAG_W-1:0] tag;
    bit [31:0]      apb_words[BEATS * APB_PER_BEAT];
  } wr_txn_t;

  wr_txn_t txns[NUM_TXNS];

  // Per-TAG schedule state
  int next_beat[NUM_TXNS];
  bit txn_done [NUM_TXNS];

  function new(string name="apb2axi_mul_wr_seq");
    super.new(name);
  endfunction

  virtual task body();
    uvm_phase phase;

    int eligible[$];
    int t, beat;
    int base;
    int widx0, widx1;

    int total_remaining;
    int global_step;
    int last_pick;

    bit [31:0] w0, w1;

    bit [31:0] sts;
    bit done, err;
    int resp;

    axi3_slave_bfm bfm_h;
logic [AXI_DATA_W-1:0] got, exp;
bit ok;

    phase = get_starting_phase();
    if (phase != null) phase.raise_objection(this);

    // ------------------------------------------------------------
    // [CHANGED] Safety: make sure we have enough unique TAGs
    // ------------------------------------------------------------
    if (NUM_TXNS > (1 << TAG_W)) begin
      `uvm_fatal("WR_MULTI",
        $sformatf("NUM_TXNS=%0d exceeds TAG space 2^TAG_W=%0d. Increase TAG_W or reduce NUM_TXNS.",
                  NUM_TXNS, (1 << TAG_W)))
    end

    // Init state
    foreach (next_beat[i]) begin
      next_beat[i] = 0;
      txn_done[i]  = 1'b0;
    end
    total_remaining = NUM_TXNS * BEATS;
    global_step     = 0;
    last_pick       = -1;

    `uvm_info("WR_MULTI", "Starting multi-AW then interleaved-W sequence", UVM_MEDIUM)

    //-----------------------------------------
    // 1) Prepare transactions
    //-----------------------------------------
    foreach (txns[i]) begin
      // [CHANGED] Correct tag assignment (no truncation via bit' cast)
      txns[i].tag  = i[TAG_W-1:0];

      txns[i].addr = 64'h0000_0000_0000_1200 + i * 64;

      foreach (txns[i].apb_words[j]) begin
        // deterministic unique pattern per txn+word
        txns[i].apb_words[j] = 32'hCAFE_0000 | (i << 8) | j;
      end
    end

    //-----------------------------------------
    // 2) Issue ALL AWs first (no W yet)
    //-----------------------------------------
    foreach (txns[i]) begin
      `uvm_info("WR_MULTI",
        $sformatf("Issuing AW only: TXN=%0d TAG=%0d ADDR=0x%0h LEN=%0d (beats=%0d)",
                  i, txns[i].tag, txns[i].addr, AXI_LEN, BEATS),
        UVM_LOW)

      apb_write(REG_ADDR_HI, txns[i].addr[63:32]);

      // CMD: write=1, size=3 (8B), len=AXI_LEN
      apb_write(REG_CMD, (32'h1 << 31) | (32'd3 << 8) | AXI_LEN);

      apb_write(REG_ADDR_LO, txns[i].addr[31:0]);
    end

    //-----------------------------------------
    // 3) Let AWs queue up
    //-----------------------------------------
    `uvm_info("WR_MULTI", "Waiting before sending W data...", UVM_LOW)
    #(500);

    //-----------------------------------------
    // 4) RANDOMIZED *INTERLEAVED* W schedule
    //-----------------------------------------
    while (total_remaining > 0) begin
      eligible.delete();

      for (int i = 0; i < NUM_TXNS; i++) begin
        if (!txn_done[i]) eligible.push_back(i);
      end

      // [CHANGED] Encourage interleaving: avoid picking same txn twice if possible
      if (eligible.size() > 1 && last_pick != -1) begin
        // with high probability, re-pick if we hit last_pick
        int tries = 0;
        do begin
          t = eligible[$urandom_range(0, eligible.size()-1)];
          tries++;
        end while (t == last_pick && tries < 5);
      end
      else begin
        t = eligible[$urandom_range(0, eligible.size()-1)];
      end

      beat = next_beat[t];

      // Your design behavior: per-TAG "window/FIFO" => same base address is fine
      base  = REG_WR_DATA_BASE + (txns[t].tag * 4);

      widx0 = beat * APB_PER_BEAT;
      widx1 = widx0 + 1;

      w0 = txns[t].apb_words[widx0];
      w1 = txns[t].apb_words[widx1];

      `uvm_info("WR_ILV",
        $sformatf("SEND_W step=%0d | TXN=%0d | TAG=%0d | BEAT=%0d/%0d | base=0x%0h | W0=0x%08x W1=0x%08x",
                  global_step, t, txns[t].tag, beat, BEATS-1, base, w0, w1),
        UVM_LOW)

      apb_write(base, w0);
      apb_write(base, w1);

      next_beat[t]++;
      total_remaining--;
      global_step++;
      last_pick = t;

      if (next_beat[t] == BEATS)
        txn_done[t] = 1'b1;

      #( $urandom_range(10, 80) );
    end

    //-----------------------------------------
    // 5) Poll completion for each TAG (correct window!)
    //-----------------------------------------
    foreach (txns[i]) begin
      done = 0;
      err  = 0;
      resp = 0;

      repeat (400) begin
        // Correct per-tag status window
        apb_read(REG_RD_STATUS_B + (txns[i].tag * 4), sts);

        done = sts[15];
        err  = sts[14];
        resp = sts[13:12];

        if (done || err) break;
        #(50);
      end

      if (!done) `uvm_fatal("WR_MULTI", $sformatf("TAG %0d did not complete. Last STS=0x%08x", txns[i].tag, sts))

      if (err) `uvm_fatal("WR_MULTI", $sformatf("TAG %0d completed with ERROR. RESP=%0d STS=0x%08x", txns[i].tag, resp, sts))

      `uvm_info("WR_MULTI", $sformatf("TAG %0d completed OK (STS=0x%08x)", txns[i].tag, sts), UVM_LOW)
    end

if (!uvm_config_db#(axi3_slave_bfm)::get(null, "", "axi_bfm_h", bfm_h)) begin
  `uvm_warning("WR_CMP", "No axi_bfm_h in config_db; skipping compare")
end
else begin
  foreach (txns[i]) begin
    for (int beat = 0; beat < BEATS; beat++) begin
      logic [63:0] a;
      int widx0, widx1;

      a     = txns[i].addr + beat*(AXI_DATA_W/8);
      widx0 = beat*APB_PER_BEAT;
      widx1 = widx0 + 1;

      // assumes little-endian packing: first APB word is lower 32b
      exp = { txns[i].apb_words[widx1], txns[i].apb_words[widx0] };

      ok = bfm_h.peek_word64(a, got);
      if (!ok) begin
        `uvm_fatal("WR_CMP", $sformatf("Peek failed: TAG=%0d addr=0x%0h", txns[i].tag, a))
      end

      if (got !== exp) begin
        `uvm_fatal("WR_CMP",
          $sformatf("MISMATCH TAG=%0d BEAT=%0d addr=0x%0h exp=0x%0h got=0x%0h",
                    txns[i].tag, beat, a, exp, got))
      end
      else begin
        `uvm_info("WR_CMP",
          $sformatf("MATCH    TAG=%0d BEAT=%0d addr=0x%0h data=0x%0h",
                    txns[i].tag, beat, a, got),
          UVM_LOW)
      end
    end
  end

  // optional: dump full memory snapshot after compare
  bfm_h.dump_mem_to_file("mem_after_mul_wr.txt");
end

    `uvm_info("WR_MULTI", "Multi-AW + interleaved-W test PASSED", UVM_MEDIUM)

    if (phase != null) phase.drop_objection(this);
  endtask

endclass