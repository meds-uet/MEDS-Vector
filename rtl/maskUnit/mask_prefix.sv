module mask_prefix #(

    parameter int N      = 4,

    parameter int W      = 1,

    parameter bit IS_ADD = 1'b0

) (

    input  logic [W-1:0] in          [N],

    output logic [W-1:0] excl_prefix [N],

    output logic [W-1:0] total

);

    // Number of doubling stages needed to cover N inputs. N<=1 needs none.
    localparam int STAGES = (N <= 1) ? 0 : $clog2(N);

    // stage[0] = raw inputs. stage[s][i] = combine of the 2**s inputs ending
    // at i (or fewer, near the low end), each stage built only from the one
    // before it -- never from another element in the same stage.
    logic [W-1:0] stage [STAGES+1][N];

    genvar s, i;

    generate

        for (i = 0; i < N; i++) begin : g_seed

            assign stage[0][i] = in[i];

        end

        for (s = 1; s <= STAGES; s++) begin : g_stage

            for (i = 0; i < N; i++) begin : g_elem

                if (i >= (1 << (s-1))) begin : g_combine

                    assign stage[s][i] = IS_ADD
                        ? (stage[s-1][i] + stage[s-1][i - (1 << (s-1))])
                        : (stage[s-1][i] | stage[s-1][i - (1 << (s-1))]);

                end
                else begin : g_pass

                    assign stage[s][i] = stage[s-1][i];

                end

            end

        end

        for (i = 0; i < N; i++) begin : g_out

            // Slice 0 has nothing before it.
            assign excl_prefix[i] = (i == 0) ? '0 : stage[STAGES][i-1];

        end

    endgenerate

    assign total = stage[STAGES][N-1];

endmodule
