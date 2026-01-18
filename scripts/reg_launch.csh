#!/bin/tcsh

# ============================================================
# APB2AXI Regression Environment Setup
# ============================================================

# ---------------------------
# Default regression knobs
# ---------------------------
if (! $?TEST_SET)        setenv TEST_SET all
if (! $?SEED_MODE)       setenv SEED_MODE rand
if (! $?SEED_COUNT)      setenv SEED_COUNT 1
if (! $?SEED_START)      setenv SEED_START 777225
if (! $?JOBS)            setenv JOBS 1
if (! $?UVM_TESTNAME)    setenv UVM_TESTNAME apb2axi_test

# Random seed range (only used when SEED_MODE=rand)
if (! $?SEED_RAND_MIN)   setenv SEED_RAND_MIN 1
if (! $?SEED_RAND_MAX)   setenv SEED_RAND_MAX 2147483647

# ---------------------------
# Info banner (debug-friendly)
# ---------------------------
echo "[INFO] APB2AXI Regression Environment"
echo "  PROJECT_HOME = $PROJECT_HOME"
echo "  BUILD_DIR    = $BUILD_DIR"
echo "  TEST_SET     = $TEST_SET"
echo "  SEED_MODE    = $SEED_MODE"
echo "  SEED_COUNT   = $SEED_COUNT"
echo "  JOBS         = $JOBS"
echo "  UVM_TESTNAME = $UVM_TESTNAME"
echo

# ---------------------------
# Dispatch to bash launcher
# ---------------------------
# ---------------------------
# Force PROJECT_HOME based on this script's location (tcsh-safe)
# ---------------------------
set script_dir = "$0:h"
if ("$script_dir" == "$0") then
  # If $0 has no '/', assume current directory
  set script_dir = "."
endif

set script_dir = `cd "$script_dir" && pwd`
set proj_dir   = `cd "$script_dir/.." && pwd`

setenv PROJECT_HOME "$proj_dir"
echo "[INFO] Forced PROJECT_HOME = $PROJECT_HOME"

# Dispatch to the bash launcher from the same tree
exec bash "$PROJECT_HOME/scripts/reg_launch.sh"