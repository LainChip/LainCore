`include "pipeline.svh"

 module core_jmp(
     input logic clk,
     input logic rst_n,
     input logic valid_i,
     input logic[1:0] branch_type_i,
     input logic[1:0] target_type_i, // 0 for no branch, 1 for call, 2 for return, 3 for immediate
     input logic[2:0] cmp_type_i,
     input bpu_predict_t bpu_predict_i,
     output bpu_correct_t bpu_correct_o,
     input logic[31:0] pc_i,
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
       end
       else begin
         predict_miss = !address_correct;
       end
     end
   end
   assign jmp_o = predict_miss;

   // true_taken 逻辑
   logic[32:0] r0,r1;
   assign r0 = {r0_i[31],r0_i};
   assign r1 = {r1_i[31] & cmp_type_i[1],r1_i};
   always_comb begin
     true_taken = '0;
     case(branch_type_i)
       default: begin
         true_taken = '0;
       end
       `_BRANCH_CONDITION: begin
         case(cmp_type_i)
           `_CMP_E: begin
             true_taken = r0_i == r1_i;
           end
           `_CMP_NE: begin
             true_taken = r0_i != r1_i;
           end
           `_CMP_LE: begin
             true_taken = r0 <= r1;
           end
           `_CMP_GT: begin
             true_taken = r0 > r1;
           end
           `_CMP_LT: begin
             true_taken = r0 < r1;
           end
           `_CMP_GE: begin
             true_taken = r0 >= r1;
           end
           `_CMP_LTU: begin
             true_taken = r0_i < r1_i;
           end
           `_CMP_GEU: begin
             true_taken = r0_i >= r1_i;
           end
         endcase
       end
       `_BRANCH_NOCONDITION: begin
         true_taken = '1;
       end
     endcase
   end

   logic true_dir_type,miss_dir_type,miss_target;
   logic[1:0] true_target_type;
   assign true_dir_type = branch_type_i == `_BRANCH_CONDITION;
   assign miss_dir_type = bpu_predict_i.dir_type != true_dir_type;
   assign true_dir_type = branch_type_i;
   assign miss_target = true_target_type != bpu_predict_i.target_type;
   // 更新逻辑
   always_comb begin
     bpu_correct_o.miss = jmp_o;
     bpu_correct_o.pc = pc_i;
     bpu_correct_o.true_taken = true_taken;
     bpu_correct_o.true_target = target_i;
     bpu_correct_o.lphr = bpu_predict_i.lphr;
     bpu_correct_o.history = bpu_predict_i.history;

     bpu_correct_o.miss_dir_type = miss_dir_type;
     bpu_correct_o.true_dir = branch_type_i;

     bpu_correct_o.miss_target_type = miss_target;
     bpu_correct_o.true_target_type = true_target_type;

     bpu_correct_o.ras_ptr = bpu_predict_i.ras_ptr;
   end

 endmodule
