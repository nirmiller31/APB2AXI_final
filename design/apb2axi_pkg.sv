/*------------------------------------------------------------------------------
 * File          : apb2axi_pkg.sv
 * Project       : APB2AXI
 * Author        : Nir Miller & Ido Oreg
 * Creation date : Nov 2, 2025
 * Description   : A file that holds all the shared constants and types for the whole Apb2Axi Converter Project
 *------------------------------------------------------------------------------*/

package apb2axi_pkg;

     // --------------------------------------------------
     // General bus widths
     // --------------------------------------------------
     parameter int APB_ADDR_W = 16;     // width of APB paddr
     parameter int APB_DATA_W = 32;     // APB data width
     parameter int APB_REG_W  = 32;
     parameter int AXI_ADDR_W = 64;     // full AXI address width
     parameter int AXI_DATA_W = 64;     // AXI data bus width
     parameter int AXI_ID_W   = 4;      // AXI ID width

     parameter int AXI_LEN_W  = 4;      // AXI ID width
     parameter int AXI_SIZE_W = 3;      // AXI ID width

     // --------------------------------------------------
     // Directory sizing
     // --------------------------------------------------
     parameter int TAG_NUM         = 16;        // number of outstanding transactions
     parameter int TAG_WIDTH       = (TAG_NUM <= 1) ? 1 : $clog2(TAG_NUM);
     parameter int TAG_W           = (TAG_NUM <= 1) ? 1 : $clog2(TAG_NUM);     
     parameter int N_TAG           = (1 << TAG_W);
     parameter int DIR_ENTRIES     = (1 << TAG_W);

     // --------------------------------------------------
     // Field offsets
     // --------------------------------------------------
     parameter int DIR_ENTRY_ISWRITE_HI = 31;
     parameter int DIR_ENTRY_ISWRITE_LO = 31;
     parameter int DIR_ENTRY_SIZE_HI    = 10;
     parameter int DIR_ENTRY_SIZE_LO    = 8;
     parameter int DIR_ENTRY_LEN_HI     = 7;
     parameter int DIR_ENTRY_LEN_LO     = 0;

     // --------------------------------------------------
     // Maximum Beats per burst in our arcitecture
     // --------------------------------------------------
     parameter int MAX_BEATS_NUM   = 16;
     parameter int FIFO_DEPTH      = TAG_NUM;

     parameter int APB_WORDS_PER_AXI_BEAT = (AXI_DATA_W / APB_DATA_W);
     
     // --------------------------------------------------
     // APB register map (byte offsets)
     // --------------------------------------------------
     parameter logic [APB_ADDR_W-1:0] REG_ADDR_ADDR_LO      = 16'h0000;
     parameter logic [APB_ADDR_W-1:0] REG_ADDR_ADDR_HI      = 16'h0004;
     parameter logic [APB_ADDR_W-1:0] REG_ADDR_CMD          = 16'h0008;
     parameter logic [APB_ADDR_W-1:0] REG_ADDR_RD_TAG_SEL   = 16'h000C;
     parameter logic [APB_ADDR_W-1:0] REG_RESP_POLICY       = 16'h0014;

     parameter logic [APB_ADDR_W-1:0] REG_ADDR_RD_STATUS    = 16'h0100;
     parameter logic [APB_ADDR_W-1:0] REG_ADDR_RD_DATA      = 16'h0200;
     parameter logic [APB_ADDR_W-1:0] REG_ADDR_WR_DATA      = 16'h0300;


     parameter int TAG_STRIDE_BYTES = (APB_DATA_W/8);
     parameter int TAG_WINDOW_BYTES = TAG_NUM * TAG_STRIDE_BYTES;

     // --------------------------------------------------
     // AXI3 resp
     // --------------------------------------------------
     typedef enum logic [1:0] {
          AXI_RESP_OKAY   = 2'b00,
          AXI_RESP_EXOKAY = 2'b01,
          AXI_RESP_SLVERR = 2'b10,
          AXI_RESP_DECERR = 2'b11
     } axi_resp_e;
     parameter int AXI_RESP_W = $bits(axi_resp_e);

     // --------------------------------------------------
     // Directory entry
     // --------------------------------------------------
     typedef enum logic [2:0] {
          DIR_ST_EMPTY,      // slot unused
          DIR_ST_STAGED,     // regs written but no commit yet (optional)
          DIR_ST_PENDING,    // committed, waiting to be issued
          DIR_ST_ISSUED,     // issued to AXI (or builder)
          DIR_ST_DONE,       // completed OK
          DIR_ST_ERROR       // completed with error
     } dir_state_e;

     typedef enum logic [1:0] {
          ST_EMPTY     = 2'd0,
          ST_ALLOCATED = 2'd1,    
          ST_PENDING   = 2'd2,
          ST_COMPLETE  = 2'd3
     } entry_state_e;

     typedef struct packed {
          logic                    is_write;
          logic [AXI_ADDR_W-1:0]   addr;
          logic [7:0]              len;
          logic [2:0]              size;
          logic [1:0]              burst;
          logic [TAG_W-1:0]        tag;
          axi_resp_e               resp;
          logic [7:0]              num_beats;
          logic [7:0]              err_beat_idx;
          dir_state_e              state;
     } directory_entry_t;
     parameter int CMD_ENTRY_W     = $bits(directory_entry_t);

     // --------------------------------------------------
     // Completion entry
     // --------------------------------------------------
     typedef struct packed {
          logic                    is_write; //1 = write completion (B) , 0 = read completion (R) 
          logic [TAG_W-1:0]        tag;
          axi_resp_e               resp;
          logic                    error;
          logic [7:0]              num_beats;
          logic [7:0]              err_beat_idx;
     } completion_entry_t;
     parameter int CPL_W           = $bits(completion_entry_t);

     // --------------------------------------------------
     // Response Handler Beat struct
     // --------------------------------------------------
     typedef struct packed {
          logic [AXI_DATA_W-1:0]   data;
          axi_resp_e               resp;
          logic                    last;
     } rd_beat_t;
     parameter int RD_BEAT_W = $bits(rd_beat_t);  

     // --------------------------------------------------
     // Read Data FIFO entry
     // --------------------------------------------------
     typedef struct packed {
          logic [TAG_W-1:0]        tag;
          logic [AXI_DATA_W-1:0]   data;
          logic                    last;
          axi_resp_e               resp;
     } rdf_entry_t;
     parameter int RDF_W = $bits(rdf_entry_t);

     // --------------------------------------------------
     // Write Data FIFO entry
     // --------------------------------------------------
     typedef struct packed {
          logic [TAG_W-1:0]        tag;
          logic [AXI_DATA_W-1:0]   data;
          logic                    last;
          logic [AXI_DATA_W/8-1:0] wstrb;
     } wr_entry_t;
     parameter int DATA_ENTRY_W = $bits(wr_entry_t);

endpackage