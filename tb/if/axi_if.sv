
interface axi_if #(parameter ADDR_WIDTH = 32,
                   parameter DATA_WIDTH = 32,
                   parameter ID_WIDTH   = 4)
(
    input  logic ACLK,
    input  logic ARESETn
);

    // ======================================================
    // Write Address Channel
    // ======================================================
    logic [ADDR_WIDTH-1:0] AWADDR;
    logic [7:0]            AWLEN;
    logic [2:0]            AWSIZE;
    logic [1:0]            AWBURST;
    logic [ID_WIDTH-1:0]   AWID;
    logic                  AWVALID;
    logic                  AWREADY;

    // ======================================================
    // Write Data Channel
    // ======================================================
    logic [DATA_WIDTH-1:0] WDATA;
    logic [(DATA_WIDTH/8)-1:0] WSTRB;
    logic                  WLAST;
    logic                  WVALID;
    logic                  WREADY;

    // ======================================================
    // Write Response Channel
    // ======================================================
    logic [1:0]            BRESP;
    logic [ID_WIDTH-1:0]   BID;
    logic                  BVALID;
    logic                  BREADY;

    // ======================================================
    // Read Address Channel
    // ======================================================
    logic [ADDR_WIDTH-1:0] ARADDR;
    logic [7:0]            ARLEN;
    logic [2:0]            ARSIZE;
    logic [1:0]            ARBURST;
    logic [ID_WIDTH-1:0]   ARID;
    logic                  ARVALID;
    logic                  ARREADY;

    // ======================================================
    // Read Data Channel
    // ======================================================
    logic [DATA_WIDTH-1:0] RDATA;
    logic [1:0]            RRESP;
    logic [ID_WIDTH-1:0]   RID;
    logic                  RVALID;
    logic                  RREADY;
    logic                  RLAST;

    // ======================================================
    // Modports for Different Roles
    // ======================================================

    // APB2AXI DUT drives: *READY*, *RDATA*, *BRESP*, etc.
    modport dut_side (
        input  ACLK, ARESETn,
        input  AWADDR, AWLEN, AWSIZE, AWBURST, AWID, AWVALID,
        output AWREADY,

        input  WDATA, WSTRB, WLAST, WVALID,
        output WREADY,

        output BRESP, BID, BVALID,
        input  BREADY,

        input  ARADDR, ARLEN, ARSIZE, ARBURST, ARID, ARVALID,
        output ARREADY,

        output RDATA, RRESP, RID, RVALID, RLAST,
        input  RREADY
    );

    // UVM driver drives VALID signals, DUT responds READY
    modport drv_side (
        input  ACLK, ARESETn,
        output AWADDR, AWLEN, AWSIZE, AWBURST, AWID, AWVALID,
        input  AWREADY,

        output WDATA, WSTRB, WLAST, WVALID,
        input  WREADY,

        input  BRESP, BID, BVALID,
        output BREADY,

        output ARADDR, ARLEN, ARSIZE, ARBURST, ARID, ARVALID,
        input  ARREADY,

        input  RDATA, RRESP, RID, RVALID, RLAST,
        output RREADY
    );

    // Monitor observes all
    modport mon_side (
        input ACLK, ARESETn,
        input AWADDR, AWLEN, AWSIZE, AWBURST, AWID, AWVALID, AWREADY,
        input WDATA, WSTRB, WLAST, WVALID, WREADY,
        input BRESP, BID, BVALID, BREADY,
        input ARADDR, ARLEN, ARSIZE, ARBURST, ARID, ARVALID, ARREADY,
        input RDATA, RRESP, RID, RVALID, RREADY, RLAST
    );

endinterface
