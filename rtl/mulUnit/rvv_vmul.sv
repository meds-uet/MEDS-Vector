// RVV integer multiplier (vmul / vmulh / vmulhu / vmulhsu), SEW 8/16/32.
//
// Each 32-bit lane builds one 64-bit product bus P from sixteen signed 9x9
// bricks (a-byte i x b-byte j, weight 2^(8*(i+j))):
//   SEW=8  : P = {p3[15:0], p2[15:0], p1[15:0], p0[15:0]}  diagonal bricks, concatenated
//   SEW=16 : P = {p1[31:0], p0[31:0]}                      two 16x16 groups, concatenated
//   SEW=32 : P = p0[63:0]                                  all bricks summed
// vmul returns the low half of each field, vmulh* the high half.
//
// Signedness: only the top byte of an element carries sign, so every byte is
// extended by one bit (sign only for the top byte of a signed operand). Each
// brick is then a plain signed multiply and the weighted sum is exact for any
// signed/unsigned mix, with no correction terms.
//
// Pipeline: [PIPE_IN] -> bricks + group sums -> [PIPE_MID] -> assemble/select -> [PIPE_OUT]
// Back-pressure is a global stall: every register advances when the output
// stage is empty or being consumed.

import v_cfg_pkg::*;

// -----------------------------------------------------------------------------
// 9x9 signed multiplier, shift-add (no '*'). Operands span -128..255 here.
// -----------------------------------------------------------------------------
module mul_brick (
    input  logic signed [8:0]  multiplicand,
    input  logic signed [8:0]  multiplier,
    output logic signed [17:0] product
);
    logic signed [17:0] ext, acc;

    always_comb begin
        ext = 18'(multiplicand);
        acc = '0;
        for (int i = 0; i < 8; i++) begin
            if (multiplier[i]) acc = acc + (ext <<< i);
        end
        // bit 8 of a two's-complement multiplier has negative weight
        if (multiplier[8]) acc = acc - (ext <<< 8);
        product = acc;
    end
endmodule


// -----------------------------------------------------------------------------
// Stage 1 (one lane): operand formatting, 16 bricks, per-16-bit-group sums.
//   grp_o [34*(2*ia+ib) +: 34] : exact signed product of a-half ia x b-half ib
//   diag_o[16*k +: 16]         : 8x8 product of byte k (SEW=8 field)
// -----------------------------------------------------------------------------
module mul_unit #(
    // Zero the a-operand of unused bricks so they do not toggle (ASIC: 1,
    // FPGA/DSP: usually 0).
    parameter bit ISOLATE = 1'b0
)(
    input  logic [31:0]      multiplicand,   // vs2 (signed side of vmulhsu)
    input  logic [31:0]      multiplier,     // vs1 / rs1
    input  vmul_sew_e        sew_i,
    input  logic             a_signed_i,
    input  logic             b_signed_i,

    output logic [4*34-1:0]  grp_o,
    output logic [4*16-1:0]  diag_o
);
    logic is8, is16, is32;
    assign is8  = (sew_i == VMUL_SEW8);
    assign is16 = (sew_i == VMUL_SEW16);
    assign is32 = !is8 && !is16;

    // top[k]: byte k is the sign-carrying byte of its element
    logic [3:0] top;
    assign top = is8 ? 4'b1111 : is16 ? 4'b1010 : 4'b1000;

    logic [35:0] ext_a, ext_b;
    for (genvar k = 0; k < 4; k++) begin : g_ext
        assign ext_a[9*k +: 9] = {top[k] & a_signed_i & multiplicand[8*k+7], multiplicand[8*k +: 8]};
        assign ext_b[9*k +: 9] = {top[k] & b_signed_i & multiplier[8*k+7],   multiplier[8*k +: 8]};
    end

    // Brick (i,j) is needed when: SEW8 i==j, SEW16 same halfword, SEW32 always.
    logic [16*18-1:0] brick_p;
    for (genvar i = 0; i < 4; i++) begin : g_bi
        for (genvar j = 0; j < 4; j++) begin : g_bj
            logic               en;
            logic signed [8:0]  op_a, op_b;
            logic signed [17:0] p;

            assign en   = is32 | (is16 & ((i >> 1) == (j >> 1))) | (is8 & (i == j));
            assign op_a = (ISOLATE && !en) ? 9'sd0 : ext_a[9*i +: 9];
            assign op_b = ext_b[9*j +: 9];

            mul_brick u_mul_brick (
                .multiplicand (op_a),
                .multiplier   (op_b),
                .product      (p)
            );
            assign brick_p[18*(4*i+j) +: 18] = p;
        end
    end

    // G = ll + ((lh + hl) << 8) + (hh << 16)
    for (genvar ia = 0; ia < 2; ia++) begin : g_ga
        for (genvar ib = 0; ib < 2; ib++) begin : g_gb
            logic signed [33:0] ll, lh, hl, hh;
            assign ll = 34'($signed(brick_p[18*(4*(2*ia  ) + (2*ib  )) +: 18]));
            assign lh = 34'($signed(brick_p[18*(4*(2*ia  ) + (2*ib+1)) +: 18]));
            assign hl = 34'($signed(brick_p[18*(4*(2*ia+1) + (2*ib  )) +: 18]));
            assign hh = 34'($signed(brick_p[18*(4*(2*ia+1) + (2*ib+1)) +: 18]));
            assign grp_o[34*(2*ia+ib) +: 34] = ll + ((lh + hl) <<< 8) + (hh <<< 16);
        end
    end

    for (genvar k = 0; k < 4; k++) begin : g_diag
        assign diag_o[16*k +: 16] = brick_p[18*(5*k) +: 16];
    end
endmodule


// -----------------------------------------------------------------------------
// Stage 2 (one lane): build the product bus, then pick the low/high half.
// Concatenate where elements are independent, add only within one element.
// -----------------------------------------------------------------------------
module mul_merge (
    input  logic [4*34-1:0]  grp_i,
    input  logic [4*16-1:0]  diag_i,
    input  vmul_sew_e        sew_i,
    input  logic             hi_i,

    output logic [63:0]      product,
    output logic [31:0]      result
);
    logic is8, is16;
    assign is8  = (sew_i == VMUL_SEW8);
    assign is16 = (sew_i == VMUL_SEW16);

    logic signed [33:0] g00, g01, g10, g11;
    assign g00 = $signed(grp_i[34*0 +: 34]);
    assign g01 = $signed(grp_i[34*1 +: 34]);
    assign g10 = $signed(grp_i[34*2 +: 34]);
    assign g11 = $signed(grp_i[34*3 +: 34]);

    // SEW=32: P = g00 + ((g01 + g10) << 16) + (g11 << 32). P[15:0] is g00[15:0],
    // so only P[63:16] needs the adder.
    logic signed [47:0] hi_sum;
    assign hi_sum = (48'(g00) >>> 16) + 48'(g01) + 48'(g10) + (48'(g11) <<< 16);

    always_comb begin
        if (is8) begin
            product = {diag_i[48 +: 16], diag_i[32 +: 16], diag_i[16 +: 16], diag_i[0 +: 16]};
        end else if (is16) begin
            product = {g11[31:0], g00[31:0]};
        end else begin
            product = {hi_sum, g00[15:0]};
        end
    end

    always_comb begin
        result = '0;
        if (is8) begin
            for (int e = 0; e < 4; e++)
                result[8*e +: 8]   = hi_i ? product[16*e + 8  +: 8]  : product[16*e +: 8];
        end else if (is16) begin
            for (int e = 0; e < 2; e++)
                result[16*e +: 16] = hi_i ? product[32*e + 16 +: 16] : product[32*e +: 16];
        end else begin
            result = hi_i ? product[63:32] : product[31:0];
        end
    end
endmodule


// -----------------------------------------------------------------------------
// Vector wrapper: op decode, pipeline control, lanes.
// -----------------------------------------------------------------------------
module vproc_mul #(
    parameter int unsigned OP_W     = 128,    // multiple of 32
    parameter bit          PIPE_IN  = 1'b0,
    parameter bit          PIPE_MID = 1'b1,
    parameter bit          PIPE_OUT = 1'b1,
    parameter bit          ISOLATE  = 1'b0
)(
    input  logic                clk_i,
    input  logic                rst_ni,

    // Vector-side input handshake
    input  logic                valid_i,
    output logic                ready_o,

    input  logic [OP_W-1:0]     op_a_i,       // vs2
    input  logic [OP_W-1:0]     op_b_i,       // vs1 (.vx: rs1 replicated per element)

    input  vmul_sew_e           sew_i,
    input  vmul_op_e            op_i,

    // Vector-side output handshake
    output logic                valid_o,
    input  logic                ready_i,

    output logic [OP_W-1:0]     result_o,
    output logic [2*OP_W-1:0]   product_o     // full per-element products (widening ops)
);
    localparam int unsigned NLANES = OP_W / 32;

    // ----------------------------
    // Op decode: vmul ignores signedness, so treat it as unsigned
    // ----------------------------
    logic a_signed_c, b_signed_c, hi_c;
    always_comb begin
        unique case (op_i)
            VMUL_MUL:   begin a_signed_c = 1'b0; b_signed_c = 1'b0; hi_c = 1'b0; end
            VMUL_MULH:  begin a_signed_c = 1'b1; b_signed_c = 1'b1; hi_c = 1'b1; end
            VMUL_MULHU: begin a_signed_c = 1'b0; b_signed_c = 1'b0; hi_c = 1'b1; end
            default:    begin a_signed_c = 1'b1; b_signed_c = 1'b0; hi_c = 1'b1; end
        endcase
    end

    // ----------------------------
    // Valid / stall control
    // ----------------------------
    logic v_in_q, v_mid_q, v_out_q;
    logic vld_s1, vld_s2, vld_o;
    logic adv;

    assign vld_s1  = PIPE_IN  ? v_in_q  : valid_i;
    assign vld_s2  = PIPE_MID ? v_mid_q : vld_s1;
    assign vld_o   = PIPE_OUT ? v_out_q : vld_s2;

    assign valid_o = vld_o;
    assign adv     = !vld_o || ready_i;
    assign ready_o = adv;

    always_ff @(posedge clk_i) begin
        if (!rst_ni) begin
            v_in_q  <= 1'b0;
            v_mid_q <= 1'b0;
            v_out_q <= 1'b0;
        end else if (adv) begin
            v_in_q  <= valid_i;
            v_mid_q <= vld_s1;
            v_out_q <= vld_s2;
        end
    end

    // ----------------------------
    // Optional input register (data regs are not reset; only valid is)
    // ----------------------------
    logic [OP_W-1:0] op_a_s1, op_b_s1;
    vmul_sew_e       sew_s1;
    logic            a_signed_s1, b_signed_s1, hi_s1;

    if (PIPE_IN) begin : g_in_reg
        always_ff @(posedge clk_i) begin
            if (adv && valid_i) begin
                op_a_s1     <= op_a_i;
                op_b_s1     <= op_b_i;
                sew_s1      <= sew_i;
                a_signed_s1 <= a_signed_c;
                b_signed_s1 <= b_signed_c;
                hi_s1       <= hi_c;
            end
        end
    end else begin : g_in_wire
        assign op_a_s1     = op_a_i;
        assign op_b_s1     = op_b_i;
        assign sew_s1      = sew_i;
        assign a_signed_s1 = a_signed_c;
        assign b_signed_s1 = b_signed_c;
        assign hi_s1       = hi_c;
    end

    // ----------------------------
    // Stage 1: bricks + group sums
    // ----------------------------
    logic [NLANES*4*34-1:0] grp_c;
    logic [NLANES*4*16-1:0] diag_c;

    for (genvar l = 0; l < NLANES; l++) begin : g_lane_s1
        mul_unit #(
            .ISOLATE (ISOLATE)
        ) u_mul_unit (
            .multiplicand (op_a_s1[32*l +: 32]),
            .multiplier   (op_b_s1[32*l +: 32]),
            .sew_i        (sew_s1),
            .a_signed_i   (a_signed_s1),
            .b_signed_i   (b_signed_s1),
            .grp_o        (grp_c [4*34*l +: 4*34]),
            .diag_o       (diag_c[4*16*l +: 4*16])
        );
    end

    // ----------------------------
    // Optional mid register
    // ----------------------------
    logic [NLANES*4*34-1:0] grp_s2;
    logic [NLANES*4*16-1:0] diag_s2;
    vmul_sew_e              sew_s2;
    logic                   hi_s2;

    if (PIPE_MID) begin : g_mid_reg
        always_ff @(posedge clk_i) begin
            if (adv && vld_s1) begin
                grp_s2  <= grp_c;
                diag_s2 <= diag_c;
                sew_s2  <= sew_s1;
                hi_s2   <= hi_s1;
            end
        end
    end else begin : g_mid_wire
        assign grp_s2  = grp_c;
        assign diag_s2 = diag_c;
        assign sew_s2  = sew_s1;
        assign hi_s2   = hi_s1;
    end

    // ----------------------------
    // Stage 2: assemble + select
    // ----------------------------
    logic [OP_W-1:0]   result_c;
    logic [2*OP_W-1:0] product_c;

    for (genvar l = 0; l < NLANES; l++) begin : g_lane_s2
        mul_merge u_mul_merge (
            .grp_i   (grp_s2 [4*34*l +: 4*34]),
            .diag_i  (diag_s2[4*16*l +: 4*16]),
            .sew_i   (sew_s2),
            .hi_i    (hi_s2),
            .product (product_c[64*l +: 64]),
            .result  (result_c [32*l +: 32])
        );
    end

    // ----------------------------
    // Optional output register
    // ----------------------------
    if (PIPE_OUT) begin : g_out_reg
        always_ff @(posedge clk_i) begin
            if (adv && vld_s2) begin
                result_o  <= result_c;
                product_o <= product_c;
            end
        end
    end else begin : g_out_wire
        assign result_o  = result_c;
        assign product_o = product_c;
    end
endmodule