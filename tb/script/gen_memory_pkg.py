#!/usr/bin/env python3
import random
from textwrap import indent

# === CONFIG ===
MEMORY_SIZE   = 2048          # how many AXI beats
AXI_DATA_W    = 64           # must match your RTL (64/128/256…)
MEM_BASE_ADDR = 0x0000000000001000  # where your test memory starts
SEED          = 0x1234       # for reproducibility, change or remove

random.seed(SEED)

def hex_literal(value, width_bits):
    hex_width = (width_bits + 3) // 4
    return f"{value:0{hex_width}X}"

def main():
    bytes_per_beat = AXI_DATA_W // 8
    hex_width_data = (AXI_DATA_W + 3) // 4
    hex_width_addr = 16  # 64-bit address printing

    lines = []
    lines.append("// ---------------------------------------------------------------------------------------------------------")
    lines.append("// AUTO-GENERATED FILE, PLEASE KEEP IT THAT WAY")
    lines.append("// Run Command: (from Project) python3 tb/script/gen_memory_pkg.py > tb/bfm/apb2axi_memory_pkg.sv ")
    lines.append("// ---------------------------------------------------------------------------------------------------------")
    lines.append("")
    lines.append("package apb2axi_memory_pkg;")
    lines.append("")
    lines.append(f"  import apb2axi_pkg::*;")
    lines.append("")
    lines.append(f"  parameter int MEM_WORDS       = {MEMORY_SIZE};")
    lines.append(f"  parameter logic [63:0] MEM_BASE_ADDR = 64'h{hex_literal(MEM_BASE_ADDR, 64)};")
    lines.append("")
    lines.append("  localparam int BYTES_PER_BEAT = AXI_DATA_W/8;")
    lines.append("")
    lines.append("  typedef logic [AXI_DATA_W-1:0] mem_word_t;")
    lines.append("")
    lines.append("  function automatic int unsigned addr2idx (logic [63:0] a);")
    lines.append("    addr2idx = (a - MEM_BASE_ADDR) >> $clog2(BYTES_PER_BEAT);")
    lines.append("  endfunction")
    lines.append("")
    lines.append("  const mem_word_t MEM [0:MEM_WORDS-1] = '{")

    # Generate memory contents
    for i in range(MEMORY_SIZE):
        addr  = MEM_BASE_ADDR + i * bytes_per_beat
        value = random.getrandbits(AXI_DATA_W)

        value_str = hex_literal(value, AXI_DATA_W)
        addr_str  = hex_literal(addr, 64)
        comma     = "," if i != MEMORY_SIZE - 1 else ""

        # SINGLE LINE OUTPUT:
        lines.append(
            f"    {AXI_DATA_W}'h{value_str}{comma}   // idx {i:3d}  addr=64'h{addr_str}"
        )

    lines.append("  };")
    lines.append("endpackage : apb2axi_memory_pkg")

    print("\n".join(lines))

if __name__ == "__main__":
    main()