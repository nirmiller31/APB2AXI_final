
class axi_seq_item extends uvm_sequence_item;

     `uvm_object_utils(axi_seq_item)

     rand bit [`AXI_ADDR_WIDTH-1 : 0]   addr;
     rand bit [`AXI_DATA_WIDTH-1 : 0]   data;
     rand bit                           write;         // write=1, read=0
     bit [1:0]                          resp;          // AXI response (OKAY, EXOKAY, SLVERR, DECERR)
     rand bit [3:0]                     id;            // AXI ID
     rand bit [7:0]                     len;           // Burst Length
     rand bit [2:0]                     size;          // Transfer Size
     rand bit [1:0]                     burst;         // Burst Type (FIXED, INCR, WRAP)

     function new(string name = "axi_seq_item");
          super.new(name);
     endfunction

     function string convert2string();
          return $sformatf("AXI_SEQUENCE_ITEM: axi_id=%0d, addr=0x%0h, data=0x%0h, type=%s, resp=%0b", id, addr, data, write ? "WRITE" : "READ", resp);
     endfunction

endclass