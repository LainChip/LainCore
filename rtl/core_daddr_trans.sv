`include "../pipeline/pipeline.svh"

module core_daddr_trans#(
    parameter bit ENABLE_TLB = 1'b0,
    parameter bit SUPPORT_32_PADDR = 1'b0
  )(
    input logic clk,
    input logic rst_n,

    input logic valid_i,
    input logic[31:0] vaddr_i,

    input logic m1_stall_i,
    output logic ready_o,

    input csr_t csr_i,
    input logic flush_trans_i, // trigger when address translation change.

    output tlb_s_req_t tlb_req_o,
    output logic tlb_req_valid_o,

    input logic tlb_req_ready_i,
    input tlb_s_resp_t tlb_resp_i,

    output tlb_s_resp_t tlb_raw_result_o
  );

  logic da_mode;
  tlb_s_resp_t dmw0_fake_tlb;
  tlb_s_resp_t dmw1_fake_tlb;
  logic[2:0] dmw0_vseg,dmw1_vseg;
  logic plv0, plv3; 

  always_comb begin
    da_mode = csr_i.crmd[`DA];
    dmw0_vseg = csr_i.dmw0[`VSEG];
    dmw0_fake_tlb.dmw = 1'b1;
    dmw0_fake_tlb.found = 1'b1;
    dmw0_fake_tlb.index = 5'd0;
    dmw0_fake_tlb.ps = 6'd12;
    dmw0_fake_tlb.ppn = '0;
    dmw0_fake_tlb.v = '1;
    dmw0_fake_tlb.d = '1;
    dmw0_fake_tlb.mat = csr_i.dmw0[`DMW_MAT];
    dmw0_fake_tlb.plv = csr_i.dmw0[`PLV];

    dmw1_vseg = csr_i.dmw1[`VSEG];
    dmw1_fake_tlb.dmw = 1'b1;
    dmw1_fake_tlb.found = 1'b1;
    dmw1_fake_tlb.index = 5'd0;
    dmw1_fake_tlb.ps = 6'd12;
    dmw1_fake_tlb.ppn = '0;
    dmw1_fake_tlb.v = '1;
    dmw1_fake_tlb.d = '1;
    dmw1_fake_tlb.mat = csr_i.dmw1[`DMW_MAT];
    dmw1_fake_tlb.plv = csr_i.dmw1[`PLV];
    if(da_mode) begin
      dmw0_fake_tlb.mat = csr_i.crmd[`DATM];
      dmw0_fake_tlb.plv = csr_i.crmd[`PLV];
      dmw1_fake_tlb.mat = csr_i.crmd[`DATM];
      dmw1_fake_tlb.plv = csr_i.crmd[`PLV];
    end
    plv0 = csr_i.crmd[`PLV] == 2'd0;
    plv3 = csr_i.crmd[`PLV] == 2'd3;
  end

  if(ENABLE_TLB) begin
    logic[7:0][1:0] valid_table_q;
    logic[7:0][1:0] istlb_table_q;
    tlb_s_resp_t[7:0] table_tmp_q; // 00 invalid, 11 tlb valid, 01 dmw0 hit, 10 dmw1 hit
    logic[7:0][28:12] tlb_vaddr_q;
    tlb_s_resp_t m1_result_q;
    logic m1_tlb_vaddr_miss_q;
    logic valid_q;
    logic istlb_q;
    logic[31:0] vaddr_q; // IN M1

    logic m1_miss;
    always_ff @(posedge clk) begin
      if(!m1_stall_i) begin
        m1_result_q <= table_tmp_q[vaddr_i[31:29]];
        m1_tlb_vaddr_miss_q <= tlb_vaddr_q[vaddr_i[31:29]] != vaddr_i[28:12];
        valid_q <= valid_table_q[vaddr_i[31:29]] || !valid_i || da_mode;
        istlb_q <= istlb_table_q[vaddr_i[31:29]] && !da_mode;
        vaddr_q <= vaddr_i;
      end
      else begin
        if(m1_miss) begin
          m1_result_q <= tlb_resp_i;
          m1_tlb_vaddr_miss_q <= !tlb_req_ready_i;
          valid_q <= tlb_req_ready_i;
          istlb_q <= tlb_req_ready_i;
        end
      end
    end

    // miss 逻辑
    assign m1_miss = !valid_q | (istlb_q & m1_tlb_vaddr_miss_q);

    // 输出逻辑
    assign tlb_raw_result_o = m1_result_q;
    assign ready_o = !m1_miss;

    // 重填状态机
    typedef logic[3:0] fast_translation_fsm_t;
    localparam fast_translation_fsm_t TRANS_FSM_NORMAL = 4'b0001;
    localparam fast_translation_fsm_t TRANS_FSM_DMW0 = 4'b0010;
    localparam fast_translation_fsm_t TRANS_FSM_DMW1 = 4'b0100;
    localparam fast_translation_fsm_t TRANS_FSM_TLB = 4'b1000;
    fast_translation_fsm_t fsm_q,fsm;
    always_ff@(posedge clk) begin
      if(!rst_n) begin
        fsm_q <= TRANS_FSM_NORMAL;
      end
      else begin
        fsm_q <= fsm;
      end
    end
    always_comb begin
      fsm = fsm_q;
      if(flush_trans_i) begin
        fsm = TRANS_FSM_DMW0;
      end
      else begin
        if(fsm_q == TRANS_FSM_DMW0) begin
          fsm = TRANS_FSM_DMW1;
        end
        else if(fsm_q == TRANS_FSM_DMW1) begin
          fsm = TRANS_FSM_NORMAL;
        end
        else if(fsm_q == TRANS_FSM_TLB) begin
          if(tlb_req_ready_i) begin
            fsm = TRANS_FSM_NORMAL;
          end
        end
        else if(m1_miss) begin
          fsm = TRANS_FSM_TLB;
        end
      end
    end
    always_ff @(posedge clk) begin
      if(!rst_n || flush_trans_i) begin
        valid_table_q <= '0;
      end
      else begin
        if(fsm_q == TRANS_FSM_DMW0) begin
          valid_table_q[dmw0_vseg] <= 1'b1;
          istlb_table_q[dmw0_vseg] <= 1'b0;
          table_tmp_q[dmw0_vseg] <= dmw0_fake_tlb;
        end
        else if(fsm_q == TRANS_FSM_DMW1) begin
          valid_table_q[dmw1_vseg] <= 1'b1;
          istlb_table_q[dmw1_vseg] <= 1'b0;
          table_tmp_q[dmw1_vseg] <= dmw1_fake_tlb;
        end
        else if(fsm_q == TRANS_FSM_TLB) begin
          valid_table_q[vaddr_q[31:29]] <= 1'b1;
          istlb_table_q[vaddr_q[31:29]] <= 1'b1;
          table_tmp_q[vaddr_q[31:29]] <= tlb_resp_i;
        end
      end
    end

    assign ready_o = !m1_miss;
  end
  else begin
    logic[31:0] paddr;
    logic dmw0_hit, dmw1_hit;
    logic[2:0] dmw_hit_result;
    logic dmw_miss;
    always_comb begin
      dmw0_hit = vaddr_i[31:29] == csr_i.dmw0[`VSEG];
      // ((csr_i.dmw0[`PLV0] && csr_i.crmd[`PLV] == 2'd0)
      // || (csr_i.dmw0[`PLV3] && csr_i.crmd[`PLV] == 2'd3))
      // && ;
      // 权限判断并不在这一级进行，由 M1 检查。
      // 本级只需要给出所谓虚拟访存结果即可
      dmw1_hit = vaddr_i[31:29] == csr_i.dmw1[`VSEG];
      dmw_miss = ~(dmw0_hit | dmw1_hit);
      dmw_hit_result = dmw0_hit ? csr_i.dmw0[`PSEG] : csr_i.dmw1[`PSEG];
    end
    if(SUPPORT_32_PADDR) begin
      assign paddr[28:0] = vaddr_i[28:0];
      assign paddr[31:29] = dmw_hit_result;
    end
    else begin
      assign paddr[28:0] = vaddr_i[28:0];
      assign paddr[31:29] = '0;
    end
    always_ff @(posedge clk) begin
      if(!m1_stall_i) begin
        tlb_raw_result_o.dmw <= '1;
        tlb_raw_result_o.ppn <= paddr[31:12];
        tlb_raw_result_o.index <= '0;
        tlb_raw_result_o.found <= '1;
        tlb_raw_result_o.ps <= 6'd12;
        tlb_raw_result_o.v <= 1;
        tlb_raw_result_o.d <= 1;
        tlb_raw_result_o.mat <= dmw1_hit ? dmw1_fake_tlb.mat : dmw0_fake_tlb.mat;
        tlb_raw_result_o.plv <= dmw1_hit ? dmw1_fake_tlb.plv : dmw0_fake_tlb.plv;
      end
    end
    assign ready_o = 1'b1;
  end
endmodule
