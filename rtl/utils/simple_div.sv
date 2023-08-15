`timescale 1ns / 1ps

module simple_div (
    input clk,
    input rst_n,
    input [31:0] A,
    input [31:0] B,
    output [31:0] rem,
    output [31:0] quo,
    input start,
    input sign,
    output logic busy
  );
  logic[31:0] a_abs, b_abs;
  assign a_abs = (sign && A[31]) ? -A : A;
  assign b_abs = (sign && B[31]) ? -B : B;
  logic[5:0] timer;
  logic[31:0] dividend_q, quo_q;
  logic[62:0] divisor_q;
  logic neg_rem_q, neg_quo_q;
  logic[63:0] sub_result;
  assign sub_result = {31'd0, dividend_q} - divisor_q[62:0];
  always_ff @(posedge clk) begin
    if(start) begin
      dividend_q <= a_abs;
      divisor_q <= {b_abs, 31'd0};
      timer <= 6'd32;
      busy <= '1;
      neg_rem_q <= A[31] && sign;
      neg_quo_q <= (A[31] != B[31]) && sign;
    end
    else begin
      if(timer != 0) begin
        if(!sub_result[63]) begin
          quo_q <= {quo_q[30:0], 1'b1};
          dividend_q <= sub_result[31:0];
        end
        else begin
          quo_q <= {quo_q[30:0], 1'b0};
        end
        timer <= timer - 6'd1;
        divisor_q <= {'0, divisor_q[62:1]};
        if(timer == 6'd1) begin
          busy <= '0;
        end
      end
      // else begin
      //   busy <= '0;
      // end
    end
  end
  assign rem = neg_rem_q ? -dividend_q[31:0] : dividend_q[31:0];
  assign quo = neg_quo_q ? -quo_q : quo_q;

endmodule
