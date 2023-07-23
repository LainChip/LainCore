`include "pipeline.svh"
`include "lsu.svh"
// 这个function应该放在前端，在fetch阶段和写入fifo阶段之间，合成inst_t的阶段进行。
function reg_info_t get_register_info(
    input is_t decode_info,
    logic[31:0] inst
  );
  reg_info_t ret;

  logic [1:0] r0_sel, w_sel;
  logic r1_sel;
  r0_sel = decode_info.reg_type_r0;
  r1_sel = decode_info.reg_type_r1;
  w_sel  = decode_info.reg_type_w;
  case(r0_sel)
    default: begin
      ret.r_reg[0] = '0;
    end
    `_REG_R0_RK: begin
      ret.r_reg[0] = inst[14:10];
    end
    `_REG_R0_RD: begin
      ret.r_reg[0] = inst[4:0];
    end
  endcase
  case(r1_sel)
    default: begin
      ret.r_reg[1] = '0;
    end
    `_REG_R1_RJ: begin
      ret.r_reg[1] = inst[9:5];
    end
  endcase
  case(w_sel)
    default: begin
      ret.w_reg = '0;
    end
    `_REG_W_RD: begin
      ret.w_reg = inst[4:0];
    end
    `_REG_W_RJD: begin
      ret.w_reg = inst[4:0] | inst[9:5];
    end
    `_REG_W_BL1: begin
      ret.w_reg = 5'd1;
    end
  endcase
  return ret;
endfunction

module core_frontend(
    input logic clk,
    input logic rst_n,
    output frontend_req_t frontend_req_o,
    input frontend_resp_t frontend_resp_i,

    input cache_bus_resp_t bus_resp_i,
    output cache_bus_req_t bus_req_o
  );

  // IDLE WAIT逻辑
  // 当出现idle指令的时候，刷新整条流水线到idle + 4的位置，并在前端停住整条流水线，以降低执行功耗。
  logic wait_i,int_i;
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
  logic[1:0][31:0] pc_vaddr;
  logic[31:0] f_pc;
  logic[1:0] f_valid;
  bpu_predict_t f_predict;
  logic f_stall;
  logic icache_ready,icache_stall;
  logic mimo_ready;
  assign f_stall = !icache_ready | !mimo_ready | idle_lock;
  assign icache_stall = !icache_ready | !mimo_ready;
  assign f_pc = pc_vaddr[0];
  core_npc  npc_inst (
         .clk(clk),
         .rst_n(rst_n),
         .rst_jmp(frontend_resp_i.rst_jmp),
         .rst_target(frontend_resp_i.rst_jmp_target),
         .f_stall_i(f_stall),
         .pc_o(pc_vaddr),
         .valid_o(f_valid),
         .predict_o(f_predict),
         .correct_i(frontend_resp_i.bpu_correct)
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
      icacheop <= frontend_resp_i.icache_op;
      icacheop_addr <= frontend_resp_i.icacheop_addr;
    end
    else if(icacheop_ready) begin
      icacheop_valid <= '0;
    end
  end
  assign frontend_req_o.icache_ready = icacheop_ready;
  // I CACHE 模块
  logic[31:0] m_pc;
  logic[1:0] m_valid;
  bpu_predict_t m_predict;
  fetch_excp_t m_excp;
  logic[1:0][31:0] m_inst;

  logic paddr_ready;
  logic[31:0] m_ppc;

  logic tlb_req_valid,tlb_req_ready; // TODO: CONNECT ME
  tlb_s_resp_t tlb_resp;

  logic uncached;
  core_iaddr_trans # (
                .ENABLE_TLB(1'b0)
              )
              iaddr_trans_inst (
                .clk(clk),
                .rst_n(rst_n),
                .valid_i(|f_valid),
                .vaddr_i(f_pc),
                .f_stall_i(!icache_ready),
                .ready_o(paddr_ready),
                .paddr_o(m_ppc),
                .fetch_excp_o(m_excp),
                .csr_i(frontend_resp_i.csr_reg),
                .flush_i(flush_i),
                .uncached_o(uncached),
                .tlb_req_vppn(tlb_req_vppn),
                .tlb_req_valid_o(tlb_req_valid),
                .tlb_req_ready_i(tlb_req_ready), // TODO: CONNECT ME
                .tlb_resp_i(tlb_resp)
              );

  logic[31:0] ppc_nc;
  core_ifetch # (
           .ATTACHED_INFO_WIDTH($bits(bpu_predict_t))
         )
         ifetch_inst (
           .clk(clk),
           .rst_n(rst_n),
           .cacheop_i(icacheop),
           .cacheop_valid_i(icacheop_valid),
           .cacheop_ready_o(icacheop_ready),
           .valid_i(f_valid),
           .ready_o(icache_ready),
           .vpc_i(f_pc),
           .attached_i(f_predict),
           .ppc_i(m_ppc),
           .paddr_valid_i(paddr_ready),
           .uncached_i(uncached),
           .vpc_o(m_pc),
           .ppc_o(ppc_nc),
           .ready_i(mimo_ready),
           .valid_o(m_valid),
           .attached_o(m_predict),
           .inst_o(m_inst),
           .clr_i(frontend_resp_i.rst_jmp),
           .bus_busy_i(frontend_resp_i.bus_busy),
           .bus_req_o(bus_req_o),
           .bus_resp_i(bus_resp_i)
         );
  // MIMO fifo
  typedef struct packed {
            logic [31:0] pc;
            logic [31:0] inst;
            fetch_excp_t fetch_excp;
            bpu_predict_t bpu_predict;
          } inst_package_t;
  inst_package_t [1:0]m_inst_pack;
  assign m_inst_pack[0].pc = {m_pc[31:3],!m_valid[0],m_pc[1:0]};
  assign m_inst_pack[1].pc = {m_pc[31:3],1'b1,m_pc[1:0]};
  assign m_inst_pack[0].inst = m_valid[0] ? m_inst[0] : m_inst[1];
  assign m_inst_pack[1].inst = m_inst[1];
  assign m_inst_pack[0].fetch_excp = m_excp;
  assign m_inst_pack[1].fetch_excp = m_excp;
  assign m_inst_pack[0].bpu_predict = m_predict;
  assign m_inst_pack[1].bpu_predict = m_predict;
  logic[1:0] m_num,d_num;
  always_comb begin
    m_num = m_valid[0] + m_valid[1];
  end
  inst_package_t[1:0] d_inst_pack;
  logic[1:0] d_valid;
  multi_channel_fifo #(
                       .DATA_WIDTH(64 + $bits(bpu_predict_t) + $bits(fetch_excp_t)),
                       .DEPTH(16),
                       .BANK(4),
                       .WRITE_PORT(2),
                       .READ_PORT(2)
                     ) inst_fifo (
                       .clk,
                       .rst_n,

                       .flush_i(frontend_resp_i.rst_jmp),

                       .write_valid_i(1'b1),
                       .write_ready_o(mimo_ready),
                       .write_num_i(m_num),
                       .write_data_i(m_inst_pack),

                       .read_valid_o(d_valid),
                       .read_ready_i(1'b1),
                       .read_num_i(d_num),
                       .read_data_o(d_inst_pack)
                     );
  // DECODER
  inst_t[1:0] decoder_inst_package;
  for(genvar p = 0;  p < 2 ;p ++ ) begin
    is_t issue_package;
    decoder  decoder_inst (
               .inst_i(d_inst_pack[p].inst),
               .fetch_err_i('0),
               .is_o(issue_package)
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
  assign frontend_req_o.inst_valid = d_valid;
  assign frontend_req_o.inst = decoder_inst_package;
  // BACKEND

endmodule
