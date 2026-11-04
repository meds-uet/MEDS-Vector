`include "vector_mask_ops.svh"

module mask_fu (

    input  logic [ELEN-1:0]        vs1_element_mask,

    input  logic [ELEN-1:0]        vs2_element_mask,

    input  logic [ELEN-1:0]        v0_element_mask,

    input  logic                   vm,

    input  logic [MASK_OP_W-1:0]   mask_op,

    input  logic [COUNT_WIDTH-1:0] element_base,

    input  logic                   found_in,      // from the top-level mask_prefix tree, not a neighbor FU

    input  logic [COUNT_WIDTH-1:0] count_in,      // from the top-level mask_prefix tree, not a neighbor FU

    output logic                   found_local,

    output logic [IDX_W-1:0]       element_index,

    output logic [COUNT_WIDTH-1:0] count_local,   // this slice's own popcount, independent of count_in

    output logic [ELEN-1:0]        result_element_mask,

    output logic [ELEN-1:0][COUNT_WIDTH-1:0] result_element_count

);

    logic [ELEN-1:0] logic_element_mask;

    logic [ELEN-1:0] scan_element_mask;

    logic            is_vid;

    always_comb begin

        is_vid = (mask_op == MASK_OP_VID);

    end

// ---- 15.1 mask-register logical -----------------------------------------

    mask_logic u_mask_logic (

        .vs1_element_mask    (vs1_element_mask),

        .vs2_element_mask    (vs2_element_mask),

        .mask_op             (mask_op),

        .result_element_mask (logic_element_mask)

    );

// ---- 15.3 / 15.4 / 15.5 / 15.6 first-set-bit scan -----------------------

    mask_scan u_mask_scan (

        .vs2_element_mask    (vs2_element_mask),

        .v0_element_mask     (v0_element_mask),

        .vm                  (vm),

        .mask_op             (mask_op),

        .found_in            (found_in),

        .found_local         (found_local),

        .element_index       (element_index),

        .result_element_mask (scan_element_mask)

    );

// ---- 15.2 / 15.8 / 15.9 popcount, iota, id ------------------------------

    mask_count u_mask_count (

        .vs2_element_mask     (vs2_element_mask),

        .v0_element_mask      (v0_element_mask),

        .vm                   (vm),

        .is_vid               (is_vid),

        .element_base         (element_base),

        .count_in             (count_in),

        .count_local          (count_local),

        .result_element_count (result_element_count)

    );

// ---- select the block that drives the mask result -----------------------

    always_comb begin

        if (mask_op_is_logic(mask_op))

            result_element_mask = logic_element_mask;

        else

            result_element_mask = scan_element_mask;

    end

endmodule
