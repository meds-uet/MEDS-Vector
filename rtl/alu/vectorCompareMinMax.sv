module vectorCompareMinMax #(
    parameter int ELEN = 32
)(
    input  logic [ELEN-1:0] a,
    input  logic [ELEN-1:0] b,
    input  logic [1:0]      sew,
    input  logic            is_minmax,   // 0 = compare (mask bits out), 1 = min/max (value out)
    input  logic [2:0]      cmp_op,      // used when is_minmax = 0
    input  logic [1:0]      minmax_op,   // used when is_minmax = 1

    output logic [ELEN-1:0] result
    // compare mode : mask bit for sub-element j lands in result[j]
    // minmax mode  : selected value for sub-element j lands in result[j*W +: W]
);

    // Loop index, one sub-element at a time within this lane.
    integer j;

    // Scratch operand pair for whichever width is active this iteration.
    // Declared once and reused every iteration (this is a combinational
    // block re-evaluated every time, so there's no state carried between
    // iterations -- these behave like wires, not registers).
    logic [7:0]  a8,  b8;
    logic [15:0] a16, b16;
    logic [31:0] a32, b32;

    // The shared magnitude core. Every compare op and every min/max op
    // is just boolean logic on these three bits -- they get recomputed
    // fresh for each sub-element, once, and then both the compare case
    // and the min/max case below
    logic eq;   // a == b
    logic ltu;  // a <  b   (unsigned)
    logic lt;   // a <  b   (signed)

    always_comb begin
        result = '0;

        unique case (sew)

            // =========================================================
            // SEW = 8 : this lane holds ELEN/8 independent 8-bit elements
            // (e.g. 4 elements packed into a 32-bit lane).
            // =========================================================
            2'b00: begin
                for (j = 0; j < ELEN/8; j = j + 1) begin

                    // Slice out element j from each operand.
                    a8 = a[j*8 +: 8];
                    b8 = b[j*8 +: 8];

                    // Compute the magnitude core ONCE for this element.
                    eq  = (a8 == b8);
                    ltu = (a8 <  b8);
                    lt  = ($signed(a8) < $signed(b8));

                    if (is_minmax) begin
                        // Min/Max: pick operand a or b, write it back at
                        // its natural byte offset so the lane still looks
                        // like a normal vector of 8-bit elements.
                        case (minmax_op)
                            2'b00: result[j*8 +: 8] = ltu       ? a8 : b8; // vminu: smaller unsigned
                            2'b01: result[j*8 +: 8] = lt        ? a8 : b8; // vmin:  smaller signed
                            2'b10: result[j*8 +: 8] = !(ltu|eq) ? a8 : b8; // vmaxu: larger unsigned
                            2'b11: result[j*8 +: 8] = !(lt|eq)  ? a8 : b8; // vmax:  larger signed
                        endcase
                    end else begin
                        // Compare: write a single mask bit for element j.
                        case (cmp_op)
                            3'b000:  result[j] = eq;            // vmseq
                            3'b001:  result[j] = !eq;           // vmsne
                            3'b010:  result[j] = ltu;           // vmsltu
                            3'b011:  result[j] = lt;            // vmslt
                            3'b100:  result[j] = ltu | eq;      // vmsleu
                            3'b101:  result[j] = lt  | eq;      // vmsle
                            3'b110:  result[j] = !(ltu | eq);   // vmsgtu
                            3'b111:  result[j] = !(lt  | eq);   // vmsgt
                            default: result[j] = 1'b0;
                        endcase
                    end
                end
            end

            // =========================================================
            // SEW = 16 : this lane holds ELEN/16 elements (e.g. 2 per
            // 32-bit lane). Same structure as the SEW=8 case above, just
            // sliced 16 bits at a time.
            // =========================================================
            2'b01: begin
                for (j = 0; j < ELEN/16; j = j + 1) begin

                    a16 = a[j*16 +: 16];
                    b16 = b[j*16 +: 16];

                    eq  = (a16 == b16);
                    ltu = (a16 <  b16);
                    lt  = ($signed(a16) < $signed(b16));

                    if (is_minmax) begin
                        case (minmax_op)
                            2'b00: result[j*16 +: 16] = ltu       ? a16 : b16; // vminu
                            2'b01: result[j*16 +: 16] = lt        ? a16 : b16; // vmin
                            2'b10: result[j*16 +: 16] = !(ltu|eq) ? a16 : b16; // vmaxu
                            2'b11: result[j*16 +: 16] = !(lt|eq)  ? a16 : b16; // vmax
                        endcase
                    end else begin
                        case (cmp_op)
                            3'b000:  result[j] = eq;
                            3'b001:  result[j] = !eq;
                            3'b010:  result[j] = ltu;
                            3'b011:  result[j] = lt;
                            3'b100:  result[j] = ltu | eq;
                            3'b101:  result[j] = lt  | eq;
                            3'b110:  result[j] = !(ltu | eq);
                            3'b111:  result[j] = !(lt  | eq);
                            default: result[j] = 1'b0;
                        endcase
                    end
                end
            end

            // =========================================================
            // SEW = 32 (default also catches the unsupported SEW=64
            // encoding, 2'b11, and just clamps it to a 32-bit element so
            // the mux above never dangles -- this lane can't hold a
            // 64-bit element anyway since ELEN=32).
            // One element fills the entire lane, so there's no loop over
            // sub-elements -- j only ever takes the value 0.
            // =========================================================
            default: begin
                for (j = 0; j < ELEN/32; j = j + 1) begin

                    a32 = a[j*32 +: 32];
                    b32 = b[j*32 +: 32];

                    eq  = (a32 == b32);
                    ltu = (a32 <  b32);
                    lt  = ($signed(a32) < $signed(b32));

                    if (is_minmax) begin
                        case (minmax_op)
                            2'b00: result[j*32 +: 32] = ltu       ? a32 : b32;
                            2'b01: result[j*32 +: 32] = lt        ? a32 : b32;
                            2'b10: result[j*32 +: 32] = !(ltu|eq) ? a32 : b32;
                            2'b11: result[j*32 +: 32] = !(lt|eq)  ? a32 : b32;
                        endcase
                    end else begin
                        case (cmp_op)
                            3'b000:  result[j] = eq;
                            3'b001:  result[j] = !eq;
                            3'b010:  result[j] = ltu;
                            3'b011:  result[j] = lt;
                            3'b100:  result[j] = ltu | eq;
                            3'b101:  result[j] = lt  | eq;
                            3'b110:  result[j] = !(ltu | eq);
                            3'b111:  result[j] = !(lt  | eq);
                            default: result[j] = 1'b0;
                        endcase
                    end
                end
            end

        endcase
    end

endmodule
