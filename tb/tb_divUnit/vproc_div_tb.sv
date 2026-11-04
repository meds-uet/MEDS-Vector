`timescale 1ns/1ps

import v_cfg_pkg::*;

module tb_vproc_div;

    // ================================================================
    // Configuration
    // ================================================================

    localparam int OP_W = 32;

    localparam int NUM_DIRECTED_SEW8  = 20;
    localparam int NUM_DIRECTED_SEW16 = 20;
    localparam int NUM_DIRECTED_SEW32 = 20;

    localparam int RANDOM_TESTS_PER_COMBINATION = 500;
    
    localparam time CLK_PERIOD = 10ns;

    // Maximum number of cycles we allow one vector operation to finish.
    localparam int TIMEOUT_CYCLES = 300;

    logic               clk_i;
    logic               rst_ni;

    logic               valid_i;
    logic               ready_o;

    logic [OP_W-1:0]    op_a_i;
    logic [OP_W-1:0]    op_b_i;

    vdiv_sew_e          sew_i;
    vdiv_op_e           op_i;

    logic               valid_o;
    logic               ready_i;

    logic [OP_W-1:0]    result_o;

    vproc_div #(
        .OP_W(OP_W)
    ) dut (
        .clk_i    (clk_i),
        .rst_ni   (rst_ni),

        .valid_i  (valid_i),
        .ready_o  (ready_o),
        .op_a_i   (op_a_i),
        .op_b_i   (op_b_i),
        .sew_i    (sew_i),
        .op_i     (op_i),

        .valid_o  (valid_o),
        .ready_i  (ready_i),
        .result_o (result_o)
    );

    initial begin
        clk_i = 1'b0;
        forever #(CLK_PERIOD/2)
            clk_i = ~clk_i;
    end

    int total_tests   = 0;
    int passed_tests  = 0;
    int failed_tests  = 0;

    function automatic int get_num_elements(
        input vdiv_sew_e sew
    );
        case (sew)
            VDIV_SEW8:
                get_num_elements = 4;
            VDIV_SEW16:
                get_num_elements = 2;
            VDIV_SEW32:
                get_num_elements = 1;
            default:
                get_num_elements = 1;
        endcase
    endfunction

    function automatic int get_sew(
        input vdiv_sew_e sew
    );
        case (sew)
            VDIV_SEW8:
                get_sew = 8;
            VDIV_SEW16:
                get_sew = 16;
            VDIV_SEW32:
                get_sew = 32;
            default:
                get_sew = 32;
        endcase
    endfunction


    // ================================================================
    // Utility: extract one element from a 32-bit vector
    // ================================================================

    function automatic logic [31:0] get_element(
        input logic [31:0] value,
        input vdiv_sew_e    sew,
        input int           index
    );
        logic [31:0] tmp;
        tmp = '0;
        case (sew)
            VDIV_SEW8: begin
                case (index)
                    0: tmp[7:0]   = value[7:0];
                    1: tmp[7:0]   = value[15:8];
                    2: tmp[7:0]   = value[23:16];
                    3: tmp[7:0]   = value[31:24];
                    default:
                        tmp = '0;
                endcase
            end
            VDIV_SEW16: begin
                case (index)
                    0: tmp[15:0]  = value[15:0];
                    1: tmp[15:0]  = value[31:16];
                    default:
                        tmp = '0;
                endcase
            end
            VDIV_SEW32: begin
                tmp = value;
            end
            default:
                tmp = value;
        endcase
        return tmp;
    endfunction

    function automatic logic [31:0] expected_element(
        input logic [31:0] a_raw,
        input logic [31:0] b_raw,
        input vdiv_sew_e    sew,
        input vdiv_op_e     op
    );

        int width;

        logic [31:0] mask;

        logic [31:0] a_u;
        logic [31:0] b_u;

        logic signed [63:0] a_s64;
        logic signed [63:0] b_s64;

        logic [63:0] quotient_u64;
        logic [63:0] remainder_u64;

        logic signed [63:0] quotient_s64;
        logic signed [63:0] remainder_s64;

        logic [31:0] result;

        width = get_sew(sew);
        case (width)
            8: mask = 32'h000000FF;
            16: mask = 32'h0000FFFF;
            32: mask = 32'hFFFFFFFF;
            default: mask = 32'hFFFFFFFF;
        endcase

        a_u = a_raw & mask;
        b_u = b_raw & mask;

        result = '0;

        quotient_u64  = '0;
        remainder_u64 = '0;

        quotient_s64  = '0;
        remainder_s64 = '0;

        if ((op == VDIV_DIVU) || (op == VDIV_REMU)) begin
            if(b_u == 32'h0000_0000) begin
                quotient_u64  = 64'hFFFFFFFF_FFFFFFFF;
                remainder_u64 = a_u / 1;
            end else begin
                quotient_u64  = a_u / b_u;
                remainder_u64 = a_u % b_u;
            end

            if (op == VDIV_DIVU)
                result = quotient_u64[31:0];
            else
                result = remainder_u64[31:0];
        end
        else begin
            case (width)
                8: begin
                    a_s64 = $signed({{56{a_u[7]}},  a_u[7:0]});
                    b_s64 = $signed({{56{b_u[7]}},  b_u[7:0]});
                end
                16: begin
                    a_s64 = $signed({{48{a_u[15]}}, a_u[15:0]});
                    b_s64 = $signed({{48{b_u[15]}}, b_u[15:0]});
                end
                32: begin
                    a_s64 = $signed({{32{a_u[31]}}, a_u[31:0]});
                    b_s64 = $signed({{32{b_u[31]}}, b_u[31:0]});
                end
                default: begin
                    a_s64 = $signed(a_u);
                    b_s64 = $signed(b_u);
                end

            endcase

            if(b_s64 == 64'h00000000_00000000) begin
                quotient_s64  = 64'hFFFFFFFF_FFFFFFFF;
                remainder_s64 = a_s64;
            end else begin
                quotient_s64  = a_s64 / b_s64;
                remainder_s64 = a_s64 % b_s64;
            end

            if (op == VDIV_DIV)
                result = quotient_s64[31:0];
            else
                result = remainder_s64[31:0];
        end

        result = result & mask;
        return result;
    endfunction


    // ================================================================
    // Expected complete 32-bit vector result
    // ================================================================

    function automatic logic [31:0] expected_vector(
        input logic [31:0] a,
        input logic [31:0] b,
        input vdiv_sew_e    sew,
        input vdiv_op_e     op
    );
        logic [31:0] result;

        int num_elements;
        int i;

        logic [31:0] a_elem;
        logic [31:0] b_elem;
        logic [31:0] r_elem;

        result = '0;

        num_elements = get_num_elements(sew);

        for (i = 0; i < num_elements; i++) begin

            a_elem = get_element(a, sew, i);
            b_elem = get_element(b, sew, i);
            
            r_elem = expected_element(
                a_elem,
                b_elem,
                sew,
                op
            );

            case (sew)
                VDIV_SEW8: begin
                    case (i)
                        0: result[7:0]   = r_elem[7:0];
                        1: result[15:8]  = r_elem[7:0];
                        2: result[23:16] = r_elem[7:0];
                        3: result[31:24] = r_elem[7:0];
                    endcase
                end
                VDIV_SEW16: begin
                    case (i)
                        0: result[15:0]  = r_elem[15:0];
                        1: result[31:16] = r_elem[15:0];
                    endcase
                end
                VDIV_SEW32:
                    result = r_elem;
                default:
                    result = r_elem;
            endcase
        end
        return result;

    endfunction

    function automatic string op_name(
        input vdiv_op_e op
    );
        case (op)
            VDIV_DIV:
                op_name = "DIV";
            VDIV_DIVU:
                op_name = "DIVU";
            VDIV_REM:
                op_name = "REM";
            VDIV_REMU:
                op_name = "REMU";
            default:
                op_name = "UNKNOWN";
        endcase

    endfunction

    function automatic string sew_name(
        input vdiv_sew_e sew
    );
        case (sew)
            VDIV_SEW8:
                sew_name = "SEW8";
            VDIV_SEW16:
                sew_name = "SEW16";
            VDIV_SEW32:
                sew_name = "SEW32";
            default:
                sew_name = "UNKNOWN";
        endcase
    endfunction

    task automatic reset_dut();

        valid_i = 1'b0;
        ready_i = 1'b0;

        op_a_i = '0;
        op_b_i = '0;

        sew_i = VDIV_SEW32;
        op_i  = VDIV_DIVU;

        rst_ni = 1'b0;

        repeat (5)
        @(posedge clk_i);
        rst_ni = 1'b1;
        repeat (2)
        @(posedge clk_i);

    endtask

    task automatic wait_for_input_ready();
        
        int timeout;
        timeout = 0;

        while (!ready_o) begin
            @(posedge clk_i);
            timeout++;

            if (timeout > TIMEOUT_CYCLES) begin
                $fatal(
                    1,
                    "[TB] TIMEOUT waiting for DUT ready_o"
                );
            end

        end

    endtask

    task automatic wait_for_result(
        output logic [31:0] received
    );
        int timeout;
        timeout = 0;
        ready_i = 1'b1;

        while (!valid_o) begin
            @(posedge clk_i);
            timeout++;

            if (timeout > TIMEOUT_CYCLES) begin
                ready_i = 1'b0;
                $fatal(
                    1,
                    "[TB] TIMEOUT waiting for valid_o"
                );
            end

        end

        received = result_o;
        // Give the DUT one clock to consume the result.
        @(posedge clk_i);
        ready_i = 1'b0;

    endtask

    task automatic direct_test(
        input logic [31:0] a,
        input logic [31:0] b,
        input vdiv_sew_e    sew,
        input vdiv_op_e     op,
        input string        test_name
    );

        logic [31:0] expected;
        logic [31:0] received;

        expected = expected_vector(
            a,
            b,
            sew,
            op
        );

        wait_for_input_ready();

        @(negedge clk_i);

        op_a_i = a;
        op_b_i = b;

        sew_i = sew;
        op_i  = op;

        valid_i = 1'b1;

        do begin
            @(posedge clk_i);
        end while (!ready_o);

        @(negedge clk_i);
        valid_i = 1'b0;

        wait_for_result(received);

        total_tests++;
        if (received === expected) begin
            passed_tests++;
            $display(
                "[PASS] %-35s %-5s %-4s A=%08h B=%08h RESULT=%08h",
                test_name,
                sew_name(sew),
                op_name(op),
                a,
                b,
                received
            );
        end
        else begin

            failed_tests++;
            $error(
                "[FAIL] %-35s %-5s %-4s A=%08h B=%08h EXPECTED=%08h RECEIVED=%08h",
                test_name,
                sew_name(sew),
                op_name(op),
                a,
                b,
                expected,
                received
            );
        end
    endtask

    task automatic random_test(
        input vdiv_sew_e sew,
        input vdiv_op_e  op,
        input int        num_tests
    );
        logic [31:0] a;
        logic [31:0] b;

        int width;
        int num_elements;

        int i;

        logic [31:0] divisor_elem;

        width = get_sew(sew);

        num_elements = get_num_elements(sew);


        repeat (num_tests) begin

            // Generates random 32-bit binary sequences
            a = $urandom;
            b = $urandom;

            // for (i = 0; i < num_elements; i++) begin

            //     divisor_elem = get_element(
            //         b,
            //         sew,
            //         i
            //     );

            //     if (divisor_elem == 0) begin
            //         case (width)
            //             8: begin
            //                 case (i)
            //                     0: b[7:0]   = 8'h01;
            //                     1: b[15:8]  = 8'h01;
            //                     2: b[23:16] = 8'h01;
            //                     3: b[31:24] = 8'h01;
            //                 endcase
            //             end
            //             16: begin
            //                 case (i)
            //                     0: b[15:0]  = 16'h0001;
            //                     1: b[31:16] = 16'h0001;
            //                 endcase
            //             end
            //             32:
            //                 b = 32'h00000001;
            //         endcase
            //     end
            // end

            direct_test(
                a,
                b,
                sew,
                op,
                "Random"
            );
        end
    endtask

    task automatic directed_edge_tests(
        input vdiv_sew_e sew
    );

        logic [31:0] min_v;
        logic [31:0] max_v;
        logic [31:0] minus_one;
        logic [31:0] one;
        logic [31:0] two;
        logic [31:0] three;
        logic [31:0] zero = 32'h00000000;

        logic [31:0] a;
        logic [31:0] b;

        case (sew)

            VDIV_SEW8: begin
                min_v     = 32'h80808080;
                max_v     = 32'h7F7F7F7F;
                minus_one = 32'hFFFFFFFF;
                one       = 32'h01010101;
                two       = 32'h02020202;
                three     = 32'h03030303;
            end

            VDIV_SEW16: begin
                min_v     = 32'h80008000;
                max_v     = 32'h7FFF7FFF;
                minus_one = 32'hFFFFFFFF;
                one       = 32'h00010001;
                two       = 32'h00020002;
                three     = 32'h00030003;
            end

            VDIV_SEW32: begin
                min_v     = 32'h80000000;
                max_v     = 32'h7FFFFFFF;
                minus_one = 32'hFFFFFFFF;
                one       = 32'h00000001;
                two       = 32'h00000002;
                three     = 32'h00000003;
            end
            default: begin
                min_v     = 32'h80000000;
                max_v     = 32'h7FFFFFFF;
                minus_one = 32'hFFFFFFFF;
                one       = 32'h00000001;
                two       = 32'h00000002;
                three     = 32'h00000003;
            end
        endcase


        // ============================================================
        // DIV signed
        // ============================================================

        direct_test(
            one,
            one,
            sew,
            VDIV_DIV,
            "1 / 1"
        );

        direct_test(
            max_v,
            one,
            sew,
            VDIV_DIV,
            "MAX / 1"
        );

        direct_test(
            min_v,
            one,
            sew,
            VDIV_DIV,
            "MIN / 1"
        );

        direct_test(
            one,
            minus_one,
            sew,
            VDIV_DIV,
            "1 / -1"
        );

        direct_test(
            minus_one,
            one,
            sew,
            VDIV_DIV,
            "-1 / 1"
        );

        direct_test(
            minus_one,
            minus_one,
            sew,
            VDIV_DIV,
            "-1 / -1"
        );

        direct_test(
            min_v,
            minus_one,
            sew,
            VDIV_DIV,
            "MIN / -1"
        );

        direct_test(
            max_v,
            minus_one,
            sew,
            VDIV_DIV,
            "MAX / -1"
        );

        direct_test(
            min_v,
            min_v,
            sew,
            VDIV_DIV,
            "MIN / MIN"
        );

        direct_test(
            max_v,
            max_v,
            sew,
            VDIV_DIV,
            "MAX / MAX"
        );

        direct_test(
            one,
            zero,
            sew,
            VDIV_DIV,
            "1 / 0"
        );

        // ============================================================
        // Signed division where quotient = 0
        // ============================================================

        direct_test(
            one,
            two,
            sew,
            VDIV_DIV,
            "1 / 2 = 0"
        );

        direct_test(
            minus_one,
            two,
            sew,
            VDIV_DIV,
            "-1 / 2 = 0"
        );

        direct_test(
            one,
            three,
            sew,
            VDIV_DIV,
            "1 / 3 = 0"
        );

        // ============================================================
        // Signed remainder
        // ============================================================

        direct_test(
            one,
            one,
            sew,
            VDIV_REM,
            "1 % 1"
        );

        direct_test(
            max_v,
            one,
            sew,
            VDIV_REM,
            "MAX % 1"
        );

        direct_test(
            min_v,
            one,
            sew,
            VDIV_REM,
            "MIN % 1"
        );

        direct_test(
            minus_one,
            one,
            sew,
            VDIV_REM,
            "-1 % 1"
        );

        direct_test(
            minus_one,
            two,
            sew,
            VDIV_REM,
            "-1 % 2"
        );

        direct_test(
            one,
            minus_one,
            sew,
            VDIV_REM,
            "1 % -1"
        );

        direct_test(
            min_v,
            minus_one,
            sew,
            VDIV_REM,
            "MIN % -1"
        );

        direct_test(
            min_v,
            two,
            sew,
            VDIV_REM,
            "MIN % 2"
        );

        direct_test(
            max_v,
            three,
            sew,
            VDIV_REM,
            "MAX % 3"
        );

        direct_test(
            one,
            zero,
            sew,
            VDIV_REM,
            "1 % 0"
        );

        // ============================================================
        // Signed remainder where remainder = dividend
        // ============================================================

        direct_test(
            one,
            two,
            sew,
            VDIV_REM,
            "1 / 2 = 0"
        );

        direct_test(
            minus_one,
            two,
            sew,
            VDIV_REM,
            "-1 / 2 = 0"
        );

        direct_test(
            one,
            three,
            sew,
            VDIV_REM,
            "1 / 3 = 0"
        );

        // ============================================================
        // Unsigned DIVU
        // ============================================================

        direct_test(
            one,
            one,
            sew,
            VDIV_DIVU,
            "1 /U 1"
        );

        direct_test(
            max_v,
            one,
            sew,
            VDIV_DIVU,
            "MAX /U 1"
        );

        direct_test(
            min_v,
            one,
            sew,
            VDIV_DIVU,
            "MIN_BITS /U 1"
        );

        direct_test(
            max_v,
            max_v,
            sew,
            VDIV_DIVU,
            "MAX /U MAX"
        );

        direct_test(
            min_v,
            min_v,
            sew,
            VDIV_DIVU,
            "MIN_BITS /U MIN_BITS"
        );

        direct_test(
            one,
            two,
            sew,
            VDIV_DIVU,
            "1 /U 2"
        );

        direct_test(
            max_v,
            two,
            sew,
            VDIV_DIVU,
            "MAX /U 2"
        );

        direct_test(
            max_v,
            three,
            sew,
            VDIV_DIVU,
            "MAX /U 3"
        );

        direct_test(
            one,
            zero,
            sew,
            VDIV_DIVU,
            "1 /U 0"
        );

        // ============================================================
        // Unsigned REMU
        // ============================================================

        direct_test(
            one,
            one,
            sew,
            VDIV_REMU,
            "1 %U 1"
        );

        direct_test(
            max_v,
            one,
            sew,
            VDIV_REMU,
            "MAX %U 1"
        );

        direct_test(
            min_v,
            min_v,
            sew,
            VDIV_REMU,
            "MIN_BITS %U MIN_BITS"
        );

        direct_test(
            max_v,
            two,
            sew,
            VDIV_REMU,
            "MAX %U 2"
        );

        direct_test(
            max_v,
            three,
            sew,
            VDIV_REMU,
            "MAX %U 3"
        );

        direct_test(
            one,
            zero,
            sew,
            VDIV_REMU,
            "1 %U 0"
        );

        // ============================================================
        // Explicit mixed-sign cases
        // ============================================================

        direct_test(
            minus_one,
            two,
            sew,
            VDIV_DIV,
            "-1 / +2"
        );

        direct_test(
            minus_one,
            two,
            sew,
            VDIV_REM,
            "-1 % +2"
        );

        direct_test(
            one,
            minus_one,
            sew,
            VDIV_DIV,
            "+1 / -1"
        );

        direct_test(
            one,
            minus_one,
            sew,
            VDIV_REM,
            "+1 % -1"
        );

        direct_test(
            min_v,
            max_v,
            sew,
            VDIV_DIV,
            "MIN / MAX"
        );

        direct_test(
            min_v,
            max_v,
            sew,
            VDIV_REM,
            "MIN % MAX"
        );

        direct_test(
            max_v,
            min_v,
            sew,
            VDIV_DIV,
            "MAX / MIN"
        );

        direct_test(
            max_v,
            min_v,
            sew,
            VDIV_REM,
            "MAX % MIN"
        );

    endtask


    // ================================================================
    // Special vector tests
    // These specifically test element extraction and result packing.
    // Particularly important for SEW8 and SEW16.
    // ================================================================

    task automatic vector_position_tests();

        // ------------------------------------------------------------
        // The same operation is used, but every element is different.
        // SEW = 8
        // ------------------------------------------------------------

        direct_test(
            32'h807F01FF,
            32'h02030100,
            VDIV_SEW8,
            VDIV_DIV,
            "SEW8 different elements"
        );

        direct_test(
            32'h807F01FF,
            32'h02030002,
            VDIV_SEW8,
            VDIV_REM,
            "SEW8 remainder elements"
        );

        direct_test(
            32'h807F01FF,
            32'h02030102,
            VDIV_SEW8,
            VDIV_DIVU,
            "SEW8 unsigned elements"
        );

        direct_test(
            32'h807F01FF,
            32'h02030102,
            VDIV_SEW8,
            VDIV_REMU,
            "SEW8 unsigned remainder"
        );

        // ------------------------------------------------------------
        // SEW = 16
        // ------------------------------------------------------------

        direct_test(
            32'h80017FFF,
            32'h00020000,
            VDIV_SEW16,
            VDIV_DIV,
            "SEW16 different elements"
        );

        direct_test(
            32'h80017FFF,
            32'h00020003,
            VDIV_SEW16,
            VDIV_REM,
            "SEW16 remainder elements"
        );

        direct_test(
            32'h80017FFF,
            32'h00020003,
            VDIV_SEW16,
            VDIV_DIVU,
            "SEW16 unsigned elements"
        );

        direct_test(
            32'h80017FFF,
            32'h00020003,
            VDIV_SEW16,
            VDIV_REMU,
            "SEW16 unsigned remainder"
        );
    endtask


    // ================================================================
    // Main test sequence
    // ================================================================

    initial begin

        $display("");
        $display("==============================================================");
        $display("              VPROC_DIV SELF-CHECKING TESTBENCH");
        $display("==============================================================");
        $display("");
        $display("Configuration:");
        $display("  OP_W = %0d", OP_W);
        $display("  Scalar divider width = 32");
        $display("  Radix = 4");
        $display("  SEW = 8 / 16 / 32");
        $display("  Operations = DIV / DIVU / REM / REMU");
        $display("  Divide-by-zero = EXCLUDED");
        $display("");

        reset_dut();

        $display("");
        $display("--------------------------------------------------------------");
        $display("DIRECTED EDGE TESTS: SEW8");
        $display("--------------------------------------------------------------");

        directed_edge_tests(VDIV_SEW8);

        $display("");
        $display("--------------------------------------------------------------");
        $display("DIRECTED EDGE TESTS: SEW16");
        $display("--------------------------------------------------------------");

        directed_edge_tests(VDIV_SEW16);

        $display("");
        $display("--------------------------------------------------------------");
        $display("DIRECTED EDGE TESTS: SEW32");
        $display("--------------------------------------------------------------");

        directed_edge_tests(VDIV_SEW32);

        // ------------------------------------------------------------
        // Explicit vector element-position tests.
        // ------------------------------------------------------------

        $display("");
        $display("--------------------------------------------------------------");
        $display("VECTOR ELEMENT POSITION / PACKING TESTS");
        $display("--------------------------------------------------------------");

        vector_position_tests();

        $display("");
        $display("--------------------------------------------------------------");
        $display(
            "RANDOM TESTS: SEW8 (%0d tests/op)",
            RANDOM_TESTS_PER_COMBINATION
        );
        $display("--------------------------------------------------------------");

        random_test(
            VDIV_SEW8,
            VDIV_DIV,
            RANDOM_TESTS_PER_COMBINATION
        );

        random_test(
            VDIV_SEW8,
            VDIV_DIVU,
            RANDOM_TESTS_PER_COMBINATION
        );

        random_test(
            VDIV_SEW8,
            VDIV_REM,
            RANDOM_TESTS_PER_COMBINATION
        );

        random_test(
            VDIV_SEW8,
            VDIV_REMU,
            RANDOM_TESTS_PER_COMBINATION
        );

        $display("");
        $display("--------------------------------------------------------------");
        $display(
            "RANDOM TESTS: SEW16 (%0d tests/op)",
            RANDOM_TESTS_PER_COMBINATION
        );
        $display("--------------------------------------------------------------");

        random_test(
            VDIV_SEW16,
            VDIV_DIV,
            RANDOM_TESTS_PER_COMBINATION
        );

        random_test(
            VDIV_SEW16,
            VDIV_DIVU,
            RANDOM_TESTS_PER_COMBINATION
        );

        random_test(
            VDIV_SEW16,
            VDIV_REM,
            RANDOM_TESTS_PER_COMBINATION
        );

        random_test(
            VDIV_SEW16,
            VDIV_REMU,
            RANDOM_TESTS_PER_COMBINATION
        );

        $display("");
        $display("--------------------------------------------------------------");
        $display(
            "RANDOM TESTS: SEW32 (%0d tests/op)",
            RANDOM_TESTS_PER_COMBINATION
        );
        $display("--------------------------------------------------------------");

        random_test(
            VDIV_SEW32,
            VDIV_DIV,
            RANDOM_TESTS_PER_COMBINATION
        );

        random_test(
            VDIV_SEW32,
            VDIV_DIVU,
            RANDOM_TESTS_PER_COMBINATION
        );

        random_test(
            VDIV_SEW32,
            VDIV_REM,
            RANDOM_TESTS_PER_COMBINATION
        );

        random_test(
            VDIV_SEW32,
            VDIV_REMU,
            RANDOM_TESTS_PER_COMBINATION
        );


        $display("");
        $display("==============================================================");
        $display("                       TEST SUMMARY");
        $display("==============================================================");
        $display("  Total tests  : %0d", total_tests);
        $display("  Passed       : %0d", passed_tests);
        $display("  Failed       : %0d", failed_tests);
        $display("==============================================================");


        if (failed_tests == 0) begin

            $display("");
            $display("##############################################################");
            $display("#                                                            #");
            $display("#                  ALL TESTS PASSED                         #");
            $display("#                                                            #");
            $display("##############################################################");
            $display("");

            $finish;

        end
        else begin

            $display("");
            $display("##############################################################");
            $display("#                                                            #");
            $display("#                  TESTS FAILED                             #");
            $display("#                                                            #");
            $display("##############################################################");
            $display("");

            $fatal(1);

        end

    end

endmodule