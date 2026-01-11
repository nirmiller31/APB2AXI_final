# ==========================================================
#  APB2AXI UVM Testbench Filelist
# ==========================================================

# === Global timescale ===
// $PROJECT_HOME/tb/global_timescale.svh    # attemt
-timescale=1ns/1ps

# === Include Directories ===
+incdir+$UVM_HOME
+incdir+$PROJECT_HOME/design
+incdir+$PROJECT_HOME/tb
+incdir+$PROJECT_HOME/tb/pkg
+incdir+$PROJECT_HOME/tb/if
+incdir+$PROJECT_HOME/tb/env
+incdir+$PROJECT_HOME/tb/agent
+incdir+$PROJECT_HOME/tb/seq
+incdir+$PROJECT_HOME/tb/seq_item
+incdir+$PROJECT_HOME/tb/tests

// -------------------------
// DesignWare (simulation models)
// -------------------------
// /eda/synopsys/2024-25/RHELx86/SYN_2024.09-SP2/dw/sim_ver/DW_fifo_s1_sf.v
// /eda/synopsys/2024-25/RHELx86/SYN_2024.09-SP2/dw/sim_ver/DW_fifoctl_s1_sf.v
// /eda/synopsys/2024-25/RHELx86/SYN_2024.09-SP2/dw/sim_ver/DW_ram_r_w_s_dff.v
// /eda/synopsys/2024-25/RHELx86/SYN_2024.09-SP2/dw/sim_ver/DW_fifo_2c_df.v
// /eda/synopsys/2024-25/RHELx86/SYN_2024.09-SP2/dw/sim_ver/DW_fifoctl_2c_df.v
// /eda/synopsys/2024-25/RHELx86/SYN_2024.09-SP2/dw/sim_ver/DW_ram_r_w_2c_dff.v
// DesignWare: make VCS search this directory for missing modules
-y /eda/synopsys/2024-25/RHELx86/SYN_2024.09-SP2/dw/sim_ver
+libext+.v

// DesignWare .inc include files (needed by some DW modules)
+incdir+/eda/synopsys/2024-25/RHELx86/SYN_2024.09-SP2/dw/sim_ver
+incdir+/eda/synopsys/2024-25/RHELx86/SYN_2024.09-SP2/dw/include
+incdir+/eda/synopsys/2024-25/RHELx86/SYN_2024.09-SP2/dw/sim_ver/include
# ============================================================
# RTL / Design files
# ============================================================
$PROJECT_HOME/design/apb2axi_pkg.sv
$PROJECT_HOME/design/if/apb_if.sv
$PROJECT_HOME/design/if/axi_if.sv
$PROJECT_HOME/design/gateway/apb2axi_reg.sv
$PROJECT_HOME/design/gateway/apb2axi_directory.sv
$PROJECT_HOME/design/apb2axi_wr_packer.sv
$PROJECT_HOME/design/apb2axi_fifo.sv
$PROJECT_HOME/design/apb2axi_fifo_async.sv
$PROJECT_HOME/design/builder/apb2axi_write_builder.sv
$PROJECT_HOME/design/builder/apb2axi_read_builder.sv
$PROJECT_HOME/design/response/apb2axi_response_collector.sv
$PROJECT_HOME/design/response/apb2axi_response_handler.sv
// $PROJECT_HOME/design/response/apb2axi_rdf.sv
$PROJECT_HOME/design/apb2axi_txn_mgr.sv
$PROJECT_HOME/design/apb2axi.sv

# === Interfaces ===
// $PROJECT_HOME/tb/if/apb_if.sv      # bringup used
// $PROJECT_HOME/tb/if/axi_if.sv      # bringup used

# === Test-Bench Package ===
$PROJECT_HOME/tb/bfm/apb2axi_memory_pkg.sv
$PROJECT_HOME/tb/pkg/apb2axi_tb_pkg.sv

# === Bringup DUT ===         to be later commented
// $PROJECT_HOME/bringup_design/apb2axi.sv

# === Top ===
$PROJECT_HOME/tb/tb_top.sv


