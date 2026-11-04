`include "vector_mask_ops.svh"

module mask_logic (
    input  logic [ELEN-1:0]      vs1_element_mask,
    input  logic [ELEN-1:0]      vs2_element_mask,
    input  logic [MASK_OP_W-1:0] mask_op,

    output logic [ELEN-1:0]      result_element_mask
);

    always_comb begin
        case (mask_op)
            MASK_OP_VMAND : result_element_mask =   vs2_element_mask &  vs1_element_mask;
            MASK_OP_VMNAND: result_element_mask = ~(vs2_element_mask &  vs1_element_mask);
            MASK_OP_VMANDN: result_element_mask =   vs2_element_mask & ~vs1_element_mask;
            MASK_OP_VMXOR : result_element_mask =   vs2_element_mask ^  vs1_element_mask;
            MASK_OP_VMOR  : result_element_mask =   vs2_element_mask |  vs1_element_mask;
            MASK_OP_VMNOR : result_element_mask = ~(vs2_element_mask |  vs1_element_mask);
            MASK_OP_VMORN : result_element_mask =   vs2_element_mask | ~vs1_element_mask;
            MASK_OP_VMXNOR: result_element_mask = ~(vs2_element_mask ^  vs1_element_mask);

            // Not a logical op -> this block contributes nothing.
            default       : result_element_mask = '0;
        endcase
    end

endmodule
