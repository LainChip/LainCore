#include "pipeline.svh"

module core_jmp(
    input logic clk,
    input logic rst_n,
    input logic valid_i,
    input logic[1:0] branch_type_i,
    input logic[2:0] cmp_type_i,
    input bpu_predict_t bpu_predict_i,
    input logic[31:0] target_i,
    input logic[31:0] r0_i,
    input logic[31:0] r1_i,
    output logic jmp_o,
  );

  logic address_correct,direction_correct;
  logic true_taken;
  logic predict_miss;
  assign address_correct = bpu_predict_i.predict_pc == target_i;
  assign direction_correct = bpu_predict_i.taken == true_taken;
  always_comb begin
    predict_miss = '0;
    if((true_taken || bpu_predict_i.taken) && valid_i) begin
      if(!direction_correct) begin
        predict_miss = '1;
      end else begin
        predict_miss = !address_correct;
      end
    end
  end
  assign jmp_o = predict_miss;

  // true_taken 逻辑
  always_comb begin
    true_taken = '0;
    
  end

endmodule