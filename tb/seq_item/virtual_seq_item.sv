
class virtual_seq_item extends uvm_sequence_item;

     `uvm_object_utils(virtual_seq_item)

     apb_seq_item                       apb_item;
     axi_seq_item                       axi_item;

     function new(string name = "virtual_seq_item");
          super.new(name);
     endfunction

     function string convert2string();
          string s;
          s = {
               "VIRTUAL_ITEM: \n",
               (apb_item ? apb_item.convert2string() : "APB=null"), "\n",
               (axi_item ? axi_item.convert2string() : "AXI=null"), "\n"
          };
          return s;
     endfunction

endclass