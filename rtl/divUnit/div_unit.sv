module div_unit #(

    parameter int WIDTH = 32

) (
    input  logic             clk,
    input  logic             rst_n,

    input  logic             valid_i,
    output logic             ready_o,

    input  logic [WIDTH-1:0] dividend,
    input  logic [WIDTH-1:0] divisor,

    output logic             valid_o,
    input  logic             ready_i,

    output logic [WIDTH-1:0] quotient,
    output logic [WIDTH-1:0] remainder

);

    // ------------------------------------------------------------
    // Number of radix-4 iterations
    //
    // Two dividend bits are processed per iteration.
    //
    // WIDTH = 32 -> 16 iterations
    // WIDTH = 16 -> 8 iterations
    // WIDTH = 8  -> 4 iterations
    // ------------------------------------------------------------

    localparam int ITERATIONS = WIDTH >> 1;
    localparam int COUNT_W    = (ITERATIONS <= 1) ? 1 : $clog2(ITERATIONS);

    // ------------------------------------------------------------
    // Internal registers
    // ------------------------------------------------------------

    logic [WIDTH-1:0] dividend_q;
    logic [WIDTH-1:0] divisor_q;
    logic [WIDTH+1:0] remainder_q;
    logic [WIDTH-1:0] quotient_q;
    logic [COUNT_W-1:0] count_q;
    logic               busy_q;

    // ------------------------------------------------------------
    // Combinational values for one radix-4 iteration
    // ------------------------------------------------------------

    logic [WIDTH+1:0] partial_value;
    logic [WIDTH+1:0] divisor_ext;
    logic [WIDTH+1:0] divisor_x2;
    logic [WIDTH+1:0] divisor_x3;
    logic [1:0] next_bits;
    logic [1:0] quotient_digit;
    logic [WIDTH+1:0] next_remainder;

    assign next_bits = dividend_q[WIDTH-1 -: 2];

    // ------------------------------------------------------------
    // T = 4R + x
    // ------------------------------------------------------------

    assign partial_value = {remainder_q[WIDTH-1:0], 2'b00}
                         + {{WIDTH{1'b0}}, next_bits};

    // ------------------------------------------------------------
    // Generate D, 2D and 3D.
    //   2D = D << 1
    //   3D = D + 2D
    // ------------------------------------------------------------

    assign divisor_ext = {{2{1'b0}}, divisor_q};
    assign divisor_x2  = {divisor_ext[WIDTH:0], 1'b0};
    assign divisor_x3  = divisor_ext + divisor_x2;

    // ------------------------------------------------------------
    // Radix-4 quotient-digit selection
    //
    // q = 0 : T < D
    // q = 1 : D <= T < 2D
    // q = 2 : 2D <= T < 3D
    // q = 3 : 3D <= T
    // ------------------------------------------------------------

    always_comb begin
        if (partial_value < divisor_ext) begin
            quotient_digit = 2'd0;
        end
        else if (partial_value < divisor_x2) begin
            quotient_digit = 2'd1;
        end
        else if (partial_value < divisor_x3) begin
            quotient_digit = 2'd2;
        end
        else begin
            quotient_digit = 2'd3;
        end
    end

    // ------------------------------------------------------------
    // Calculate the next remainder.
    //
    // q = 0 -> T - 0D
    // q = 1 -> T - D
    // q = 2 -> T - 2D
    // q = 3 -> T - 3D
    // ------------------------------------------------------------

    always_comb begin
        case (quotient_digit)
            2'd0: next_remainder = partial_value;
            2'd1: next_remainder = partial_value - divisor_ext;
            2'd2: next_remainder = partial_value - divisor_x2;
            2'd3: next_remainder = partial_value - divisor_x3;
            default:
                next_remainder = '0;
        endcase
    end

    // ------------------------------------------------------------
    // Ready-valid handshake
    //
    // The divider can accept a new operation only when it is not
    // currently processing an operation or holding a result.
    //
    // Therefore:
    //
    //     valid_i && ready_o
    //
    // is the input transaction.
    //
    //     valid_o && ready_i
    //
    // is the output transaction.
    // ------------------------------------------------------------

    assign ready_o = !busy_q;

    // ------------------------------------------------------------
    // Sequential controller
    // ------------------------------------------------------------

    always_ff @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin
            dividend_q <= '0;
            divisor_q  <= '0;
            remainder_q <= '0;
            quotient_q  <= '0;
            count_q <= '0;
            quotient  <= '0;
            remainder <= '0;
            valid_o <= 1'b0;
            busy_q  <= 1'b0;
        end
        else begin

            // ----------------------------------------------------
            // Output handshake
            //
            // Once the result is valid, it remains valid until
            // the receiving unit accepts it.
            // ----------------------------------------------------

            if (valid_o && ready_i) begin
                valid_o <= 1'b0;
                busy_q <= 1'b0;
            end

            // ----------------------------------------------------
            // Input handshake
            //
            // A new division begins only when both valid_i and
            // ready_o are asserted.
            // ----------------------------------------------------

            if (valid_i && ready_o) begin
                // Load operands.
                dividend_q <= dividend;
                divisor_q  <= divisor;

                // Initial partial remainder = 0.
                remainder_q <= '0;

                // Quotient starts at zero.
                quotient_q <= '0;

                // First iteration is about to execute.
                count_q <= '0;
                busy_q <= 1'b1;

            end

            else if (busy_q && !valid_o) begin
                dividend_q <= {dividend_q[WIDTH-3:0], 2'b00};

                // Store the new partial remainder.
                remainder_q <= next_remainder;

                // Append the new radix-4 quotient digit.
                //     Q_next = 4Q + q
                quotient_q <= {quotient_q[WIDTH-3:0], quotient_digit};

                // ------------------------------------------------
                // Last iteration
                // ------------------------------------------------
                if (count_q == ITERATIONS-1) begin
                    quotient  <= {quotient_q[WIDTH-3:0], quotient_digit};
                    remainder <= next_remainder[WIDTH-1:0];
                    // ------------------------------------------------
                    // Result is now available.
                    //
                    // Do NOT clear busy here. The result must remain
                    // stable until valid_o && ready_i.
                    // ------------------------------------------------
                    valid_o <= 1'b1;
                end
                else begin
                    count_q <= count_q + 1'b1;
                end

            end

        end

    end

endmodule