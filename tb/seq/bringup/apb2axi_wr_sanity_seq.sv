class apb2axi_wr_sanity_seq extends apb2axi_base_seq;
  `uvm_object_utils(apb2axi_wr_sanity_seq)
















  localparam int REG_ADDR_LO      = 'h00;
  localparam int REG_ADDR_HI      = 'h04;
  localparam int REG_CMD          = 'h08;
  localparam int REG_RD_STATUS_B  = 'h0100;
  localparam int REG_WR_DATA_B    = 'h0300;   // change: MUST match your package REG_ADDR_WR_DATA

  function new(string name="apb2axi_wr_sanity_seq");
    super.new(name);
  endfunction

  virtual task body();
    bit [63:0] addr;
    int unsigned tag;
    bit [31:0] w0, w1, w2, w3, w4, w5, w6, w7;
    bit [31:0] sts;
    bit done, err;
    int resp;

    tag  = 0;                       // simple fixed tag
    addr = 64'h0000_0000_0000_1148; // any legal addr in your map

    // For AXI_DATA_W=64 and APB_DATA_W=32: 1 beat == 2 APB words
    w0 = 32'hCAFE_0000;
    w1 = 32'hCAFE_0001;
    w2 = 32'hFFFF_EEEE;
    w3 = 32'hAAAA_BBBB;
    w4 = 32'hABAB_0101;
    w5 = 32'h0606_CDCD;
    w6 = 32'h1234_4567;
    w7 = 32'h89AB_CDEF;

    // --------------------------------------------
    // Program the command (WRITE, LEN=0 => 1 beat)
    // CMD fields per your pkg offsets:
    // is_write: bit 31
    // size:     [10:8]   (3 for 8B)
    // len:      [7:0]    (0 for 1 beat)
    // --------------------------------------------
    
    apb_write(REG_ADDR_HI, addr[63:32]);

    // is_write=1, size=3, len=0
    apb_write(REG_CMD, (32'h1 << 31) | (32'(3) << 8) | 32'(3));

    apb_write(REG_ADDR_LO, addr[31:0]);

    // --------------------------------------------
    // Push write data into WR_DATA window for TAG
    // (2 APB words => 1 AXI beat)
    // --------------------------------------------
    apb_write(REG_WR_DATA_B + tag*4, w0);
    apb_write(REG_WR_DATA_B + tag*4, w1);
    apb_write(REG_WR_DATA_B + tag*4, w2);
    apb_write(REG_WR_DATA_B + tag*4, w3);
    apb_write(REG_WR_DATA_B + tag*4, w4);
    apb_write(REG_WR_DATA_B + tag*4, w5);
    apb_write(REG_WR_DATA_B + tag*4, w6);
    apb_write(REG_WR_DATA_B + tag*4, w7);

    // --------------------------------------------
    // Poll RD_STATUS[tag] until done/error
    // --------------------------------------------
    repeat (100) begin
      apb_read(REG_RD_STATUS_B + tag*4, sts);

      done = sts[15];
      err  = sts[14];
      resp = sts[13:12];

      if (done || err) begin
        `uvm_info("WR_SANITY",
          $sformatf("TAG=%0d STS=0x%08x done=%0d err=%0d resp=%0d",
                    tag, sts, done, err, resp),
          UVM_LOW)
        break;
      end
      // small delay between polls
      #(100);
    end

    if (!done) `uvm_fatal("WR_SANITY", $sformatf("Write did not complete. TAG=%0d STS=0x%08x", tag, sts))
    if (err)   `uvm_fatal("WR_SANITY", $sformatf("Write completed with ERROR. TAG=%0d RESP=%0d STS=0x%08x", tag, resp, sts))

    `uvm_info("WR_SANITY", "PASS: single-tag single-beat write completed OK", UVM_LOW)
  endtask
endclass