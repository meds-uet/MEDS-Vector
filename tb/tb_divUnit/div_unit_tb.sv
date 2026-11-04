`timescale 1ns/1ps

module div_unit_tb;

    localparam int WIDTH = 32;

    logic clk;
    logic rst_n;

    logic             valid_i;
    logic             ready_o;
    logic [WIDTH-1:0] dividend;
    logic [WIDTH-1:0] divisor;

    logic             valid_o;
    logic             ready_i;
    logic [WIDTH-1:0] quotient;
    logic [WIDTH-1:0] remainder;

    // ------------------------------------------------------------
    // DUT
    // ------------------------------------------------------------

    div_unit #(
        .WIDTH(WIDTH)
    ) dut (
        .clk      (clk),
        .rst_n    (rst_n),

        .valid_i  (valid_i),
        .ready_o  (ready_o),
        .dividend (dividend),
        .divisor  (divisor),

        .valid_o  (valid_o),
        .ready_i  (ready_i),
        .quotient (quotient),
        .remainder(remainder)
    );

    // ------------------------------------------------------------
    // Clock
    // 10 ns period
    // ------------------------------------------------------------

    initial begin
        clk = 1'b0;

        forever #5 clk = ~clk;
    end

    // ------------------------------------------------------------
    // Test counters
    // ------------------------------------------------------------

    int total_tests  = 0;
    int passed_tests = 0;
    int failed_tests = 0;

    // ------------------------------------------------------------
    // Reset
    // ------------------------------------------------------------

    task automatic reset_dut();

        begin

            rst_n    = 1'b0;
            valid_i  = 1'b0;
            ready_i  = 1'b0;
            dividend = '0;
            divisor  = '0;

            repeat (3) @(posedge clk);

            rst_n = 1'b1;

            @(posedge clk);

        end

    endtask

    // ------------------------------------------------------------
    // Perform one division
    //
    // Expected:
    //
    // quotient  = dividend / divisor
    // remainder = dividend % divisor
    //
    // Divide-by-zero is intentionally not tested.
    // ------------------------------------------------------------

    task automatic test_division(
        input logic [WIDTH-1:0] test_dividend,
        input logic [WIDTH-1:0] test_divisor,
        input string            test_name
    );

        logic [WIDTH-1:0] expected_quotient;
        logic [WIDTH-1:0] expected_remainder;

        begin

            total_tests++;

            // ----------------------------------------------------
            // Calculate reference result using SystemVerilog
            // arithmetic.
            // ----------------------------------------------------

            expected_quotient  = test_dividend / test_divisor;
            expected_remainder = test_dividend % test_divisor;

            // ----------------------------------------------------
            // Wait until DUT can accept an operation.
            // ----------------------------------------------------

            while (!ready_o)
                @(posedge clk);

            // ----------------------------------------------------
            // Present input transaction.
            // ----------------------------------------------------

            @(negedge clk);

            dividend = test_dividend;
            divisor  = test_divisor;
            valid_i  = 1'b1;

            @(posedge clk);

            // Input transaction occurred:
            //
            // valid_i && ready_o
            //
            // Deassert valid after the transaction.

            @(negedge clk);

            valid_i = 1'b0;

            // ----------------------------------------------------
            // Wait for divider to produce a result.
            // ----------------------------------------------------

            while (!valid_o)
                @(posedge clk);

            // ----------------------------------------------------
            // Check result.
            // ----------------------------------------------------

            if ((quotient  === expected_quotient) &&
                (remainder === expected_remainder)) begin

                passed_tests++;

                $display(
                    "[PASS] %-25s A=%h B=%h Q=%h R=%h",
                    test_name,
                    test_dividend,
                    test_divisor,
                    quotient,
                    remainder
                );

            end
            else begin

                failed_tests++;

                $display(
                    "[FAIL] %-25s A=%h B=%h | Expected Q=%h R=%h | Got Q=%h R=%h",
                    test_name,
                    test_dividend,
                    test_divisor,
                    expected_quotient,
                    expected_remainder,
                    quotient,
                    remainder
                );

            end

            // ----------------------------------------------------
            // Consume the result.
            //
            // ready_i = 1 means the receiver accepts the result.
            // ----------------------------------------------------

            @(negedge clk);

            ready_i = 1'b1;

            @(posedge clk);

            @(negedge clk);

            ready_i = 1'b0;

        end

    endtask

    // ------------------------------------------------------------
    // Directed tests
    // ------------------------------------------------------------

    task automatic directed_tests();

        begin

            $display("");
            $display("==============================================");
            $display(" DIRECTED TESTS");
            $display("==============================================");

            // ----------------------------------------------------
            // Basic divisions
            // ----------------------------------------------------

            test_division(
                32'd10,
                32'd2,
                "10 / 2"
            );

            test_division(
                32'd100,
                32'd10,
                "100 / 10"
            );

            test_division(
                32'd100,
                32'd3,
                "100 / 3"
            );

            // ----------------------------------------------------
            // Dividend smaller than divisor
            //
            // Q = 0
            // R = dividend
            // ----------------------------------------------------

            test_division(
                32'd3,
                32'd10,
                "3 / 10"
            );

            // ----------------------------------------------------
            // Equal operands
            // ----------------------------------------------------

            test_division(
                32'd12345,
                32'd12345,
                "A == B"
            );

            // ----------------------------------------------------
            // Dividend = 0
            // ----------------------------------------------------

            test_division(
                32'd0,
                32'd123,
                "0 / 123"
            );

            // ----------------------------------------------------
            // Divisor = 1
            // ----------------------------------------------------

            test_division(
                32'd123456789,
                32'd1,
                "A / 1"
            );

            // ----------------------------------------------------
            // Remainder cases
            // ----------------------------------------------------

            test_division(
                32'd7,
                32'd3,
                "7 / 3"
            );

            test_division(
                32'd15,
                32'd4,
                "15 / 4"
            );

            test_division(
                32'd31,
                32'd7,
                "31 / 7"
            );

            // ----------------------------------------------------
            // Powers of two
            // ----------------------------------------------------

            test_division(
                32'd256,
                32'd16,
                "256 / 16"
            );

            test_division(
                32'd1024,
                32'd32,
                "1024 / 32"
            );

            test_division(
                32'd65536,
                32'd256,
                "65536 / 256"
            );

            // ----------------------------------------------------
            // Maximum values
            // ----------------------------------------------------

            test_division(
                32'hFFFFFFFF,
                32'h00000001,
                "MAX / 1"
            );

            test_division(
                32'hFFFFFFFF,
                32'hFFFFFFFF,
                "MAX / MAX"
            );

            test_division(
                32'hFFFFFFFF,
                32'h00000002,
                "MAX / 2"
            );

            test_division(
                32'hFFFFFFFF,
                32'h00000003,
                "MAX / 3"
            );

            // ----------------------------------------------------
            // Large arbitrary values
            // ----------------------------------------------------

            test_division(
                32'h80000000,
                32'h00000002,
                "80000000 / 2"
            );

            test_division(
                32'h80000000,
                32'h00000003,
                "80000000 / 3"
            );

            test_division(
                32'hDEADBEEF,
                32'h12345678,
                "DEADBEEF / 12345678"
            );

            test_division(
                32'hCAFEBABE,
                32'h00001234,
                "CAFEBABE / 1234"
            );

        end

    endtask

    // ------------------------------------------------------------
    // Random tests
    // ------------------------------------------------------------

    task automatic random_tests(
        input int NUM_TESTS
    );

        logic [WIDTH-1:0] random_dividend;
        logic [WIDTH-1:0] random_divisor;

        begin

            $display("");
            $display("==============================================");
            $display(" RANDOM TESTS: %0d", NUM_TESTS);
            $display("==============================================");

            for (int i = 0; i < NUM_TESTS; i++) begin

                random_dividend = $urandom;
                random_divisor  = $urandom;

                // ------------------------------------------------
                // Avoid divide-by-zero.
                // ------------------------------------------------

                if (random_divisor == 0)
                    random_divisor = 32'd1;

                test_division(
                    random_dividend,
                    random_divisor,
                    $sformatf("Random %0d", i)
                );

            end

        end

    endtask

    // ------------------------------------------------------------
    // Main test sequence
    // ------------------------------------------------------------

    initial begin

        $display("");
        $display("==============================================");
        $display(" RADIX-4 DIVIDER TESTBENCH");
        $display(" WIDTH = %0d", WIDTH);
        $display("==============================================");

        reset_dut();

        directed_tests();

        random_tests(100);

        // --------------------------------------------------------
        // Final report
        // --------------------------------------------------------

        $display("");
        $display("==============================================");
        $display(" TEST SUMMARY");
        $display("==============================================");

        $display("Total tests : %0d", total_tests);
        $display("Passed      : %0d", passed_tests);
        $display("Failed      : %0d", failed_tests);

        if (failed_tests == 0) begin

            $display("");
            $display("**************************************");
            $display("*** ALL TESTS PASSED               ***");
            $display("**************************************");
            $display("");

        end
        else begin

            $display("");
            $display("**************************************");
            $display("*** TEST FAILED                    ***");
            $display("**************************************");
            $display("");

            $fatal(1);

        end

        $finish;

    end

endmodule