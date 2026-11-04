`include "vector_mask_ops.svh"

module mask_scan (

    input  logic [ELEN-1:0]      vs2_element_mask,

    input  logic [ELEN-1:0]      v0_element_mask,

    input  logic                 vm,            // 1 = unmasked, 0 = use v0.t

    input  logic [MASK_OP_W-1:0] mask_op,

    input  logic                 found_in,      // exclusive OR-prefix from the top-level parallel-prefix network: did any EARLIER slice already find a bit? (NOT a neighbor chain)

    output logic                 found_local,   // first set bit is in this slice -- depends only on this slice's own bits

    output logic [IDX_W-1:0]     element_index, // index within this slice

    output logic [ELEN-1:0]      result_element_mask

);

    logic [ELEN-1:0]      search_mask;

    logic [NUM_GROUP-1:0] group_found;

    logic [GRP_W-1:0]     selected_group;

    logic [BIT_W-1:0]     selected_bit;

    logic [IDX_W-1:0]     local_index;

// -------------------------------------------------------------------------
// Active source bits
// -------------------------------------------------------------------------

    always_comb begin

        if (vm)

            search_mask = vs2_element_mask;

        else

            search_mask = vs2_element_mask & v0_element_mask;

    end

// -------------------------------------------------------------------------
// Level 1: check each 4-bit group
// -------------------------------------------------------------------------

    always_comb begin

        group_found = '0;

        for (int g = 0; g < NUM_GROUP; g++) begin

            group_found[g] = |search_mask[g*GROUP_W +: GROUP_W];

        end

    end

// -------------------------------------------------------------------------
// Level 2: find the lowest group with a set bit
// -------------------------------------------------------------------------

    always_comb begin

        found_local    = |group_found;

        selected_group = '0;

        for (int g = NUM_GROUP-1; g >= 0; g--) begin

            if (group_found[g])

                selected_group = GRP_W'(g);

        end

    end

// -------------------------------------------------------------------------
// Level 3: find the lowest set bit inside the selected group
// -------------------------------------------------------------------------

    always_comb begin

        selected_bit = '0;

        for (int b = GROUP_W-1; b >= 0; b--) begin

            if (search_mask[selected_group*GROUP_W + b])

                selected_bit = BIT_W'(b);

        end

    end

// -------------------------------------------------------------------------
// Index (found_out was removed: the top level now gets "did an earlier
// slice find something" from the mask_prefix tree, not from chaining
// found_out slice to slice)
// -------------------------------------------------------------------------

    always_comb begin

        local_index = IDX_W'({selected_group, selected_bit});

    end

    always_comb begin

        if (found_local)

            element_index = local_index;

        else

            element_index = '0;          // keep unused value clean in waves

    end

// -------------------------------------------------------------------------
// Generate the mask result
// -------------------------------------------------------------------------

    always_comb begin

        result_element_mask = '0;

        case (mask_op)

// ---- vmsbf.m: set bits before the first --------------------------

            MASK_OP_VMSBF: begin

                if (found_in) begin

                    result_element_mask = '0;

                end

                else if (!found_local) begin

                    result_element_mask = '1;

                end

                else begin

                    for (int i = 0; i < ELEN; i++)

                        result_element_mask[i] = (i < int'(local_index));

                end

            end

// ---- vmsif.m: set bits through the first -------------------------

            MASK_OP_VMSIF: begin

                if (found_in) begin

                    result_element_mask = '0;

                end

                else if (!found_local) begin

                    result_element_mask = '1;

                end

                else begin

                    for (int i = 0; i < ELEN; i++)

                        result_element_mask[i] = (i <= int'(local_index));

                end

            end

// ---- vmsof.m: set only the first ---------------------------------

            MASK_OP_VMSOF: begin

                if (!found_in && found_local)

                    result_element_mask[local_index] = 1'b1;

            end

// ---- everything else produces no mask ----------------------------

            default: result_element_mask = '0;

        endcase

    end

endmodule
