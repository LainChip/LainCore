`include "decoder.svh"

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
logic get_high, get_high_m1, get_high_q;
assign get_high = op_i == `_MUL_TYPE_MULH || op_i == `_MUL_TYPE_MULHU;

logic[31:0] a;
logic[31:0] b;
assign a = r0_i;
assign b = r1_i;
logic[63:32] h_fix;
assign h_fix = ((a[31] & signed_ext) ? -b : '0) +
  ((b[31] & signed_ext) ? -a : '0);

// EX-M1 stage: do 4 multiply
(* use_dsp = "yes" *) logic[47:0] l_q;
(* use_dsp = "yes" *) logic[63:16] h_q;
logic[63:32] h_fix_q;
always_ff@(posedge clk) begin
  if(!m1_stall_i) begin
    l_q <= a[15: 0] * b[31:0];
    h_q <= a[31:16] * b[31:0];
    h_fix_q <= h_fix;
    get_high_m1 <= get_high;
  end
end

// M1-M2 stage: do sum up
(* use_dsp = "yes" *) logic[63:0] full_result;
always_ff @(posedge clk) begin
  if(!m2_stall_i) begin
    full_result <= {16'd0,l_q} + {h_q,16'd0} + {h_fix_q,32'd0};
    get_high_q <= get_high_m1;
  end
end

// OUTPUT LOGIC
assign result_o = get_high_q ? full_result[63:32] : full_result[31:0];

endmodule
