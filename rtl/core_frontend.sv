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

module core_frontend (
  input  logic            clk            ,
  input  logic            rst_n          ,
  output frontend_req_t   frontend_req_o ,
  input  frontend_resp_t  frontend_resp_i,
  input  cache_bus_resp_t bus_resp_i     ,
  output cache_bus_req_t  bus_req_o
);

  // IDLE WAIT逻辑
  // 当出现idle指令的时候，刷新整条流水线到idle + 4的位置，并在前端停住整条流水线，以降低执行功耗。
  logic idle_lock;
  always @(posedge clk) begin
    if (~rst_n) begin
      idle_lock <= 1'b0;
    end
    else if (frontend_resp_i.wait_inst && !frontend_resp_i.int_detect) begin
      idle_lock <= 1'b1;
    end
    else if (frontend_resp_i.int_detect) begin
      idle_lock <= 1'b0;
    end
  end

  // NPC 模块
  logic paddr_ready;
  logic[31:0] pc_vaddr;
  logic[31:0] f_pc;
  logic[1:0] f_valid;
  bpu_predict_t [1:0] f_predict   ;
  logic               f_stall     ;
  logic               icache_ready,icache_stall;
  logic               mimo_ready  ;
  assign f_stall      = !icache_ready | !mimo_ready | idle_lock | !paddr_ready;
  assign icache_stall = !icache_ready | !mimo_ready;
  assign f_pc         = pc_vaddr;
  core_npc npc_inst (
    .clk       (clk                           ),
    .rst_n     (rst_n                         ),
    .rst_jmp   (frontend_resp_i.rst_jmp       ),
    .rst_target(frontend_resp_i.rst_jmp_target),
    .f_stall_i (f_stall                       ),
    .pc_o      (pc_vaddr                      ),
    .npc_o     (npc_vaddr                     ),
    .valid_o   (f_valid                       ),
    .predict_o (f_predict                     ),
    .correct_i (frontend_resp_i.bpu_correct   )
  );

  // ICACHE 模块
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
  // I CACHE 模块
  logic[31:0] m_pc;
  logic[1:0] m_valid;
  bpu_predict_t[1:0] m_predict;
  logic[1:0][31:0] m_inst;

  tlb_s_resp_t trans_result;
  fetch_excp_t m_excp      ; // TODO: check me
  logic[31:0] f_ppc;   // TODO: check me
  logic uncached; // TODO: check me
  assign f_ppc    = {trans_result.value.ppn, f_pc[11:0]};
  assign uncached = trans_result.value.mat != 2'b01;
  always_comb begin
    m_excp.adef = (|f_ppc[1:0]) || (trans_result.dmw ? '0 :
      ((frontend_resp_i.csr_reg.crmd[`PLV] == 2'd3) && f_pc[31]));
    m_excp.tlbr = (!m_excp) && !trans_result.found;
    m_excp.pif  = (!m_excp) && trans_result.value.v;
    m_excp.ppi  = (!m_excp) && (trans_result.value.plv == 2'd0 &&
      frontend_resp_i.csr_reg.crmd[`PLV] = = 2'd3);
    // m_excp.ipe = (!m_excp) && (trans_result.value.plv == 2'd0 &&
    // frontend_resp_i.csr_reg.crmd[`PLV] = = 2'd3);
  end
  core_addr_trans #(
    .ENABLE_TLB('1), // TODO: PARAMETERIZE ME
    .FETCH_ADDR('1)
  ) core_iaddr_trans_inst (
    .clk             (clk                    ),
    .rst_n           (rst_n                  ),
    .valid_i         (|f_valid               ),
    .vaddr_i         (npc_vaddr              ),
    .m1_stall_i      (f_stall                ),
    .ready_o         (paddr_ready            ),
    .csr_i           (frontend_resp_i.csr_reg),
    .tlb_update_req_i(tlb_update_req_i       ),
    .trans_result_o  (trans_result           )
  );
  logic[31:0] ppc_nc;
  core_ifetch #(.ATTACHED_INFO_WIDTH(2*$bits(bpu_predict_t))) ifetch_inst (
    .clk            (clk                     ),
    .rst_n          (rst_n                   ),
    .cacheop_i      (icacheop                ),
    .cacheop_valid_i(icacheop_valid          ),
    .cacheop_ready_o(icacheop_ready          ),
    .valid_i        (f_valid                 ),
    .ready_o        (icache_ready            ),
    .vpc_i          (f_pc                    ),
    .attached_i     (f_predict               ),
    .ppc_i          (f_ppc                   ),
    .paddr_valid_i  (/**/    1'b1            ),
    .uncached_i     (uncached                ),
    .vpc_o          (m_pc                    ),
    .ppc_o          (ppc_nc                  ),
    .ready_i        (mimo_ready && !idle_lock),
    .valid_o        (m_valid                 ),
    .attached_o     (m_predict               ),
    .inst_o         (m_inst                  ),
    .clr_i          (frontend_resp_i.rst_jmp ),
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
  inst_package_t [1:0] m_inst_pack;
  assign m_inst_pack[0].pc = {m_pc[31:3],!m_valid[0],m_pc[1:0]};
  assign m_inst_pack[1].pc = {m_pc[31:3],1'b1,m_pc[1:0]};
  assign m_inst_pack[0].inst = m_valid[0] ? m_inst[0] : m_inst[1];
  assign m_inst_pack[1].inst = m_inst[1];
  assign m_inst_pack[0].fetch_excp = m_excp;
  assign m_inst_pack[1].fetch_excp = m_excp;
  assign m_inst_pack[0].bpu_predict = m_valid[0] ? m_predict[0] : m_predict[1];
  assign m_inst_pack[1].bpu_predict = m_predict[1];
  logic[1:0] m_num,d_num;
  always_comb begin
    m_num = m_valid[0] + m_valid[1];
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
    .write_num_i  (m_num                  ),
    .write_data_i (m_inst_pack            ),
    
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
  //   .write_num_i  (m_num                  ),
  //   .write_data_i (m_inst_pack            ),

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

endmodule
