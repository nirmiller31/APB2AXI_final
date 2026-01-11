
class apb_seq_item extends uvm_sequence_item;

     `uvm_object_utils(apb_seq_item)

     rand bit [`APB_ADDR_WIDTH-1 : 0]   addr;
     rand bit [`APB_DATA_WIDTH-1 : 0]   data;
     rand bit                           write;         // write=1, read=0
     bit                                slverr;

     function new(string name = "apb_seq_item");
          super.new(name);
     endfunction

     function string convert2string();
          return $sformatf("APB_SEQUENCE_ITEM: addr=0x%0h, data=0x%0h, type=%s, slverr=%0b", addr, data, write ? "WRITE" : "READ", slverr);
     endfunction

endclass