/*------------------------------------------------------------------------------
 * File          : apb2axi_wr_packer.sv
 * Project       : APB2AXI
 * Author        : Nir Miller & Ido Oreg
 * Description   : - Accumulates APB write words (per TAG) into full AXI WDATA beats
 *                 - Stages completed beats through a single-entry ready/valid buffer
 *                 - Forwards packed write data to the AXI write-data FIFO
 *------------------------------------------------------------------------------*/
 
import apb2axi_pkg::*;

module apb2axi_wr_packer #()(
     input  logic                                pclk,
     input  logic                                presetn,

     // From apb2axi_reg (per-tag write window)
     input  logic                                wr_word_valid,
     input  logic [TAG_W-1:0]                    wr_word_tag,
     input  logic [APB_DATA_W-1:0]               wr_word_data,

     // To write-data FIFO (single stream of ready AXI beats)
     output logic                                wdf_pop_vld,
     output logic [DATA_ENTRY_W-1:0]             wdf_pop_payload,
     input  logic                                wdf_pop_rdy
);

     // ----------------------------------------------------------------
     // Per-TAG pack state: accumulate APB words into one AXI beat
     // ----------------------------------------------------------------
     logic [AXI_DATA_W-1:0]                       pack_data [TAG_NUM];
     logic [$clog2(APB_WORDS_PER_AXI_BEAT+1)-1:0] pack_cnt  [TAG_NUM];

     logic                                        out_hold;
     wr_entry_t                                   out_ent;

     assign wdf_pop_vld                           = out_hold;
     assign wdf_pop_payload                       = out_ent;

     always_ff @(posedge pclk) begin
          if (!presetn) begin
               for (int t = 0; t < TAG_NUM; t++) begin
                    pack_data[t]                  <= '0;
                    pack_cnt[t]                   <= '0;
               end
               out_hold                           <= 1'b0;
               out_ent                            <= '0;
          end else begin
               // -----------------------------------------
               // If FIFO accepted our staged beat, clear hold
               // -----------------------------------------
               if (out_hold && wdf_pop_rdy) begin
                    out_hold                      <= 1'b0;
               end

               // -----------------------------------------
               // Accept one incoming APB word (if any)
               // If a beat completes, stage it for FIFO push.
               // -----------------------------------------
               if (wr_word_valid) begin
                    int tg;
                    int bit_idx;
                    tg                            = wr_word_tag;
                    bit_idx                       = pack_cnt[tg] * APB_DATA_W;

                    if (!out_hold) begin
                         pack_data[tg][bit_idx +: APB_DATA_W] <= wr_word_data;   // store this word into pack buffer

                         if (pack_cnt[tg] == APB_WORDS_PER_AXI_BEAT-1) begin
                              wr_entry_t ent;                                   // completed a full AXI beat -> stage output
                              ent.tag             = tg[TAG_W-1:0];
                              ent.last            = 1'b0;                       // builder computes true last via LEN tracking
                              ent.wstrb           = '1;                         // Option-1 for now
                              ent.data            = pack_data[tg];
                              ent.data[bit_idx +: APB_DATA_W] = wr_word_data;   // ensure current word included

                              out_ent             <= ent;
                              out_hold            <= 1'b1;
                              
                              pack_cnt[tg]        <= '0;                        // reset packer for this tag
                              pack_data[tg]       <= '0;
                         end
                         else begin
                              pack_cnt[tg]        <= pack_cnt[tg] + 1'b1;
                         end
                    end
               end
          end
     end

endmodule