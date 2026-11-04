`timescale 1ns/1ps

module tb_v_alu;
    import v_alu_pkg::*;

    localparam int WIDTH = v_cfg_pkg::ELEN;
    localparam int NB    = WIDTH/8;

    logic [WIDTH-1:0]    vs2, vs1, vd;
    logic [NB-1:0]       vmask;
    logic [1:0]          Sew;
    logic [OPTYPE_W-1:0] optype;

    v_alu #(.WIDTH(WIDTH)) dut (
        .vs2(vs2), .vs1(vs1), .vmask(vmask),
        .Sew(Sew), .optype(optype), .vd(vd)
    );

    //   kind 0 : elementwise at SEW (adc/sbc family, plain add/sub)
    //   kind 1 : widening, both operands narrow   (.vv/.vx)
    //   kind 2 : widening, vs2 already wide       (.wv/.wx)
    //   kind 3 : integer extension (vzext/vsext), ratio = 2 or 4

    task automatic props(input  logic [OPTYPE_W-1:0] op,
                         output int   kind, output int ratio,
                         output logic sub, sgn, has_min, mask_out);
        kind = 0; ratio = 0; sub = 0; sgn = 0; has_min = 0; mask_out = 0;
        case (op)
            OP_VADC_VVM,  OP_VADC_VXM,  OP_VADC_VIM:  has_min = 1;
            OP_VMADC_VVM, OP_VMADC_VXM, OP_VMADC_VIM: begin mask_out = 1; has_min = 1; end
            OP_VMADC_VV,  OP_VMADC_VX,  OP_VMADC_VI:  mask_out = 1;
            OP_VSBC_VVM,  OP_VSBC_VXM:                begin sub = 1; has_min = 1; end
            OP_VMSBC_VVM, OP_VMSBC_VXM:               begin sub = 1; mask_out = 1; has_min = 1; end
            OP_VMSBC_VV,  OP_VMSBC_VX:                begin sub = 1; mask_out = 1; end
            OP_VADD_VV,   OP_VADD_VX,   OP_VADD_VI:   ;
            OP_VSUB_VV,   OP_VSUB_VX:                 sub = 1;

            OP_VWADDU_VV, OP_VWADDU_VX: kind = 1;
            OP_VWADD_VV,  OP_VWADD_VX:  begin kind = 1; sgn = 1; end
            OP_VWSUBU_VV, OP_VWSUBU_VX: begin kind = 1; sub = 1; end
            OP_VWSUB_VV,  OP_VWSUB_VX:  begin kind = 1; sub = 1; sgn = 1; end
            OP_VWADDU_WV, OP_VWADDU_WX: kind = 2;
            OP_VWADD_WV,  OP_VWADD_WX:  begin kind = 2; sgn = 1; end
            OP_VWSUBU_WV, OP_VWSUBU_WX: begin kind = 2; sub = 1; end
            OP_VWSUB_WV,  OP_VWSUB_WX:  begin kind = 2; sub = 1; sgn = 1; end

            OP_VZEXT_VF2: begin kind = 3; ratio = 2; end
            OP_VSEXT_VF2: begin kind = 3; ratio = 2; sgn = 1; end
            OP_VZEXT_VF4: begin kind = 3; ratio = 4; end
            OP_VSEXT_VF4: begin kind = 3; ratio = 4; sgn = 1; end
            default: ;
        endcase
    endtask

    // Which SEWs are legal for an opcode when ELEN = 32.
    function automatic logic legal(input int kind, input int ratio, input int sew);
        case (kind)
            0:       legal = (sew <= 2);
            1, 2:    legal = (sew <= 1);                        // 2*SEW must fit in 32 bits
            3:       legal = (ratio == 2) ? (sew >= 1) : (sew == 2); // source EEW must be >= 8 bits
            default: legal = 0;
        endcase
    endfunction

    // Reference model: plain integer arithmetic, one element at a time.

    // Extract a field of width w starting at bit lo from a 32-bit vector v.
    function automatic longint unsigned field(input logic [31:0] v, input int lo, input int w);
        field = 0;
        for (int k = 0; k < w; k++)
            field = field | (longint'(v[lo+k]) << k);
    endfunction

    // Sign-extend a value v of width w to a longint, if sgn is true.
    function automatic longint sext(input longint unsigned v, input int w, input logic sgn);
        if (sgn && (((v >> (w-1)) & 1) == 1)) sext = longint'(v) - (longint'(1) << w);
        else                                  sext = longint'(v);
    endfunction


    task automatic reference(input  logic [OPTYPE_W-1:0] op,
                             input  logic [31:0] v2, v1,
                             input  logic [NB-1:0] m,
                             input  int sew,
                             output logic [31:0] expected);
        
        // bits: sew width in bits, dbits: destination width in bits, sbits: source width in bits
        int   kind, ratio, bits, dbits, sbits;
        logic sub, sgn, has_min, mask_out, flag;
        longint a, b, cin, r, msk;
        longint unsigned acc;

        props(op, kind, ratio, sub, sgn, has_min, mask_out);
        bits = 8 << sew;
        acc  = 0;

        //msk: mask for the result of each element; sew 8 msk = 0xFF, sew 16 msk = 0xFFFF, sew 32 msk = 0xFFFFFFFF
        if (kind == 0) begin
            msk = (longint'(1) << bits) - 1;
            for (int j = 0; j < 32/bits; j++) begin
                a   = field(v2, j*bits, bits); //extracting the j-th element from v2
                b   = field(v1, j*bits, bits); //extracting the j-th element from v1
                cin = has_min ? longint'(m[j]) : 0;
                if (sub) begin r = a - b - cin; flag = (r < 0);                end //flag is set if the result is negative, indicating a borrow
                else if (has_min) begin r = a + b + cin; flag = (r > msk); end //flag is set if the result exceeds the maximum value for the element width
                else     begin r = a + b + cin; flag = ((r >> bits) & 1) == 1; end
                if (mask_out) acc = acc | (longint'(flag) << j);
                else          acc = acc | ((r & msk) << (j*bits));
            end
        end
        else if (kind == 1 || kind == 2) begin
            sbits = bits;  dbits = 2*bits;
            msk   = (longint'(1) << dbits) - 1;
            for (int j = 0; j < 32/dbits; j++) begin
                b = sext(field(v1, j*sbits, sbits), sbits, sgn); // extracting the j-th element from v1 and sign-extending it if necessary
                a = (kind == 1) ? sext(field(v2, j*sbits, sbits), sbits, sgn)// extracting the j-th element from v2 and sign-extending it if necessary
                                : longint'(field(v2, j*dbits, dbits)); // for kind == 2, v2 is already wide, so we extract the j-th element directly
                r = sub ? (a - b) : (a + b);
                acc = acc | ((r & msk) << (j*dbits));
            end
        end
        else begin // kind 3
            dbits = bits;  sbits = dbits / ratio;
            msk   = (longint'(1) << dbits) - 1;
            for (int j = 0; j < 32/dbits; j++) begin
                r = sext(field(v2, j*sbits, sbits), sbits, sgn);
                acc = acc | ((r & msk) << (j*dbits));
            end
        end
        expected = acc[31:0];
    endtask

    // Checkers
    int pass_cnt = 0;
    int fail_cnt = 0;
    int per_op [NUM_OPS];

    task automatic drive(input logic [OPTYPE_W-1:0] op, input logic [31:0] a2, a1,
                         input logic [NB-1:0] m, input int sew);
        optype = op; vs2 = a2; vs1 = a1; vmask = m; Sew = sew[1:0];
        #1;
    endtask

    // compare against the reference model
    task automatic check(input logic [OPTYPE_W-1:0] op, input logic [31:0] a2, a1,
                         input logic [NB-1:0] m, input int sew);
        logic [31:0] want;
        reference(op, a2, a1, m, sew, want);
        drive(op, a2, a1, m, sew);
        per_op[op]++;
        if (vd === want) pass_cnt++;
        else begin
            fail_cnt++;
            if (fail_cnt <= 20)
                $display("FAIL op=%0d Sew=%0d vs2=%08h vs1=%08h vmask=%b : vd=%08h expected=%08h",
                         op, sew, a2, a1, m, vd, want);
        end
    endtask

    // Stimulus

    logic [31:0] corner [8];
    logic [3:0]  masks  [4];
    int          kind, ratio;
    logic        sub, sgn, has_min, mask_out;
    logic [OPTYPE_W-1:0] op;

    initial begin
        corner[0] = 32'h0000_0000;  corner[1] = 32'hFFFF_FFFF;
        corner[2] = 32'h7F7F_7F7F;  corner[3] = 32'h8080_8080;
        corner[4] = 32'h7FFF_7FFF;  corner[5] = 32'h8000_8000;
        corner[6] = 32'h7FFF_FFFF;  corner[7] = 32'h8000_0000;
        masks[0] = 4'b0000; masks[1] = 4'b1111; masks[2] = 4'b0101; masks[3] = 4'b1010;
        for (int i = 0; i < NUM_OPS; i++) per_op[i] = 0;

        // every opcode x every legal SEW: corner pairs x masks, then random 
        for (int o = 0; o < NUM_OPS; o++) begin
            op = o;
            props(op, kind, ratio, sub, sgn, has_min, mask_out);
            for (int s = 0; s < 3; s++) begin
                if (legal(kind, ratio, s)) begin
                    for (int x = 0; x < 8; x++)
                        for (int y = 0; y < 8; y++)
                            for (int k = 0; k < 4; k++)
                                check(op, corner[x], corner[y], masks[k], s);
                    for (int r = 0; r < 100; r++)
                        check(op, $urandom, $urandom, $urandom, s);
                end
            end
        end

        // every opcode must have been checked 
        for (int o = 0; o < NUM_OPS; o++)
            if (per_op[o] == 0) begin
                fail_cnt++;
                $display("FAIL opcode %0d was never tested", o);
            end

        $display("----------------------------------------------------");
        $display("PASS = %0d   FAIL = %0d", pass_cnt, fail_cnt);
        if (fail_cnt == 0) $display("RESULT: ALL TESTS PASSED");
        else               $display("RESULT: FAILURES DETECTED");
        $display("----------------------------------------------------");
        $finish;
    end
endmodule