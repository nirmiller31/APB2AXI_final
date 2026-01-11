/*------------------------------------------------------------------------------
* File          : axi_if.sv
* Project       : RTL
* Author        : epnimo
* Creation date : Nov 2, 2025
* Description   : AXI3 Side Interface (Standard Uppercase Naming)
*------------------------------------------------------------------------------*/

import apb2axi_pkg::*;

interface axi_if #(
     parameter int ID_WIDTH   = AXI_ID_W,
     parameter int ADDR_WIDTH = AXI_ADDR_W,
     parameter int DATA_WIDTH = AXI_DATA_W,
     parameter int STRB_WIDTH = DATA_WIDTH / 8
     )(
     input logic ACLK,
     input logic ARESETn
     );

     // ----------------------------------------------------------
     // Write Address Channel (AW)
     // ----------------------------------------------------------
     logic [ID_WIDTH-1:0]    AWID;
     logic [ADDR_WIDTH-1:0]  AWADDR;
     logic [3:0]             AWLEN;
     logic [2:0]             AWSIZE;
     logic [1:0]             AWBURST;
     logic                   AWLOCK;
     logic [3:0]             AWCACHE;
     logic [2:0]             AWPROT;
     logic                   AWVALID;
     logic                   AWREADY;

     // ----------------------------------------------------------
     // Write Data Channel (W)
     // ----------------------------------------------------------
     logic [ID_WIDTH-1:0]    WID;
     logic [DATA_WIDTH-1:0]  WDATA;
     logic [STRB_WIDTH-1:0]  WSTRB;
     logic                   WLAST;
     logic                   WVALID;
     logic                   WREADY;

     // ----------------------------------------------------------
     // Write Response Channel (B)
     // ----------------------------------------------------------
     logic [ID_WIDTH-1:0]    BID;
     logic [1:0]             BRESP;
     logic                   BVALID;
     logic                   BREADY;

     // ----------------------------------------------------------
     // Read Address Channel (AR)
     // ----------------------------------------------------------
     logic [ID_WIDTH-1:0]    ARID;
     logic [ADDR_WIDTH-1:0]  ARADDR;
     logic [3:0]             ARLEN;
     logic [2:0]             ARSIZE;
     logic [1:0]             ARBURST;
     logic                   ARLOCK;
     logic [3:0]             ARCACHE;
     logic [2:0]             ARPROT;
     logic                   ARVALID;
     logic                   ARREADY;

     // ----------------------------------------------------------
     // Read Data Channel (R)
     // ----------------------------------------------------------
     logic [ID_WIDTH-1:0]    RID;
     logic [DATA_WIDTH-1:0]  RDATA;
     logic [1:0]             RRESP;
     logic                   RLAST;
     logic                   RVALID;
     logic                   RREADY;

     // ----------------------------------------------------------
     // Modports
     // ----------------------------------------------------------
     modport Master (
          input  ACLK, ARESETn,

          // Write address
          output AWID, AWADDR, AWLEN, AWSIZE, AWBURST, AWLOCK, AWCACHE, AWPROT, AWVALID,
          input  AWREADY,

          // Write data
          output WID, WDATA, WSTRB, WLAST, WVALID,
          input  WREADY,

          // Write response
          output BREADY,
          input  BID, BRESP, BVALID,

          // Read address
          output ARID, ARADDR, ARLEN, ARSIZE, ARBURST, ARLOCK, ARCACHE, ARPROT, ARVALID,
          input  ARREADY,

          // Read data
          output RREADY,
          input  RID, RDATA, RRESP, RLAST, RVALID
     );

     modport Slave (
          input  ACLK, ARESETn,

          // Write address
          input  AWID, AWADDR, AWLEN, AWSIZE, AWBURST, AWLOCK, AWCACHE, AWPROT, AWVALID,
          output AWREADY,

          // Write data
          input  WID, WDATA, WSTRB, WLAST, WVALID,
          output WREADY,

          // Write response
          input  BREADY,
          output BID, BRESP, BVALID,

          // Read address
          input  ARID, ARADDR, ARLEN, ARSIZE, ARBURST, ARLOCK, ARCACHE, ARPROT, ARVALID,
          output ARREADY,

          // Read data
          input  RREADY,
          output RID, RDATA, RRESP, RLAST, RVALID
     );

endinterface
