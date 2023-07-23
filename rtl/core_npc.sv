`include "pipeline.svh"

function logic[`_BHT_ADDR_WIDTH - 1 : 0] get_bht_addr(logic[31:0]va);
  return va[`_BHT_ADDR_WIDTH + 2 : 3] ^ va[`_BHT_ADDR_WIDTH + `_BHT_ADDR_WIDTH + 2 : `_BHT_ADDR_WIDTH + 3];
endfunction
function logic[`_LPHT_ADDR_WIDTH - 1 : 0] get_lpht_addr(logic[`_BHT_DATA_WIDTH - 1 : 0] bht,logic[31:0]va);
  return {va[11:10],bht}; // TODO: PARAMETERIZE ME
endfunction
function logic[`_BTB_ADDR_WIDTH - 1 : 0] get_btb_addr(logic[31:0] va);
  return {va[`_BTB_ADDR_WIDTH + 2 : 3]};
endfunction
function logic[`_BTB_TAG_ADDR_WIDTH - 1 : 0] get_btb_tag(logic[31:0] va);
  return va[`_BTB_TAG_ADDR_WIDTH + `_BTB_ADDR_WIDTH + 2 : `_BTB_ADDR_WIDTH + 3];
endfunction
function logic[1:0] gen_next_lphr(logic[1:0] old, logic direction);
  case(old)
    default: begin
      return {1'b0,direction};
    end
    2'b01: begin
      return {direction,1'b0};
    end
    2'b10: begin
      return {direction,1'b1};
    end
    2'b11: begin
      return {1'b1,direction};
    end
  endcase
endfunction

module core_npc(
    input logic clk,
    input logic rst_n,

    input logic rst_jmp,
    input logic[31:0] rst_target,

    input logic f_stall_i,
    output logic[1:0][31:0] pc_o,
    output logic[1:0] valid_o, // 2'b00 | 2'b01 | 2'b11 | 2'b10

    output bpu_predict_t predict_o,
    input bpu_correct_t correct_i
  );

  logic[7:0][31:0] ras_stack;
  logic[31:0] ppc, ppcplus4, pc;
  // 使用 ppc 输入 bram 得到下周期的预测依据
  // 也就是说这些预测信息实际上是 PC 所有的
  btb_t btb_q;
  logic[1:0] lpht;
  logic[`_BTB_ADDR_WIDTH - 1 : 0] btb_addr;
  logic[`_BHT_ADDR_WIDTH - 1 : 0] bht_addr_q; // TODO: GEN ME
  logic[`_BHT_DATA_WIDTH - 1 : 0] bht_data;
  logic[`_LPHT_ADDR_WIDTH - 1 : 0] lpht_addr;
  logic [`_RAS_ADDR_WIDTH - 1: 0] ras_ptr_q,ras_ptr,r_ras_ptr_q,r_ras_ptr;

  // bht_addr_q
  always_ff @(posedge clk) begin
    if(!rst_n) begin
      pc <= 32'h1fc00000;
      pc_o[0] <= 32'h1fc00000;
      pc_o[1] <= 32'h1fc00004;
    end
    pc <= ppc;
    pc_o[0][2] <= '0;
    pc_o[1][2] <= '0;
    if(!f_stall_i) begin
      {pc_o[0][31:3],pc_o[0][1:0]} <= {ppc[31:3],ppc[1:0]};
      {pc_o[1][31:3],pc_o[1][1:0]} <= {ppc[31:3],ppc[1:0]};
    end
  end

  // lpht gen
  assign lpht_addr = get_lpht_addr(bht_data, ppc);

  // 本周期 pc 对应的预测依据
  logic predict_dir_type_q;
  logic predict_dir_jmp;
  logic [1:0] predict_target_type_q;
  logic [31:0] ras_target_q,btb_target,npc_target;
  logic hit;
  always_comb begin
    predict_dir_type_q = btb_q.dir_type && hit;
    predict_target_type_q = btb_q.branch_type;
    predict_dir_jmp = |lpht[1] && hit;
  end
  assign hit = btb_q.tag == get_btb_tag(ppc) && (!ppc[2] || btb_q.fsc);

  // ppc 以及 VALID 输出逻辑
  always_comb begin
    valid_o = pc[2] ? 2'b10 : 2'b11;
    if(rst_jmp) begin
      ppc = rst_target;
    end
    else begin
      if(!predict_dir_type_q) begin
        if(predict_dir_jmp) begin
          ppc = btb_target;
          if(!btb_q.fsc) begin
            valid_o = 2'b01;
          end
        end
        else begin
          ppc = npc_target;
        end
      end
      else begin
        if(predict_target_type_q == `_BPU_TARGET_NPC) begin
          ppc = npc_target;
        end
        else if(predict_target_type_q == `_BPU_TARGET_RETURN) begin
          ppc = ras_target_q;
          if(!btb_q.fsc) begin
            valid_o = 2'b01;
          end
        end
        else begin
          ppc = btb_target;
          if(!btb_q.fsc) begin
            valid_o = 2'b01;
          end
        end
      end
    end
    if(f_stall_i) begin
      valid_o = 2'b00;
    end
  end

  always_ff@(posedge clk) begin
    if(!rst_n) begin
      ras_ptr_q <= '0;
      r_ras_ptr_q <= '1;
    end
    else if(!f_stall_i) begin
      ras_ptr_q <= ras_ptr;
      r_ras_ptr_q <= r_ras_ptr;
    end
  end

  // ras_ptr 逻辑
  always_comb begin
    ras_ptr = ras_ptr_q;
    r_ras_ptr = r_ras_ptr_q;
    if(!predict_dir_jmp && predict_target_type_q == `_BPU_TARGET_CALL) begin
      // CALL + 1,
      ras_ptr = ras_ptr_q + 1;
      r_ras_ptr = r_ras_ptr_q + 1;
    end
    else if(!predict_dir_jmp && predict_target_type_q == `_BPU_TARGET_RETURN) begin
      // RETURN - 1,
      ras_ptr = ras_ptr_q - 1;
      r_ras_ptr = r_ras_ptr_q - 1;
    end
    else if(correct_i.miss) begin
      // RECOVER FROM EXECUTE
      if(correct_i.true_target_type == `_BPU_TARGET_CALL) begin
        ras_ptr = correct_i.ras_ptr + 1;
        r_ras_ptr = correct_i.ras_ptr;
      end
      else begin
        ras_ptr = correct_i.ras_ptr;
        r_ras_ptr = correct_i.ras_ptr - 1;
      end
    end
  end

  // RAS 逻辑
  always_ff@(posedge clk) begin
    // 预测 CALL 时，自动入栈
    if(!predict_dir_jmp && predict_target_type_q == `_BPU_TARGET_CALL) begin
      ras_stack[ras_ptr_q] <= ppcplus4;
    end
    else if(correct_i.miss && correct_i.true_target_type == `_BPU_TARGET_CALL) begin
      ras_stack[correct_i.ras_ptr] <= correct_i.pc + 4;
    end
  end

  // ppcplus4 逻辑
  assign ppcplus4 = {ppc[31:3],1'b1,ppc[1:0]};

  // NPC 逻辑
  assign npc_target = pc + 32'd8;

  // BTB 地址逻辑
  assign btb_addr = get_btb_addr(ppc);

  logic btb_we;
  logic[`_BTB_ADDR_WIDTH - 1 : 0] btb_waddr;
  btb_t btb_wdata;

  logic bht_we;
  logic[`_BHT_ADDR_WIDTH - 1 : 0] bht_waddr;
  logic[`_BHT_DATA_WIDTH - 1 : 0] bht_wdata;

  logic lpht_we;
  logic[`_LPHT_ADDR_WIDTH - 1 : 0] lpht_waddr;
  logic[1:0] lpht_wdata;
  // btb 生成
  simpleDualPortRamRE # (
                        .dataWidth($bits(btb_wdata)),
                        .ramSize((1 << `_BTB_ADDR_WIDTH)),
                        .latency(1),
                        .readMuler(1)
                      )
                      btb_table (
                        .clk(clk),
                        .rst_n(rst_n),
                        .addressA(btb_waddr),
                        .we(btb_we),
                        .addressB(btb_addr),
                        .re(!f_stall_i),
                        .inData(btb_wdata),
                        .outData(btb_q)
                      );
  // bht, lpht 生成
  simpleDualPortLutRam # (
                         .dataWidth(`_BHT_DATA_WIDTH),
                         .ramSize((1 << `_LPHT_ADDR_WIDTH)),
                         .latency(0),
                         .readMuler(1)
                       )
                       bht_table (
                         .clk(clk),
                         .rst_n(rst_n),
                         .addressA(bht_waddr),
                         .we(bht_we),
                         .addressB(bht_addr_q),
                         .re(1'b1),
                         .inData(bht_wdata),
                         .outData(bht_data)
                       );
  simpleDualPortLutRam # (
                         .dataWidth(2),
                         .ramSize((1 << `_LPHT_ADDR_WIDTH)),
                         .latency(0),
                         .readMuler(1)
                       )
                       lpht_table (
                         .clk(clk),
                         .rst_n(rst_n),
                         .addressA(lpht_waddr),
                         .we(lpht_we),
                         .addressB(lpht_addr),
                         .re(1'b1),
                         .inData(lpht_wdata),
                         .outData(lpht)
                       );

  // 更新逻辑
  always_comb begin
    btb_we = '0;
    btb_waddr = get_btb_addr(correct_i.pc);
    btb_wdata.fsc = correct_i.pc[2];
    btb_wdata.target_pc = correct_i.true_target[31:2];
    btb_wdata.tag = get_btb_tag(correct_i.pc);
    btb_wdata.dir_type = correct_i.true_dir;
    btb_wdata.branch_type = correct_i.true_target_type;

    bht_we = '0;
    bht_waddr = get_bht_addr(correct_i.pc);
    bht_wdata = {correct_i.history[3:1], correct_i.true_taken};

    lpht_we = '0;
    lpht_waddr = get_lpht_addr(bht_wdata, correct_i.pc);
    lpht_wdata = gen_next_lphr(correct_i.lphr, correct_i.true_taken);
    if(correct_i.miss) begin
      btb_we = 1'b1;
      if(correct_i.true_dir) begin
        bht_we = 1'b1;
        lpht_we = 1'b1;
      end
    end
  end

endmodule
