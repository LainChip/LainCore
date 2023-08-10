`include "pipeline.svh"
`include "lsu.svh"
// 这个function应该放在前端，在fetch阶段和写入fifo阶段之间，合成inst_t的阶段进行。
function reg_info_t get_register_info(
    input is_t decode_info,
    input logic[31:0] inst
  );
  reg_info_t ret;

  logic [1:0] r0_sel, w_sel;
  logic r1_sel;
  r0_sel = decode_info.reg_type_r0;
  r1_sel = decode_info.reg_type_r1;
  w_sel  = decode_info.reg_type_w;
  case(r0_sel)
    default : begin
      ret.r_reg[0] = '0;
    end
    `_REG_R0_RK : begin
      ret.r_reg[0] = inst[14:10];
    end
    `_REG_R0_RD : begin
      ret.r_reg[0] = inst[4:0];
    end
  endcase
  case(r1_sel)
    default : begin
      ret.r_reg[1] = '0;
    end
    `_REG_R1_RJ : begin
      ret.r_reg[1] = inst[9:5];
    end
  endcase
  case(w_sel)
    default : begin
      ret.w_reg = '0;
    end
    `_REG_W_RD : begin
      ret.w_reg = inst[4:0];
    end
    `_REG_W_RJD : begin
      ret.w_reg = inst[4:0] | inst[9:5];
    end
    `_REG_W_BL1 : begin
      ret.w_reg = 5'd1;
    end
  endcase
  return ret;
endfunction

module core_frontend #(parameter bit ENABLE_TLB = 1'b1) (
  input  logic            clk            ,
  input  logic            rst_n          ,
  output frontend_req_t   frontend_req_o ,
  input  frontend_resp_t  frontend_resp_i,
  input  cache_bus_resp_t bus_resp_i     ,
  output cache_bus_req_t  bus_req_o
);

  logic f1_stall, f2_stall;
  logic addr_trans_stall, idle_stall, icache_stall, mimo_stall;
  logic addr_trans_ready; // F1 级别的模块
  assign addr_trans_stall = !addr_trans_ready;
  logic mimo_ready; // F2 级别的模块
  assign mimo_stall = !mimo_ready;
  assign f1_stall   = f2_stall | addr_trans_stall | idle_stall;
  assign f2_stall   = icache_stall | mimo_stall;

  // NPC 模块
  logic[31:0] pc_vaddr, npc_vaddr;
  logic[31:0] f1_pc;
  logic[1:0] f1_valid;
  bpu_predict_t [1:0] f_predict;
  assign f1_pc = pc_vaddr;
  core_npc npc_inst (
    .clk       (clk                           ),
    .rst_n     (rst_n                         ),
    .rst_jmp   (frontend_resp_i.rst_jmp       ),
    .rst_target(frontend_resp_i.rst_jmp_target),
    .f_stall_i (f1_stall                      ),
    .pc_o      (pc_vaddr                      ),
    .npc_o     (npc_vaddr                     ),
    .valid_o   (f1_valid                      ),
    .predict_o (f_predict                     ),
    .correct_i (frontend_resp_i.bpu_correct   )
  );

  // ICACHE 指令
  logic icacheop_valid;
  logic[1:0] icacheop;
  logic[31:0] icacheop_addr;
  logic icacheop_ready;
  always_ff @(posedge clk) begin
    if(~rst_n) begin
      icacheop_valid <= '0;
    end
    else if(frontend_resp_i.icache_op_valid) begin
      icacheop_valid <= '1;
      icacheop       <= frontend_resp_i.icache_op;
      icacheop_addr  <= frontend_resp_i.icacheop_addr;
    end
    else if(icacheop_ready) begin
      icacheop_valid <= '0;
    end
  end

  assign frontend_req_o.icache_ready = icacheop_ready;
  assign icacheop_ready              = !f2_stall;
  // ICACHE 模块
  logic[31:0] f2_pc;
  logic[1:0] f2_valid;
  bpu_predict_t[1:0] f2_predict;
  logic[1:0][31:0] f2_inst;

  tlb_s_resp_t f1_trans_result;
  fetch_excp_t f1_excp, f2_excp;
  logic[31:0] f1_ppc;
  logic f1_uncached;
  assign f1_ppc      = {f1_trans_result.value.ppn, f1_pc[11:0]};
  assign f1_uncached = f1_trans_result.value.mat != 2'b01;
  always_comb begin
    f1_excp      = '0;
    f1_excp.adef = (|f1_ppc[1:0]) || (f1_trans_result.dmw ? '0 :
      ((frontend_resp_i.csr_reg.crmd[`PLV] == 2'd3) && f1_pc[31]));
    f1_excp.tlbr = (!f1_excp) && !f1_trans_result.found;
    f1_excp.pif  = (!f1_excp) && !f1_trans_result.value.v;
    f1_excp.ppi  = (!f1_excp) && (f1_trans_result.value.plv == 2'd0 && frontend_resp_i.csr_reg.crmd[`PLV] == 2'd3);
  end
  core_addr_trans #(
    .ENABLE_TLB(ENABLE_TLB), // TODO: PARAMETERIZE ME
    .FETCH_ADDR('1        )
  ) core_iaddr_trans_inst (
    .clk             (clk                                 ),
    .rst_n           (rst_n                               ),
    .valid_i         (|f1_valid                           ),
    .vaddr_i         (npc_vaddr                           ),
    .m1_stall_i      (f1_stall && !frontend_resp_i.rst_jmp),
    .ready_o         (addr_trans_ready                    ),
    .csr_i           (frontend_resp_i.csr_reg             ),
    .tlb_update_req_i(frontend_resp_i.tlb_update_req      ),
    .trans_result_o  (f1_trans_result                     )
  );
  logic[31:0] ppc_nc;

  core_ifetch #(
    .ATTACHED_INFO_WIDTH(2*$bits(bpu_predict_t)+$bits(fetch_excp_t)),
    .ENABLE_TLB         (ENABLE_TLB                                ),
    .EARLY_BRAM         ('0                                        )
  ) core_ifetch_inst (
    .clk            (clk                     ),
    .rst_n          (rst_n                   ),
    .cacheop_i      (icacheop                ),
    .cacheop_valid_i(icacheop_valid          ),
    .cacheop_paddr_i(icacheop_addr           ), // 注意：这个是物理地址
    .valid_i        (f1_valid                ),
    .npc_i          (npc_vaddr               ),
    .vpc_i          (f1_pc                   ),
    .ppc_i          (f1_ppc                  ),
    .uncached_i     (f1_uncached             ),
    .attached_i     ({f_predict, f1_excp}    ),
    .f1_stall_i     (f1_stall                ),
    .f2_stall_i     (f2_stall                ),
    .f2_stall_req_o (icache_stall            ),
    .valid_o        (f2_valid                ),
    .attached_o     ({f2_predict, f2_excp}   ),
    .inst_o         (f2_inst                 ),
    .pc_o           (f2_pc                   ),
    .flush_i        (frontend_resp_i.rst_jmp ),
    .bus_busy_i     (frontend_resp_i.bus_busy),
    .bus_req_o      (bus_req_o               ),
    .bus_resp_i     (bus_resp_i              )
  );

  // MIMO fifo
  typedef struct packed {
    logic [31:0]  pc         ;
    logic [31:0]  inst       ;
    fetch_excp_t  fetch_excp ;
    bpu_predict_t bpu_predict;
  } inst_package_t;
  inst_package_t [1:0] f2_inst_pack;
  assign f2_inst_pack[0].pc = {f2_pc[31:3],!f2_valid[0],f2_pc[1:0]};
  assign f2_inst_pack[1].pc = {f2_pc[31:3],1'b1,f2_pc[1:0]};
  assign f2_inst_pack[0].inst = f2_valid[0] ? f2_inst[0] : f2_inst[1];
  assign f2_inst_pack[1].inst = f2_inst[1];
  assign f2_inst_pack[0].fetch_excp = f2_excp;
  assign f2_inst_pack[1].fetch_excp = f2_excp;
  assign f2_inst_pack[0].bpu_predict = f2_valid[0] ? f2_predict[0] : f2_predict[1];
  assign f2_inst_pack[1].bpu_predict = f2_predict[1];
  logic[1:0] f2_num,d_num;
  always_comb begin
    f2_num = f2_valid[0] + f2_valid[1];
  end
  inst_package_t[1:0] d_inst_pack;
  logic[1:0] d_valid_fifo;
  logic[1:0] d_valid;
  assign d_valid = d_valid_fifo & {2{~frontend_resp_i.rst_jmp}};

  multi_channel_fifo #(
    .DATA_WIDTH(64 + $bits(bpu_predict_t) + $bits(fetch_excp_t)),
    .DEPTH     (16                                             ),
    .BANK      (2                                              ),
    .WRITE_PORT(2                                              ),
    .READ_PORT (2                                              )
  ) inst_fifo (
    .clk                                   ,
    .rst_n                                 ,
    
    .flush_i      (frontend_resp_i.rst_jmp),
    
    .write_valid_i(1'b1                   ),
    .write_ready_o(mimo_ready             ),
    .write_num_i  (f2_num                 ),
    .write_data_i (f2_inst_pack           ),
    
    .read_valid_o (d_valid_fifo           ),
    .read_ready_i (1'b1                   ),
    .read_num_i   (d_num                  ),
    .read_data_o  (d_inst_pack            )
  );
  // compress_fifo #(
  //   .DATA_WIDTH(64 + $bits(bpu_predict_t) + $bits(fetch_excp_t)),
  //   .DEPTH     (8                                              ),
  //   .WRITE_PORT(2                                              ),
  //   .READ_PORT (2                                              )
  // ) inst_fifo (
  //   .clk                                   ,
  //   .rst_n                                 ,

  //   .flush_i      (frontend_resp_i.rst_jmp),

  //   .write_valid_i(1'b1                   ),
  //   .write_ready_o(mimo_ready             ),
  //   .write_num_i  (f2_num                  ),
  //   .write_data_i (f2_inst_pack            ),

  //   .read_valid_o (d_valid                ),
  //   .read_ready_i (1'b1                   ),
  //   .read_num_i   (d_num                  ),
  //   .read_data_o  (d_inst_pack            )
  // );
  // DECODER
  inst_t[1:0] decoder_inst_package;
  for(genvar p = 0;  p < 2 ;p ++ ) begin
    is_t issue_package;
    decoder decoder_inst (
      .inst_i     (d_inst_pack[p].inst),
      .fetch_err_i('0                 ),
      .is_o       (issue_package      )
    );
    always_comb begin
      decoder_inst_package[p].decode_info = issue_package;
      decoder_inst_package[p].imm_domain = d_inst_pack[p].inst[25:0];
      decoder_inst_package[p].reg_info = get_register_info(issue_package,d_inst_pack[p].inst);
      decoder_inst_package[p].bpu_predict = d_inst_pack[p].bpu_predict;
      decoder_inst_package[p].fetch_excp = d_inst_pack[p].fetch_excp;
      decoder_inst_package[p].pc = d_inst_pack[p].pc;
    end
  end
  // assign frontend_req_o.inst_valid = d_valid;
  // assign frontend_req_o.inst       = decoder_inst_package;
  // assign d_num                     = frontend_resp_i.issue[0] + frontend_resp_i.issue[1];
  // ISSUE
  (*MAX_FANOUT=70*) inst_t[1:0] is_inst_package_q, is_inst_package;
  (*MAX_FANOUT=70*) logic[1:0] is_valid_q, is_valid;
  always_ff @(posedge clk) begin
    if(frontend_resp_i.rst_jmp || ~rst_n) begin
      is_valid_q <= '0;
    end else begin
      is_valid_q <= is_valid;
    end
    is_inst_package_q <= is_inst_package;
  end
  always_comb begin
    d_num           = '0;
    is_valid        = is_valid_q;
    is_inst_package = is_inst_package_q;
    unique casez({is_valid_q, d_valid, frontend_resp_i.issue})
      // NO VALID INST YET
      6'b00???? : begin
        is_valid        = d_valid;
        d_num           = d_valid[0] + d_valid[1];
        is_inst_package = decoder_inst_package;
      end
      // HAS ONE VALID INST
      6'b01?0?0 : begin
        is_valid = 2'b01;
      end
      6'b01?0?1 : begin
        is_valid = '0;
      end
      6'b01?1?0 : begin
        is_valid           = 2'b11;
        is_inst_package[1] = decoder_inst_package[0];
        d_num              = 1;
      end
      6'b01?1?1 : begin
        is_valid           = 2'b01;
        is_inst_package[0] = decoder_inst_package[0];
        d_num              = 1;
      end
      // HAS TWO VALID INST
      6'b1???00 : begin
        is_valid = 2'b11;
      end
      6'b1?0001 : begin
        is_valid           = 2'b01;
        is_inst_package[0] = is_inst_package_q[1];
      end
      6'b1?001? : begin
        is_valid = 2'b00;
      end
      6'b1?0101 : begin
        is_valid           = 2'b11;
        is_inst_package[0] = is_inst_package_q[1];
        is_inst_package[1] = decoder_inst_package[0];
        d_num              = 1;
      end
      6'b1?011? : begin
        is_valid           = 2'b01;
        is_inst_package[0] = decoder_inst_package[0];
        d_num              = 1;
      end
      6'b1?1?01 : begin
        is_valid           = 2'b11;
        is_inst_package[0] = is_inst_package_q[1];
        is_inst_package[1] = decoder_inst_package[0];
        d_num              = 1;
      end
      6'b1?1?1? : begin
        is_valid           = 2'b11;
        is_inst_package[0] = decoder_inst_package[0];
        is_inst_package[1] = decoder_inst_package[1];
        d_num              = 2;
      end
    endcase
  end
  assign frontend_req_o.inst_valid = is_valid_q;
  assign frontend_req_o.inst       = is_inst_package_q;

  // IDLE-WAIT 逻辑
  // 当出现idle指令的时候，刷新整条流水线到idle + 4的位置，并在前端停住整条流水线，以降低执行功耗。
  always @(posedge clk) begin
    if (~rst_n) begin
      idle_stall <= 1'b0;
    end
    else if (frontend_resp_i.wait_inst && !frontend_resp_i.int_detect) begin
      idle_stall <= 1'b1;
    end
    else if (frontend_resp_i.int_detect) begin
      idle_stall <= 1'b0;
    end
  end

endmodule
