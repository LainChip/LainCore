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

module core_frontend_renew #(parameter bit ENABLE_TLB = 1'b1) (
  input  logic            clk            ,
  input  logic            rst_n          ,
  output frontend_req_t   frontend_req_o ,
  input  frontend_resp_t  frontend_resp_i,
  input  cache_bus_resp_t bus_resp_i     ,
  output cache_bus_req_t  bus_req_o
);

  // NPC 模块
  logic idle_stall;
  logic npc_ready ; // FROM ICACHE -> NPC
  logic[31:0] f1_pc;
  logic[1:0] f1_valid;
  bpu_predict_t [1:0] f1_predict;
  core_npc npc_inst (
    .clk       (clk                           ),
    .rst_n     (rst_n                         ),
    .rst_jmp   (frontend_resp_i.rst_jmp       ),
    .rst_target(frontend_resp_i.rst_jmp_target),
    .f_stall_i (!npc_ready || idle_stall      ),
    .pc_o      (f1_pc                         ),
    .npc_o     (/* NC */                      ),
    .valid_o   (f1_valid                      ),
    .predict_o (f1_predict                    ),
    .correct_i (frontend_resp_i.bpu_correct   )
  );

  // ICACHE 指令
  logic rnd_stall;
  assign rnd_stall = '0;
  // tests_random_stall # (
  //   .PERCETAGE(75)
  // )
  // tests_random_stall_inst (
  //   .clk(clk),
  //   .rst_n(rst_n),
  //   .stall_o(rnd_stall)
  // );
  logic[1:0] f1_icacheop;
  logic[31:0] f1_icacheop_addr;
  logic f1_icacheop_ready, f1_icacheop_valid;
  assign frontend_req_o.icache_ready = f1_icacheop_ready; // 这个信号由 ICACHE 产生
  always_ff @(posedge clk) begin
    if(~rst_n) begin
      f1_icacheop_valid <= '0;
    end
    else if(frontend_resp_i.icache_op_valid) begin
      f1_icacheop_valid <= '1;
    end
    else if(f1_icacheop_ready) begin
      f1_icacheop_valid <= '0;
    end
  end

  always_ff @(posedge clk) begin
    if(frontend_resp_i.icache_op_valid) begin
      f1_icacheop      <= frontend_resp_i.icache_op;
      f1_icacheop_addr <= frontend_resp_i.icacheop_addr;
    end
  end

  // ICACHE 模块
  logic f1_f2_clken;
  logic[1:0] ifetch_valid;
  fetch_excp_t ifetch_excp;
  bpu_predict_t[1:0] ifetch_predict;
  logic[1:0][31:0] ifetch_inst;
  logic[31:0] ifetch_pc;
  logic decode_ready; // 连接到 D 级，解码就绪， D - IS 级中安插一个 PIPE，亦可作为 SKIDBUF 降低延迟

  // I-MMU 模块
  tlb_s_resp_t f2_trans_result;
  fetch_excp_t f2_excp        ;
  logic[31:0] f2_ppc;
  logic[31:0] f2_vpc;
  always_ff @(posedge clk) begin
    if(f1_f2_clken) f2_vpc <= f1_pc;
  end
  logic f2_uncached;
  assign f2_ppc      = {f2_trans_result.value.ppn, f2_vpc[11:0]};
  assign f2_uncached = f2_trans_result.value.mat != 2'b01;
  always_comb begin
    f2_excp      = '0;
    f2_excp.adef = (|f2_vpc[1:0]) || (f2_trans_result.dmw ? '0 :
      ((frontend_resp_i.csr_reg.crmd[`PLV] == 2'd3) && f2_vpc[31]));
    f2_excp.tlbr = (!f2_excp) && !f2_trans_result.found;
    f2_excp.pif  = (!f2_excp) && !f2_trans_result.value.v;
    f2_excp.ppi  = (!f2_excp) && (f2_trans_result.value.plv == 2'd0 && frontend_resp_i.csr_reg.crmd[`PLV] == 2'd3);
  end
  core_addr_trans #(
    .ENABLE_TLB(ENABLE_TLB), // TODO: PARAMETERIZE ME
    .FETCH_ADDR('1        )
  ) core_iaddr_trans_inst (
    .clk             (clk                           ),
    .rst_n           (rst_n                         ),
    .clken_i         (f1_f2_clken                   ),
    .valid_i         ('1                            ),
    .vaddr_i         (f1_pc                         ),
    .ready_o         (/*     NC     */              ),
    .csr_i           (frontend_resp_i.csr_reg       ),
    .tlb_update_req_i(frontend_resp_i.tlb_update_req),
    .trans_result_o  (f2_trans_result               )
  );
  core_fetch #(
    .ATTACHED_INFO_WIDTH   (2*$bits(bpu_predict_t)),
    .F2_ATTACHED_INFO_WIDTH($bits(fetch_excp_t)   )
  ) core_fetch_inst (
    .clk            (clk                                 ),
    .rst_n          (rst_n                               ),
    .flush_i        (frontend_resp_i.rst_jmp             ),
    .bus_busy_i     (frontend_resp_i.bus_busy            ),
    .bus_req_o      (bus_req_o                           ),
    .bus_resp_i     (bus_resp_i                          ),
    
    .npc_ready_o    (npc_ready                           ),
    .valid_i        (f1_valid& {!idle_stall, !idle_stall}),
    .cacheop_ready_o(f1_icacheop_ready                   ),
    .cacheop_valid_i(f1_icacheop_valid                   ),
    .cacheop_i      (f1_icacheop                         ),
    .cacheop_paddr_i(f1_icacheop_addr                    ),
    .vpc_i          (f1_pc                               ),
    .attached_i     (f1_predict                          ),
    
    .f1_f2_clken_o  (f1_f2_clken                         ),
    
    .uncache_i      (f2_uncached                         ),
    .f2_attached_i  (f2_excp                             ),
    .ppc_i          (f2_ppc                              ),
    .f2_attached_o  (ifetch_excp                         ),
    .attached_o     (ifetch_predict                      ),
    .pc_o           (ifetch_pc                           ),
    .valid_o        (ifetch_valid                        ),
    .inst_o         (ifetch_inst                         ),
    .ready_i        (decode_ready && !rnd_stall          )
  );

  // DECODER
  logic         [ 1:0]       decode_valid_q  ;
  logic         [ 1:0][31:0] decode_inst_q   ;
  logic         [31:0]       decode_pc_q     ;
  fetch_excp_t        decode_excp_q   ;
  bpu_predict_t [ 1:0]       decode_predict_q;
  always_ff @(posedge clk) begin
    if(!rst_n || frontend_resp_i.rst_jmp) begin
      decode_valid_q <= '0;
    end else begin
      if(decode_ready) begin
        decode_valid_q <= ifetch_valid;
      end
    end
  end
  always_ff @(posedge clk) begin
    if(decode_ready) begin
      decode_excp_q    <= ifetch_excp;
      decode_predict_q <= ifetch_predict;
      decode_pc_q      <= ifetch_pc;
      decode_inst_q    <= ifetch_inst;
    end
  end
  inst_t[1:0] decoder_inst_package;
  for(genvar p = 0;  p < 2 ;p ++ ) begin
    is_t issue_package;
    decoder decoder_inst (
      .inst_i     (decode_inst_q[p]),
      .fetch_err_i('0              ),
      .is_o       (issue_package   )
    );
    always_comb begin
      decoder_inst_package[p].decode_info = issue_package;
      decoder_inst_package[p].imm_domain = decode_inst_q[p][25:0];
      decoder_inst_package[p].reg_info = get_register_info(issue_package,decode_inst_q[p]);
      decoder_inst_package[p].bpu_predict = decode_predict_q[p];
      decoder_inst_package[p].fetch_excp = decode_excp_q;
      decoder_inst_package[p].pc = {decode_pc_q[31:3],p[0],decode_pc_q[1:0]};
    end
  end
  // ISSUE FIFO
  multi_channel_fifo #(
    .DATA_WIDTH($bits(inst_t)),
    .DEPTH     (4            ),
    .BANK      (2            ),
    .WRITE_PORT(2            ),
    .READ_PORT (2            )
  ) inst_fifo (
    .clk                                                               ,
    .rst_n                                                             ,
    
    .flush_i      (frontend_resp_i.rst_jmp                            ),
    
    .write_valid_i(1'b1                                               ),
    .write_ready_o(decode_ready                                       ),
    .write_num_i  (decode_valid_q[0] + decode_valid_q[1]              ),
    .write_data_i ({decoder_inst_package[1],                          
                   decode_valid_q[0] ? decoder_inst_package[0] : decoder_inst_package[1]}), 
    
    .read_valid_o (frontend_req_o.inst_valid                          ),
    .read_ready_i (1'b1                                               ),
    .read_num_i   (frontend_resp_i.issue[0] + frontend_resp_i.issue[1]),
    .read_data_o  (frontend_req_o.inst                                )
  );

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
