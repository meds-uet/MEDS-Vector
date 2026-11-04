// Self-checking testbench for vproc_mul (works with either implementation).
// Exhaustive 8-bit sweep per element, then corner-biased random at all SEWs,
// with random valid/ready stalls. Compares result_o and product_o.
import v_cfg_pkg::*;

module tb_vproc_mul;
  parameter int unsigned OP_W      = 128;
  parameter bit          PIPE_IN   = 1'b0;
  parameter bit          PIPE_MID  = 1'b1;
  parameter bit          PIPE_OUT  = 1'b1;
  parameter int          N_RAND    = 200000;
  parameter int          VALID_PCT = 80;
  parameter int          READY_PCT = 70;

  localparam int TOTAL = 4*65536 + N_RAND;

  logic clk_i = 1'b0, rst_ni = 1'b0;
  always #5 clk_i = ~clk_i;

  logic               valid_i, ready_o, valid_o, ready_i;
  logic [OP_W-1:0]    op_a_i, op_b_i, result_o;
  logic [2*OP_W-1:0]  product_o;
  vmul_sew_e          sew_i;
  vmul_op_e           op_i;

  vproc_mul #(.OP_W(OP_W), .PIPE_IN(PIPE_IN), .PIPE_MID(PIPE_MID), .PIPE_OUT(PIPE_OUT)) dut (.*);

  typedef struct { logic [OP_W-1:0] res; logic [2*OP_W-1:0] prod; } exp_t;
  exp_t exp_q[$];

  function automatic void golden(input vmul_op_e op, input vmul_sew_e sew,
                                 input logic [OP_W-1:0] a, input logic [OP_W-1:0] b,
                                 output logic [OP_W-1:0] res, output logic [2*OP_W-1:0] prod);
    int w;
    logic [63:0] ua, ub;
    logic signed [127:0] sa, sb, p;
    w = (sew == VMUL_SEW8) ? 8 : (sew == VMUL_SEW16) ? 16 : 32;
    res = '0; prod = '0;
    for (int e = 0; e < OP_W / w; e++) begin
      ua = 64'(a >> (e*w)) & ((64'd1 << w) - 64'd1);
      ub = 64'(b >> (e*w)) & ((64'd1 << w) - 64'd1);
      sa = $signed(128'(ua)); if (ua[w-1]) sa = sa - (128'sd1 <<< w);
      sb = $signed(128'(ub)); if (ub[w-1]) sb = sb - (128'sd1 <<< w);
      case (op)
        VMUL_MUL:    p = $signed(128'(ua)) * $signed(128'(ub));
        VMUL_MULH:   p = sa * sb;
        VMUL_MULHU:  p = $signed(128'(ua)) * $signed(128'(ub));
        default:     p = sa * $signed(128'(ub));
      endcase
      for (int k = 0; k < 2*w; k++) prod[2*w*e + k] = p[k];
      for (int k = 0; k < w; k++)
        res[w*e + k] = (op == VMUL_MUL) ? p[k] : p[w + k];
    end
  endfunction

  function automatic logic [7:0] corner_byte();
    case ($urandom_range(0, 7))
      0: return 8'h00;  1: return 8'h01;  2: return 8'h7F;  3: return 8'h80;
      4: return 8'h81;  5: return 8'hFF;  6: return 8'hFE;  default: return 8'($urandom);
    endcase
  endfunction

  function automatic logic [31:0] rnd_word();
    logic [31:0] w;
    int m = $urandom_range(0, 3);
    for (int by = 0; by < 4; by++) w[8*by +: 8] = (m == 0) ? 8'($urandom) : corner_byte();
    return w;
  endfunction

  int issued, sent, recv, errors;

  task automatic gen(input int n);
    if (n < 4*65536) begin
      int idx = n % 65536;
      op_i  <= vmul_op_e'(n / 65536);
      sew_i <= VMUL_SEW8;
      for (int e = 0; e < OP_W/8; e++) begin
        int pi = (idx + e*16411) % 65536;
        op_a_i[8*e +: 8] <= pi[15:8];
        op_b_i[8*e +: 8] <= pi[7:0];
      end
    end else begin
      op_i <= vmul_op_e'($urandom_range(0, 3));
      case ($urandom_range(0, 2))
        0: sew_i <= VMUL_SEW8;
        1: sew_i <= VMUL_SEW16;
        default: sew_i <= VMUL_SEW32;
      endcase
      for (int l = 0; l < OP_W/32; l++) begin
        op_a_i[32*l +: 32] <= rnd_word();
        op_b_i[32*l +: 32] <= rnd_word();
      end
    end
  endtask

  initial begin
    valid_i = 0; ready_i = 0; op_a_i = '0; op_b_i = '0; op_i = VMUL_MUL; sew_i = VMUL_SEW8;
    issued = 0; sent = 0; recv = 0; errors = 0;
    repeat (4) @(posedge clk_i);
    rst_ni <= 1'b1;
  end

  logic [OP_W-1:0] g_res;  logic [2*OP_W-1:0] g_prod;
  exp_t tmp_e;
  always @(posedge clk_i) if (rst_ni) begin
    // accepted at this edge?
    if (valid_i && ready_o) begin
      golden(op_i, sew_i, op_a_i, op_b_i, g_res, g_prod);
      tmp_e.res = g_res; tmp_e.prod = g_prod;
      exp_q.push_back(tmp_e);
      sent++;
    end
    // drive next (hold while not accepted)
    if (!valid_i || ready_o) begin
      if (issued < TOTAL && $urandom_range(0, 99) < VALID_PCT) begin
        gen(issued); issued++; valid_i <= 1'b1;
      end else valid_i <= 1'b0;
    end
    ready_i <= ($urandom_range(0, 99) < READY_PCT);
    // check output
    if (valid_o && ready_i) begin
      if (exp_q.size() == 0) begin errors++; $display("ERR: output with empty queue"); end
      else begin
        exp_t x = exp_q.pop_front();
        if (result_o !== x.res || product_o !== x.prod) begin
          errors++;
          if (errors < 10) $display("ERR @%0t #%0d: res %h exp %h | prod %h exp %h", $time, recv, result_o, x.res, product_o, x.prod);
        end
      end
      recv++;
      if (recv == TOTAL) begin
        $display("%s  OP_W=%0d IN=%0d MID=%0d OUT=%0d  txns=%0d errors=%0d",
                 errors == 0 ? "PASS" : "FAIL", OP_W, PIPE_IN, PIPE_MID, PIPE_OUT, recv, errors);
        $finish;
      end
    end
  end

  initial begin #(64'd400000000); $display("FAIL timeout recv=%0d/%0d", recv, TOTAL); $finish; end
endmodule