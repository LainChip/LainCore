`timescale 1ns / 1ps

module fast_div (
    input clk,
    input rst_n,
    input [31:0] A,
    input [31:0] B,
    output [31:0] rem,
    output [31:0] quo,
    input start,
    input sign,
    output busy
);

  wire [63:0] result;
  assign rem = result[63:32];
  assign quo = result[31:0];
  wire negA = A[31] && sign, negB = B[31] && sign;
  reg negRemainder, negQuotient;
  wire [31:0] absA = negA ? -A : A, absB = negB ? -B : B;
  wire [63:0] absA64 = {32'b0, absA};
  wire [63:0] abs64B = {absB, 32'b0};
  reg [31:0] timer;
  assign busy = timer[1];
  reg [66:0] tmpA, tmpB1, tmpB2, tmpB3;
  wire [66:0] sub1 = (tmpA << 2) - tmpB1, sub2 = (tmpA << 2) - tmpB2, sub3 = (tmpA << 2) - tmpB3;

  wire [31:0] remainder = tmpA[63:32], quotient = tmpA[31:0];
  assign result = {(negRemainder ? -remainder : remainder), (negQuotient ? -quotient : quotient)};

  always @(posedge clk) begin
    if (~rst_n) begin
        timer <= 'h00000000;
    end else begin
      if (start) begin
        negRemainder <= negA;
        negQuotient <= negA != negB;
        timer <= 'hFFFFFFFF;

        tmpA <= absA64;
        tmpB1 <= abs64B;
        tmpB2 <= abs64B + abs64B;
        tmpB3 <= {abs64B, 1'b0} + abs64B;
      end else if (timer[15] && (tmpA[47:16] < tmpB1[63:32])) begin
        timer <= timer >> 16;
        tmpA  <= tmpA << 16;
      end else if (timer[7] && (tmpA[55:24] < tmpB1[63:32])) begin
        timer <= timer >> 8;
        tmpA  <= tmpA << 8;
      end else if (timer[3] && (tmpA[59:28] < tmpB1[63:32])) begin
        timer <= timer >> 4;
        tmpA  <= tmpA << 4;
      end else if (timer[0]) begin
        timer <= timer >> 2;
        tmpA <= (!sub3[66]) ? sub3 + 3:
                (!sub2[66]) ? sub2 + 2:
                (!sub1[66]) ? sub1 + 1:
                tmpA << 2;
      end
    end
  end

endmodule
