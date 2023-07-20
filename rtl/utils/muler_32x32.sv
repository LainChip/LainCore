`include "../pipeline/decoder.svh"

module muler_32x32(
    input wire clk,
    input wire rst_n,
    input wire[1:0] op_i,
    input wire ex_stall_i,
    input wire m1_stall_i,
    input wire m2_stall_i,
    input wire[31:0] r0_i,
    input wire[31:0] r1_i,
    output logic[31:0] result_o
  );

  logic signed_ext;
  assign signed_ext = op_i == `_MUL_TYPE_MULH;
  logic get_high, get_high_q;
  assign get_high = op_i == `_MUL_TYPE_MULH || op_i == `_MUL_TYPE_MULHU;

  logic[48:0] l_q;
  logic[63:16] h_q;

  logic[32:0] a;
  logic[32:0] b;
  always_comb begin
    a[31:0] = r0_i;
    a[32] = r0_i[31] & signed_ext;
    b[31:0] = r1_i;
    b[32] = r1_i[31] & signed_ext;
  end

  always @(posedge clk) begin
    if(!m1_stall_i) begin
      get_high_q <= get_high;
      l_q <= a[32:0] * b[15:0];
      h_q <= a[32:0] * b[32:16];
    end
  end

  logic[63:16] high_part_result;
  assign full_result = {{15{l_q[48]}}, l_q[48:16]} + {h_q[63:16]};
  always @(posedge clk) begin
    if(!m2_stall_i) begin
      if(get_high_q) begin
        result_o <= high_part_result[63:32];
      end
      else begin
        result_o <= l_q[31:0] + {h_q[31:16], 16'd0};
      end
    end
  end

endmodule
