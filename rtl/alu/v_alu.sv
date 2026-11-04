module v_alu
    import v_alu_pkg::*;
#(
    parameter  int WIDTH     = v_cfg_pkg::ELEN,
    parameter  int VLEN      = v_cfg_pkg::VLEN,
    // derived from WIDTH, so not overridable on purpose
    localparam int NB        = WIDTH/8,      // bytes per lane (4)
    localparam int Mask_Bits = NB,
    localparam int PACKED_W  = WIDTH + NB    // 36
) (
    input  logic [WIDTH-1:0]     vs2,
    input  logic [WIDTH-1:0]     vs1,
    input  logic [Mask_Bits-1:0] vmask,
    input  logic [1:0]           Sew,       // SOURCE Sew for widening ops; DEST Sew for vzext/vsext
    input  logic [OPTYPE_W-1:0]  optype,

    output logic [WIDTH-1:0]     vd
);

    logic is_sub, is_mask_out, has_min;
    logic is_wide, is_wform, is_ext, sign_extend;
    logic [1:0] ext_shift;

    always_comb begin
        is_sub      = 1'b0; // subtraction vs addition
        is_mask_out = 1'b0; // whether the result is a mask (carry/borrow) instead of an arithmetic result
        has_min     = 1'b0; // whether the operation has a mask input (carry-in for addition, borrow-in for subtraction)
        is_wide     = 1'b0; // whether the operation is widening (2*SEW = SEW +/-)
        is_wform    = 1'b0; //whether the operation is widening with vs2 already wide (2*SEW = 2*SEW +/-)
        is_ext      = 1'b0; //whether the operation is integer extension (vzext/vsext)
        sign_extend = 1'b0; // whether the operation is signed (subtraction, widening signed, or vsext)
        ext_shift   = 2'd0; // shift amount for integer extension (1 for vf2, 2 for vf4). This shifting is done on the source operand.

        unique case (optype)
            OP_VADC_VVM, OP_VADC_VXM, OP_VADC_VIM:
                begin has_min = 1'b1; end
            OP_VMADC_VVM, OP_VMADC_VXM, OP_VMADC_VIM:
                begin is_mask_out = 1'b1; has_min = 1'b1; end
            OP_VMADC_VV, OP_VMADC_VX, OP_VMADC_VI:
                begin is_mask_out = 1'b1; end
            OP_VSBC_VVM, OP_VSBC_VXM:
                begin is_sub = 1'b1; has_min = 1'b1; end
            OP_VMSBC_VVM, OP_VMSBC_VXM:
                begin is_sub = 1'b1; is_mask_out = 1'b1; has_min = 1'b1; end
            OP_VMSBC_VV, OP_VMSBC_VX:
                begin is_sub = 1'b1; is_mask_out = 1'b1; end

            OP_VWADDU_VV, OP_VWADDU_VX:
                begin is_wide = 1'b1; end
            OP_VWADD_VV, OP_VWADD_VX:
                begin is_wide = 1'b1; sign_extend = 1'b1; end
            OP_VWSUBU_VV, OP_VWSUBU_VX:
                begin is_wide = 1'b1; is_sub = 1'b1; end
            OP_VWSUB_VV, OP_VWSUB_VX:
                begin is_wide = 1'b1; is_sub = 1'b1; sign_extend = 1'b1; end
            OP_VWADDU_WV, OP_VWADDU_WX:
                begin is_wide = 1'b1; is_wform = 1'b1; end
            OP_VWADD_WV, OP_VWADD_WX:
                begin is_wide = 1'b1; is_wform = 1'b1; sign_extend = 1'b1; end
            OP_VWSUBU_WV, OP_VWSUBU_WX:
                begin is_wide = 1'b1; is_wform = 1'b1; is_sub = 1'b1; end
            OP_VWSUB_WV, OP_VWSUB_WX:
                begin is_wide = 1'b1; is_wform = 1'b1; is_sub = 1'b1; sign_extend = 1'b1; end

            OP_VZEXT_VF2:
                begin is_ext = 1'b1; ext_shift = 2'd1; end
            OP_VSEXT_VF2:
                begin is_ext = 1'b1; ext_shift = 2'd1; sign_extend = 1'b1; end
            OP_VZEXT_VF4:
                begin is_ext = 1'b1; ext_shift = 2'd2; end
            OP_VSEXT_VF4:
                begin is_ext = 1'b1; ext_shift = 2'd2; sign_extend = 1'b1; end

            OP_VADD_VV, OP_VADD_VX, OP_VADD_VI:
                begin end
            OP_VSUB_VV, OP_VSUB_VX:
                begin is_sub = 1'b1; end

            default: ;
        endcase
    end

    // Sew Mapping: 0 -> 8, 1 -> 16, 2 -> 32

    logic [2:0] elem_bytes;
    assign elem_bytes = is_wide ? (3'd2 << Sew) : (3'd1 << Sew); // 2*SEW in case of widening, SEW otherwise. This is the number of bytes per element in the operation.

    logic [2:0] vs1_src_bytes, vs2_src_bytes;
    assign vs1_src_bytes = (3'd1 << Sew); 
    assign vs2_src_bytes = is_ext  ? (elem_bytes >> ext_shift) :
                            is_wform ? elem_bytes :
                                       vs1_src_bytes;


    function automatic logic [31:0] extend_slot(input logic [31:0] slot,
                                                  input int src_bytes,
                                                  input logic is_signed_ext);
        logic [31:0] result;
        logic        sign_bit;
        result   = '0;
        sign_bit = 1'b0;
        unique case (src_bytes)
            1: begin result[7:0]   = slot[7:0];   sign_bit = slot[7];  end
            2: begin result[15:0]  = slot[15:0];  sign_bit = slot[15]; end
            4: begin result[31:0]  = slot[31:0];  sign_bit = 1'b0;     end
            default: ;
        endcase
        if (is_signed_ext && sign_bit) begin
            unique case (src_bytes)
                1: result[31:8]  = '1;
                2: result[31:16] = '1;
                default: ;
            endcase
        end
        return result;
    endfunction

    logic [WIDTH-1:0] vs2_ext, vs1_ext;
    logic [31:0]       ext_tmp;
    always_comb begin
        vs2_ext = vs2;
        vs1_ext = vs1;
        if (is_wide || is_ext) begin
            unique case (elem_bytes)
                3'd2: begin
                    for (int g = 0; g < 2; g++) begin
                        if (is_wide) begin
                            ext_tmp = extend_slot(vs1 >> (8*vs1_src_bytes*g), vs1_src_bytes, sign_extend); 
                            vs1_ext[16*g +: 16] = ext_tmp[15:0];
                        end
                        if ((is_wide && !is_wform) || is_ext) begin
                            ext_tmp = extend_slot(vs2 >> (8*vs2_src_bytes*g), vs2_src_bytes, sign_extend);
                            vs2_ext[16*g +: 16] = ext_tmp[15:0];
                        end
                    end
                end
                3'd4: begin
                    if (is_wide)
                        vs1_ext = extend_slot(vs1, vs1_src_bytes, sign_extend);
                    if ((is_wide && !is_wform) || is_ext)
                        vs2_ext = extend_slot(vs2, vs2_src_bytes, sign_extend);
                end
                default: ;
            endcase
        end
    end

    logic cin0; // carry-in for the first element (borrow-in for subtraction); 0 for all widen/ext ops
    assign cin0 = is_sub ? (has_min ? ~vmask[0] : 1'b1)
                          : (has_min ?  vmask[0] : 1'b0);

    logic [PACKED_W-1:0] packed_vs2, packed_vs1;
    logic                inject_val;
    always_comb begin
        packed_vs2 = '0;
        packed_vs1 = '0;
        for (int i = 0; i < NB; i++) begin
            // pack vs2_ext/vs1_ext into 9-bit slots -- identical to before,
            // just reading the (possibly extended) operands instead of the
            // raw ports directly.
            packed_vs2[9*i +: 8] = vs2_ext[8*i +: 8];
            packed_vs1[9*i +: 8] = is_sub ? ~vs1_ext[8*i +: 8] : vs1_ext[8*i +: 8];

            if (i == NB-1) begin
                packed_vs1[9*i+8] = 1'b1;
                packed_vs2[9*i+8] = 1'b0;

            end else if (((i+1) % elem_bytes) == 0) begin
                inject_val = is_sub ? (has_min ? ~vmask[(i+1) >> Sew] : 1'b1)
                                     : (has_min ?  vmask[(i+1) >> Sew] : 1'b0);
                packed_vs1[9*i+8] = inject_val;
                packed_vs2[9*i+8] = inject_val;

            end else begin
                packed_vs1[9*i+8] = 1'b1;
                packed_vs2[9*i+8] = 1'b0;
            end
        end
    end

    logic [PACKED_W:0] sum37;
    assign sum37 = {1'b0, packed_vs2} + {1'b0, packed_vs1} + {{PACKED_W{1'b0}}, cin0}; // 37 bit sum

    logic [WIDTH-1:0] arith_result;
    always_comb
        for (int i = 0; i < NB; i++)
            arith_result[8*i +: 8] = sum37[9*i +: 8];

    logic [NB-1:0] carry_at_boundary;
    always_comb
        for (int i = 0; i < NB; i++)
            carry_at_boundary[i] = (i == NB-1) ? sum37[PACKED_W] : sum37[9*i+8];

    // borrow_out = ~carry_out
    logic [NB-1:0] mask_bit;
    assign mask_bit = is_sub ? ~carry_at_boundary : carry_at_boundary;

    logic [WIDTH-1:0] mask_result;
    always_comb begin
        mask_result = '0;
        unique case (elem_bytes)
            3'd1: mask_result[NB-1:0]   = mask_bit;                          // Sew=8:  ends at bytes 0,1,2,3
            3'd2: mask_result[NB/2-1:0] = {mask_bit[3], mask_bit[1]};        // Sew=16: ends at bytes 1,3
            3'd4: mask_result[0]        = mask_bit[3];                       // Sew=32: ends at byte 3
            default: ;
        endcase
    end

    // is_ext bypasses the adder entirely -- vzext/vsext do no arithmetic,
    // vd is just the extended operand.
    assign vd = is_ext      ? vs2_ext :
                is_mask_out ? mask_result : arith_result;

endmodule