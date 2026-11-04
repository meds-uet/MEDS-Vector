`include "vector_mask_ops.svh"

module mask_unit_top (

    input  logic [VLEN-1:0]      vs1_mask,   // vs1, one bit per element

    input  logic [VLEN-1:0]      vs2_mask,   // vs2, one bit per element

    input  logic [VLEN-1:0]      v0_mask,    // v0 body mask

    input  logic                 vm,         // 1 = unmasked, 0 = use v0.t

    input  logic [MASK_OP_W-1:0] mask_op,

    output logic [VLEN-1:0]                  result_mask,          // -> vd

    output logic [XLEN-1:0]                  result_scalar,        // -> x[rd]

    output logic [VLEN-1:0][COUNT_WIDTH-1:0] result_element_count, // -> vd elements

    output logic                             result_mask_valid,

    output logic                             result_scalar_valid,

    output logic                             result_count_valid

);

// -------------------------------------------------------------------------
// Per-slice signals
//
// fu_found_local[f] / fu_count_local[f] are each slice's OWN result and
// depend only on that slice's own vs1/vs2/v0 bits -- every slice computes
// them at the same time, nothing is chained in.
//
// fu_found_in[f] / fu_count_in[f] are "everything before slice f", supplied
// by the mask_prefix networks below in O(log NUM_FU) levels instead of a
// NUM_FU-deep ripple.
// -------------------------------------------------------------------------

    logic [0:0]             fu_found_local [NUM_FU];

    logic                   fu_found_in    [NUM_FU];

    logic [IDX_W-1:0]       fu_element_idx [NUM_FU];

    logic [COUNT_WIDTH-1:0] fu_count_local [NUM_FU];

    logic [COUNT_WIDTH-1:0] fu_count_in    [NUM_FU];

    logic [ELEN-1:0]        fu_result_mask [NUM_FU];

    logic [ELEN-1:0][COUNT_WIDTH-1:0] fu_result_count [NUM_FU];

    logic [0:0]             found_excl_prefix [NUM_FU];

    logic [0:0]             found_total;

    logic [COUNT_WIDTH-1:0] count_excl_prefix [NUM_FU];

    logic [COUNT_WIDTH-1:0] count_total;

    logic             first_found;

    logic [FU_W-1:0]  first_fu;

    logic [IDX_W-1:0] first_index;

// -------------------------------------------------------------------------
// Check the geometry from the header during simulation
// -------------------------------------------------------------------------

    initial begin

        if (VLEN % ELEN != 0)

            $fatal(1, "mask_unit_top: VLEN(%0d) must be a multiple of ELEN(%0d)", VLEN, ELEN);

        if (ELEN % GROUP_W != 0)

            $fatal(1, "mask_unit_top: ELEN(%0d) must be a multiple of GROUP_W(%0d)", ELEN, GROUP_W);

        if (GRP_W + BIT_W != IDX_W)

            $fatal(1, "mask_unit_top: GRP_W(%0d)+BIT_W(%0d) must equal IDX_W(%0d)", GRP_W, BIT_W, IDX_W);

        if (COUNT_WIDTH < $clog2(VLEN + 1))

            $fatal(1, "mask_unit_top: COUNT_WIDTH(%0d) cannot hold a count of VLEN(%0d)", COUNT_WIDTH, VLEN);

        if (XLEN < FU_W + IDX_W)

            $fatal(1, "mask_unit_top: XLEN(%0d) cannot hold an element index", XLEN);

    end

// -------------------------------------------------------------------------
// Cross-slice "found" and "count" networks
//
// These replace the old fu_found_out[f-1] -> fu_found_in[f] and
// fu_count_out[f-1] -> fu_count_in[f] ripple: every slice's found_in/count_in
// now comes from a shared O(log NUM_FU)-deep tree fed by ALL slices' local
// results at once, instead of waiting on its immediate neighbor.
// -------------------------------------------------------------------------

    mask_prefix #(

        .N      (NUM_FU),

        .W      (1),

        .IS_ADD (1'b0)

    ) u_found_prefix (

        .in          (fu_found_local),

        .excl_prefix (found_excl_prefix),

        .total       (found_total)

    );

    mask_prefix #(

        .N      (NUM_FU),

        .W      (COUNT_WIDTH),

        .IS_ADD (1'b1)

    ) u_count_prefix (

        .in          (fu_count_local),

        .excl_prefix (count_excl_prefix),

        .total       (count_total)

    );

    for (genvar f = 0; f < NUM_FU; f++) begin : g_prefix_unpack

        assign fu_found_in[f] = found_excl_prefix[f][0];

        assign fu_count_in[f] = count_excl_prefix[f];

    end

// -------------------------------------------------------------------------
// Instantiate the mask slices -- fully independent of each other now; each
// one only waits on the two prefix trees above, never on a neighbor slice.
// -------------------------------------------------------------------------

    for (genvar f = 0; f < NUM_FU; f++) begin : g_mask_fu

        mask_fu u_mask_fu (

            .vs1_element_mask     (vs1_mask[f*ELEN +: ELEN]),

            .vs2_element_mask     (vs2_mask[f*ELEN +: ELEN]),

            .v0_element_mask      (v0_mask [f*ELEN +: ELEN]),

            .vm                   (vm),

            .mask_op              (mask_op),

            .element_base         (COUNT_WIDTH'(f*ELEN)),

            .found_in             (fu_found_in[f]),

            .count_in             (fu_count_in[f]),

            .found_local          (fu_found_local[f][0]),

            .element_index        (fu_element_idx[f]),

            .count_local          (fu_count_local[f]),

            .result_element_mask  (fu_result_mask[f]),

            .result_element_count (fu_result_count[f])

        );

    end

// -------------------------------------------------------------------------
// Merge the mask results
// -------------------------------------------------------------------------

    always_comb begin

        result_mask = '0;

        for (int f = 0; f < NUM_FU; f++) begin

            result_mask[f*ELEN +: ELEN] = fu_result_mask[f];

        end

    end

// -------------------------------------------------------------------------
// Merge the per-element count results
// -------------------------------------------------------------------------

    always_comb begin

        result_element_count = '0;

        for (int f = 0; f < NUM_FU; f++) begin

            for (int i = 0; i < ELEN; i++) begin

                result_element_count[f*ELEN + i] = fu_result_count[f][i];

            end

        end

    end

// -------------------------------------------------------------------------
// Find which slice contains the first set bit
//
// Old version: a for-loop that overwrote first_fu/first_index while
// walking high-to-low -- that's a priority chain NUM_FU deep. Instead,
// isolate the lowest set bit of the found_local vector with the classic
// x & (-x) trick (a small adder, not a chain), then OR-reduce each
// candidate's masked contribution -- every term is independent, so the
// reduction is a balanced O(log NUM_FU) tree rather than a priority chain.
// -------------------------------------------------------------------------

    logic [NUM_FU-1:0] found_local_bits;

    logic [NUM_FU-1:0] first_onehot;

    always_comb begin

        for (int f = 0; f < NUM_FU; f++)

            found_local_bits[f] = fu_found_local[f][0];

    end

    assign first_onehot = found_local_bits & (-found_local_bits);

    always_comb begin

        first_found = found_total[0];

        first_fu    = '0;

        first_index = '0;

        for (int f = 0; f < NUM_FU; f++) begin

            first_fu    |= first_onehot[f] ? FU_W'(f)          : '0;

            first_index |= first_onehot[f] ? fu_element_idx[f] : '0;

        end

    end

// -------------------------------------------------------------------------
// Build the scalar result
//
// vfirst.m returns the global element index, or -1 if no bit was found.
// vcpop.m returns the total count from the parallel-prefix network.
// -------------------------------------------------------------------------

    always_comb begin

        case (mask_op)

            MASK_OP_VCPOP: begin

                result_scalar = XLEN'(count_total);

            end

            MASK_OP_VFIRST: begin

                if (first_found)

                    result_scalar = XLEN'({first_fu, first_index});

                else

                    result_scalar = {XLEN{1'b1}};     // -1

            end

            default: begin

                result_scalar = '0;

            end

        endcase

    end

// -------------------------------------------------------------------------
// Select which result bus is valid for write-back
// -------------------------------------------------------------------------

    always_comb begin

        result_mask_valid   = mask_op_is_logic(mask_op) || mask_op_is_setmask(mask_op);

        result_scalar_valid = mask_op_is_scalar(mask_op);

        result_count_valid  = mask_op_is_count(mask_op);

    end

endmodule
