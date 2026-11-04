// Compile order does not matter for the modules, but the include directory
// must be on the search path because every file pulls in vector_mask_ops.svh
// at $unit scope.
+incdir+.

// ---- RTL ----
mask_logic.sv
mask_scan.sv
mask_count.sv
mask_prefix.sv
mask_fu.sv
mask_unit_top.sv

// ---- testbench (drop this line for synthesis / lint of RTL only) ----
mask_unit_tb.sv
