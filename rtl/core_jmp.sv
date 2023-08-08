`include "pipeline.svh"

module core_jmp(
    input logic clk,
    input logic rst_n,
    input logic valid_i,
    //  input logic[1:0] branch_type_i,
    input logic[1:0] target_type_i, // 0 for no branch, 1 for call, 2 for return, 3 for immediate
    input logic[3:0] cmp_type_i,
    input bpu_predict_t bpu_predict_i,
    output bpu_correct_t bpu_correct_o,
    input logic[31:0] pc_i,
    input logic[31:0] target_i,
    output logic[31:0] target_o,
    input logic[31:0] r0_i,
    input logic[31:0] r1_i,
    output logic jmp_o
  );

  logic address_correct,direction_correct;
  logic true_taken;
  logic predict_miss;
  assign address_correct = bpu_predict_i.predict_pc == target_i;
  assign direction_correct = (
           bpu_predict_i.taken &&
           bpu_predict_i.pc_off == pc_i[2]
         ) == true_taken;
  always_comb begin
    predict_miss = '0;
    if((true_taken || bpu_predict_i.taken) && valid_i) begin
      predict_miss = !address_correct || !direction_correct;
    end
  end
  assign jmp_o = predict_miss;

  // true_taken 逻辑
  logic[32:0] r0,r1;
  assign r0 = {(~r0_i[31]) & cmp_type_i[0],r0_i};
  assign r1 = {(~r1_i[31]) & cmp_type_i[0],r1_i};
  logic[3:1] cmp_result;
  assign cmp_result[3] = r1 < r0;
  assign cmp_result[2] = r1 == r0;
  assign cmp_result[1] = r1 > r0;
  assign true_taken = |(cmp_result & cmp_type_i[3:1]);

  logic true_conditional_jmp,miss_dir_type,miss_target_type;
  logic[1:0] true_target_type;
  assign true_conditional_jmp = |cmp_result[3:1]/*JUMPABLE*/ && !(&cmp_result[3:1]) /*BUT NOT ALWAYS JUMP*/;
  assign miss_dir_type = bpu_predict_i.dir_type != true_conditional_jmp;
  assign miss_target_type = true_target_type != bpu_predict_i.target_type;
  assign true_target_type = target_type_i;
  // 更新逻辑
  always_comb begin
    bpu_correct_o.miss = predict_miss;
    bpu_correct_o.pc = pc_i;
    bpu_correct_o.true_taken = true_taken;
    // bpu_correct_o.true_target = true_taken ? target_i : (pc_i + 32'd4);
    bpu_correct_o.true_target = target_i;
    bpu_correct_o.lphr = bpu_predict_i.lphr;
    bpu_correct_o.history = bpu_predict_i.history;

    //  bpu_correct_o.miss_dir_type = miss_dir_type;
    bpu_correct_o.need_update = (((|true_target_type) || miss_target_type) && valid_i) || predict_miss;
    bpu_correct_o.true_conditional_jmp = true_conditional_jmp;

    bpu_correct_o.true_target_type = true_target_type;

    bpu_correct_o.ras_ptr = bpu_predict_i.ras_ptr;
    bpu_correct_o.ras_miss_type = '0;
    if(true_target_type == `_BPU_TARGET_CALL && miss_target_type) begin
      bpu_correct_o.ras_ptr = bpu_predict_i.ras_ptr + 1;
      bpu_correct_o.ras_miss_type = '1;
    end
    if(true_target_type == `_BPU_TARGET_RETURN && miss_target_type) begin
      bpu_correct_o.ras_ptr = bpu_predict_i.ras_ptr - 1;
      bpu_correct_o.ras_miss_type = '1;
    end
  end
  assign target_o = true_taken ? target_i : (pc_i + 32'd4);
  // debug
  int total = 0;
  int miss = 0;
  always_ff @(negedge clk) begin
    if (true_target_type != `_BPU_TARGET_NPC && valid_i /* && (total % 10 == 0) */) begin
      total <= total + 1;
      if (predict_miss) begin
        miss <= miss + 1;
        $display("SRC: %x", pc_i);
        $display("DST: %x", target_o);
        $display("MISS: %d", predict_miss);
        $display("predict_i: lphr: %d, predict_pc: %x, taken: %d, target_type: %d, pc_off: %d", bpu_predict_i.lphr, bpu_predict_i.predict_pc, bpu_predict_i.taken, bpu_predict_i.target_type, bpu_predict_i.pc_off);
        $display("update_o: target: %x, target_type: %d, taken: %d", bpu_correct_o.true_target, bpu_correct_o.true_target_type, true_taken);
        $display("total: %d, miss: %d, miss_rate: %f", total, miss, 1.0 * miss/total);

      end
    end
  end

endmodule
