//------------------------------------------------------------------------------
// AXI3 Slave BFM (Full Version)
// Supports:
//   * Multi-beat bursts (ARLEN/AWLEN)
//   * SIZE-qualified beat size (2^SIZE bytes)
//   * WSTRB byte-level writes
//   * Backpressure-safe R and B channels
//   * Non-interleaved mode (AXI3-compliant for single outstanding ID)
//   * Real memory model
//------------------------------------------------------------------------------
// Modes:
//   - regular           (default)
//   - outstanding       (+LINEAR_OUTSTANDING)
//   - extreme           (+EXTREME_OUTSTANDING)
//------------------------------------------------------------------------------

import uvm_pkg::*;
`include "uvm_macros.svh"
import apb2axi_pkg::*;


class axi3_slave_bfm extends uvm_component;

     `uvm_component_utils(axi3_slave_bfm)

     virtual axi_if vif;

     // ------------------------------------------------------------
     // Memory Model
     // ------------------------------------------------------------
     localparam int                MEM_DEPTH = 4096;
     localparam int                AXI_BYTES = AXI_DATA_W / 8;
     typedef bit [AXI_DATA_W-1:0]  data_word_t;
     data_word_t                   mem [0:MEM_DEPTH-1];
     bit                           mem_written [0:MEM_DEPTH-1];

     bit [AXI_ID_W-1:0] beat_order_q[$];   // one entry per R beat
     bit [AXI_ID_W-1:0] burst_order_q[$];  // one entry per completed burst

     // ------------------------------------------------------------
     // Read mode
     // ------------------------------------------------------------
     typedef enum int { MODE_REGULAR = 0,
                         MODE_OUTSTANDING = 1,
                         MODE_EXTREME = 2 } read_mode_e;
     read_mode_e read_mode = MODE_REGULAR;

     // ------------------------------------------------------------
     // Error injection tables (DISABLED BY DEFAULT)
     // ------------------------------------------------------------
     localparam int unsigned     ID_NUM = (1 << AXI_ID_W);

     axi_resp_e                  rerr_map       [ID_NUM][256];   // [RID][beat_idx]
     bit                         rerr_map_valid [ID_NUM];        // enable per RID

     axi_resp_e                  berr_map       [ID_NUM];        // [BID] -> BRESP
     bit                         berr_map_valid [ID_NUM];        // enable per BID
     bit                         berr_one_shot  = 1'b1;

     // ------------------------------------------------------------
     // Read tracking
     // ------------------------------------------------------------
     typedef struct {
          logic [AXI_ADDR_W-1:0] addr;
          logic [3:0]            beats_left;  // remaining beats
          logic [2:0]            size;
          logic [AXI_ID_W-1:0]   id;
          logic [1:0]            burst;
          int unsigned           mem_idx;     // pointer to memory
          int unsigned           beat_idx;
     } active_read_t;
     active_read_t active_reads[$];

     // ------------------------------------------------------------
     // Write tracking
     // ------------------------------------------------------------
     typedef struct {
          logic [AXI_ADDR_W-1:0] addr;
          logic [3:0]            beats_left;  // remaining beats
          logic [2:0]            size;
          logic [AXI_ID_W-1:0]   id;
          int unsigned           mem_idx;     // pointer to memory
     } active_write_t;

     active_write_t active_writes[$];
     bit [AXI_ID_W-1:0] pending_b_ids[$];

     // ------------------------------------------------------------
     // Constructor
     // ------------------------------------------------------------
     function new(string name="axi3_slave_bfm", uvm_component parent=null);
          super.new(name,parent);
     endfunction

     // ------------------------------------------------------------
     // Build
     // ------------------------------------------------------------
     function void build_phase(uvm_phase phase);
          super.build_phase(phase);
          if (!uvm_config_db#(virtual axi_if)::get(this,"","axi_vif",vif))
               `uvm_fatal("AXI3_BFM","No virtual interface bound to BFM");

          if ($test$plusargs("EXTREME_OUTSTANDING")) begin
               read_mode = MODE_EXTREME;
               `uvm_info("AXI3_BFM", "Read mode: EXTREME_OUTSTANDING", apb2axi_verbosity)
          end
          else if ($test$plusargs("LINEAR_OUTSTANDING")) begin
               read_mode = MODE_OUTSTANDING;
               `uvm_info("AXI3_BFM", "Read mode: LINEAR_OUTSTANDING", apb2axi_verbosity)
          end
          else begin
               read_mode = MODE_REGULAR;
               `uvm_info("AXI3_BFM", "Read mode: LINEAR (default)", apb2axi_verbosity)
          end

          // initialize error injection (SAFE DEFAULT)
          foreach (rerr_map[i,j])       rerr_map[i][j]      = AXI_RESP_OKAY;
          foreach (rerr_map_valid[i])   rerr_map_valid[i]   = 1'b0;
          foreach (berr_map[i])         berr_map[i]         = AXI_RESP_OKAY;
          foreach (berr_map_valid[i])   berr_map_valid[i]   = 1'b0;

     endfunction



     // ------------------------------------------------------------
     // Initialize memory with deterministic pattern
     // ------------------------------------------------------------
     task automatic init_mem();
          for (int i = 0; i < MEM_WORDS; i++) begin
               mem[i]         = MEM[i];
               mem_written[i] = 1'b0;
          end
     endtask


     // ------------------------------------------------------------
     // Public API for tests
     // ------------------------------------------------------------
     task automatic inject_read_error(
          input logic [AXI_ID_W-1:0] id,
          input int unsigned         beat_idx,
          input axi_resp_e           resp
     );
          if (id >= ID_NUM)        `uvm_fatal("AXI3_BFM", $sformatf("inject_read_error: id=%0d out of range (ID_NUM=%0d)", id, ID_NUM))
          if (beat_idx >= 256)     `uvm_fatal("AXI3_BFM", $sformatf("inject_read_error: beat_idx=%0d out of range (max 255)", beat_idx))

          rerr_map[id][beat_idx]     = resp;
          rerr_map_valid[id]         = 1'b1;
          `uvm_info("AXI3_BFM", $sformatf("Injecting RRESP=%0d for RID=%0d at beat=%0d", resp, id, beat_idx), apb2axi_verbosity)
     endtask

     task automatic inject_write_error(
          input logic [AXI_ID_W-1:0] id,
          input axi_resp_e           resp
     );
          if (id >= ID_NUM) begin
               `uvm_fatal("AXI3_BFM", $sformatf("inject_write_error: id=%0d out of range (ID_NUM=%0d)", id, ID_NUM))
          end
          berr_map[id]               = resp;
          berr_map_valid[id]         = 1'b1;
          `uvm_info("AXI3_BFM", $sformatf("Injecting BRESP=%0d for BID=%0d (one_shot=%0b)", resp, id, berr_one_shot), apb2axi_verbosity)
     endtask

     task automatic clear_write_error(input logic [AXI_ID_W-1:0] id);
          if (id >= ID_NUM) begin
               `uvm_fatal("AXI3_BFM", $sformatf("clear_write_error: id=%0d out of range (ID_NUM=%0d)", id, ID_NUM))
          end
          berr_map[id]               = AXI_RESP_OKAY;
          berr_map_valid[id]         = 1'b0;
     endtask

     // ------------------------------------------------------------
     // R-channel driver when using outstanding modes
     // ------------------------------------------------------------
     task automatic drive_read_queue();
          int idx;
          active_read_t ar;
          int unsigned nbytes;
          int unsigned byte_off;
          int unsigned abs_byte;
          int unsigned wi;
          int unsigned li;
          logic [AXI_DATA_W-1:0] rdata;
          forever begin
               @(posedge vif.ACLK);
               // No active reads -> wait
               if (active_reads.size() == 0)
                    continue;

               // Scheduling policy
               case (read_mode)
                    MODE_REGULAR:       idx = 0;
                    MODE_OUTSTANDING:  idx = 0;
                    MODE_EXTREME:      idx = $urandom_range(0, active_reads.size()-1);
               endcase

               // Pick a random outstanding burst
               // idx = $urandom_range(0, active_reads.size()-1);
               ar = active_reads[idx];

               // RANDOM latency before issuing the beat (optional)
               repeat ($urandom_range(0,30)) @(posedge vif.ACLK);

               // ======== SEND ONE R BEAT ========
               rdata  = '0;
               nbytes = 1 << ar.size;

               for (int b = 0; b < nbytes; b++) begin
                    longint unsigned a;
                    int unsigned idx;
                    int unsigned byte_off8;
                    byte a_byte;

                    a         = ar.addr + b;        // absolute byte address
                    idx       = addr2idx(a);        // 8-byte-word index (>>3)
                    byte_off8 = a[$clog2(AXI_BYTES)-1:0];             // byte within 64-bit MEM word

                    a_byte = 8'h00;
                    if (idx < MEM_DEPTH)
                         a_byte = mem[idx][8*byte_off8 +: 8];

                    rdata[8*b +: 8] = a_byte;
               end

               `uvm_info("AXI3_BFM", $sformatf("TOOK READ: id=%d, idx=0x%0d rdata=%0h", ar.id, wi, rdata), apb2axi_verbosity)

               vif.RID        <= ar.id;
               vif.RDATA      <= rdata;
               vif.RRESP      <= AXI_RESP_OKAY;
               if ((ar.id < ID_NUM) && rerr_map_valid[ar.id])
                    vif.RRESP <= rerr_map[ar.id][ar.beat_idx];        // Error injection
               vif.RLAST      <= (ar.beats_left == 1);
               vif.RVALID     <= 1'b1;

               `uvm_info("AXI3_BFM", $sformatf("%t BFM_DRIVE_R rid=%0d rlast=%0b rvalid=%0b", $time, ar.id, (ar.beats_left == 1), vif.RVALID), apb2axi_verbosity)

               // Wait for RREADY
               do @(posedge vif.ACLK);
               while (!vif.RREADY && vif.ARESETn);

               vif.RVALID     <= 0;

               beat_order_q.push_back(ar.id);

               if (ar.beats_left == 1) burst_order_q.push_back(ar.id);

               // ======== UPDATE STATE ========
               ar.beats_left--;
               ar.beat_idx++;

               if (ar.burst == 2'b01) begin
                    ar.addr += nbytes;
                    if ((byte_off + nbytes) >= AXI_BYTES)
                    ar.mem_idx++;
               end

               if (ar.beats_left == 0) begin
                    active_reads.delete(idx);
               end else begin
                    active_reads[idx] = ar;
               end
          end
     endtask

     // ------------------------------------------------------------
     // Main BFM process
     // ------------------------------------------------------------
     task run_phase(uvm_phase phase);
          active_read_t arx;

          init_mem();

          // Initialize interface outputs
          vif.ARREADY <= 0;
          vif.AWREADY <= 0;
          vif.WREADY  <= 0;
          vif.RVALID  <= 0;
          vif.RLAST   <= 0;
          vif.RRESP   <= 0;
          vif.BVALID  <= 0;
          vif.BRESP   <= 0;

          wait (vif.ARESETn === 1'b1);
          @(posedge vif.ACLK);

          `uvm_info("AXI3_BFM","BFM is alive and ready", apb2axi_verbosity)

          fork
               drive_read_queue();
          join_none

          forever begin
               @(posedge vif.ACLK);

               // Always ready for address
               if (read_mode == MODE_REGULAR)
                    vif.ARREADY <= (active_reads.size() == 0);   // only accept when empty
               else
                    vif.ARREADY <= 1;
               vif.AWREADY <= 1;

               // Always ready for write data
               vif.WREADY  <= 1;

               // ========= READ ADDRESS =========
               if (vif.ARVALID && vif.ARREADY) begin
                    active_read_t arx;

                    arx.addr       = vif.ARADDR;
                    arx.beats_left = vif.ARLEN + 1;
                    arx.size       = vif.ARSIZE;
                    arx.id         = vif.ARID;
                    arx.burst      = vif.ARBURST;
                    arx.mem_idx    = addr2idx(vif.ARADDR);
                    arx.beat_idx   = 0;

                    case (read_mode)
                         MODE_REGULAR: begin
                              // Allow only one outstanding
                              wait (active_reads.size() == 0);
                              active_reads.push_back(arx);
                         end

                         MODE_OUTSTANDING: begin
                              // Multiple outstanding, but ordered issue
                              active_reads.push_back(arx);
                         end

                         MODE_EXTREME: begin
                              // Same as outstanding, scheduling handled later
                              active_reads.push_back(arx);
                         end
                    endcase

            end

               // ========= WRITE ADDRESS =========
               if (vif.AWVALID && vif.AWREADY) begin
                    active_write_t wx;
                    wx.addr       = vif.AWADDR;
                    wx.beats_left = vif.AWLEN + 1;
                    wx.size       = vif.AWSIZE;
                    wx.id         = vif.AWID;
                    wx.mem_idx    = addr2idx(vif.AWADDR);
                    active_writes.push_back(wx);
               end
               // =========== WRITE DATA ===========
               if (vif.WVALID && vif.WREADY) begin
                    foreach (active_writes[i]) begin
                         if (active_writes[i].id == vif.WID) begin
                              int idx = active_writes[i].mem_idx % MEM_DEPTH;
                              for (int b=0;b<AXI_DATA_W/8;b++)
                                   if (vif.WSTRB[b])
                                        mem[idx][8*b+:8] = vif.WDATA[8*b+:8];
                              mem_written[idx] = 1'b1;

                              active_writes[i].mem_idx++;
                              active_writes[i].beats_left--;

                              if (active_writes[i].beats_left==0) begin
                                   pending_b_ids.push_back(active_writes[i].id);
                                   active_writes.delete(i);
                              end
                              break;
                         end
                    end
               end
               // ========= WRITE RESPONSE =========
               if (!vif.BVALID && pending_b_ids.size()!=0) begin
                    logic [AXI_ID_W-1:0] id;
                    axi_resp_e br;
                    id = pending_b_ids.pop_front();
                    br = AXI_RESP_OKAY;
                    if (id < ID_NUM && berr_map_valid[id]) begin
                         br = berr_map[id];
                         if (berr_one_shot) begin
                              berr_map_valid[id] = 1'b0; // auto-clear after first use
                              berr_map[id]       = AXI_RESP_OKAY;
                         end
                    end
                    vif.BID    <= id;
                    vif.BRESP  <= br;
                    vif.BVALID <= 1'b1;
               end
               else if (vif.BVALID && vif.BREADY) begin
                    vif.BVALID <= 0;
               end
          end

     endtask


     // ------------------------------------------------------------
     // WRITE handler (multi-beat) + WSTRB support
     // ------------------------------------------------------------
     task automatic do_write(
          logic [AXI_ADDR_W-1:0] awaddr,
          logic [3:0]            awlen,
          logic [2:0]            awsize,
          logic [AXI_ID_W-1:0]   awid
     );
          int beats = awlen + 1;
          int base_word = awaddr >> $clog2(AXI_DATA_W/8);
          int idx; 

          axi_resp_e br;

          `uvm_info("AXI3_BFM",
               $sformatf("WRITE: addr=0x%0h beats=%0d size=%0d id=%0d",
                         awaddr, beats, awsize, awid),
               UVM_MEDIUM)

          for (int i = 0; i < beats; i++) begin
               // Wait for W beat
               do @(posedge vif.ACLK);
               while (!vif.WVALID && vif.ARESETn);

               idx = (base_word + i) % MEM_DEPTH;

               // ---------- BYTE-WISE write using WSTRB ----------
               for (int b = 0; b < (AXI_DATA_W/8); b++) begin
                    if (vif.WSTRB[b])
                         mem[idx][8*b +: 8] = vif.WDATA[8*b +: 8];
               end

               // Check WLAST correctness
               if ((i == beats-1) && !vif.WLAST)
                    `uvm_error("AXI3_BFM","WLAST missing in final beat")
               if ((i != beats-1) && vif.WLAST)
                    `uvm_error("AXI3_BFM","WLAST asserted too early")
          end

          // Send BRESP after all beats
          @(posedge vif.ACLK);
          br = AXI_RESP_OKAY;
          if (awid < ID_NUM && berr_map_valid[awid]) begin
               br = berr_map[awid];
               if (berr_one_shot) begin
                    berr_map_valid[awid] = 1'b0;
                    berr_map[awid]       = AXI_RESP_OKAY;
               end
          end
          vif.BID    <= awid;
          vif.BRESP  <= br[1:0];
          vif.BVALID <= 1;

          // Wait for BREADY
          do @(posedge vif.ACLK);
          while (!vif.BREADY && vif.ARESETn);

          vif.BVALID <= 0;
    endtask

     function void report_phase(uvm_phase phase);
          string s;
          int fd;
          string fname = "axi_memory_dump.hex";

          fd = $fopen(fname, "w");
          if (!fd) begin
               `uvm_error("AXI3_BFM", "Failed to open memory dump file")
               return;
          end

          for (int i = 0; i < MEM_WORDS; i++) begin
               $fwrite(fd,
               "IDX %4d  ADDR 0x%016h  DATA 0x%016h  %s\n",
               i,
               MEM_BASE_ADDR + i*(AXI_DATA_W/8),
               mem[i],
               mem_written[i] ? "WRITTEN" : "INIT");
          end

          $fclose(fd);

          `uvm_info("AXI3_BFM", $sformatf("Full AXI memory dumped to %s", fname), UVM_LOW)

          if (burst_order_q.size() > 0) begin
               s = "{";
               foreach (burst_order_q[i]) begin
                    if (i) s = {s, ", "};
                    s = {s, $sformatf("%0d", burst_order_q[i])};
                    // or "%0h" if you prefer hex
               end
               s = {s, "}"};
               `uvm_info("AXI3_BFM", $sformatf("Burst completion RID order = %s", s), apb2axi_verbosity)
          end

          if (beat_order_q.size() > 0) begin
               s = "{";
               foreach (beat_order_q[i]) begin
                    if (i) s = {s, ", "};
                    s = {s, $sformatf("%0d", beat_order_q[i])};
               end
               s = {s, "}"};
               `uvm_info("AXI3_BFM", $sformatf("Beat-level RID order   = %s", s), apb2axi_verbosity)
          end
     endfunction


function automatic bit peek_word64(input logic [63:0] addr,
                                   output logic [AXI_DATA_W-1:0] data);
  int unsigned idx;
  idx = addr2idx(addr);

  if (idx >= MEM_DEPTH) begin
    data = '0;
    return 0;
  end

  data = mem[idx];
  return 1;
endfunction

task automatic dump_mem_to_file(string fname);
  int fd;
  fd = $fopen(fname, "w");
  if (fd == 0) begin
    `uvm_error("AXI3_BFM", $sformatf("Failed to open %s", fname))
    return;
  end

  for (int i = 0; i < MEM_DEPTH; i++) begin
    $fwrite(fd, "IDX %0d ADDR 0x%016h DATA 0x%0h\n",
            i, (MEM_BASE_ADDR + (i*(AXI_DATA_W/8))), mem[i]);
  end
  $fclose(fd);
  `uvm_info("AXI3_BFM", $sformatf("Dumped memory to %s", fname), UVM_LOW)
endtask

endclass