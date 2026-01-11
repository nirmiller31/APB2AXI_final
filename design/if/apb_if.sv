/*------------------------------------------------------------------------------
 * File          : apb_if.sv
 * Project       : APB2AXI
 * Author        : Nir Miller & Ido Oreg
 * Creation date : Nov 2, 2025
 * Description   : APB Side Interface (Standard Uppercase Naming)
 *------------------------------------------------------------------------------*/

import apb2axi_pkg::*;

interface apb_if #(
    parameter int ADDR_WIDTH = APB_ADDR_W,
    parameter int DATA_WIDTH = APB_DATA_W
)(
    input logic PCLK,
    input logic PRESETn
);

    // ----------------------------------------------------------
    // APB Bus Signals
    // ----------------------------------------------------------
    logic  [ADDR_WIDTH-1:0] PADDR;
    logic                   PSEL;
    logic                   PENABLE;
    logic                   PWRITE;
    logic  [DATA_WIDTH-1:0] PWDATA;

    // ----------------------------------------------------------
    // Response Signals
    // ----------------------------------------------------------
    logic  [DATA_WIDTH-1:0] PRDATA;
    logic                   PREADY;
    logic                   PSLVERR;

    // ----------------------------------------------------------
    // Modports
    // ----------------------------------------------------------
    modport Master (
        input  PCLK, PRESETn,
        output PADDR, PSEL, PENABLE, PWRITE, PWDATA,
        input  PRDATA, PREADY, PSLVERR
    );

    modport Slave (
        input  PCLK, PRESETn,
        input  PADDR, PSEL, PENABLE, PWRITE, PWDATA,
        output PRDATA, PREADY, PSLVERR
    );

endinterface
