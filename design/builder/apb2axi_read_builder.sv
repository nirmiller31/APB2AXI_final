/*------------------------------------------------------------------------------
 * File          : apb2axi_read_builder.sv
 * Project       : APB2AXI
 * Author        : Nir Miller & Ido Oreg
 * Description   : - Pops read descriptors from the RD FIFO and drives AXI AR
 *                 - Holds ARVALID until ARREADY handshake completes
 *                 - Issues exactly one FIFO pop per accepted AR transaction (ACLK domain)
 *------------------------------------------------------------------------------*/
 
module apb2axi_read_builder #(
    parameter int FIFO_ENTRY_W = CMD_ENTRY_W
)(
    input  logic                    aclk,
    input  logic                    aresetn,
    // AXI AR
    output logic [AXI_ID_W-1:0]     arid,
    output logic [AXI_ADDR_W-1:0]   araddr,
    output logic [3:0]              arlen,
    output logic [2:0]              arsize,
    output logic [1:0]              arburst,
    output logic                    arlock,
    output logic [3:0]              arcache,
    output logic [2:0]              arprot,
    output logic                    arvalid,
    input  logic                    arready,
    // READ FIFO
    input  logic                    rd_pop_vld,
    input  logic [FIFO_ENTRY_W-1:0] rd_pop_data,
    output logic                    rd_pop_rdy
);

    directory_entry_t               entry;
    assign entry                    = rd_pop_data;

    assign arlock                   = 1'b0;
    assign arcache                  = 4'b0011;
    assign arprot                   = 3'b000;
    // FIXME additional field handling

    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            arvalid                 <= 1'b0;
            rd_pop_rdy              <= 1'b0;
        end else begin
            rd_pop_rdy              <= 1'b0;   // default (zero the pulse)
            if (arvalid && !arready) begin     // Hold ARVALID until handshake
                arvalid             <= 1'b1;
            end
            else if (!arvalid && rd_pop_vld) begin  
                arid                <= entry.tag;
                araddr              <= entry.addr;
                arlen               <= entry.len;
                arsize              <= entry.size;
                arburst             <= 2'b01;       // FIXME support non-INCR
                arvalid             <= 1'b1;
                rd_pop_rdy          <= 1'b1;   // pop exactly once
            end
            else begin                         // Otherwise: drop ARVALID after handshake
                arvalid <= 1'b0;
            end
        end
    end

// ==========================================================================================================================
// =================================================== DEBUG infra (per-tag) ================================================
// ==========================================================================================================================

    bit rb_dbg;
    initial begin
        rb_dbg = $test$plusargs("APB2AXI_RB_DEBUG");
        if (rb_dbg)
            $display("%t [RB_DBG] ReadBuilder debug ENABLED (+APB2AXI_RB_DEBUG)", $time);
    end

    always_ff @(posedge aclk) if (rb_dbg && aresetn) begin
        if (rd_pop_vld && rd_pop_rdy)
            $display("%t [RB] POP  tag=%0d addr=%h len=%0d size=%0d",
                    $time, entry.tag, entry.addr, entry.len, entry.size);

        if (arvalid && arready)
            $display("%t [RB] AR   tag=%0d addr=%h len=%0d size=%0d",
                    $time, arid, araddr, arlen, arsize);
    end

// ==========================================================================================================================
// ==========================================================================================================================
// ==========================================================================================================================


endmodule