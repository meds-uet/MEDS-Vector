
// v_alu_pkg : constants that the ALU, its testbenchmust all agree on.
package v_alu_pkg;

    localparam int OPTYPE_W = 6;

    // SEW encoding used on the Sew port: 0 -> 8, 1 -> 16, 2 -> 32
    localparam logic [1:0] SEW_8  = 2'd0;
    localparam logic [1:0] SEW_16 = 2'd1;
    localparam logic [1:0] SEW_32 = 2'd2;

    // add/sub with carry/borrow 
    localparam logic [OPTYPE_W-1:0] OP_VADC_VVM   = 6'd0;
    localparam logic [OPTYPE_W-1:0] OP_VADC_VXM   = 6'd1;
    localparam logic [OPTYPE_W-1:0] OP_VADC_VIM   = 6'd2;
    localparam logic [OPTYPE_W-1:0] OP_VMADC_VVM  = 6'd3;
    localparam logic [OPTYPE_W-1:0] OP_VMADC_VXM  = 6'd4;
    localparam logic [OPTYPE_W-1:0] OP_VMADC_VIM  = 6'd5;
    localparam logic [OPTYPE_W-1:0] OP_VMADC_VV   = 6'd6;
    localparam logic [OPTYPE_W-1:0] OP_VMADC_VX   = 6'd7;
    localparam logic [OPTYPE_W-1:0] OP_VMADC_VI   = 6'd8;
    localparam logic [OPTYPE_W-1:0] OP_VSBC_VVM   = 6'd9;
    localparam logic [OPTYPE_W-1:0] OP_VSBC_VXM   = 6'd10;
    localparam logic [OPTYPE_W-1:0] OP_VMSBC_VVM  = 6'd11;
    localparam logic [OPTYPE_W-1:0] OP_VMSBC_VXM  = 6'd12;
    localparam logic [OPTYPE_W-1:0] OP_VMSBC_VV   = 6'd13;
    localparam logic [OPTYPE_W-1:0] OP_VMSBC_VX   = 6'd14;

    // widening, 2*SEW = SEW +/- 
    localparam logic [OPTYPE_W-1:0] OP_VWADDU_VV  = 6'd15;
    localparam logic [OPTYPE_W-1:0] OP_VWADDU_VX  = 6'd16;
    localparam logic [OPTYPE_W-1:0] OP_VWADD_VV   = 6'd17;
    localparam logic [OPTYPE_W-1:0] OP_VWADD_VX   = 6'd18;
    localparam logic [OPTYPE_W-1:0] OP_VWSUBU_VV  = 6'd19;
    localparam logic [OPTYPE_W-1:0] OP_VWSUBU_VX  = 6'd20;
    localparam logic [OPTYPE_W-1:0] OP_VWSUB_VV   = 6'd21;
    localparam logic [OPTYPE_W-1:0] OP_VWSUB_VX   = 6'd22;

    // widening, 2*SEW = 2*SEW +/- 
    localparam logic [OPTYPE_W-1:0] OP_VWADDU_WV  = 6'd23;
    localparam logic [OPTYPE_W-1:0] OP_VWADDU_WX  = 6'd24;
    localparam logic [OPTYPE_W-1:0] OP_VWADD_WV   = 6'd25;
    localparam logic [OPTYPE_W-1:0] OP_VWADD_WX   = 6'd26;
    localparam logic [OPTYPE_W-1:0] OP_VWSUBU_WV  = 6'd27;
    localparam logic [OPTYPE_W-1:0] OP_VWSUBU_WX  = 6'd28;
    localparam logic [OPTYPE_W-1:0] OP_VWSUB_WV   = 6'd29;
    localparam logic [OPTYPE_W-1:0] OP_VWSUB_WX   = 6'd30;

    // integer extension , vf8 is illegal at ELEN=32 
    localparam logic [OPTYPE_W-1:0] OP_VZEXT_VF2  = 6'd31;
    localparam logic [OPTYPE_W-1:0] OP_VSEXT_VF2  = 6'd32;
    localparam logic [OPTYPE_W-1:0] OP_VZEXT_VF4  = 6'd33;
    localparam logic [OPTYPE_W-1:0] OP_VSEXT_VF4  = 6'd34;

    // plain add/sub 
    localparam logic [OPTYPE_W-1:0] OP_VADD_VV    = 6'd35;
    localparam logic [OPTYPE_W-1:0] OP_VADD_VX    = 6'd36;
    localparam logic [OPTYPE_W-1:0] OP_VADD_VI    = 6'd37;
    localparam logic [OPTYPE_W-1:0] OP_VSUB_VV    = 6'd38;
    localparam logic [OPTYPE_W-1:0] OP_VSUB_VX    = 6'd39;

    // Testbench loopsover this range
    localparam int NUM_OPS = 40;

endpackage