
import uvm_pkg::*;
import apb2axi_tb_pkg::*;

module tb_top;

     localparam time APB_CLK_DELAY = 5ns;
     localparam time AXI_CLK_DELAY = 5ns;

     logic          PCLK;
     logic          PRESETn;

     logic          ACLK;
     logic          ARESETn;

     int unsigned rp;

     initial begin
          PCLK      = 0;
          forever   #APB_CLK_DELAY PCLK = ~PCLK;
     end

     initial begin
          ACLK      = 0;
          forever   #AXI_CLK_DELAY ACLK = ~ACLK;
     end

     initial begin
          PRESETn   = 0;
          ARESETn   = 0;
          #50ns;
          PRESETn   = 1;
          ARESETn   = 1;
     end

     apb_if apb_vif (
          .PCLK(PCLK), 
          .PRESETn(PRESETn)
     );

     axi_if axi_vif (
          .ACLK(ACLK), 
          .ARESETn(ARESETn)
     );

     apb2axi #() dut (
          // ------------------ APB side ------------------
          .PCLK      (PCLK),
          .PRESETn   (PRESETn),
          .PADDR     (apb_vif.PADDR),
          .PWDATA    (apb_vif.PWDATA),
          .PWRITE    (apb_vif.PWRITE),
          .PSEL      (apb_vif.PSEL),
          .PENABLE   (apb_vif.PENABLE),
          .PRDATA    (apb_vif.PRDATA),
          .PREADY    (apb_vif.PREADY),
          .PSLVERR   (apb_vif.PSLVERR),

          // ------------------ AXI side ------------------
          .ACLK     (ACLK),
          .ARESETn  (ARESETn),

          // Write address channel
          .AWID     (axi_vif.AWID),
          .AWADDR   (axi_vif.AWADDR),
          .AWLEN    (axi_vif.AWLEN),
          .AWSIZE   (axi_vif.AWSIZE),
          .AWBURST  (axi_vif.AWBURST),
          .AWLOCK   (axi_vif.AWLOCK),
          .AWCACHE  (axi_vif.AWCACHE),
          .AWPROT   (axi_vif.AWPROT),
          .AWVALID  (axi_vif.AWVALID),
          .AWREADY  (axi_vif.AWREADY),

          // Write data channel
          .WID      (axi_vif.WID),
          .WDATA    (axi_vif.WDATA),
          .WSTRB    (axi_vif.WSTRB),
          .WLAST    (axi_vif.WLAST),
          .WVALID   (axi_vif.WVALID),
          .WREADY   (axi_vif.WREADY),

          // Write response channel
          .BID      (axi_vif.BID),
          .BRESP    (axi_vif.BRESP),
          .BVALID   (axi_vif.BVALID),
          .BREADY   (axi_vif.BREADY),

          // Read address channel
          .ARID     (axi_vif.ARID),
          .ARADDR   (axi_vif.ARADDR),
          .ARLEN    (axi_vif.ARLEN),
          .ARSIZE   (axi_vif.ARSIZE),
          .ARBURST  (axi_vif.ARBURST),
          .ARLOCK   (axi_vif.ARLOCK),
          .ARCACHE  (axi_vif.ARCACHE),
          .ARPROT   (axi_vif.ARPROT),
          .ARVALID  (axi_vif.ARVALID),
          .ARREADY  (axi_vif.ARREADY),

          // Read data channel
          .RID      (axi_vif.RID),
          .RDATA    (axi_vif.RDATA),
          .RRESP    (axi_vif.RRESP),
          .RLAST    (axi_vif.RLAST),
          .RVALID   (axi_vif.RVALID),
          .RREADY   (axi_vif.RREADY)
     );

     initial begin
          $display("### FSDB DUMP BLOCK HIT at time %0t", $time);
          $fsdbDumpfile("waves.fsdb");
          $fsdbDumpvars(0, tb_top, "+all");
          $fsdbDumpMDA();
     end

     // initial begin
     //      uvm_config_db#(virtual apb_if)::set(null, "*", "apb_vif", apb_vif);
     //      uvm_config_db#(virtual axi_if)::set(null, "*", "axi_vif", axi_vif);
     //      run_test("apb2axi_bringup_test");
     // end



     initial begin
          uvm_config_db#(virtual apb_if)::set(null, "*", "apb_vif", apb_vif);
          uvm_config_db#(virtual axi_if)::set(null, "*", "axi_vif", axi_vif);
          run_test("apb2axi_test");
     end

endmodule