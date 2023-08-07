`include "pipeline.svh"
/*--JSON--{"module_name":"core_npc","module_ver":"2","module_type":"module"}--JSON--*/

// function logic[`_BHT_ADDR_WIDTH - 1 : 0] get_bht_addr(input logic[31:0]va);
//   return va[`_BHT_ADDR_WIDTH + 2 : 3] ^ va[`_BHT_ADDR_WIDTH + `_BHT_ADDR_WIDTH + 2 : `_BHT_ADDR_WIDTH + 3];
// endfunction
// function logic[`_LPHT_ADDR_WIDTH - 1 : 0] get_lpht_addr(input logic[`_BHT_DATA_WIDTH - 1 : 0] bht,input logic[31:0]va);
//   return {va[11:10],bht}; // TODO: PARAMETERIZE ME
// endfunction
// function logic[`_BTB_ADDR_WIDTH - 1 : 0] get_btb_addr(input logic[31:0] va);
//   return {va[`_BTB_ADDR_WIDTH + 2 : 3]};
// endfunction
// function logic[`_BTB_TAG_ADDR_WIDTH - 1 : 0] get_btb_tag(input logic[31:0] va);
//   return va[`_BTB_TAG_ADDR_WIDTH + `_BTB_ADDR_WIDTH + 2 : `_BTB_ADDR_WIDTH + 3];
// endfunction
function logic[1:0] gen_next_lphr(input logic[1:0] old, input logic direction);
  case(old)
    default : begin
      return {1'b0,direction};
    end
    2'b01 : begin
      return {direction,1'b0};
    end
    2'b10 : begin
      return {direction,1'b1};
    end
    2'b11 : begin
      return {1'b1,direction};
    end
  endcase
endfunction
function logic[5:0] get_tag(input logic[31:0] addr);
  return addr[16:11];
endfunction

// 8.7 还是只做 8 对齐的 npc 模块

module core_npc (
    input  logic              clk       ,
    input  logic              rst_n     ,
    input  logic              rst_jmp   ,
    input  logic [31:0]       rst_target,
    input  logic              f_stall_i ,
    output logic [31:0]       pc_o      , // F1 STAGE
    output logic [31:0]       npc_o     ,
    output logic [ 1:0]       valid_o   , // 2'b00 | 2'b01 | 2'b11 | 2'b10
    output bpu_predict_t      predict_o ,
    input  bpu_correct_t      correct_i
  );
  // PC: pc 寄存器，f1 流水级
  // NPC: 下一个 PC 值，f1 流水级前
  // PPC_RAS_Q: RAS 方式预测的下一个跳转地址
  // PPC_BTB: BTB 方式预测的下一个跳转地址
  // PPC_PLUS8: 不预测跳转情况下，正常 +8
  // JPC: 后端刷新管线的跳转地址
  logic[31:0] pc, npc, ppc_ras_q, ppc_btb, ppc_plus8, jpc;
  logic[7:0][31:0] ras_q;
  assign npc_o = npc;
  assign pc_o = pc;
  logic[1:0] valid_q,nvalid;
  always_ff @(posedge clk) begin
    if(!rst_n) begin
      pc <= 32'h1c000000;
      valid_q <= 2'b11;
    end
    else begin
      if(!f_stall_i || rst_jmp) begin
        pc <= npc;
        valid_q <= nvalid;
      end
    end
  end

  // TARGET_TYPE: 分为 NPC，CALL，RETURN，IMM 四种
  // 其中 NPC 表示非跳转/分支指令，CALL 表示调用指令，RETURN 表示返回指令，IMM 表示立即数跳转指令
  // 立即数跳转指令中，又包含 条件跳转， 以及永远跳转两种类型
  logic[1:0] npc_target_type; // TODO: CHECK
  // 对于条件跳转指令，预测是否会 taken
  logic npc_predict_taken;    // TODO: CHECK

  // TODO: check npc 组合逻辑
  always_comb begin
    // npc = pc;
    predict_o.taken = '0;
    case(npc_target_type)
      default/*`_BPU_TARGET_NPC*/: begin
        npc = ppc_plus8;
      end
      `_BPU_TARGET_CALL: begin
        npc = ppc_btb;
        predict_o.taken = '1;
      end
      `_BPU_TARGET_RETURN: begin
        npc = ppc_ras_q;
        predict_o.taken = '1;
      end
      `_BPU_TARGET_IMM: begin
        if(npc_predict_taken) begin
          npc = ppc_btb;
          predict_o.taken = '1;
        end
        else begin
          npc = ppc_plus8;
        end
      end
    endcase
    if(rst_jmp) begin
      npc = jpc;
    end
  end

  // TODO:check ppc_ras_q 时序逻辑
  logic[2:0] ras_w_ptr_q,ras_ptr_q; // TODO:check
  always_ff @(posedge clk) begin
    ppc_ras_q <= {ras_q[ras_ptr_q][31:2], 2'b00};
  end

  // TODO:check ppc_btb 逻辑
  logic inst_0_jmp;
  logic[1:0][31:0] raw_ppc_btb;
  assign ppc_btb = inst_0_jmp ? raw_ppc_btb[0] : raw_ppc_btb[1];

  // TODO:check ppc_plus8 组合逻辑
  assign ppc_plus8 = {pc[31:3] + 1'd1, 3'b000};

  // TODO:check jpc 组合逻辑
  assign jpc = rst_target;

  // TODO: RAS 更新逻辑
  always_ff @(posedge clk) begin
    if(!rst_n) begin
      ras_ptr_q <= '1;
      ras_w_ptr_q <= '0;
    end
    else begin
      // TODO: check
      // RETURN MISS: RAS_PTR_Q <= (TRUE_PTR == R_PTR)
      // CALL MISS RAS_PTR_Q <= TRUE_PTR AND ras_q[TRUE_PTR] <= TRUE_TARGET;
      if(correct_i.miss) begin
        /* 考虑一下，没有 miss 但是类型估计错误的情况，这时候也需要更新 */
        /* printf */
        ras_w_ptr_q <= correct_i.ras_ptr + 3'd1;
        ras_ptr_q <= correct_i.ras_ptr;
        if(correct_i.true_target_type == `_BPU_TARGET_CALL) begin
          ras_q[correct_i.ras_ptr] <= correct_i.pc + 3'd4;
        end
      end
      else begin
        if(npc_target_type == `_BPU_TARGET_CALL && !f_stall_i) begin
          ras_q[ras_w_ptr_q] <= {pc[31:3], 3'b000} + (inst_0_jmp ? 3'd4 : 3'd8);
          ras_w_ptr_q <= ras_w_ptr_q + 3'd1;
          ras_ptr_q <= ras_ptr_q + 3'd1;
        end
        if(npc_target_type == `_BPU_TARGET_RETURN && !f_stall_i) begin
          ras_w_ptr_q <= ras_w_ptr_q - 3'd1;
          ras_ptr_q <= ras_ptr_q - 3'd1;
        end
      end
    end
  end

  // BTB 以及 分支信息 ram
  // 注意：BTB 使用 2 * 2k bram 存储，信息为 (32bits addr) * 512 entry * 2
  // 也就是说，BTB 中仅存放间接跳转目标信息。

  // 分支信息 ram 使用 lutram 存储
  // 注意：lutram 大小受限，不可以存储过多表项
  // 目前使用 2 * 256 entry 的配置，共 512 entry。
  // 表格中存储 2bits 分支类型, 1bits 条件跳转, 5bits 历史信息, 6bits tag 信息。
  // 也即是说，可以在 17位 == 128KB 的代码中区别开两个分支
  // 这一点已经足够使用了。
  //
  typedef struct packed {
            logic [1:0] target_type; // 0 npc, 1 call, 2 return, 3 imm
            logic conditional_jmp;   // 0 / 1 condition
            logic [4:0] history;
            logic [5:0] tag;
          } branch_info_t;
  logic[8:0] btb_waddr,btb_raddr;
  logic[1:0] btb_we;
  logic[31:0] btb_wdata;
  logic[1:0][31:0] btb_rdata;
  assign raw_ppc_btb = btb_rdata;
  assign btb_raddr = npc[11:3];
  assign btb_waddr = correct_i.pc[11:3];
  assign btb_wdata = correct_i.true_target;
  always_comb begin
    btb_we = '0;
    btb_we[correct_i.pc[2]] = correct_i.need_update;
  end

  logic[7:0] info_waddr,info_raddr;
  logic[1:0] info_we;
  branch_info_t winfo;
  branch_info_t [1:0]rinfo_q;
  // 注意：这个 rinfo_q 实际上是对应 PC 持有的预测信息
  // 也就是在这之后的有效域，转为 PC 了。
  assign info_raddr = npc[10:3];
  assign info_waddr = correct_i.pc[10:3];
  always_comb begin
    info_we = '0;
    info_we[correct_i.pc[2]] = correct_i.need_update;
  end
  always_comb begin
    winfo.target_type = correct_i.true_target_type;
    winfo.conditional_jmp = correct_i.true_conditional_jmp;
    winfo.history = {correct_i.history[3:0], correct_i.true_taken};
    winfo.tag = get_tag(correct_i.pc);
  end
  for(genvar p = 0 ; p < 2 ; p++) begin
    // 创建两个 btb 和 info mem，用于写更新时区别开来。
    simpleDualPortRamRE #(
                          .dataWidth(30 ),
                          .ramSize  (512),
                          .latency  (1  ),
                          .readMuler(1  )
                        ) btb_table (
                          .clk     (clk       ),
                          .rst_n   (rst_n     ),
                          .addressA(btb_waddr ),
                          .we      (btb_we[p] ),
                          .addressB(btb_raddr ),
                          .re      (!f_stall_i),
                          .inData  (btb_wdata[31:2]),
                          .outData (btb_rdata[p][31:2])
                        );
    assign btb_rdata[p][1:0] = '0;
    simpleDualPortLutRam #(
                           .dataWidth($bits(branch_info_t)),
                           .ramSize  (256),
                           .latency  (1  ),
                           .readMuler(1  )
                         ) info_table (
                           .clk     (clk       ),
                           .rst_n   (rst_n     ),
                           .addressA(info_waddr),
                           .we      (info_we[p]),
                           .addressB(info_raddr),
                           .re      (!f_stall_i),
                           .inData  (winfo),
                           .outData (rinfo_q[p])
                         );
  end

  // 预测逻辑
  // 根据 info 中指定的 history，寻址查找第二级 lutram，获得最终用于预测跳转信息的两位饱和计数器
  logic level2_we;
  logic [4:0] level2_waddr;
  logic [1:0] level2_wdata;
  logic [1:0][4:0] level2_raddr;
  logic [1:0][1:0] level2_cnt;

  assign level2_wdata = gen_next_lphr(correct_i.lphr, correct_i.true_taken);
  assign level2_waddr = correct_i.history;
  assign level2_we = correct_i.true_conditional_jmp && correct_i.need_update;

  // taken 逻辑
  logic [1:0] branch_need_jmp;
  logic [1:0] tag_match;
  for(genvar p = 0 ; p < 2; p++) begin
    simpleDualPortLutRam #(
                           .dataWidth(2 ),
                           .ramSize  (32),
                           .latency  (0 ),
                           .readMuler(1 )
                         ) l2_table (
                           .clk     (clk            ),
                           .rst_n   (rst_n          ),
                           .addressA(level2_waddr   ),
                           .we      (level2_we      ),
                           .addressB(level2_raddr[p]),
                           .re      (1'b1           ),
                           .inData  (level2_wdata   ),
                           .outData (level2_cnt[p]  )
                         );
    assign level2_raddr[p] = rinfo_q[p].history;
    // 可以被综合成一个 lut6
    always_comb begin
      branch_need_jmp[p] = '0; // 注意这个信号有 3 级逻辑
      if(rinfo_q[p].target_type != `_BPU_TARGET_NPC && tag_match[p]) begin
        if(rinfo_q[p].target_type != `_BPU_TARGET_IMM || !rinfo_q[p].conditional_jmp) begin
          // 这些情况下，是无条件跳转的
          branch_need_jmp[p] = /*'1*/valid_q[p];
        end
        else begin
          // 这个情况下，依据
          branch_need_jmp[p] = level2_cnt[p][1] && valid_q[p];
        end
      end
    end
    assign tag_match[p] = rinfo_q[p].tag == get_tag(pc);
  end

  // nvalid 逻辑
  always_comb begin
    nvalid = 2'b11;
    if(npc[2]) begin
      nvalid[0] = '0;
    end
  end

  // valid_o 逻辑
  always_comb begin
    valid_o = valid_q;
    if(inst_0_jmp) begin
      valid_o[1] = '0;
    end
  end

  // 合成两路结果
  // 对于条件跳转指令，预测是否会 taken
  always_comb begin
    npc_target_type = '0;
    npc_predict_taken = 1'b0;
    if(branch_need_jmp[0]) begin
      npc_target_type = rinfo_q[0].target_type;
      npc_predict_taken = 1'b1;
    end
    else if(branch_need_jmp[1]) begin
      npc_target_type = rinfo_q[1].target_type;
      npc_predict_taken = 1'b1;
    end
  end
  assign inst_0_jmp = branch_need_jmp[0];
  always_comb begin
    // predict_o.taken = '0; // 在npc 逻辑块中描述
    predict_o.pc_off = pc[2];
    predict_o.predict_pc = npc;
    predict_o.lphr = level2_cnt[0];
    predict_o.history = rinfo_q[0].history;
    predict_o.target_type = '0;
    predict_o.dir_type = rinfo_q[0].conditional_jmp;
    // predict_o.lphr = inst_0_jmp ? level2_cnt[0] :
    //                level2_cnt[1];
    // predict_o.history = inst_0_jmp ? rinfo_q[0].history :
    //                   rinfo_q[1].history;
    // predict_o.target_type = inst_0_jmp ? rinfo_q[0].target_type :
    //                       rinfo_q[1].target_type;
    // predict_o.dir_type = inst_0_jmp ? rinfo_q[0].conditional_jmp :
    //                    rinfo_q[1].conditional_jmp;
    predict_o.ras_ptr = ras_ptr_q;
    if(/*tag_match[0] && */branch_need_jmp[0]) begin
      predict_o.pc_off = '0;
      predict_o.target_type = rinfo_q[0].target_type;
    end else if(/*tag_match[1] && */branch_need_jmp[1]) begin
      predict_o.pc_off = '1;
      predict_o.lphr = level2_cnt[1];
      predict_o.history = rinfo_q[1].history;
      predict_o.target_type = rinfo_q[1].target_type;
      predict_o.dir_type = rinfo_q[1].conditional_jmp;
    end
  end

endmodule
