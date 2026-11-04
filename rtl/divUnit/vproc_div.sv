import v_cfg_pkg::*;

module vproc_div#(
    parameter int unsigned OP_W = 32
)(
    input  logic               clk_i,
    input  logic               rst_ni,

    // Vector-side input handshake (one OP_W-bit instruction's worth of data)
    input  logic               valid_i,
    output logic               ready_o,

    input logic [OP_W-1:0]     op_a_i,     // vs2 (dividend)
    input logic [OP_W-1:0]     op_b_i,     // vs1 (divisor)

    input  vdiv_sew_e           sew_i,
    input  vdiv_op_e            op_i,

    // Vector-side output handshake

    output logic               valid_o,
    input  logic                ready_i,

    output logic [OP_W-1:0]     result_o

);
    localparam int unsigned MAX_ELEMS  = (OP_W+1) / VDIV_SEW8;
    localparam int unsigned ELEM_CNT_W = $clog2(MAX_ELEMS);

    logic [OP_W-1:0]        op_a_q, op_b_q;
    vdiv_sew_e               sew_q;
    vdiv_op_e                op_q;

    logic                    busy_q;
    logic                    out_valid_q;

    logic [ELEM_CNT_W-1:0]   elem_idx_q;
    logic                    elem_sent_q;

    logic [OP_W-1:0]         result_q;

    assign ready_o = !busy_q;
    assign valid_o = out_valid_q;
    assign result_o = result_q;

    logic [ELEM_CNT_W:0] num_elems;
    logic [ELEM_CNT_W-1:0] last_elem_idx;

    assign num_elems      = sew_num_elems(sew_q, OP_W);
    assign last_elem_idx = num_elems - 1'b1;

    // ----------------------------
    // Slice of the operands
    // ----------------------------

    logic [OP_W-1:0] raw_a, raw_b;
    always_comb begin
        raw_a = '0;
        raw_b = '0;
        unique case (sew_q)
            VDIV_SEW32: begin
                raw_a = op_a_q;
                raw_b = op_b_q;
            end
            VDIV_SEW16: begin
                raw_a = elem_idx_q[0] ? {16'b0, op_a_q[31:16]} : {16'b0, op_a_q[15:0]};
                raw_b = elem_idx_q[0] ? {16'b0, op_b_q[31:16]} : {16'b0, op_b_q[15:0]};
            end
            VDIV_SEW8: begin
                unique case (elem_idx_q)
                    2'd0: begin raw_a = {24'b0, op_a_q[7:0]};   raw_b = {24'b0, op_b_q[7:0]};   end
                    2'd1: begin raw_a = {24'b0, op_a_q[15:8]};  raw_b = {24'b0, op_b_q[15:8]};  end
                    2'd2: begin raw_a = {24'b0, op_a_q[23:16]}; raw_b = {24'b0, op_b_q[23:16]}; end
                    2'd3: begin raw_a = {24'b0, op_a_q[31:24]}; raw_b = {24'b0, op_b_q[31:24]}; end
                    default: begin raw_a = '0; raw_b = '0; end
                endcase
            end
            default: begin
                raw_a = op_a_q;
                raw_b = op_b_q;
            end
        endcase
    end

    logic is_signed, is_rem;
    assign is_signed = ((op_q == VDIV_DIV) || (op_q == VDIV_REM)) ? 1 : 0;
    assign is_rem = ((op_q == VDIV_REMU) || (op_q == VDIV_REM)) ? 1 : 0;

    // Sign/zero-extend the sliced sub-element up to the full 32-bit
    // div_unit operand width.

    logic [31:0] elem_a_temp, elem_b_temp;
    always_comb begin
        elem_a_temp = raw_a;
        elem_b_temp = raw_b;
        if (is_signed) begin
            unique case (sew_q)
                VDIV_SEW8: begin
                    elem_a_temp = {{24{raw_a[7]}},  raw_a[7:0]};
                    elem_b_temp = {{24{raw_b[7]}},  raw_b[7:0]};
                end
                VDIV_SEW16: begin
                    elem_a_temp = {{16{raw_a[15]}}, raw_a[15:0]};
                    elem_b_temp = {{16{raw_b[15]}}, raw_b[15:0]};
                end
                default: ;
            endcase
        end
    end
    logic [31:0] elem_a, elem_b;
    logic is_a_signed, is_b_signed;
    assign is_a_signed = (is_signed) ? elem_a_temp[31] : 0;
    assign is_b_signed = (is_signed) ? elem_b_temp[31] : 0;
    
    always_comb begin
        if(is_signed) begin
            elem_a = (is_a_signed) ? ~elem_a_temp + 1 : elem_a_temp;
            elem_b = (is_b_signed) ? ~elem_b_temp + 1 : elem_b_temp;
        end else begin
            elem_a = elem_a_temp;
            elem_b = elem_b_temp;
        end
    end

    // Detect divide-by-zero before starting the scalar divider.
    // The zero check is identical for signed and unsigned division.

    logic div_by_zero;
    assign div_by_zero = (elem_b == 32'b0);

    logic        scalar_valid_i, scalar_ready_o;
    logic        scalar_valid_o, scalar_ready_i;
    logic [31:0] scalar_quot, scalar_rem;


    assign scalar_valid_i = busy_q && !out_valid_q && !elem_sent_q && !div_by_zero;
    assign scalar_ready_i = 1'b1;

    div_unit #(
        .WIDTH (32)
    ) u_div_unit (
        .clk       (clk_i),
        .rst_n      (rst_ni),

        .valid_i    (scalar_valid_i),
        .ready_o    (scalar_ready_o),

        .dividend   (elem_a),
        .divisor    (elem_b),

        .valid_o    (scalar_valid_o),
        .ready_i    (scalar_ready_i),

        .quotient   (scalar_quot),
        .remainder  (scalar_rem)
    );

    logic [31:0] elem_result, elem_result_temp;

    always_comb begin
        if (div_by_zero) begin
            if (is_rem) elem_result_temp = elem_a;
            else elem_result_temp = 32'hFFFFFFFF;
        end else begin
            elem_result_temp = (is_rem) ? scalar_rem : scalar_quot;
        end
    end

    always_comb begin
        if(is_signed) begin
            if (!is_rem && !div_by_zero) elem_result = (is_a_signed^is_b_signed)? (~elem_result_temp+1) : elem_result_temp;
            else if(!is_rem && div_by_zero) elem_result = elem_result_temp;
            else elem_result = (is_a_signed)? (~elem_result_temp+1) : elem_result_temp;
        end
        else elem_result = elem_result_temp;
    end

    always_ff @(posedge clk_i) begin
        if (!rst_ni) begin
            busy_q      <= 1'b0;
            out_valid_q <= 1'b0;
            elem_idx_q  <= '0;
            elem_sent_q <= 1'b0;
            op_a_q      <= '0;
            op_b_q      <= '0;
            sew_q       <= VDIV_SEW32;
            op_q        <= VDIV_DIVU;
            result_q    <= '0;
        end else if (!busy_q) begin
            // Accept a new vector op
            if (valid_i) begin
                op_a_q      <= op_a_i;
                op_b_q      <= op_b_i;
                sew_q       <= sew_i;
                op_q        <= op_i;
                busy_q      <= 1'b1;
                elem_idx_q  <= '0;
                elem_sent_q <= 1'b0;
                out_valid_q <= 1'b0;
            end
        end else if (!out_valid_q) begin

            // Note when the scalar divider has accepted the current sub-element.
            // Divide-by-zero is completed locally instead.

            if (scalar_valid_i && scalar_ready_o) begin
                elem_sent_q <= 1'b1;
            end

            // Capture either a finished scalar-divider result or a
            // locally generated divide-by-zero result.

            if ((scalar_valid_o && scalar_ready_i) || div_by_zero) begin
                unique case (sew_q)
                    VDIV_SEW32:
                        result_q <= elem_result;
                    VDIV_SEW16: begin
                        if (elem_idx_q[0]) result_q[31:16] <= elem_result[15:0];
                        else result_q[15:0]  <= elem_result[15:0];
                    end
                    VDIV_SEW8: begin
                        unique case (elem_idx_q)
                            2'd0: result_q[7:0]    <= elem_result[7:0];
                            2'd1: result_q[15:8]   <= elem_result[7:0];
                            2'd2: result_q[23:16]  <= elem_result[7:0];
                            2'd3: result_q[31:24]  <= elem_result[7:0];
                            default: ;
                        endcase
                    end
                    default:
                        result_q <= elem_result;
                endcase
                if (elem_idx_q == last_elem_idx) begin
                    // That was the last sub-element -- present the full result
                    out_valid_q <= 1'b1;
                end else begin
                    elem_idx_q  <= elem_idx_q + 1'b1;
                    elem_sent_q <= 1'b0;
                end
            end
        end else begin
            // Full result formed, waiting for the vector-side consumer
            if (ready_i) begin
                busy_q      <= 1'b0;
                out_valid_q <= 1'b0;
            end
        end
    end
endmodule