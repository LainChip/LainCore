`include "common.svh"
`include "pipeline.svh"
`include "lsu.svh"

function fwd_data_t mkfwddata(input pipeline_wdata_t in);
mkfwddata.valid = in.w_flow.w_valid;
mkfwddata.id = in.w_flow.w_id[2:0];
mkfwddata.data = in.w_data;
endfunction

  function logic[1:0] mkmemsize(input logic[2:0] sel);
    case(sel[1:0])
      default : mkmemsize = 2'b11;
      2'b10   : mkmemsize = 2'b01;
      2'b11   : mkmemsize = 2'b00;
    endcase
  endfunction

  function logic[27:0] mkimm_addr(input logic[1:0] addr_imm_type, input logic[25:0] raw_imm);
    case (addr_imm_type)
      default : /*`_ADDR_IMM_S12:*/
        begin
          mkimm_addr = {{16{raw_imm[21]}},raw_imm[21:10]};
        end
      `_ADDR_IMM_S14 : begin
        mkimm_addr = {{12{raw_imm[23]}},raw_imm[23:10],2'b00};
      end
      `_ADDR_IMM_S16 : begin
        mkimm_addr = {{10{raw_imm[25]}},raw_imm[25:10],2'b00};
      end
      `_ADDR_IMM_S26 : begin
        mkimm_addr = {raw_imm[9:0],raw_imm[25:10],2'b00};
      end
    endcase
  endfunction

  function logic[31:0] mkimm_data(input logic[2:0] data_imm_type, input logic[25:0] raw_imm);
    // !!! CAUTIOUS !!! : DOESN'T SUPPORT IMM U16 | IMM S21 FOR NOW
    case(data_imm_type[1:0])
      // default/*IMM U5*/: begin
      //   mkimm_data = {27'd0, raw_imm[15:10]};
      // end NO NEED ANY MORE
      default : begin
        mkimm_data = {20'd0, raw_imm[21:10]};
      end
      `_IMM_S12 : begin
        mkimm_data = {{20{raw_imm[21]}}, raw_imm[21:10]};
      end
      `_IMM_S20 : begin
        mkimm_data = {{12{raw_imm[24]}}, raw_imm[24:5]};
      end
    endcase
  endfunction

module core_backend #(parameter bit ENABLE_TLB = 1'b1) (
  input  logic            clk            ,
  input  logic            rst_n          ,
  input  logic [7:0]      int_i          , // 中断输入
  input  frontend_req_t   frontend_req_i ,
  output frontend_resp_t  frontend_resp_o,
  input  cache_bus_resp_t bus_resp_i     ,
  output cache_bus_req_t  bus_req_o
);

    /* -- -- -- -- -- GLOBAL CONTROLLING LOGIC BEGIN -- -- -- -- -- */
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
    pipeline_wdata_t [1:0] pipeline_wdata_ex,pipeline_wdata_ex_q,
      pipeline_wdata_m1_q,pipeline_wdata_m1,
        pipeline_wdata_m2_q,pipeline_wdata_m2,
          pipeline_wdata_wb;

    fwd_data_t [1:0] fwd_data_ex,fwd_data_m1,fwd_data_m2,fwd_data_wb;

    exc_flow_t [1:0] exc_is,exc_skid_q,exc_ex_q,exc_m1_q,exc_m2_q,exc_wb_q;

    logic ex_stall;
    logic m1_stall;
    logic m2_stall;
    logic wb_stall;

    logic[1:0] ex_stall_req;
    logic[1:0] m1_stall_req;
    logic[1:0] m2_stall_req;
    logic[1:0] wb_stall_req;

    // 注意： invalidate 不同于 ~rst_n ，只要求无效化指令，不清除管线中的指令。
    logic       m1_refetch   ;
    logic [1:0] m1_ertn_excp ; // 对于 ertn 和 excp 的情况，有可能改变地址转换结果
    logic [1:0] m1_invalidate, m1_invalidate_req, m1_invalidate_exclude_self;
    logic       ex_invalidate, ex_m1_invalidate;

    logic is_skid_q;
    // 读取寄存器堆，或者生成立即数
    logic[1:0][1:0][4:0] is_r_addr;
    logic[1:0][1:0][31:0] is_r_data;
    logic[1:0][1:0] is_r_ready;
    logic[1:0][1:0][3:0] is_r_id;
    logic[1:0][4:0] is_w_addr;
    logic[4:0] is_w_id;

    logic[1:0][4:0] wb_w_addr;
    logic[1:0][31:0] wb_w_data;
    logic[4:0] wb_w_id;
    logic[1:0] wb_valid;
    logic[1:0] wb_commit;
    // 流水线处理，不可复位部分
    always_ff @(posedge clk) begin
      if(!ex_stall) begin
        pipeline_ctrl_ex_q  <= pipeline_ctrl_ex;
        pipeline_wdata_ex_q <= pipeline_wdata_ex;
      end
    end
    always_ff @(posedge clk) begin
      if(!m1_stall) begin
        pipeline_ctrl_m1_q  <= pipeline_ctrl_m1;
        pipeline_wdata_m1_q <= pipeline_wdata_m1;
      end
    end
    always_ff @(posedge clk) begin
      if(!m2_stall) begin
        pipeline_ctrl_m2_q  <= pipeline_ctrl_m2;
        pipeline_wdata_m2_q <= pipeline_wdata_m2;
      end
    end
    always_ff @(posedge clk) begin
      if(!wb_stall) begin
        pipeline_ctrl_wb_q <= pipeline_ctrl_wb;
      end
    end


    // 流水线处理
    for(genvar p = 0 ; p < 2 ;p ++) begin : PIPELINE_MANAGE
      // SKID
      always_ff @(posedge clk) begin
        if(~rst_n) begin
          exc_skid_q[p] <= '0;
        end
        else begin
          if(!is_skid_q) begin
            exc_skid_q[p] <= exc_is[p];
          end else begin
            if(ex_invalidate) begin
              exc_skid_q[p].need_commit <= '0;
            end
          end
        end
      end
      always_ff @(posedge clk) begin
        if(~rst_n) begin
          exc_ex_q[p] <= '0;
        end
        else begin
          if(!ex_stall) begin
            if(ex_invalidate) begin
              exc_ex_q[p].valid_inst <= is_skid_q?exc_skid_q[p].valid_inst : exc_is[p].valid_inst;
              exc_ex_q[p].need_commit <= '0;
            end else begin
              exc_ex_q[p] <= is_skid_q?exc_skid_q[p] : exc_is[p];
            end
          end else begin
            if(ex_invalidate) begin
              exc_ex_q[p].need_commit <= '0;
            end
          end
        end
      end
      always_ff @(posedge clk) begin
        if(~rst_n) begin
          exc_m1_q[p] <= '0;
        end
        else begin
          if(!m1_stall) begin
            exc_m1_q[p].valid_inst <= exc_ex_q[p].valid_inst;
            if(ex_m1_invalidate || ex_stall) begin
              exc_m1_q[p].need_commit <= '0;
            end else begin
              exc_m1_q[p].need_commit <= exc_ex_q[p].need_commit;
            end
            if(ex_stall) begin
              exc_m1_q[p].valid_inst <= '0;
            end
          end else begin
            if(m1_invalidate[p]) begin
              exc_m1_q[p].need_commit <= '0;
            end
          end
        end
      end

      always_ff @(posedge clk) begin
        if(~rst_n) begin
          exc_m2_q[p] <= '0;
        end
        else begin
          if(!m2_stall) begin
            exc_m2_q[p].valid_inst <= exc_m1_q[p].valid_inst;
            if(m1_invalidate[p] || m1_stall) begin
              exc_m2_q[p].need_commit <= '0;
            end
            else begin
              exc_m2_q[p].need_commit <= exc_m1_q[p].need_commit;
            end
            if(m1_stall) begin
              exc_m2_q[p].valid_inst <= '0;
            end
          end
        end
      end

      always_ff @(posedge clk) begin
        if(~rst_n) begin
          exc_wb_q[p] <= '0;
        end
        else begin
          if(!wb_stall) begin
            if(m2_stall) begin
              exc_wb_q[p] <= '0;
            end else begin
              exc_wb_q[p] <= exc_m2_q[p];
            end
          end
        end
      end
    end
    // STALL MANAGER
    // 后续级可以阻塞前级
    // 就算前级中有气泡，也不可以前进（并没有必要，徒增stall逻辑复杂度）。但前级不能阻塞后级。
    logic[1:0] m1_lsu_busy,m2_lsu_busy;
    logic rstall_1, rstall_2, rstall_3, rstall_4;
    logic[1:0] m1_addr_trans_ready;
    always_comb begin
      ex_stall = |ex_stall_req | |m1_stall_req         | !(&m1_addr_trans_ready) | |m2_stall_req | |wb_stall_req | |m1_lsu_busy | |m2_lsu_busy | rstall_1 | rstall_2 | rstall_3 | rstall_4;
      m1_stall = |m1_stall_req | !(&m1_addr_trans_ready) | |m2_stall_req         | |wb_stall_req | |m1_lsu_busy  | |m2_lsu_busy | rstall_2 | rstall_3 | rstall_4;
      m2_stall = |m2_stall_req | |wb_stall_req         | |m2_lsu_busy          | rstall_3 | rstall_4;
      wb_stall = |wb_stall_req | rstall_4;
    end

  tests_random_stall #(.PERCETAGE(`_GLOBAL_BACK_STALL_P)) tests_random_stall_ex (
    .clk    (clk     ),
    .rst_n  (rst_n   ),
    .stall_o(rstall_1)
  );
  tests_random_stall #(.PERCETAGE(`_GLOBAL_BACK_STALL_P)) tests_random_stall_m1 (
    .clk    (clk     ),
    .rst_n  (rst_n   ),
    .stall_o(rstall_2)
  );
  tests_random_stall #(.PERCETAGE(`_GLOBAL_BACK_STALL_P)) tests_random_stall_n2 (
    .clk    (clk     ),
    .rst_n  (rst_n   ),
    .stall_o(rstall_3)
  );
  tests_random_stall #(.PERCETAGE(`_GLOBAL_BACK_STALL_P)) tests_random_stall_wb (
    .clk    (clk     ),
    .rst_n  (rst_n   ),
    .stall_o(rstall_4)
  );

    // M2 级的跳转寄存器设计位

    logic[1:0][31:0] m1_target;
    logic[31:0] m2_jump_target_q;
    bpu_correct_t[1:0] m1_bpu_feedback_req;
    bpu_correct_t m2_bpu_feedback_q    ;
    logic         m2_jump_valid_q      ;
    logic         m2_jump_addr_change_q; // 导致地址转换改变的跳转，需要暂停前端等待地址转换同步
    logic         addr_change_stall_q  ;
    always_ff @(posedge clk) begin
      if(!rst_n) begin
        addr_change_stall_q <= '0;
      end else begin
        if(m2_jump_addr_change_q) begin
          // 有地址改变，需要暂停前端同步
          addr_change_stall_q <= '1;
        end else begin
          if(addr_change_stall_q && !m2_stall) begin
            addr_change_stall_q <= '0;
          end
        end
      end
    end
    assign frontend_resp_o.addr_trans_stall = addr_change_stall_q;
    always_ff @(posedge clk) begin
      m2_jump_valid_q       <= (m1_stall) ? '0 : |m1_invalidate_req;
      m2_jump_target_q      <= (m1_invalidate_req[0]) ? m1_target[0] : m1_target[1];
      m2_bpu_feedback_q     <= (m1_bpu_feedback_req[0].need_update || m1_bpu_feedback_req[0].ras_miss_type) ? m1_bpu_feedback_req[0] : m1_bpu_feedback_req[1];
      m2_jump_addr_change_q <= (m1_stall) ? '0 : ((|m1_ertn_excp) || m1_refetch);
    end
    assign frontend_resp_o.rst_jmp        = m2_jump_valid_q;
    assign frontend_resp_o.rst_jmp_target = m2_jump_target_q;
    assign frontend_resp_o.bpu_correct    = m2_bpu_feedback_q;


    // INVALIDATE MANAGER
    always_comb begin
      ex_invalidate    = /*|m1_invalidate_req*/ m2_jump_valid_q;
      ex_m1_invalidate = |m1_invalidate_req | m2_jump_valid_q;
      m1_invalidate[0] = (m1_invalidate_req[0] & !m1_invalidate_exclude_self[0]) |
        m2_jump_valid_q;
      m1_invalidate[1] = (m1_invalidate_req[0] | (m1_invalidate_req[1] & !m1_invalidate_exclude_self[1])) |
        m2_jump_valid_q;
    end

    // forwarding manager
    /* 所有级流水的前递模块在这里实例化*/
    for(genvar p = 0 ; p < 2 ; p++) begin : FWD_BLOCK
      core_fwd_unit #(3) is_fwd(
        {fwd_data_wb, fwd_data_ex, fwd_data_m1/* NO MEM FEEDBACK LD-NOP-ALU*/},
        pipeline_data_is[p],
        pipeline_data_is_fwd[p]
      );
    core_fwd_unit #(2) is_skid_fwd (
      {fwd_data_wb, fwd_data_ex},
      pipeline_data_skid_q[p],
      pipeline_data_skid_fwd[p]
    );
    core_fwd_unit #(3) ex_fwd (
      {fwd_data_wb, fwd_data_m1, fwd_data_m2 /* SUPPORT FULL */},
      pipeline_data_ex_q[p],
      pipeline_data_ex_fwd[p]
    );
      always_ff@(posedge clk) begin
        if(ex_stall) begin
          pipeline_data_ex_q[p] <= pipeline_data_ex_fwd[p];
        end
        else begin
          pipeline_data_ex_q[p] <= is_skid_q?pipeline_data_skid_fwd[p] : pipeline_data_is_fwd[p];
        end
      end
      core_fwd_unit #(2) m1_fwd(
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
      core_fwd_unit #(1) m2_fwd(
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
    // dram_manager_req_t[1:0] dm_req;
    // dram_manager_resp_t[1:0] dm_resp;
    // dram_manager_snoop_t dm_snoop;
    rport_state_t [1:0] rstate   ;
    wport_state_t [1:0] wstate   ;
    wport_wreq_t        wport_req;
  core_lsu_wport #(
    .PIPE_MANAGE_NUM(2),
    // .BANK_NUM       (2),
    .WAY_CNT        (2),
    .SLEEP_CNT      (4)
  ) lsu_wport_inst (
    .clk        (clk       ),
    .rst_n      (rst_n     ),
    .rstate_i   (rstate    ),
    .wstate_o   (wstate    ),
    .wport_req_o(wport_req ),
    .bus_req_o  (bus_req_o ),
    .bus_resp_i (bus_resp_i),
    .bus_busy_o (bus_busy  )
  );
    // BUS 一致锁
    assign frontend_resp_o.bus_busy = bus_busy;
    // LSU 端口实例化
    logic[1:0] ex_mem_read,m1_mem_read,m2_mem_valid,m1_mem_uncached,m2_mem_uncached;
    logic[1:0][1:0] m2_mem_size;
    logic[1:0][31:0] ex_mem_vaddr,m1_mem_vaddr,m1_mem_paddr,m2_mem_vaddr,m2_mem_paddr;
    logic[1:0][3:0] m1_mem_strobe, m2_mem_strobe;
    logic[1:0][2:0] m2_mem_type;

    logic[1:0] m1_mem_rvalid,m2_mem_rvalid;
    logic[1:0][31:0] m1_mem_rdata,m2_mem_rdata;
    logic[1:0][31:0] m2_mem_wdata;
    logic[1:0][2:0] m2_mem_op;
    for(genvar p = 0 ; p < 2 ; p ++) begin : lsu_pm_block
      core_lsu_rport # (
        .WAY_CNT(2)
      )
      lsu_inst (
        .clk(clk),
        .rst_n(rst_n),
        .ex_vaddr_i(ex_mem_vaddr[p]),
        .ex_read_i(ex_mem_read[p]),
        .m1_vaddr_i(m1_mem_vaddr[p]),
        .m1_paddr_i(m1_mem_paddr[p]),
        .m1_strobe_i(m1_mem_strobe[p]),
        .m1_read_i(m1_mem_read[p]),
        .m1_uncached_i(m1_mem_uncached[p]),
        .m1_busy_o(m1_lsu_busy[p]),
        .m1_stall_i(m1_stall),
        .m1_rdata_o(m1_mem_rdata[p]),
        .m1_rvalid_o(m1_mem_rvalid[p]),
        .m2_vaddr_i(m2_mem_vaddr[p]),
        .m2_paddr_i(m2_mem_paddr[p]),
        .m2_wdata_i(m2_mem_wdata[p]),
        .m2_strobe_i(m2_mem_strobe[p]),
        .m2_type_i(m2_mem_type[p]),
        .m2_valid_i(m2_mem_valid[p]),
        .m2_uncached_i(m2_mem_uncached[p]),
        .m2_size_i(m2_mem_size[p]),
        .m2_busy_o(m2_lsu_busy[p]),
        .m2_stall_i(m2_stall),
        .m2_op_i(m2_mem_op[p]),
        .m2_rdata_o(m2_mem_rdata[p]),
        .m2_rvalid_o(m2_mem_rvalid[p]),
        // .dm_req_o(dm_req[p]),
        // .dm_resp_i(dm_resp[p]),
        // .dm_snoop_i(dm_snoop)
        .rstate_o(rstate[p]),
        .wstate_i(wstate[p]),
        .wreq_i(wport_req) // 需要做 snoop
      );
    end
    // MUL 端口实例化
    logic[1:0] mul_req;
    logic[1:0][1:0] mul_op_req;
    logic[1:0][31:0] mul_r0_req,mul_r1_req;
    logic[1:0] mul_op;
    logic[31:0] mul_r0,mul_r1;
    logic[1:0][31:0] mul_result;
    always_comb begin
      mul_op        = mul_req[0] ? mul_op_req[0] : mul_op_req[1];
      mul_r0        = mul_req[0] ? mul_r0_req[0] : mul_r0_req[1];
      mul_r1        = mul_req[0] ? mul_r1_req[0] : mul_r1_req[1];
      mul_result[1] = mul_result[0];
    end
  muler_32x32 mul_i (
    .clk       (clk          ),
    .rst_n     (rst_n        ),
    .op_i      (mul_op       ),
    
    .ex_stall_i(ex_stall     ),
    .m1_stall_i(m1_stall     ),
    .m2_stall_i(m2_stall     ),
    
    .r0_i      (mul_r0       ),
    .r1_i      (mul_r1       ),
    
    .result_o  (mul_result[0])
  );
    // for(genvar p = 0; p < 2 ; p++) begin
    //   muler_32x32 mul_i (
    //     .clk       (clk       ),
    //     .rst_n     (rst_n     ),
    //     .op_i      (mul_op_req[p]),

    //     .ex_stall_i(ex_stall  ),
    //     .m1_stall_i(m1_stall  ),
    //     .m2_stall_i(m2_stall  ),

    //     .r0_i      (mul_r0_req[p]),
    //     .r1_i      (mul_r1_req[p]),

    //     .result_o  (mul_result[p])
    //   );
    // end

    // 除法器例化 FIXME: FREQUENCY
    logic[1:0] div_req;
    logic[1:0][1:0] div_op_req;
    logic[1:0][1:0][31:0] div_input_req;
    logic div_valid;
    logic div_ready;
    logic[1:0] div_op;
    logic[2:0] div_push_id; // EX
    logic[2:0] div_pop_id;  // M2
    logic[1:0][31:0] div_input;

    logic[1:0] div_request_req;
    logic div_request;
    logic[31:0] div_result;
    logic div_result_valid;
    always_comb begin
      div_valid   = |div_req;
      div_input   = div_req[0] ? div_input_req[0] : div_input_req[1];
      div_op      = div_req[0] ? div_op_req[0] : div_op_req[1];
      div_request = |div_request_req;
      div_push_id = pipeline_wdata_ex[0].w_flow.w_id[2:0];
      div_pop_id  = pipeline_wdata_m2[0].w_flow.w_id[2:0];
    end
  core_divider_manager core_divider_manager_inst (
    .clk           (clk             ),
    .rst_n         (rst_n           ),
    .r0_i          (div_input[0]    ),
    .r1_i          (div_input[1]    ),
    .op_i          (div_op          ),
    .push_valid_i  (div_valid       ),
    .push_ready_o  (div_ready       ),
    .push_id_i     (div_push_id     ),
    .wb_stall_i    (wb_stall        ),
    .pop_id_i      (div_pop_id      ),
    .result_valid_o(div_result_valid),
    .result_o      (div_result      )
  );

    // DADDR_TRANS 接入 (EX - M1)
    // 注意：暂停信号在 M1 级产生
    // TLB REQ 接入
    tlb_op_t tlb_op; // ONE HOT ENCODING OF TLBSRCH | TLBRD | TLBWR | TLBFILL | INVTLB

    // CACHE | MMU opcode 接入
    logic[4:0] ctlb_opcode;

    // CSR output
    csr_t csr_value;

    // CSR STALL

    assign frontend_resp_o.csr_reg = csr_value;
    logic[1:0] ex_addr_trans_valid; // TODO: CHECK ME
    logic[1:0] addr_tlb_req_valid,addr_tlb_req_ready; // TODO: CHECK ME
    tlb_s_resp_t[1:0] addr_tlb_resp;
    tlb_s_resp_t[1:0] m1_addr_trans_result;

    // tlb 更新信号
    tlb_update_req_t tlb_update_req;
    assign frontend_resp_o.tlb_update_req = tlb_update_req;

    for(genvar p = 0 ; p < 2 ; p++) begin : DADDR_TRANS
      core_addr_trans #(
        .ENABLE_TLB(ENABLE_TLB), // TODO: PARAMETERIZE ME
        .FETCH_ADDR('0)
      ) core_daddr_trans_inst (
        .clk             (clk                    ),
        .rst_n           (rst_n                  ),
        .valid_i         (ex_addr_trans_valid[p] ),
        .vaddr_i         (ex_mem_vaddr[p]        ),
        .m1_stall_i      (m1_stall               ),
        .jmp_i           ('0                     ),
        .flush_i         ('0                     ),
        .ready_o         (m1_addr_trans_ready[p] ),
        .csr_i           (csr_value              ),
        .tlb_update_req_i(tlb_update_req         ),
        .trans_result_o  (m1_addr_trans_result[p])
      );
    end

    // DADDR_TRANS 结果流水 (M1 - M2): 提供给 CSR 使用。

    // CSR 接入 (M1)
    logic[13:0] csr_r_addr;
    logic[1:0]  csr_rdcnt          ;
    logic csr_m1_int         ;
    logic csr_m1_commit_valid;
    logic csr_m2_commit_valid;

    // CSR 接入 (M2)
    logic[1:0] csr_excp_req;
    logic[1:0] m2_valid_req;
    logic[1:0] m2_commit_req;
    logic[1:0][31:0] m2_badv_req;
    logic[1:0][31:0] m2_csr_pc_req;
    excp_flow_t [1:0] m2_excp_req;
    logic             csr_we     ;
    logic             csr_valid,csr_commit;
    logic             csr_ertn   ;
    logic[31:0] csr_badv;
    logic[31:0] csr_pc;
    excp_flow_t csr_excp;
    logic[13:0] csr_w_addr;
    logic[31:0] csr_r_data,csr_w_data,csr_w_mask;
    always_comb begin
      csr_valid  = (csr_we | csr_excp_req[0]) ? m2_valid_req[0] : m2_valid_req[1];
      csr_commit = (csr_we | csr_excp_req[0]) ? m2_commit_req[0] : m2_commit_req[1];
      csr_badv   = csr_excp_req[0] ? m2_badv_req[0] : m2_badv_req[1];
      csr_excp   = csr_excp_req[0] ? m2_excp_req[0] : (csr_excp_req[1] ? m2_excp_req[1] : '0);
      csr_pc     = csr_excp_req[0] ? m2_csr_pc_req[0] : m2_csr_pc_req[1];
    end

    logic llbit_set  ; // TODO: CHECK ME
    logic llbit_value;
    core_csr #(.ENABLE_TLB(ENABLE_TLB)/*TODO:PARAMETERPASS*/) core_csr_inst (
      .clk             (clk                            ),
      .rst_n           (rst_n                          ),
      .int_i           (int_i                          ),
      .excp_i          (csr_excp                       ),
      .ertn_i          (csr_ertn                       ),
      .valid_i         (csr_valid                      ),
      .commit_i        (csr_commit                     ),
      .m1_stall_i      (m1_stall                       ),
      .m1_not_interruptable_i('0),
      .m2_stall_i      (m2_stall                       ),
      .csr_r_addr_i    (csr_r_addr                     ),
      .rdcnt_i         (csr_rdcnt                      ),
      .csr_we_i        (csr_we                         ),
      .csr_w_addr_i    (csr_w_addr                     ),
      .csr_w_mask_i    (csr_w_mask                     ),
      .csr_w_data_i    (csr_w_data                     ),
      .badv_i          (csr_badv                       ),
      .tlb_op_vaddr_i  (pipeline_data_m1_q[0].r_data[0]),
      .tlb_op_asid_i   (pipeline_data_m1_q[0].r_data[1]),
      .tlb_op_i        (tlb_op                         ),
      .tlb_inv_op_i    (ctlb_opcode                    ),
      .tlb_update_req_o(tlb_update_req                 ),

      .llbit_set_i     (llbit_set                     ),
      .llbit_i         (llbit_value                   ),

      .pc_i            (csr_pc                         ),
      .vaddr_i         (csr_badv                       ),

      .m1_commit_i     (csr_m1_commit_valid            ),
      .m1_int_o        (csr_m1_int                     ),

      .m2_commit_i     (csr_m2_commit_valid            ),

      .csr_r_data_o    (csr_r_data                     ),
      .csr_o           (csr_value                      )
    );
    assign csr_m1_commit_valid = exc_m1_q[0].need_commit;
    assign csr_m2_commit_valid = exc_m2_q[0].need_commit;

    /* -- -- -- -- -- GLOBAL CONTROLLING LOGIC BEGIN -- -- -- -- -- */

    /* ------ ------ ------ ------ ------ IS 级 ------ ------ ------ ------ ------ */
    // ISSUE 级别：
    // 判定来自前段的指令能否发射
    logic       is_ready       ;
    logic       ex_skid_ready_q,ex_skid_valid;
    logic [1:0] issue          ;
    inst_t[1:0] is_inst_pack;
    assign is_inst_pack = frontend_req_i.inst;
  issue issue_inst (
    .clk       (clk                                            ),
    .rst_n     (rst_n                                          ),
    .inst_i    (is_inst_pack                                   ),
    .d_valid_i (frontend_req_i.inst_valid & {is_ready,is_ready}),
    .ex_ready_i(ex_skid_ready_q                                ),
    .ex_valid_o(ex_skid_valid                                  ),
    .is_o      (issue                                          )
  );
    assign frontend_resp_o.issue = issue;

  reg_file #(.DATA_WIDTH(32)) reg_file_inst (
    .clk     (clk                 ),
    .rst_n   (rst_n               ),
    .r_addr_i(is_r_addr           ),
    .r_data_o(is_r_data           ),
    .w_addr_i(wb_w_addr           ),
    .w_data_i(wb_w_data           ),
    .w_en_i  (wb_valid & wb_commit)
  );

    // 读取 scoreboard，判断寄存器值是否有效
  scoreboard scoreboard_inst (
    .clk          (clk          ),
    .rst_n        (rst_n        ),
    .invalidate_i (ex_invalidate),
    .issue_ready_o(is_ready     ),
    .is_r_addr_i  (is_r_addr    ),
    .is_r_id_o    (is_r_id      ),
    .is_r_valid_o (is_r_ready   ),
    .is_w_addr_i  (is_w_addr    ),
    .is_i         (issue        ),
    .is_w_id_o    (is_w_id      ),
    .wb_w_addr_i  (wb_w_addr    ),
    .wb_w_id_i    (wb_w_id      ),
    .wb_valid_i   (wb_valid     )
  );

    // 产生 EX 级的流水线信号 x 2
    logic ex_ready;
    assign ex_ready = !ex_stall;
    // IS 数据前递部分（EX、WB），输入是 pipeline_ctrl_is ，输出 pipeline_ctrl_is_fwd 不完全。

    /* SKID BUF */
    // SKID 数据前递部分（EX、WB） 不完全。
    // 输入是 pipeline_ctrl_skid_q，输出 pipeline_ctrl_skid_fwd
    // SKID BUF 对于 scoreboard 来说应该是透明的，使用 valid-ready 握手
    // assign ex_skid_ready_q = ~is_skid_q;
    always_ff @(posedge clk) begin
      if(~rst_n/* || ex_invalidate*/) begin
        is_skid_q       <= '0;
        ex_skid_ready_q <= '1;
      end
      else begin
        if(is_skid_q) begin
          if(ex_ready) begin
            is_skid_q       <= '0;
            ex_skid_ready_q <= '1;
          end
          pipeline_data_skid_q <= pipeline_data_skid_fwd;
        end
        else begin
          if(ex_skid_valid & ~ex_ready) begin
            is_skid_q       <= '1;
            ex_skid_ready_q <= '0;
          end
          pipeline_data_skid_q <= pipeline_data_is_fwd;
        end
      end
    end
    always_ff @(posedge clk) begin
      if(!is_skid_q) begin
        pipeline_ctrl_skid_q <= pipeline_ctrl_is;
        // exc_skid_q           <= exc_is;
      end
    end
    /* SKID BUF 结束*/
    always_comb begin
      pipeline_ctrl_ex = is_skid_q ? pipeline_ctrl_skid_q : pipeline_ctrl_is;
    end
    for(genvar p = 0 ; p < 2 ; p++) begin : ISSUE
      // 产生 pipeline_ctrl_is 用于控制流水线
      always_comb begin
        is_r_addr[p] = is_inst_pack[p].reg_info.r_reg;
        is_w_addr[p] = is_inst_pack[p].reg_info.w_reg;
        pipeline_ctrl_is[p].decode_info = get_ex_from_is(is_inst_pack[p].decode_info);
        pipeline_ctrl_is[p].w_reg = is_inst_pack[p].reg_info.w_reg;
        pipeline_ctrl_is[p].w_id = is_w_id;
        pipeline_ctrl_is[p].bpu_predict = is_inst_pack[p].bpu_predict;
        pipeline_ctrl_is[p].fetch_excp = is_inst_pack[p].fetch_excp;
        pipeline_ctrl_is[p].addr_imm = mkimm_addr(is_inst_pack[p].decode_info.addr_imm_type, is_inst_pack[p].imm_domain);
        pipeline_ctrl_is[p].op_code = is_inst_pack[p].imm_domain[4:0];
        pipeline_ctrl_is[p].pc = is_inst_pack[p].pc;
        exc_is[p].valid_inst = issue[p];
        exc_is[p].need_commit = issue[p];
        pipeline_data_is[p].r_data[0] = is_inst_pack[p].decode_info.reg_type_r0 == `_REG_R0_IMM ?
          mkimm_data(is_inst_pack[p].decode_info.imm_type,
            is_inst_pack[p].imm_domain) :
          is_r_data[p][0];
        pipeline_data_is[p].r_data[1] = is_r_data[p][1];
        pipeline_data_is[p].r_flow.r_addr[0] = is_r_addr[p][0];
        pipeline_data_is[p].r_flow.r_addr[1] = is_r_addr[p][1];
        pipeline_data_is[p].r_flow.r_id[0] = is_r_id[p][0];
        pipeline_data_is[p].r_flow.r_id[1] = is_r_id[p][1];
        pipeline_data_is[p].r_flow.r_ready[0] = is_r_ready[p][0];
        pipeline_data_is[p].r_flow.r_ready[1] = is_r_ready[p][1];
      end
    end
    /* ------ ------ ------ ------ ------ EX 级 ------ ------ ------ ------ ------ */
    for(genvar p = 0 ; p < 2 ; p++) begin : EX
      // EX 级别
      // EX 的 FU 部分，接入 ALU、乘法器、除法队列 pusher（Optional）
      logic[31:0] alu_result;
      logic[31:0] jump_target;
      logic[31:0] vaddr, rel_target;
      ex_t decode_info;
      assign decode_info = pipeline_ctrl_ex_q[p].decode_info;
    core_detachable_alu #(
      .USE_LI (1),
      .USE_INT(0),
      .USE_SFT(0),
      .USE_CMP(0)
    ) ex_alu (
      .grand_op_i(decode_info.alu_grand_op       ),
      .op_i      (decode_info.alu_op             ),
      
      .mul_i     ('0                             ),
      .r0_i      (pipeline_data_ex_q[p].r_data[0]),
      .r1_i      (pipeline_data_ex_q[p].r_data[1]),
      .pc_i      (pipeline_ctrl_ex_q[p].pc       ),
      
      .res_o     (alu_result                     )
    );

      excp_flow_t ex_excp_flow;
      // ex_excp_flow 产生逻辑
      always_comb begin
        ex_excp_flow       = '0;
        ex_excp_flow.m1int = '0;
        ex_excp_flow.pil   = '0;
        ex_excp_flow.pis   = '0;
        ex_excp_flow.pme   = '0;
        ex_excp_flow.ppi   = '0;
        ex_excp_flow.adem  = '0;
        ex_excp_flow.ale   = '0;
        ex_excp_flow.tlbr  = '0;


        ex_excp_flow.adef  = (!(|ex_excp_flow)) && pipeline_ctrl_ex_q[p].fetch_excp.adef && exc_ex_q[p].need_commit;
        ex_excp_flow.itlbr = (!(|ex_excp_flow)) && pipeline_ctrl_ex_q[p].fetch_excp.tlbr && exc_ex_q[p].need_commit;
        ex_excp_flow.pif   = (!(|ex_excp_flow)) && pipeline_ctrl_ex_q[p].fetch_excp.pif && exc_ex_q[p].need_commit;
        ex_excp_flow.ippi  = (!(|ex_excp_flow)) && pipeline_ctrl_ex_q[p].fetch_excp.ppi && exc_ex_q[p].need_commit;

        // TODO: CACOP IN HIT IS NOT A PRIVILIGE INST
        // BUT WE JUST TAKE ALL CACHE OP AS NOT PRIVILIGE INST.
        // THIS MAY ALLOW APPLICATION USE OP==0 TO HARM OUR OPERATING SYSTEM.
        ex_excp_flow.ipe = (!(|ex_excp_flow)) && exc_ex_q[p].need_commit &&
          (csr_value.crmd[`PLV] == 2'd3 && decode_info.priv_inst);

        ex_excp_flow.ine = (!(|ex_excp_flow)) && exc_ex_q[p].need_commit &&
          (decode_info.invalid_inst || (ENABLE_TLB && decode_info.invtlb_en && (pipeline_ctrl_ex_q[p].op_code > 5'd6)));
        ex_excp_flow.sys = (!(|ex_excp_flow)) && decode_info.syscall_inst && exc_ex_q[p].need_commit;
        ex_excp_flow.brk = (!(|ex_excp_flow)) && decode_info.break_inst && exc_ex_q[p].need_commit;

      end
      // EX 的额外部分
      // EX 级别的访存地址计算 / 地址翻译逻辑
      always_comb begin
        vaddr = {{4{pipeline_ctrl_ex_q[p].addr_imm[27]}},
          pipeline_ctrl_ex_q[p].addr_imm} +
        pipeline_data_ex_q[p].r_data[1];
      end
      always_comb begin
        rel_target = pipeline_ctrl_ex_q[p].pc + {{4{pipeline_ctrl_ex_q[p].addr_imm[27]}},
          pipeline_ctrl_ex_q[p].addr_imm};
      end
      always_comb begin
        jump_target = decode_info.target_type == `_TARGET_ABS ?
          vaddr : rel_target;
      end

      // EX 的结果选择部分
      always_comb begin
        pipeline_wdata_ex[p].w_data = alu_result;
        pipeline_wdata_ex[p].w_flow.w_id = pipeline_ctrl_ex_q[p].w_id;
        pipeline_wdata_ex[p].w_flow.w_addr = pipeline_ctrl_ex_q[p].w_reg;
        pipeline_wdata_ex[p].w_flow.w_valid = exc_ex_q[p].need_commit && (decode_info.fu_sel_ex == `_FUSEL_EX_ALU ? (
            (&pipeline_data_ex_q[p].r_flow.r_ready)) :
          '0);
      end

      // 接入转发源
      always_comb begin
        fwd_data_ex[p] = mkfwddata(pipeline_wdata_ex[p]);
      end

      // 接入暂停请求
      always_comb begin
        ex_stall_req[p] = ((decode_info.latest_r0_ex & ~pipeline_data_ex_q[p].r_flow.r_ready[0]) |
          (decode_info.latest_r1_ex & ~pipeline_data_ex_q[p].r_flow.r_ready[1]) |
          (decode_info.need_div & ~div_ready)) &
        exc_ex_q[p].need_commit; // LUT6 - 1
      end

      // 接入 dcache
      // 接入 addr-trans 模块
      assign ex_mem_read[p] = decode_info.mem_read && exc_ex_q[p].need_commit;
      assign ex_mem_vaddr[p]        = vaddr;
      assign ex_addr_trans_valid[p] = decode_info.need_lsu;

      // 接入 mul
      always_comb begin
        mul_req[p]    = decode_info.need_mul;
        mul_op_req[p] = decode_info.alu_op;
        mul_r0_req[p] = pipeline_data_ex_q[p].r_data[0];
        mul_r1_req[p] = pipeline_data_ex_q[p].r_data[1];
      end

      // 接入 div
      always_comb begin
        div_req[p] = decode_info.need_div && exc_ex_q[p].need_commit && exc_ex_q[p].need_commit &&
          &pipeline_data_ex_q[p].r_flow.r_ready;
        div_op_req[p]       = decode_info.alu_op;
        div_input_req[p][0] = pipeline_data_ex_q[p].r_data[0];
        div_input_req[p][1] = pipeline_data_ex_q[p].r_data[1];
      end

      // 流水线间信息传递
      always_comb begin
        pipeline_ctrl_m1[p].decode_info = get_m1_from_ex(pipeline_ctrl_ex_q[p].decode_info);
        pipeline_ctrl_m1[p].bpu_predict = pipeline_ctrl_ex_q[p].bpu_predict;
        pipeline_ctrl_m1[p].excp_flow = ex_excp_flow;
        pipeline_ctrl_m1[p].op_code = pipeline_ctrl_ex_q[p].op_code;
        // 注意，这里 inst[9:0] -> addr_imm[27:18]
        // inst[25:10] -> addr_imm[17:2]
        // pipeline_ctrl_m1[p].csr_id = (decode_info.csr_rdcnt == 0) ?
        //   pipeline_ctrl_ex_q[p].addr_imm[15:2] :
        //     {pipeline_ctrl_ex_q[p].addr_imm[15:7],pipeline_ctrl_ex_q[p].addr_imm[22:18]};
        pipeline_ctrl_m1[p].csr_id = pipeline_ctrl_ex_q[p].addr_imm[15:2];
        pipeline_ctrl_m1[p].jump_target = jump_target;
        pipeline_ctrl_m1[p].vaddr = vaddr;
        pipeline_ctrl_m1[p].pc = pipeline_ctrl_ex_q[p].pc;
      end
    end

    /* ------ ------ ------ ------ ------ M1 级 ------ ------ ------ ------ ------ */
    logic[1:0] m1_excpertn_detect;
    for(genvar p = 0 ; p < 2 ; p++) begin : M1
      // M1 的 FU 部分，接入 ALU、LSU（EARLY）
      m1_t decode_info;
      assign decode_info = pipeline_ctrl_m1_q[p].decode_info;
      logic[31:0] alu_result, lsu_result, paddr;
      assign lsu_result = m1_mem_rdata[p];
      logic[31:0] excp_target;
      excp_flow_t m1_excp_flow;
      logic       lsu_valid   ;
    core_detachable_alu #(
      .USE_LI (0),
      .USE_INT(1),
      .USE_SFT(1),
      .USE_CMP(1)
    ) m1_alu (
      .clk       (clk                            ),
      .rst_n     (rst_n                          ),
      .grand_op_i(decode_info.alu_grand_op       ),
      .op_i      (decode_info.alu_op             ),
      
      .mul_i     ('0                             ),
      .r0_i      (pipeline_data_m1_q[p].r_data[0]),
      .r1_i      (pipeline_data_m1_q[p].r_data[1]),
      .pc_i      (pipeline_ctrl_m1_q[p].pc       ),
      
      .res_o     (alu_result                     )
    );

      // M1 的额外部分
      // 跳转的处理：TODO 完成相关模块
      logic        m1_branch_jmp_req;
      logic [ 1:0] target_type      ;
      logic [31:0] true_bpu_target  ;
    core_jmp m1_cmp (
      .clk          (clk                                 ),
      .rst_n        (rst_n                               ),
      .valid_i      (!m1_stall && exc_m1_q[p].need_commit),
      .target_type_i(target_type                         ),
      .cmp_type_i   (decode_info.cmp_type                ),
      .bpu_predict_i(pipeline_ctrl_m1_q[p].bpu_predict   ),
      .bpu_correct_o(m1_bpu_feedback_req[p]              ),
      .pc_i         (pipeline_ctrl_m1_q[p].pc            ),
      .target_i     (pipeline_ctrl_m1_q[p].jump_target   ),
      .target_o     (true_bpu_target                     ),
      .r0_i         (pipeline_data_m1_q[p].r_data[0]     ),
      .r1_i         (pipeline_data_m1_q[p].r_data[1]     ),
      .jmp_o        (m1_branch_jmp_req                   )
    );

      always_comb begin
        target_type = '0;
        if(decode_info.need_bpu && pipeline_wdata_m1[p].w_flow.w_addr == 5'd1) begin // 1 -> CALL JIRL BL
          target_type = 2'd1;
        end else if(decode_info.need_bpu && pipeline_data_m1_q[p].r_flow.r_addr[1] == 5'd1) begin // 2 -> RETURN
          target_type = 2'd2;
        end else if(decode_info.need_bpu) begin  // 3 -> IMM
          target_type = 2'd3;
        end
      end

      assign m1_mem_read[p]     = exc_m1_q[p].need_commit && decode_info.mem_read;
      assign m1_mem_uncached[p] = m1_addr_trans_result[p].value.mat != 2'd1 &&
        !decode_info.mem_cacop; // TODO: CHECKME
      // assign m1_mem_uncached[p] = !decode_info.mem_cacop; // TODO: CHECKME
      assign m1_mem_vaddr[p]  = pipeline_ctrl_m1_q[p].vaddr;
      assign m1_mem_paddr[p]  = paddr;
      assign m1_mem_strobe[p] = mkwstrobe(decode_info.mem_type, pipeline_ctrl_m1_q[p].vaddr);
      // 异常的处理：完成相关模块
      logic local_excp_detect;
      core_excp_handler m1_excp (
        .clk        (clk                  ),
        .rst_n      (rst_n                ),
        .csr_i      (csr_value            ),
        .valid_i    (!m1_stall && exc_m1_q[p].need_commit
          && (p == 0 ? 1'b1 : !m1_invalidate_req[0])),
        .ertn_inst_i(decode_info.ertn_inst),
        .excp_flow_i(m1_excp_flow         ),
        .target_o   (excp_target          ),
        .trigger_o  (local_excp_detect    )
      );
      // assign m1_excpertn_detect[p] = p == 0 ? local_excp_detect :
      // (local_excp_detect && !m1_invalidate_req[0]);/
      assign m1_excpertn_detect[p] = local_excp_detect;

      // 物理地址产生
      assign paddr = {m1_addr_trans_result[p].value.ppn, pipeline_ctrl_m1_q[p].vaddr[11:0]};

      // CSR 控制 TODO: FIXME

      // BARRIER 指令的执行（DBAR、 IBAR）。 TODO：FIXME

      // M1 的结果选择部分: 注意： 转发逻辑不受跳转逻辑影响。 对于跳转指令，本身后续指令流就会被丢弃。
      always_comb begin
        pipeline_wdata_m1[p] = pipeline_wdata_ex_q[p]; // TODO: FIXME
        case(decode_info.fu_sel_m1)
          default : begin
            pipeline_wdata_m1[p].w_flow.w_valid &= exc_m1_q[p].need_commit;
          end
          `_FUSEL_M1_ALU : begin
            pipeline_wdata_m1[p].w_data = alu_result;
            pipeline_wdata_m1[p].w_flow.w_valid = exc_m1_q[p].need_commit && &pipeline_data_m1_q[p].r_flow.r_ready;
          end
          `_FUSEL_M1_MEM : begin
            pipeline_wdata_m1[p].w_data = lsu_result;
            pipeline_wdata_m1[p].w_flow.w_valid = exc_m1_q[p].need_commit && lsu_valid;
          end
        endcase
      end
      assign lsu_valid = m1_mem_rvalid[p];

      // REFETCHER
      logic[31:0] jump_target;
      if(p == 0) begin
        assign m1_refetch  = decode_info.refetch && exc_m1_q[p].need_commit;
        assign jump_target = decode_info.refetch ? (pipeline_ctrl_m1_q[p].pc + 4) :
          pipeline_ctrl_m1_q[p].jump_target;
        assign m1_ertn_excp[p] = exc_m1_q[p].need_commit && m1_excpertn_detect[p];
        assign m1_invalidate_req[p]          = m1_branch_jmp_req || m1_refetch || m1_excpertn_detect[p];
        assign m1_invalidate_exclude_self[p] = ((m1_branch_jmp_req || m1_refetch) && !m1_excpertn_detect[p])
          || (decode_info.ertn_inst && !(|m1_excp_flow))
            // || m1_excp_flow.brk || m1_excp_flow.sys
            // || m1_excp_flow.ine || m1_excp_flow.adef
            ;
        /* TODO: JUDGE WHETHER IS ONLY NEEDED IN CHIPLAB ? */
      end else begin
        assign jump_target     = pipeline_ctrl_m1_q[p].jump_target;
        assign m1_ertn_excp[p] = exc_m1_q[p].need_commit &&
          (m1_excpertn_detect[p]);
        assign m1_invalidate_req[p]          = m1_branch_jmp_req || m1_excpertn_detect[p];
        assign m1_invalidate_exclude_self[p] = m1_branch_jmp_req && !m1_excpertn_detect[p];
      end
      assign m1_target[p] = m1_excpertn_detect[p] ? excp_target : true_bpu_target;

      // 接入转发源
      always_comb begin
        fwd_data_m1[p] = mkfwddata(pipeline_wdata_m1[p]);
      end

      // m1_excp_flow 产生逻辑
      always_comb begin
        // 按照产生优先级排序
        m1_excp_flow       = '0;
        if(p == 0) begin
          m1_excp_flow.m1int = csr_m1_int && exc_m1_q[p].need_commit; // TODO: FIXME
        end else begin
          m1_excp_flow.m1int = '0; // TODO: FIXME
        end
        // NOT MASKABLE INTERRUPT
        m1_excp_flow.ipe = pipeline_ctrl_m1_q[p].excp_flow.ipe &&
         !csr_m1_int && exc_m1_q[p].need_commit && (p == 0 ? 1'b1 : !m1_invalidate_req[0]); // TODO: FIXME
        m1_excp_flow.adef = pipeline_ctrl_m1_q[p].excp_flow.adef &&
         !csr_m1_int && exc_m1_q[p].need_commit && (p == 0 ? 1'b1 : !m1_invalidate_req[0]);
        m1_excp_flow.itlbr = pipeline_ctrl_m1_q[p].excp_flow.itlbr &&
         !csr_m1_int && exc_m1_q[p].need_commit && (p == 0 ? 1'b1 : !m1_invalidate_req[0]);
        m1_excp_flow.pif = pipeline_ctrl_m1_q[p].excp_flow.pif &&
         !csr_m1_int && exc_m1_q[p].need_commit && (p == 0 ? 1'b1 : !m1_invalidate_req[0]);
        m1_excp_flow.ippi = pipeline_ctrl_m1_q[p].excp_flow.ippi &&
         !csr_m1_int && exc_m1_q[p].need_commit && (p == 0 ? 1'b1 : !m1_invalidate_req[0]);
        m1_excp_flow.ine = pipeline_ctrl_m1_q[p].excp_flow.ine &&
         !csr_m1_int && exc_m1_q[p].need_commit && (p == 0 ? 1'b1 : !m1_invalidate_req[0]);

        m1_excp_flow.ale = (!(|m1_excp_flow) && exc_m1_q[p].need_commit && (p == 0 ? 1'b1 : !m1_invalidate_req[0])) && (
          (decode_info.mem_type[1:0] == 2'd1 /*WORD*/&& (|pipeline_ctrl_m1_q[p].vaddr[1:0])) ||
          (decode_info.mem_type[1:0] == 2'd2 /*HALF WORD*/&& pipeline_ctrl_m1_q[p].vaddr[0]));
        // SUPPORT LLSC
        m1_excp_flow.adem = m1_addr_trans_result[p].dmw ? '0 : (
          (!(|m1_excp_flow) && exc_m1_q[p].need_commit && (p == 0 ? 1'b1 : !m1_invalidate_req[0])) &&
          (csr_value.crmd[`PLV] == 2'd3 && m1_mem_vaddr[p][31] && decode_info.need_lsu && !decode_info.mem_cacop)
        );
        m1_excp_flow.tlbr = (
          (!(|m1_excp_flow) && exc_m1_q[p].need_commit && (p == 0 ? 1'b1 : !m1_invalidate_req[0])) &&
          (!m1_addr_trans_result[p].found && decode_info.need_lsu &&
            (!ENABLE_TLB || p != 0 || !decode_info.llsc_inst || !decode_info.mem_write || csr_value.llbit)
            && (!ENABLE_TLB || p != 0 || !(decode_info.mem_cacop && (pipeline_ctrl_m1_q[p].op_code[4:1] == 0)))
          )
        ); // TODO: CHECK
        m1_excp_flow.pis = (
          (!(|m1_excp_flow) && exc_m1_q[p].need_commit && (p == 0 ? 1'b1 : !m1_invalidate_req[0])) &&
          (!m1_addr_trans_result[p].value.v && decode_info.mem_write) &&
          (!ENABLE_TLB || p != 0 || !decode_info.llsc_inst || !decode_info.mem_write || csr_value.llbit)
        ); // TODO: CHECK
        m1_excp_flow.pil = (
          (!(|m1_excp_flow) && exc_m1_q[p].need_commit && (p == 0 ? 1'b1 : !m1_invalidate_req[0])) &&
          (!m1_addr_trans_result[p].value.v && decode_info.need_lsu && !decode_info.mem_write
            && (!ENABLE_TLB || p == 1 || !(decode_info.mem_cacop && (pipeline_ctrl_m1_q[p].op_code[4:1] == 0)))
          )
        ); // TODO: CHECK
        m1_excp_flow.ppi = (
          (!(|m1_excp_flow) && exc_m1_q[p].need_commit && (p == 0 ? 1'b1 : !m1_invalidate_req[0])) &&
          (m1_addr_trans_result[p].value.plv == 2'b00 && csr_value.crmd[`PLV] == 2'd3
            && decode_info.need_lsu &&
            (!ENABLE_TLB || p != 0 || !decode_info.llsc_inst || !decode_info.mem_write || csr_value.llbit)
            && (!ENABLE_TLB || p == 1 || !(decode_info.mem_cacop && (pipeline_ctrl_m1_q[p].op_code[4:1] == 0)))
          ) // MAY LEAD TO SOME SECURITY BUG.
        ); // TODO: CHECK
        m1_excp_flow.pme = (
          (!(|m1_excp_flow) && exc_m1_q[p].need_commit && (p == 0 ? 1'b1 : !m1_invalidate_req[0])) &&
          (!m1_addr_trans_result[p].value.d && decode_info.mem_write) &&
          (!ENABLE_TLB || p != 0 || !decode_info.llsc_inst || !decode_info.mem_write || csr_value.llbit)
        ); // TODO: CHECK
        m1_excp_flow.brk = pipeline_ctrl_m1_q[p].excp_flow.brk && exc_m1_q[p].need_commit && (p == 0 ? 1'b1 : !m1_invalidate_req[0]);
        m1_excp_flow.sys = pipeline_ctrl_m1_q[p].excp_flow.sys && exc_m1_q[p].need_commit && (p == 0 ? 1'b1 : !m1_invalidate_req[0]);
      end

      // 接入暂停请求
      always_comb begin
        m1_stall_req[p] = ((decode_info.latest_r0_m1 & ~pipeline_data_m1_q[p].r_flow.r_ready[0]) |
          (decode_info.latest_r1_m1 & ~pipeline_data_m1_q[p].r_flow.r_ready[1]) ) &
        exc_m1_q[p].need_commit; // LUT6 - 1
      end

      // 流水线间信息传递
      always_comb begin
        pipeline_ctrl_m2[p].decode_info = get_m2_from_m1(decode_info);
        pipeline_ctrl_m2[p].excp_flow = m1_excp_flow;
        pipeline_ctrl_m2[p].excp_valid = m1_excpertn_detect[p];
        pipeline_ctrl_m2[p].mem_uncached = m1_mem_uncached[p];
        pipeline_ctrl_m2[p].op_code = pipeline_ctrl_m1_q[p].op_code;
        pipeline_ctrl_m2[p].csr_id = pipeline_ctrl_m1_q[p].csr_id;
        pipeline_ctrl_m2[p].vaddr = pipeline_ctrl_m1_q[p].vaddr;
        pipeline_ctrl_m2[p].paddr = paddr;
        pipeline_ctrl_m2[p].pc = pipeline_ctrl_m1_q[p].pc;
      end
    end

    // CSR 相关指令接入，注意： 只会在第一条管线
    assign csr_r_addr = pipeline_ctrl_m1_q[0].csr_id;
    assign csr_rdcnt  = pipeline_ctrl_m1_q[0].decode_info.csr_rdcnt |
      (((|pipeline_ctrl_m1_q[0].decode_info.csr_rdcnt) && (pipeline_ctrl_m1_q[0].op_code != 0)) ? 2'b10 : 2'b00);

    /* ------ ------ ------ ------ ------ M2 级 ------ ------ ------ ------ ------ */
    for(genvar p = 0 ; p < 2 ; p++) begin : M2
      m2_t decode_info;
      assign decode_info = pipeline_ctrl_m2_q[p].decode_info;
      // M2 的 FU 部分，接入 ALU、LSU、MUL、CSR
      logic[31:0] alu_result, lsu_result;
      assign lsu_result = m2_mem_rdata[p];
      excp_flow_t excp_flow;
      assign excp_flow = pipeline_ctrl_m2_q[p].excp_flow;
      // MUL 结果复用 ALU 传回
    core_detachable_alu #(
      .USE_LI (0),
      .USE_INT(0),
      .USE_MUL(1),
      .USE_SFT(1),
      .USE_CMP(0)
    ) m2_alu (
      .clk       (clk                            ),
      .rst_n     (rst_n                          ),
      .grand_op_i(decode_info.alu_grand_op       ),
      .op_i      (decode_info.alu_op             ),
      
      .mul_i     (mul_result[p]                  ),
      // .div_i     (div_result                     ),
      .r0_i      (pipeline_data_m2_q[p].r_data[0]),
      .r1_i      (pipeline_data_m2_q[p].r_data[1]),
      .pc_i      (pipeline_ctrl_m2_q[p].pc       ),
      
      .res_o     (alu_result                     )
    );

      // M2 的额外部分
      // CSR 修改相关指令的执行，如写 CSR、写 TLB、缓存控制均在此处执行。
      if( p == 0) begin
        always_comb begin
          {
            tlb_op.invtlb,
            tlb_op.tlbfill,
            tlb_op.tlbwr,
            tlb_op.tlbrd,
            tlb_op.tlbsrch
          } = {
            decode_info.invtlb_en && exc_m2_q[p].need_commit,
            decode_info.tlbfill_en && exc_m2_q[p].need_commit,
            decode_info.tlbwr_en && exc_m2_q[p].need_commit,
            decode_info.tlbrd_en && exc_m2_q[p].need_commit,
            decode_info.tlbsrch_en && exc_m2_q[p].need_commit};
        end
      end
      // 写数据输入
      // div.wu -> st.w ，在 st.w miss ， 且 div.wu 的输入较大的时候可能写入内存错误的数据。
      always_comb begin
        m2_mem_op[p]       = '0;
        m2_mem_valid[p]    = '0;
        m2_mem_uncached[p] = pipeline_ctrl_m2_q[p].mem_uncached; // TODO: FIXME
        if(decode_info.mem_read) begin
          m2_mem_valid[p] = exc_m2_q[p].need_commit;
          m2_mem_op[p]    = `_DCAHE_OP_READ ;
        end
        if(decode_info.mem_write) begin
          m2_mem_valid[p] = exc_m2_q[p].need_commit && pipeline_data_m2_q[p].r_flow.r_ready[0];
          m2_mem_op[p]    = `_DCAHE_OP_WRITE;
        end
        // TODO: CHECK CACOP
        if(p == 0 && ENABLE_TLB && decode_info.mem_cacop) begin
          m2_mem_valid[p] = /**/(ctlb_opcode[2:0] == 3'd1) && exc_m2_q[p].need_commit;
          case(ctlb_opcode[4:3])
            default/*2'd0*/: begin
              m2_mem_op[p] = `_DCAHE_OP_DIRECT_INVWB;
            end
            2'd1 : begin
              m2_mem_op[p] = `_DCAHE_OP_DIRECT_INVWB;
            end
            2'd2 : begin
              m2_mem_op[p] = `_DCAHE_OP_HIT_INV;
            end
          endcase
        end
        // TODO: CHECK LLSC
        if(p == 0) begin
          if(ENABLE_TLB && decode_info.llsc_inst) begin
            if( decode_info.mem_write) begin
              if(csr_value.llbit == 1'b0) begin
                m2_mem_valid[0] = '0;
              end
            end
          end
        end
      end
      if(p == 0) begin
        // assign frontend_resp_o.icache_op_valid = '0;
        always_comb begin
          llbit_set   = '0;
          llbit_value = '0;
          if(ENABLE_TLB && decode_info.llsc_inst && exc_m2_q[0].need_commit && !m2_stall) begin
            if(decode_info.mem_write) begin
              // SC
              llbit_set   = '1;
              llbit_value = '0;
            end else begin
              // LL
              llbit_set   = '1;
              llbit_value = '1;
            end
          end
        end
        always_comb begin
          frontend_resp_o.icache_op_valid = decode_info.mem_cacop && ctlb_opcode[2:0] == 3'd0 && exc_m2_q[0].need_commit;
          frontend_resp_o.icache_op       = ctlb_opcode[4:3];
          frontend_resp_o.icacheop_addr   = m2_mem_paddr[p];
        end
      end
      assign m2_mem_size[p]   = mkmemsize(decode_info.mem_type);
      assign m2_mem_vaddr[p]  = pipeline_ctrl_m2_q[p].vaddr;
      assign m2_mem_paddr[p]  = pipeline_ctrl_m2_q[p].paddr;
      assign m2_mem_strobe[p] = mkwstrobe(decode_info.mem_type, pipeline_ctrl_m2_q[p].vaddr);
      assign m2_mem_type[p]   = decode_info.mem_type;
      assign m2_mem_wdata[p]  = pipeline_data_m2_q[p].r_data[0];
      // M2 的数据选择
      if(p == 0) begin
        always_comb begin
          pipeline_wdata_m2[p] = pipeline_wdata_m1_q[p]; // TODO: FIXME
          case(decode_info.fu_sel_m2)
            default : begin
              pipeline_wdata_m2[p].w_flow.w_valid &= exc_m2_q[p].need_commit;
            end
            `_FUSEL_M2_ALU : begin
              pipeline_wdata_m2[p].w_data = alu_result;
              pipeline_wdata_m2[p].w_flow.w_valid = exc_m2_q[p].need_commit && (&pipeline_data_m2_q[p].r_flow.r_ready);
            end
            `_FUSEL_M2_MEM : begin
              pipeline_wdata_m2[p].w_data = (decode_info.mem_write && ENABLE_TLB) ?
                {31'd0, csr_value.llbit} : lsu_result;
              pipeline_wdata_m2[p].w_flow.w_valid = exc_m2_q[p].need_commit &&
                (m2_mem_rvalid[p] || (decode_info.mem_write && ENABLE_TLB));
            end
            `_FUSEL_M2_CSR : begin
              pipeline_wdata_m2[p].w_data = csr_r_data;
              pipeline_wdata_m2[p].w_flow.w_valid = exc_m2_q[p].need_commit;
            end
          endcase
        end
      end
      else begin
        always_comb begin
          pipeline_wdata_m2[p] = pipeline_wdata_m1_q[p]; // TODO: FIXME
          case(decode_info.fu_sel_m2)
            default : begin
              pipeline_wdata_m2[p].w_flow.w_valid &= exc_m2_q[p].need_commit;
            end
            `_FUSEL_M2_ALU : begin
              pipeline_wdata_m2[p].w_data = alu_result;
              pipeline_wdata_m2[p].w_flow.w_valid = exc_m2_q[p].need_commit && (&pipeline_data_m2_q[p].r_flow.r_ready);
            end
            `_FUSEL_M2_MEM : begin
              pipeline_wdata_m2[p].w_data = lsu_result;
              pipeline_wdata_m2[p].w_flow.w_valid = exc_m2_q[p].need_commit && m2_mem_rvalid[p];
            end
          endcase
        end
      end
      // 接入转发源
      always_comb begin
        fwd_data_m2[p] = mkfwddata(pipeline_wdata_m2[p]);
      end

      // 接入暂停请求
      always_comb begin
        m2_stall_req[p] = ((decode_info.latest_r0_m2 & ~pipeline_data_m2_q[p].r_flow.r_ready[0]) |
          (decode_info.latest_r1_m2 & ~pipeline_data_m2_q[p].r_flow.r_ready[1])) &
        exc_m2_q[p].need_commit; // LUT6 + MUXF7
      end

      // 接入异常写回
      assign m2_excp_req[p]   = excp_flow;
      assign m2_badv_req[p]   = pipeline_ctrl_m2_q[p].vaddr;
      assign m2_csr_pc_req[p] = pipeline_ctrl_m2_q[p].pc;
      assign csr_excp_req[p]  = pipeline_ctrl_m2_q[p].excp_valid;

      // 流水线间信息传递
      always_comb begin
        pipeline_ctrl_wb[p].decode_info = get_wb_from_m2(decode_info);
        // pipeline_ctrl_wb[p].vaddr = pipeline_ctrl_m2[p].vaddr;
        // pipeline_ctrl_wb[p].paddr = pipeline_ctrl_m2[p].paddr;
        pipeline_ctrl_wb[p].pc = pipeline_ctrl_m2_q[p].pc;
      end

      // WAIT 指令接入
      if(p == 0) begin
        assign frontend_resp_o.wait_inst  = decode_info.wait_inst && exc_m2_q[p].need_commit;
        assign frontend_resp_o.int_detect = csr_m1_int;
      end
    end
    // CSR 控制接线，一定在流水线级1
    assign ctlb_opcode = pipeline_ctrl_m2_q[0].op_code;
    assign csr_w_addr  = pipeline_ctrl_m2_q[0].csr_id;
    assign csr_w_data  = pipeline_data_m2_q[0].r_data[0];
    assign csr_w_mask  = pipeline_data_m2_q[0].r_flow.r_addr[1] == 5'd1 ?
      32'hffffffff :
      pipeline_data_m2_q[0].r_data[1];
    assign csr_we   = pipeline_ctrl_m2_q[0].decode_info.csr_op_en && exc_m2_q[0].need_commit && !m2_stall;
    assign csr_ertn = pipeline_ctrl_m2_q[0].decode_info.ertn_inst && exc_m2_q[0].need_commit && !m2_stall;
    /* ------ ------ ------ ------ ------ WB 级 ------ ------ ------ ------ ------ */
    // 不存在数据前递

    for(genvar p = 0 ; p < 2 ; p++) begin : WB
      // WB 的 FU 部分，接入 DIV，等待 DIV 完成。
      wb_t decode_info;
      assign decode_info = pipeline_ctrl_wb_q[p].decode_info;

      // WB 需要接回 IS 级的 寄存器堆和 scoreboard

      // 生成写数据
      always_comb begin
        pipeline_wdata_wb[p] = pipeline_wdata_m2_q[p];
        if(decode_info.fu_sel_wb == `_FUSEL_WB_DIV) begin
          pipeline_wdata_wb[p].w_data = div_result;
          pipeline_wdata_wb[p].w_flow.w_valid = exc_wb_q[p].need_commit && div_result_valid;
        end else begin
          pipeline_wdata_wb[p].w_flow.w_valid &= exc_wb_q[p].need_commit;
        end
      end

      // 接入转发源
      always_comb begin
        fwd_data_wb[p] = mkfwddata(pipeline_wdata_wb[p]);
      end

      // 接入暂停请求
      always_comb begin
        wb_stall_req[p] = exc_wb_q[p].need_commit
          & decode_info.need_div & !div_result_valid; // 4 - 1
      end

      // 接入 scoreboard、寄存器堆
      always_comb begin
        wb_w_data[p] = pipeline_wdata_wb[p].w_data;
        wb_w_addr[p] = pipeline_wdata_wb[p].w_flow.w_addr;
        wb_commit[p] = exc_wb_q[p].need_commit && !wb_stall;
        wb_valid[p]  = exc_wb_q[p].valid_inst && !wb_stall;
      end
    end
    assign wb_w_id = pipeline_wdata_wb[0].w_flow.w_id;


`ifdef _DIFFTEST_ENABLE
    // 接入差分测试
    logic[63:0] m2_timer_64,wb_timer_64,cb_timer_64;
    csr_t csr_value_q,skid_csr_value_q;
    logic csr_skid   ;
    always_ff @(posedge clk) begin
      if(!csr_skid) begin
        skid_csr_value_q <= csr_value;
      end
      if(!m2_stall) begin
        m2_timer_64 <= core_csr_inst.timer_64_q;
      end
      if(!wb_stall) begin
        wb_timer_64 <= m2_timer_64;
      end
      cb_timer_64 <= wb_timer_64;
      csr_skid    <= wb_stall;
      csr_value_q <= csr_skid ? skid_csr_value_q : csr_value;
    end
    logic [4:0] m2_rand_index, wb_rand_index;
    logic [4:0] debug_rand_index; // TODO: CONNECT ME
    assign m2_rand_index = core_csr_inst.tlbfill_rnd_idx_q;
    always_ff @(posedge clk) begin
      if(!wb_stall) begin
        wb_rand_index <= m2_rand_index;
      end
      debug_rand_index <= wb_rand_index;
    end
    // WB 的信号，全部打一拍，以等待写操作完成。
    // 注意，csr_value 跟着打一拍
    for(genvar p = 0 ; p < 2 ; p++) begin : DIFFTEST
      is_t  cm_inst_info;
      logic wb_wen,cm_wen;
      logic[4:0] wb_waddr,cm_waddr;
      logic wb_valid,cm_valid;
      logic wb_excp,cm_excp;
      logic wb_ertn,cm_ertn;
      logic m2_llbit,wb_llbit,cm_llbit;
      logic[31:0] wb_pc,cm_pc;
      logic[31:0] wb_instr,cm_instr;
      logic[31:0] wb_wdata,cm_wdata;
      logic[31:0] m2_mdata,wb_mdata,cm_mdata;
      logic[31:0] m2_vaddr,wb_vaddr,cm_vaddr;
      logic[31:0] m2_paddr,wb_paddr,cm_paddr;
      assign m2_mdata = lsu_pm_block[p].lsu_inst.rstate_o.wdata;
      assign m2_vaddr = pipeline_ctrl_m2_q[p].vaddr;
      assign m2_paddr = pipeline_ctrl_m2_q[p].paddr;
      assign m2_llbit = csr_value.llbit;

      assign wb_wen   = pipeline_wdata_wb[p].w_flow.w_valid && exc_wb_q[p].need_commit;
      assign wb_waddr = pipeline_wdata_wb[p].w_flow.w_addr;
      assign wb_valid = exc_wb_q[p].need_commit && !wb_stall;
      assign wb_pc    = pipeline_ctrl_wb_q[p].pc;
      assign wb_instr = pipeline_ctrl_wb_q[p].decode_info.debug_inst;
      assign wb_wdata = pipeline_wdata_wb[p].w_data;
      always_ff @(posedge clk) begin
        if(!wb_stall) begin
          wb_mdata <= m2_mdata;
          wb_vaddr <= m2_vaddr;
          wb_paddr <= m2_paddr;
          wb_excp  <= |m2_excp_req[p] && exc_m2_q[p].valid_inst && !m2_stall;
          wb_ertn  <= p == 0 ? csr_ertn : '0;
          wb_llbit <= m2_llbit;
        end
      end
      always_ff @(posedge clk) begin
        cm_pc    <= wb_pc;
        cm_instr <= wb_instr;
        cm_wdata <= wb_wdata;
        cm_valid <= wb_stall ? '0 : wb_valid;
        cm_waddr <= wb_waddr;
        cm_wen   <= wb_stall ? '0 : wb_wen;
        cm_mdata <= wb_mdata;
        cm_vaddr <= wb_vaddr;
        cm_paddr <= wb_paddr;
        cm_ertn  <= wb_stall ? '0 : wb_ertn;
        cm_excp  <= wb_stall ? '0 : wb_excp;
        cm_llbit <= wb_stall ? '0 : wb_llbit;
      end
      decoder  decoder_inst_p (
        .inst_i(cm_instr),
        .fetch_err_i('0),
        .is_o(cm_inst_info)
      );
      DifftestInstrCommit DifftestInstrCommit_p (
        .clock         (clk             ),
        .coreid        ('0              ),
        .index         (p               ),
        .valid         (cm_valid        ),
        .pc            (cm_pc           ),
        .instr         (cm_instr        ),
        .skip          ('0              ),
        .is_TLBFILL    (cm_inst_info.tlbfill_en && cm_valid), // TODO: CHECK
        .TLBFILL_index (debug_rand_index),
        .is_CNTinst    (cm_inst_info.csr_rdcnt != '0),
        .timer_64_value(cb_timer_64     ),
        .wen           (cm_waddr == '0 ? '0 : cm_wen          ),
        .wdest         (cm_waddr        ),
        .wdata         (cm_waddr == '0 ? '0 : cm_wdata),
        .csr_rstat     (p == 0          ),
        .csr_data      (csr_value_q.estat)
      );

      // if(p == 0) begin
      DifftestStoreEvent DifftestStoreEvent_p (
        .clock     (clk),
        .coreid    (0  ),
        .index     (p  ),
        .valid     (cm_valid && cm_inst_info.mem_write &&
          (!cm_inst_info.llsc_inst || cm_llbit)),
        .storePAddr(cm_paddr),
        .storeVAddr(cm_vaddr),
        .storeData (cm_mdata)
      );
      DifftestLoadEvent DifftestLoadEvent_p (
        .clock (clk),
        .coreid(0),
        .index (p),
        .valid (cm_valid && cm_inst_info.mem_read),
        .paddr (cm_paddr),
        .vaddr (cm_vaddr)
      );
      // end
    end
  DifftestExcpEvent DifftestExcpEvent (
    .clock     (clk                                       ),
    .coreid    (0                                         ),
    .excp_valid(DIFFTEST[0].cm_excp || DIFFTEST[1].cm_excp),
    // .excp_valid         ('0),
    .eret      (DIFFTEST[0].cm_ertn || DIFFTEST[1].cm_ertn),
    // .eret               ('0),
    .intrNo    (csr_value_q.estat[12:2]                   ),
    .cause     (csr_value_q.estat[21:16]                  ),
    .exceptionPC((DIFFTEST[0].cm_ertn || DIFFTEST[0].cm_excp) ?
                DIFFTEST[0].cm_pc : DIFFTEST[1].cm_pc     ), 
    .exceptionInst((DIFFTEST[0].cm_ertn || DIFFTEST[0].cm_excp) ?
                DIFFTEST[0].cm_instr : DIFFTEST[1].cm_instr)  
  );

  DifftestTrapEvent DifftestTrapEvent (
    .clock   (clk       ),
    .coreid  (0         ),
    .valid   ('0/*TODO*/),
    .code    ('0/*TODO*/),
    .pc      ('0/*TODO*/),
    .cycleCnt('0/*TODO*/),
    .instrCnt('0/*TODO*/)
  );

  DifftestCSRRegState DifftestCSRRegState_inst (
    .clock    (clk                                        ),
    .coreid   (0                                          ),
    .crmd     (csr_value_q.crmd                           ),
    .prmd     (csr_value_q.prmd                           ),
    .euen     (csr_value_q.euen                           ),
    .ecfg     (csr_value_q.ectl                           ),
    .estat    (csr_value_q.estat                          ),
    .era      (csr_value_q.era                            ),
    .badv     (csr_value_q.badv                           ),
    .eentry   (csr_value_q.eentry                         ),
    .tlbidx   (csr_value_q.tlbidx                         ),
    .tlbehi   (csr_value_q.tlbehi                         ),
    .tlbelo0  (csr_value_q.tlbelo0                        ),
    .tlbelo1  (csr_value_q.tlbelo1                        ),
    .asid     (csr_value_q.asid                           ),
    .pgdl     (csr_value_q.pgdl                           ),
    .pgdh     (csr_value_q.pgdh                           ),
    .save0    (csr_value_q.save0                          ),
    .save1    (csr_value_q.save1                          ),
    .save2    (csr_value_q.save2                          ),
    .save3    (csr_value_q.save3                          ),
    .tid      (csr_value_q.tid                            ),
    .tcfg     (csr_value_q.tcfg                           ),
    .tval     (csr_value_q.tval                           ),
    .ticlr    (csr_value_q.ticlr                          ),
    .tlbrentry(csr_value_q.tlbrentry                      ),
    .dmw0     (csr_value_q.dmw0                           ),
    .dmw1     (csr_value_q.dmw1                           ),
    .llbctl   ({csr_value_q.llbctl,1'b0,csr_value_q.llbit})
  );

    `endif


  endmodule

