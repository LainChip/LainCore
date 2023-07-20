`include "pipeline.svh"
`include "../lsu/lsu_types.svh"

function fwd_data_t mkfwddata(pipeline_wdata_t in);
  mkfwddata.valid = in.w_flow.valid;
  mkfwddata.id = in.w_flow.w_id;
  mkfwddata.data = in.w_data;
endfunction

module backend(
    input logic clk,
    input logic rst_n,

    input frontend_req_t frontend_req_i,
    output frontend_resp_t frontend_resp_o,

    input cache_bus_resp_t bus_resp_i,
    output cache_bus_req_t bus_req_o
  );

  /* -- -- -- -- -- GLOBAL CONTROLLING LOGIC BEGIN -- -- -- -- -- */
  // TODO: PIPELINE ME
  pipeline_ctrl_ex_t[1:0] pipeline_ctrl_is,pipeline_ctrl_skid_q,
                    pipeline_ctrl_ex,pipeline_ctrl_ex_q;
  pipeline_ctrl_m1_t[1:0] pipeline_ctrl_m1,pipeline_ctrl_m1_q;
  pipeline_ctrl_m2_t[1:0] pipeline_ctrl_m2,pipeline_ctrl_m2_q;
  pipeline_ctrl_wb_t[1:0] pipeline_ctrl_wb,pipeline_ctrl_wb_q;

  pipeline_data_t [1:0] pipeline_data_is,pipeline_data_is_fwd,
                  pipeline_data_skid_q,pipeline_data_skid_fwd,
                  pipeline_data_ex_q,pipeline_data_ex_fwd,
                  pipeline_data_m1_q,pipeline_data_m1_fwd,
                  pipeline_data_m2_q,pipeline_data_m2_fwd,
                  pipeline_data_wb_q;
  // TODO: PIPELINE ME
  pipeline_wdata_t [1:0] pipeline_wdata_ex,pipeline_wdata_m1_q,
                   pipeline_wdata_m1,pipeline_wdata_m2_q,
                   pipeline_wdata_m2,pipeline_wdata_wb_q,
                   pipeline_wdata_wb;

  fwd_data_t [1:0] fwd_data_ex,fwd_data_m1,fwd_data_m2,fwd_data_wb;

  // TODO: PIPELINE ME
  exc_flow_t [1:0] exc_is,exc_ex_q,exc_m1_q,exc_m2_q,exc_wb_q;

  logic ex_stall;
  logic m1_stall;
  logic m2_stall;
  logic wb_stall;

  logic[1:0] ex_stall_req;
  logic[1:0] m1_stall_req;
  logic[1:0] m2_stall_req;
  logic[1:0] wb_stall_req;
  logic[1:0] lsu_stall_req;

  // 注意： invalidate 不同于 ~rst_n ，只要求无效化指令，不清除管线中的指令。
  logic m1_refetch;
  logic [1:0][31:0]m1_jump_target_req;
  logic [1:0]m1_invalidate, m1_invalidate_req;
  logic ex_invalidate;

  logic is_skid_q;

  // STALL MANAGER
  // 后续级可以阻塞前级
  // 就算前级中有气泡，也不可以前进（并没有必要，徒增stall逻辑复杂度）。但前级不能阻塞后级。
  always_comb begin
    ex_stall = |ex_stall_req | |m1_stall_req | |m2_stall_req | |wb_stall_req;
    m1_stall = |m1_stall_req | |m2_stall_req | |wb_stall_req;
    m2_stall = |m2_stall_req | |wb_stall_req;
    wb_stall = |wb_stall_req;
  end

  // M2 级的跳转寄存器设计位 : TODO CONNECT ME
  logic[31:0] m2_jump_target_q;
  logic m2_jump_valid_q;
  always_ff @(posedge clk) begin
    m2_jump_valid_q <= |m1_invalidate_req | m1_refetch;
    m2_jump_target_q <= (m1_invalidate_req[1]) ? m1_jump_target_req[1] : m1_jump_target_req[0];
  end


  // INVALIDATE MANAGER
  always_comb begin
    ex_invalidate = |m1_invalidate_req | m1_refetch;
    m1_invalidate[0] = m1_invalidate_req[0];
    m1_invalidate[1] = m1_invalidate_req[0] | m1_invalidate_req[1];
  end

  // forwarding manager
  /* 所有级流水的前递模块在这里实例化*/
  for(genvar p = 0 ; p < 2 ; p++) begin
    dyn_fwd_unit #(2) is_fwd(
                   {fwd_data_wb, fwd_data_ex},
                   pipeline_data_is[p],
                   pipeline_data_is_fwd[p]
                 );
    dyn_fwd_unit #(2) is_skid_fwd(
                   {fwd_data_wb, fwd_data_ex},
                   pipeline_data_skid_q[p],
                   pipeline_data_skid_fwd[p]
                 );
    dyn_fwd_unit #(3) ex_fwd(
                   {fwd_data_wb, fwd_data_m2, fwd_data_m1},
                   pipeline_data_ex_q[p],
                   pipeline_data_ex_fwd[p]
                 );
    always_ff@(posedge clk) begin
      if(ex_stall) begin
        pipeline_data_ex_q[p] <= pipeline_data_ex_fwd[p];
      end
      else begin
        pipeline_data_ex_q[p] <= is_skid_q ? pipeline_data_skid_fwd[p]: pipeline_data_is_fwd[p];
      end
    end
    dyn_fwd_unit #(2) m1_fwd(
                   {fwd_data_wb, fwd_data_m2},
                   pipeline_data_m1_q[p],
                   pipeline_data_m1_fwd[p]
                 );
    always_ff@(posedge clk) begin
      if(m1_stall) begin
        pipeline_data_m1_q[p] <= pipeline_data_m1_fwd[p];
      end
      else begin
        pipeline_data_m1_q[p] <= pipeline_data_ex_fwd[p];
      end
    end
    dyn_fwd_unit #(1) m2_fwd(
                   {fwd_data_wb},
                   pipeline_data_m2_q[p],
                   pipeline_data_m2_fwd[p]
                 );
    always_ff@(posedge clk) begin
      if(m1_stall) begin
        pipeline_data_m2_q[p] <= pipeline_data_m2_fwd[p];
      end
      else begin
        pipeline_data_m2_q[p] <= pipeline_data_m1_fwd[p];
      end
    end
  end

  // DM 模块实例化
  dram_manager_req_t[1:0] dm_req;
  dram_manager_resp_t[1:0] dm_resp;
  dram_manager_snoop_t dm_snoop;
  lsu_dm # (
           .PIPE_MANAGE_NUM(2),
           .BANK_NUM(2),
           .WAY_CNT(1),
           .SLEEP_CNT(4)
         )
         lsu_dm_inst (
           .clk(clk),
           .rst_n(rst_n),
           .dm_req_i(dm_req),
           .dm_resp_o(dm_resp),
           .dm_snoop_i(dm_snoop),
           .bus_req_o(bus_req_o),
           .bus_resp_i(bus_resp_i),
           .bus_busy_o(bus_busy_o)
         );
  // LSU 端口实例化
  logic m1_lsu_busy,m2_lsu_busy;
  logic[1:0] ex_mem_read,m1_mem_read,m2_mem_valid,m1_mem_uncached,m2_mem_uncached;
  logic[1:0][1:0] m2_mem_size;
  logic[1:0][31:0] ex_mem_vaddr,m1_mem_vaddr,m1_mem_paddr,m2_mem_vaddr,m2_mem_paddr;
  logic[1:0][3:0] m1_mem_strobe, m2_mem_strobe;

  logic[1:0] m1_mem_rvalid,m2_mem_rvalid;
  logic[1:0][31:0] m1_mem_rdata,m2_mem_rdata;
  logic[1:0][31:0] m2_mem_wdata;
  logic[1:0][2:0] m2_mem_op;
  for(genvar p = 0 ; p < 2 ; p ++) begin
    lsu # (
          .WAY_CNT(1)
        )
        lsu_inst (
          .clk(clk),
          .rst_n(rst_n),
          .ex_vaddr_i(ex_mem_vaddr[p]),
          .ex_valid_i(ex_mem_read[p]),
          .m1_vaddr_i(m1_mem_vaddr[p]),
          .m1_paddr_i(m1_mem_paddr[p]),
          .m1_strobe_i(m1_mem_strobe[p]),
          .m1_read_i(m1_mem_read[p]),
          .m1_uncached_i(m1_mem_uncached[p]),
          .m1_busy_o(m1_lsu_busy[p]),
          .m1_stall_i(m1_stall[p]),
          .m1_rdata_o(m1_mem_rdata[p]),
          .m1_rvalid_o(m1_mem_rvalid[p]),
          .m2_vaddr_i(m2_mem_vaddr[p]),
          .m2_paddr_i(m2_mem_paddr[p]),
          .m2_wdata_i(m2_mem_wdata[p]),
          .m2_strobe_i(m2_mem_strobe[p]),
          .m2_valid_i(m2_mem_valid[p]),
          .m2_uncached_i(m2_mem_uncached[p]),
          .m2_size_i(m2_mem_size[p]),
          .m2_busy_o(m2_lsu_busy[p]),
          .m2_stall_i(m2_stall[p]),
          .m2_op_i(m2_mem_op[p]),
          .m2_rdata_o(m2_mem_rdata[p]),
          .m2_rvalid_o(m2_mem_rvalid[p]),
          .wb_rdata_o(),
          .wb_rvalid_o(),
          .dm_req_o(dm_req[p]),
          .dm_resp_i(dm_resp[p]),
          .dm_snoop_i(dm_snoop)
        );
  end
  // TODO: DTLB L0 HERE
  for(genvar p = 0 ; p < 2 ; p++) begin

  end
  // MUL 端口实例化
  logic[1:0] mul_req;
  logic[1:0][1:0] mul_op_req;
  logic[1:0][31:0] mul_r0_req,mul_r1_req;
  logic[1:0] mul_op;
  logic[31:0] mul_r0,mul_r1,mul_result;
  always_comb begin
    mul_op = mul_req[0] ? mul_op_req[0] : mul_op_req[1];
    mul_r0 = mul_req[0] ? mul_r0_req[0] : mul_r0_req[1];
    mul_r1 = mul_req[0] ? mul_r1_req[0] : mul_r1_req[1];
  end
  muler_32x32 mul_i(
                .clk(clk),
                .rst_n(rst_n),
                .op_i(mul_op),

                .ex_stall_i(ex_stall),
                .m1_stall_i(m1_stall),
                .m2_stall_i(m2_stall),

                .r0_i(mul_r0),
                .r1_i(mul_r1),

                .result_o(mul_result)
              );

  // 除法器例化 TODO: FIXME
  logic[31:0] div_result;
  logic div_result_valid;

  // TODO: CONNECT CSR

  // CSR 接入 (M1)
  logic[13:0] csr_r_addr;
  logic csr_rdcnt;

  // CSR 接入 (M2)
  logic[1:0] csr_excp_req;
  logic[1:0] m2_valid_req;
  logic[1:0] m2_commit_req;
  logic[1:0][31:0] m2_badv_req;
  excp_flow_t [1:0] m2_excp_req;
  logic csr_we;
  logic csr_valid,csr_commit;
  logic[31:0] csr_badv;
  excp_flow_t [1:0] csr_excp;
  logic[13:0] csr_w_addr;
  logic[31:0] csr_r_data,csr_w_data,csr_w_mask;
  always_comb begin
    csr_valid = (csr_we | csr_excp_req[0]) ? m2_valid_req[0] : m2_valid_req[1];
    csr_commit = (csr_we | csr_excp_req[0]) ? m2_commit_req[0] : m2_commit_req[1];
    csr_badv = csr_excp_req[0] ? m2_badv_req[0] : m2_badv_req[1];
    csr_excp = csr_excp_req[0] ? m2_excp_req[0] : m2_excp_req[1];
  end

  // TLB REQ 接入
  tlb_op_t tlb_op; // ONE HOT ENCODING OF TLBSRCH | TLBRD | TLBWR | TLBFILL | INVTLB

  // CACHE | MMU opcode 接入
  logic[4:0] ctlb_opcode;

  // CSR output
  csr_t csr_value;

  la_csr  la_csr_inst (
            .clk(clk),
            .rst_n(rst_n),
            .excp_i(csr_excp),
            .valid_i(csr_valid),
            .commit_i(csr_commit),
            .m2_stall_i(m2_stall),
            .csr_r_addr_i(csr_r_addr),
            .rdcnt_i(csr_rdcnt),
            .csr_we_i(csr_we),
            .csr_w_addr_i(csr_w_addr),
            .csr_w_mask_i(csr_w_mask),
            .csr_w_data_i(csr_w_data),
            .badv_i(csr_badv),
            .tlb_op_i(tlb_op),
            .tlb_srch_i(/*TODO*/),
            .tlb_entry_i(/*TODO*/),
            .llbit_set_i(/*TODO*/),
            .llbit_i(/*TODO*/),
            .csr_r_data_o(csr_r_data),
            .csr_o(csr_value)
          );

  /* -- -- -- -- -- GLOBAL CONTROLLING LOGIC BEGIN -- -- -- -- -- */

  /* ------ ------ ------ ------ ------ IS 级 ------ ------ ------ ------ ------ */
  // ISSUE 级别：
  // 判定来自前段的指令能否发射
  logic is_ready;
  logic ex_skid_ready_q,ex_skid_valid;
  logic [1:0] issue;
  issue issue_inst (
          .clk(clk),
          .rst_n(rst_n),
          .inst_i(frontend_req_i.inst),
          .d_valid_i(frontend_req_i.inst_valid & {is_ready,is_ready}),
          .ex_ready_i(ex_skid_ready_q),
          .ex_valid_o(ex_skid_valid),
          .is_o(issue)
        );
  assign frontend_resp_o.issue = issue;

  // 读取寄存器堆，或者生成立即数
  logic[1:0][1:0][4:0] is_r_addr;
  logic[1:0][1:0][31:0] is_r_data;
  logic[1:0][1:0] is_r_ready;
  logic[1:0][1:0][3:0] is_r_id;
  logic[1:0][4:0] is_w_addr;
  logic[2:0] is_w_id;

  logic[1:0][4:0] wb_w_addr;
  logic[1:0][31:0] wb_w_data;
  logic[2:0] wb_w_id;
  logic[1:0] wb_valid;
  logic[1:0] wb_commit;
  reg_file # (
             .DATA_WIDTH(32)
           )
           reg_file_inst (
             .clk(clk),
             .rst_n(rst_n),
             .r_addr_i(is_r_addr),
             .r_data_o(is_r_data),
             .w_addr_i(wb_w_addr),
             .w_data_i(wb_w_data),
             .w_en_i(wb_valid & wb_commit)
           );

  // 读取 scoreboard，判断寄存器值是否有效
  scoreboard  scoreboard_inst (
                .clk(clk),
                .rst_n(rst_n),
                .invalidate_i(),
                .issue_ready_o(is_ready),
                .is_r_addr_i(is_r_addr),
                .is_r_id_o(is_r_id),
                .is_r_valid_o(is_r_ready),
                .is_w_addr_i(is_w_addr),
                .is_i(issue),
                .is_w_id_o(is_w_id),
                .wb_w_addr_i(wb_w_addr),
                .wb_w_id_i(wb_w_id),
                .wb_valid_i(wb_valid)
              );

  // 产生 EX 级的流水线信号 x 2
  logic ex_ready, ex_valid;
  // IS 数据前递部分（EX、WB），输入是 pipeline_ctrl_is ，输出 pipeline_ctrl_is_fwd 不完全。

  /* SKID BUF */
  // SKID 数据前递部分（EX、WB） 不完全。
  // 输入是 pipeline_ctrl_skid_q，输出 pipeline_ctrl_skid_fwd
  // SKID BUF 对于 scoreboard 来说应该是透明的，使用 valid-ready 握手
  // assign ex_skid_ready_q = ~is_skid_q;
  always_ff @(posedge clk) begin
    if(~rst_n || ex_invalidate) begin
      is_skid_q <= '0;
      ex_skid_ready_q <= '1;
    end
    else begin
      if(is_skid_q) begin
        if(ex_ready) begin
          is_skid_q <= '0;
          ex_skid_ready_q <= '1;
        end
        pipeline_data_skid_q <= pipeline_data_skid_fwd;
      end
      else begin
        if(ex_skid_valid & ~ex_ready) begin
          is_skid_q <= '1;
          ex_skid_ready_q <= '0;
        end
        pipeline_data_skid_q <= pipeline_data_is_fwd;
      end
    end
  end
  /* SKID BUF 结束*/
  /* ------ ------ ------ ------ ------ EX 级 ------ ------ ------ ------ ------ */
  for(genvar p = 0 ; p < 2 ; p++) begin
    // EX 级别
    // EX 的 FU 部分，接入 ALU、乘法器、除法队列 pusher（Optional）
    logic[31:0] alu_result;
    logic[31:0] jump_target;
    logic[31:0] vaddr, rel_target;
    detachable_alu #(
                     .USE_LI(1),
                     .USE_INT(0),
                     .USE_SFT(0),
                     .USE_CMP(0)
                   )ex_alu(
                     .grand_op_i(pipeline_ctrl_ex_q[p].decode_info.alu_grand_op),
                     .op_i(pipeline_ctrl_ex_q[p].decode_info.alu_op),

                     .mul_i('0),
                     .r0_i(pipeline_data_ex_q[p].r_data[0]),
                     .r1_i(pipeline_data_ex_q[p].r_data[1]),
                     .pc_i(pipeline_ctrl_ex_q[p].pc),

                     .res_o(alu_result)
                   );

    excp_flow_t ex_excp_flow;
    // ex_excp_flow 产生逻辑: TODO
    always_comb begin

    end
    // EX 的额外部分
    // EX 级别的访存地址计算 / 地址翻译逻辑
    always_comb begin
      vaddr = {{6{pipeline_ctrl_ex_q[p].addr_imm[25]}},
               pipeline_ctrl_ex_q[p].addr_imm} +
            pipeline_data_ex_q[p].r_data[1];
    end
    always_comb begin
      rel_target = pipeline_ctrl_ex_q[p].pc + {{6{pipeline_ctrl_ex_q[p].addr_imm[25]}},
                 pipeline_ctrl_ex_q[p].addr_imm};
    end
    always_comb begin
      // TODO
      jump_target = pipeline_ctrl_ex_q[p].target_type == `_TARGET_ABS ?
                  vaddr : rel_target;
    end

    // EX 的结果选择部分
    always_comb begin
      pipeline_wdata_ex[p].w_data = alu_result;
      pipeline_wdata_ex[p].w_flow.w_id = pipeline_ctrl_ex_q[p].w_id; // TODO: FIXME
      pipeline_wdata_ex[p].w_flow.w_addr = pipeline_ctrl_ex_q[p].w_reg;
      pipeline_wdata_ex[p].w_flow.w_valid =
                       pipeline_ctrl_ex_q[p].fu_sel_ex == `_FUSEL_EX_ALU ? (
                         (&pipeline_data_ex_q[p].r_flow.r_ready)) :
                       '0;
    end

    // 接入转发源
    always_comb begin
      fwd_data_ex[p] = mkfwddata(pipeline_wdata_ex[p]);
    end

    // 接入暂停请求
    always_comb begin
      ex_stall_req[p] = ((pipeline_ctrl_ex_q[p].latest_r0_ex & ~pipeline_data_ex_q[p].r_flow.r_ready[0]) |
                         (pipeline_ctrl_ex_q[p].latest_r1_ex & ~pipeline_data_ex_q[p].r_flow.r_ready[1]) ) &
                  exc_ex_q.valid_inst & exc_ex_q.need_commit; // LUT6 - 1
    end

    // 接入 dcache
    assign ex_mem_read[p] = decode_info.mem_read;
    assign ex_mem_vaddr[p] = vaddr;

    // 接入 mul
    always_comb begin
      mul_req[p] = pipeline_ctrl_ex_q[p].decode_info.need_mul;
      mul_op_req[p] = pipeline_ctrl_ex_q[p].decode_info.alu_op;
      mul_r0_req[p] = pipeline_data_ex_q[p].r_data[0];
      mul_r1_req[p] = pipeline_data_ex_q[p].r_data[1];
    end

    // 流水线间信息传递
    always_comb begin
      pipeline_ctrl_m1[p].decode_info = get_m1_from_ex(pipeline_ctrl_ex_q[p].decode_info);
      pipeline_ctrl_m1[p].bpu_predict = pipeline_ctrl_ex_q[p].bpu_predict;
      pipeline_ctrl_m1[p].excp_flow = ex_excp_flow;
      pipeline_ctrl_m1[p].ctlb_opcode = pipeline_ctrl_ex[p].ctlb_opcode;
      pipeline_ctrl_m1[p].csr_id = pipeline_ctrl_ex_q[p].addr_imm[13:0];
      pipeline_ctrl_m1[p].jump_target = jump_target;
      pipeline_ctrl_m1[p].vaddr = vaddr;
      pipeline_ctrl_m1[p].pc = pipeline_ctrl_ex_q[p].pc;
    end
  end

  /* ------ ------ ------ ------ ------ M1 级 ------ ------ ------ ------ ------ */
  logic[1:0] m1_missed_branch, m1_excp_detect;
  logic[1:0][31:0] m1_target;
  for(genvar p = 0 ; p < 2 ; p++) begin
    // M1 的 FU 部分，接入 ALU、LSU（EARLY）
    m1_t decode_info;
    assign decode_info = pipeline_ctrl_m1_q[p].decode_info;
    logic[31:0] alu_result, lsu_result, paddr;
    logic[31:0] excp_target; // TODO: CONNECT ME
    excp_flow_t m1_excp_flow; // TODO: FIXME
    logic lsu_valid;
    detachable_alu #(
                     .USE_LI(0),
                     .USE_INT(1),
                     .USE_SFT(1),
                     .USE_CMP(1)
                   )m1_alu(
                     .clk(clk),
                     .rst_n(rst_n),
                     .grand_op_i(decode_info.alu_grand_op),
                     .op_i(decode_info.alu_op),

                     .mul_i('0),
                     .r0_i(pipeline_data_m1_q[p].r_data[0]),
                     .r1_i(pipeline_data_m1_q[p].r_data[1]),
                     .pc_i(pipeline_ctrl_m1_q[p].pc),

                     .result_o(alu_result)
                   );

    // M1 的额外部分
    // 跳转的处理：TODO 完成相关模块
    b_cmp m1_cmp(
            .clk(clk),
            .rst_n(rst_n),
            .valid_i(!m1_stall && exc_m1_q.valid_inst && exc_m1_q.need_commit),
            .branch_type_i(decode_info.branch_type),
            .cmp_type_i(decode_info.cmp_type),
            .bpu_predict_i(pipeline_ctrl_m1_q[p].bpu_predict),
            .target_i(pipeline_ctrl_m1_q[p].jump_target),
            .r0_i(pipeline_data_m1_q[p].r_data[0]),
            .r1_i(pipeline_data_m1_q[p].r_data[1]),
            .miss_o(m1_missed_branch[p])
          );
    // 异常的处理：完成相关模块
    excp_handler m1_excp(
                   .clk(clk),
                   .rst_n(rst_n),
                   .csr_i(csr_value),
                   .valid_i(!m1_stall && exc_m1_q.valid_inst && exc_m1_q.need_commit),
                   .excp_flow_i(m1_excp_flow),
                   .target_o(excp_target),
                   .trigger_o(m1_excp_detect)
                 );

    assign m1_target[p] = m1_excp_detect[p] ? excp_target : pipeline_ctrl_m1_q[p].jump_target;

    // CSR 控制 TODO: FIXME

    // BARRIER 指令的执行（DBAR、 IBAR）。 TODO：FIXME

    // M1 的结果选择部分: 注意： 转发逻辑不受跳转逻辑影响。 对于跳转指令，本身后续指令流就会被丢弃。
    always_comb begin
      pipeline_wdata_m1[p] = pipeline_wdata_m1_q[p]; // TODO: FIXME
      case(pipeline_ctrl_m1_q[p].fu_sel_m1)
        default: begin
          // NOTING TO DO
        end
        `_FUSEL_M1_ALU: begin
          pipeline_wdata_m1[p].w_data = alu_result;
          pipeline_wdata_m1[p].w_flow.w_valid = &pipeline_data_m1_q[p].r_flow.r_ready;
        end
        `_FUSEL_M1_MEM: begin
          pipeline_wdata_m1[p].w_data = lsu_result;
          pipeline_wdata_m1[p].w_flow.w_valid = lsu_valid;
        end
      endcase
    end

    // REFETCHER
    if(p == 0) begin
      assign m1_refetch = decode_info.refetch;
    end

    // 接入转发源
    always_comb begin
      fwd_data_m1[p] = mkfwddata(pipeline_wdata_m1[p]);
    end

    // 接入暂停请求
    always_comb begin
      m1_stall_req[p] = ((pipeline_ctrl_m1_q[p].latest_r0_m1 & ~pipeline_data_m1_q[p].r_flow.r_ready[0]) |
                         (pipeline_ctrl_m1_q[p].latest_r1_m1 & ~pipeline_data_m1_q[p].r_flow.r_ready[1]) ) &
                  exc_m1_q.valid_inst & exc_m1_q.need_commit; // LUT6 - 1
    end

    // 流水线间信息传递
    always_comb begin
      pipeline_ctrl_m2[p].decode_info = get_m2_from_m1(decode_info);
      pipeline_ctrl_m2[p].ctlb_opcode = pipeline_ctrl_m1[p].ctlb_opcode;
      pipeline_ctrl_m2[p].vaddr = pipeline_ctrl_m1[p].vaddr;
      pipeline_ctrl_m2[p].paddr = paddr;
      pipeline_ctrl_m2[p].pc = pipeline_ctrl_ex_q[p].pc;
    end
  end
  /* ------ ------ ------ ------ ------ M2 级 ------ ------ ------ ------ ------ */
  for(genvar p = 0 ; p < 2 ; p++) begin
    m1_t decode_info;
    assign decode_info = pipeline_ctrl_m2_q[p].decode_info;
    // M2 的 FU 部分，接入 ALU、LSU、MUL、CSR
    logic[31:0] alu_result, lsu_result, mul_result, csr_result;
    // MUL 结果复用 ALU 传回
    detachable_alu #(
                     .USE_LI(0),
                     .USE_INT(0),
                     .USE_MUL(1),
                     .USE_SFT(1),
                     .USE_CMP(0)
                   )m2_alu(
                     .clk(clk),
                     .rst_n(rst_n),
                     .grand_op_i(pipeline_ctrl_m2_q[p].decode_info.alu_grand_op),
                     .op_i(pipeline_ctrl_m2_q[p].decode_info.alu_op),

                     .mul_i(mul_result),
                     .r0_i(pipeline_data_m2_q[p].r_data[0]),
                     .r1_i(pipeline_data_m2_q[p].r_data[1]),
                     .pc_i(pipeline_ctrl_m2_q[p].pc),

                     .result_o(alu_result)
                   );

    // M2 的额外部分
    // CSR 修改相关指令的执行，如写 CSR、写 TLB、缓存控制均在此处执行。
    if( p == 0) begin
      always_comb begin
        {
          tlb_op_req.invtlb,
          tlb_op_req.tlbfill,
          tlb_op_req.tlbwr,
          tlb_op_req.tlbrd,
          tlb_op_req.tlbsrch
        } = {
          decode_info.invtlb_en,
          decode_info.tlbfill_en,
          decode_info.tlbwr_en,
          decode_info.tlbrd_en,
          decode_info.tlbsrch_en};
      end
    end

    // M2 的数据选择
    always_comb begin
      pipeline_wdata_m2[p] = pipeline_wdata_m1_q[p]; // TODO: FIXME
      case(pipeline_ctrl_m2_q[p].fu_sel_m1)
        default: begin
          // NOTING TO DO
        end
        `_FUSEL_M2_ALU: begin
          pipeline_wdata_m2[p].w_data = alu_result;
          pipeline_wdata_m2[p].w_flow.w_valid = &pipeline_data_m1_q[p].r_flow.r_ready;
        end
        `_FUSEL_M2_MEM: begin
          pipeline_wdata_m2[p].w_data = lsu_result;
          pipeline_wdata_m2[p].w_flow.w_valid = 1'b1;
        end
        `_FUSEL_M2_CSR: begin
          pipeline_wdata_m2[p].w_data = csr_result;
          pipeline_wdata_m2[p].w_flow.w_valid = 1'b1;
        end
      endcase
    end

    // 接入转发源
    always_comb begin
      fwd_data_m2[p] = mkfwddata(pipeline_wdata_m2[p]);
    end

    // 接入暂停请求
    always_comb begin
      m2_stall_req[p] = ((decode_info.latest_r0_m2 & ~pipeline_data_m2_q[p].r_flow.r_ready[0]) |
                         (decode_info.latest_r1_m2 & ~pipeline_data_m2_q[p].r_flow.r_ready[1]) |
                         lsu_stall_req[p]) &
                  exc_m2_q.valid_inst & exc_m2_q.need_commit; // LUT6 + MUXF7
    end


    // 流水线间信息传递
    always_comb begin
      pipeline_ctrl_wb[p].decode_info = get_wb_from_m2(decode_info);
      // pipeline_ctrl_wb[p].vaddr = pipeline_ctrl_m2[p].vaddr;
      // pipeline_ctrl_wb[p].paddr = pipeline_ctrl_m2[p].paddr;
      pipeline_ctrl_wb[p].pc = pipeline_ctrl_m2_q[p].pc;
    end
  end
  /* ------ ------ ------ ------ ------ WB 级 ------ ------ ------ ------ ------ */
  // 不存在数据前递

  for(genvar p = 0 ; p < 2 ; p++) begin
    // WB 的 FU 部分，接入 DIV，等待 DIV 完成。
    wb_t decode_info;
    assign decode_info = pipeline_ctrl_wb_q[p].decode_info;

    // WB 需要接回 IS 级的 寄存器堆和 scoreboard

    // 生成写数据
    always_comb begin
      pipeline_wdata_wb[p] = pipeline_wdata_m2_q[p];
      if(decode_info.fu_sel_wb == `_FUSEL_WB_DIV) begin
        pipeline_wdata_wb[p].w_data = div_result;
        pipeline_wdata_wb[p].w_flow.w_valid = div_result_valid;
      end
    end

    // 接入转发源
    always_comb begin
      fwd_data_wb[p] = mkfwddata(pipeline_wdata_wb[p]);
    end

    // 接入暂停请求
    always_comb begin
      wb_stall_req[p] = exc_ex_q.valid_inst & exc_ex_q.need_commit
                  & decode_info.need_div & !div_result_valid; // 4 - 1
    end

    // 接入 scoreboard、寄存器堆
    always_comb begin
      wb_w_data[p] = pipeline_wdata_wb[p].w_data;
      wb_w_addr[p] = pipeline_wdata_wb[p].w_flow.w_addr;
      wb_commit[p] = exc_wb_q.need_commit;
      wb_valid[p] = exc_wb_q.valid_inst;
    end
  end
  assign wb_w_id = pipeline_wdata_wb[0].w_flow.w_id;

endmodule

