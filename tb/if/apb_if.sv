
interface apb_if
     #(
          parameter ADDR_WIDTH = 32,
          parameter DATA_WIDTH = 32
     )
     (
          input  logic                PCLK,
          input  logic                PRESETn
     );

     // --------------------------------------------------
     // APB3 Standard Signals
     // --------------------------------------------------
     logic [ADDR_WIDTH-1:0]      PADDR;
     logic                       PWRITE;
     logic [DATA_WIDTH-1:0]      PWDATA;
     logic [DATA_WIDTH-1:0]      PRDATA;
     logic                       PENABLE;
     logic                       PSEL;
     logic                       PREADY;
     logic                       PSLVERR;

     // --------------------------------------------------
     // Master/Slave modports
     // --------------------------------------------------

     // Master drives address and control; receives PRDATA/PREADY/PSLVERR
     modport master_mp (
          input  PREADY, PRDATA, PSLVERR,
          output PADDR, PWRITE, PWDATA, PSEL, PENABLE
     );

     // Slave receives address/control; drives PRDATA/PREADY/PSLVERR
     modport slave_mp (
          input  PADDR, PWRITE, PWDATA, PSEL, PENABLE,
          output PRDATA, PREADY, PSLVERR
     );

     // Monitor — observes everything passively
     modport monitor_mp (
          input  PADDR, PWRITE, PWDATA, PRDATA,
                    PSEL, PENABLE, PREADY, PSLVERR
     );

     // --------------------------------------------------
     // Clocking block for timing-safe access (optional but recommended)
     // --------------------------------------------------
     clocking cb @(posedge PCLK);
          default input #1step output #1step;
          input  PREADY, PRDATA, PSLVERR;
          output PADDR, PWRITE, PWDATA, PSEL, PENABLE;
     endclocking


endinterface
