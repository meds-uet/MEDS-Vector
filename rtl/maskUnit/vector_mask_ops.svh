`ifndef VECTOR_MASK_OPS_SVH
`define VECTOR_MASK_OPS_SVH

// -----------------------------------------------------------------------------
// Geometry
//
//   The mask register is VLEN bits wide, one bit per element.
//   It is sliced into NUM_FU pieces of ELEN bits.  Slice f owns mask bits
//   [f*ELEN +: ELEN], and slice 0 owns the LOWEST element indices (bit 0 of the
//   mask register == element 0 == LSB).
// -----------------------------------------------------------------------------

localparam int VLEN   = 128;            // mask register width (1 bit / element)
localparam int ELEN   = 32;             // mask bits handled by one FU slice
localparam int XLEN   = 32;             // scalar register width (x[rd])
localparam int NUM_FU = VLEN / ELEN;    // 4 slices

// Width of a running / prefix element count.  Must hold 0..VLEN.
localparam int COUNT_WIDTH = $clog2(VLEN + 1);      // 8  (0..128)

// Index widths
localparam int IDX_W = $clog2(ELEN);               // 5  element index inside a slice
localparam int FU_W  = $clog2(NUM_FU);             // 2  which slice

// Local popcount width.  Must hold 0..ELEN.
localparam int LOCAL_W = $clog2(ELEN + 1);         // 6  (0..32)

// Two-level priority encoder shape used by the first-set-bit scan.
localparam int GROUP_W   = 4;                      // bits per group
localparam int NUM_GROUP = ELEN / GROUP_W;         // 8  groups per slice
localparam int GRP_W     = $clog2(NUM_GROUP);      // 3  group select width
localparam int BIT_W     = $clog2(GROUP_W);        // 2  bit-in-group select width
// GRP_W + BIT_W must equal IDX_W (3 + 2 = 5).


// -----------------------------------------------------------------------------
// Vector Mask Operation Encoding
//
//   bit[3] == 0  ->  mask-register logical op (reads vs1 and vs2, never masked)
//   bit[3] == 1  ->  mask special op          (reads vs2 only, chained slice
//                                              to slice, honours vm / v0.t)
// -----------------------------------------------------------------------------

localparam int MASK_OP_W = 4;

// ---- 15.1 mask-register logical ---------------------------------------------

localparam logic [MASK_OP_W-1:0] MASK_OP_VMAND  = 4'h0; // vs2 &  vs1
localparam logic [MASK_OP_W-1:0] MASK_OP_VMNAND = 4'h1; // ~(vs2 &  vs1)
localparam logic [MASK_OP_W-1:0] MASK_OP_VMANDN = 4'h2; // vs2 & ~vs1
localparam logic [MASK_OP_W-1:0] MASK_OP_VMXOR  = 4'h3; // vs2 ^  vs1
localparam logic [MASK_OP_W-1:0] MASK_OP_VMOR   = 4'h4; // vs2 |  vs1
localparam logic [MASK_OP_W-1:0] MASK_OP_VMNOR  = 4'h5; // ~(vs2 |  vs1)
localparam logic [MASK_OP_W-1:0] MASK_OP_VMORN  = 4'h6; // vs2 | ~vs1
localparam logic [MASK_OP_W-1:0] MASK_OP_VMXNOR = 4'h7; // ~(vs2 ^  vs1)

// ---- 15.4 / 15.5 / 15.6 set-before/including/only-first -------------------

localparam logic [MASK_OP_W-1:0] MASK_OP_VMSBF = 4'h8;
localparam logic [MASK_OP_W-1:0] MASK_OP_VMSIF = 4'h9;
localparam logic [MASK_OP_W-1:0] MASK_OP_VMSOF = 4'hA;

// ---- 15.3 / 15.2 scalar producers ------------------------------------------

localparam logic [MASK_OP_W-1:0] MASK_OP_VFIRST = 4'hB;
localparam logic [MASK_OP_W-1:0] MASK_OP_VCPOP  = 4'hC;

// ---- 15.8 / 15.9 element-index producers -----------------------------------

localparam logic [MASK_OP_W-1:0] MASK_OP_VIOTA = 4'hD;
localparam logic [MASK_OP_W-1:0] MASK_OP_VID   = 4'hE;

// ---- decode helpers ---------------------------------------------------------

function automatic logic mask_op_is_logic (
    input logic [MASK_OP_W-1:0] op
);
    return (op[3] == 1'b0);
endfunction

function automatic logic mask_op_is_setmask (
    input logic [MASK_OP_W-1:0] op
);
    return (op == MASK_OP_VMSBF) ||
           (op == MASK_OP_VMSIF) ||
           (op == MASK_OP_VMSOF);
endfunction

function automatic logic mask_op_is_scalar (
    input logic [MASK_OP_W-1:0] op
);
    return (op == MASK_OP_VFIRST) ||
           (op == MASK_OP_VCPOP);
endfunction

function automatic logic mask_op_is_count (
    input logic [MASK_OP_W-1:0] op
);
    return (op == MASK_OP_VIOTA) ||
           (op == MASK_OP_VID);
endfunction

`endif // VECTOR_MASK_OPS_SVH
