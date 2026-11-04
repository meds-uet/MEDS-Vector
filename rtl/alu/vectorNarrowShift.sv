module vectorNarrowShift #(
    parameter int ELEN = 32
)(
    input  logic [ELEN-1:0] vs1_element_integer,    // Holds Shift Value
    input  logic [ELEN-1:0] vs2_element_integer,    // Holds Element value (2*SEW)

    input  logic [1:0]      sew,
    input  logic            is_arithmetic,          // Check if the Shift is Arithmetic or Logical

    output logic [ELEN-1:0] result_element_integer  // Holds SEW sized Elements
);

    always_comb begin
        case (sew)

            // Destination SEW = 8
            // Source element = 16 bits
            2'b00: begin
                if (is_arithmetic)
                    result_element_integer[7:0] = $signed(vs2_element_integer[15:0]) >>> vs1_element_integer[3:0];
                else
                    result_element_integer[7:0] = vs2_element_integer[15:0] >> vs1_element_integer[3:0];
            end

            // Destination SEW = 16
            // Source element = 32 bits
            2'b01: begin
                if (is_arithmetic)
                    result_element_integer[15:0] = $signed(vs2_element_integer[31:0]) >>> vs1_element_integer[4:0];
                else
                    result_element_integer[15:0] = vs2_element_integer[31:0] >> vs1_element_integer[4:0];
            end

            default: begin
                result_element_integer = '0;
            end

        endcase
    end

endmodule
