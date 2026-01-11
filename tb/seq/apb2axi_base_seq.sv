import uvm_pkg::*;
`include "uvm_macros.svh"
import apb2axi_pkg::*;

class apb2axi_base_seq extends uvm_sequence #(apb_seq_item);
     `uvm_object_utils(apb2axi_base_seq)

     // ------------------------------------------------
     // Common address constraints (aligned to your memory map)
     // ------------------------------------------------
     localparam longint unsigned AXI_ADDR_MIN = 64'h0000_0000_0000_1000;
     localparam longint unsigned AXI_ADDR_MAX = 64'h0000_0000_0000_17F8;

     apb2axi_env m_env;

     // ------------------------------------------------
     // Construction
     // ------------------------------------------------
     function new(string name="apb2axi_base_seq");
          super.new(name);
     endfunction

     task automatic peek_axi_word64(
          input  bit [AXI_ADDR_W-1:0]   addr,
          output bit [AXI_DATA_W-1:0]   data,
          output bit                    ok
     );
          ok = m_env.axi_bfm.peek_word64(addr, data);
     endtask

     // =================================================
     // Low-level APB access
     // =================================================
     task automatic apb_write(bit [APB_ADDR_W-1:0] addr, bit [APB_DATA_W-1:0] data);
          apb_seq_item req    = apb_seq_item::type_id::create("req");
          start_item(req);
          req.addr            = addr;
          req.write           = 1'b1;
          req.data            = data;
          finish_item(req);
     endtask

     task automatic apb_read(bit [APB_ADDR_W-1:0] addr, output bit [APB_DATA_W-1:0] data, output bit slverr);
          apb_seq_item req    = apb_seq_item::type_id::create("req");
          start_item(req);
          req.addr            = addr;
          req.write           = 1'b0;
          finish_item(req);
          data                = req.data;
          slverr              = req.slverr;
     endtask

     // =================================================
     // Directory programming helpers
     // =================================================
     task automatic program_addr(bit [AXI_ADDR_W-1:0] addr);
          apb_write(REG_ADDR_ADDR_HI, addr[63:32]);
          apb_write(REG_ADDR_ADDR_LO, addr[31:0]);
     endtask

     task automatic program_cmd(bit is_write, bit [AXI_SIZE_W-1:0] size, bit [AXI_LEN_W-1:0] len);
          bit [APB_REG_W-1:0] cmd;

          cmd                                          = '0;
          cmd[DIR_ENTRY_ISWRITE_HI]                    = is_write;
          cmd[DIR_ENTRY_SIZE_HI : DIR_ENTRY_SIZE_LO]   = size;
          cmd[DIR_ENTRY_LEN_HI : DIR_ENTRY_LEN_LO]     = len;

          apb_write(REG_ADDR_CMD, cmd);
     endtask

     task automatic program_write_cmd(bit [AXI_LEN_W-1:0] len);
          program_cmd(1'b1, $clog2(AXI_DATA_W/8), len);
     endtask

     task automatic program_read_cmd(bit [AXI_LEN_W-1:0] len, bit [AXI_SIZE_W-1:0] size = $clog2(AXI_DATA_W/8));
          program_cmd(1'b0, size, len);
     endtask

     // =================================================
     // Common math helpers
     // =================================================
     function automatic int axi_beats_from_len(bit [AXI_LEN_W-1:0] len);
          return int'(len) + 1;
     endfunction

     function automatic int apb_words_per_axi_beat();
          return APB_WORDS_PER_AXI_BEAT;
     endfunction

     function automatic int unsigned apb_words_per_beat_from_size(bit [AXI_SIZE_W-1:0] size);
          int unsigned bytes_per_beat;
          bytes_per_beat = (1 << int'(size));
          return (bytes_per_beat + (APB_DATA_W/8) - 1) / (APB_DATA_W/8);
     endfunction

     function automatic bit [AXI_ADDR_W-1:0] rand_addr_in_range_aligned();
          bit [AXI_ADDR_W-1:0] address;

          if (!std::randomize(address) with {
               address inside {[64'h0000_0000_0000_1000 : 64'h0000_0000_0000_4FF8]};
               address[2:0] == 3'b000;                 // 8-byte aligned
               // address[3:0] == 4'b0000;                 // 16-byte aligned (for AXI_DATA_W=128)
          }) begin
               `uvm_fatal("ADDR_RAND", "std::randomize() failed for rand_addr_in_range_aligned()")
          end

          return address;
     endfunction

     function automatic bit ranges_overlap(bit [AXI_ADDR_W-1:0] a0,
                                        int unsigned bytes0,
                                        bit [AXI_ADDR_W-1:0] a1,
                                        int unsigned bytes1);
          bit [AXI_ADDR_W-1:0] e0, e1;
          e0 = a0 + bytes0 - 1;
          e1 = a1 + bytes1 - 1;
          return !(e0 < a1 || e1 < a0);
     endfunction

     function automatic bit [AXI_ADDR_W-1:0] pick_non_overlapping_addr(
          input int unsigned idx,
          input bit [AXI_LEN_W-1:0] len,
          inout bit [AXI_ADDR_W-1:0] addrs[],
          inout int unsigned         bytes[]);
          bit [AXI_ADDR_W-1:0] a;
          bit ok;
          int unsigned b;
          int tries;

          b = (axi_beats_from_len(len) * (AXI_DATA_W/8));

          tries = 0;
          do begin
               a = rand_addr_in_range_aligned();
               tries++;
               ok = 1;
               for (int j = 0; j < idx; j++) begin
                    if (ranges_overlap(a, b, addrs[j], bytes[j])) begin
                              ok = 0;
                              break;
                    end
               end
               if (ok) begin
                    addrs[idx] = a;
                    bytes[idx] = b;
                    return a;
               end
          end while (tries < 2000);

          `uvm_fatal("ADDR_PICK", $sformatf("Failed to pick non-overlapping addr for idx=%0d bytes=%0d", idx, b))
          return '0;
     endfunction

     // =================================================
     // TAG window address helpers (base + tag*stride)
     // =================================================
     function automatic bit [APB_ADDR_W-1:0] tag_win_addr(bit [APB_ADDR_W-1:0] base, bit [TAG_W-1:0] tag);
          bit [APB_ADDR_W-1:0] result;
          result = base + (int'(tag) * TAG_STRIDE_BYTES);
          return result;
     endfunction

     // =================================================
     // Response policy helpers
     // =================================================
     task automatic program_resp_policy_worst();
          bit [APB_DATA_W-1:0] rd;
          bit                  slverr;

          // Write 1 -> resp_policy_cfg (LSB)
          apb_write(REG_RESP_POLICY, 32'h1);

          // Optional sanity readback (keeps debug easy)
          apb_read(REG_RESP_POLICY, rd, slverr);
          if (slverr) begin
               `uvm_fatal(get_name(), "RESP_POLICY readback PSLVERR")
          end
          if (rd[0] !== 1'b1) begin
               `uvm_fatal(get_name(), $sformatf("RESP_POLICY readback mismatch: got 0x%08h (expected LSB=1)", rd))
          end
     endtask

     // =================================================
     // Write data helpers
     // =================================================
     task automatic push_wr_apb_word(bit [TAG_W-1:0] tag, bit [APB_DATA_W-1:0] data);
          apb_write(tag_win_addr(REG_ADDR_WR_DATA, tag), data);
     endtask

     task automatic push_wr_beat(bit [TAG_W-1:0] tag, bit [APB_DATA_W-1:0] words[]);
          foreach (words[i]) begin
               push_wr_apb_word(tag, words[i]);
          end
     endtask

     // =================================================
     // Read data helpers
     // =================================================
     task automatic pop_rd_apb_word(bit [TAG_W-1:0] tag, output bit [APB_DATA_W-1:0] data, output bit slverr);
          apb_read(tag_win_addr(REG_ADDR_RD_DATA, tag), data, slverr);
     endtask

     function automatic logic [AXI_DATA_W-1:0] pack_beat_from_apb_words(bit [APB_DATA_W-1:0] lo, bit [APB_DATA_W-1:0] hi);
          return {hi, lo};
     endfunction

     // =================================================
     // Completion & status helpers
     // =================================================
     task automatic read_status(bit [TAG_W-1:0] tag,
                               output bit done,
                               output bit error,
                               output bit [1:0] resp,
                               output bit [7:0] num_beats);
          bit [APB_REG_W-1:0] sts;
          bit                 slverr;

          apb_read(tag_win_addr(REG_ADDR_RD_STATUS, tag), sts, slverr);

          done                                         = sts[15];
          error                                        = sts[14];
          resp                                         = sts[13:12];
          num_beats                                    = sts[7:0];
     endtask

     task automatic wait_completion(bit [TAG_W-1:0] tag, int timeout = 500);
          bit done, error;
          bit [1:0] resp;
          bit [7:0] num_beats;

          repeat (timeout) begin
               read_status(tag, done, error, resp, num_beats);
               if (done || error) begin
                    if (error) `uvm_fatal(get_name(), $sformatf("TAG %0d ERROR resp=%0d", tag, resp))
                    return;
               end
               #50;
          end

          `uvm_fatal(get_name(), $sformatf("TAG %0d TIMEOUT waiting for completion", tag))
     endtask

endclass