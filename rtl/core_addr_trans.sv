`include "pipeline.svh"

// 这个模块在一周期后输出查找结果
// 后续可能的优化是将此模块对 TLB 的查找放在 M1 级别，
// L0 MISS 之后，等待一周期真实 TLB 的查找再返回查找结果。
// L0 TLB 完全可以用 FPGA-CAM 电路进行优化
module core_addr_trans #(
  parameter bit ENABLE_TLB       = 1'b1           ,
  parameter bit FETCH_ADDR       = 1'b0           ,
  parameter bit SUPPORT_32_PADDR = 1'b0           ,
  parameter int TLB_ENTRY_NUM    = `_TLB_ENTRY_NUM
) (
  input  logic            clk             ,
  input  logic            rst_n           ,
  input  logic            valid_i         ,
  input  logic [31:0]     vaddr_i         ,
  input  logic            m1_stall_i      ,
  input  logic            jmp_i           ,
  input  logic            flush_i         ,
  output logic            ready_o         ,
  input  csr_t            csr_i           ,
  input  tlb_update_req_t tlb_update_req_i,
  output tlb_s_resp_t     trans_result_o
);

  logic[31:0] vaddr, vaddr_q;
  always_ff @(posedge clk) begin
    if(!m1_stall_i || jmp_i) begin
      vaddr_q <= vaddr_i;
    end
  end
  assign vaddr = (m1_stall_i && !jmp_i) ? vaddr_q : vaddr_i;

// TLB 表项匹配逻辑
  logic [TLB_ENTRY_NUM-1:0] tlb_match;
  for(genvar i = 0 ; i < TLB_ENTRY_NUM ; i++) begin
    tlb_match_single # (
      .ENABLE_OPT('0),
      .ENABLE_RST('1)
    )
    tlb_match_single_i (
      .clk(clk),
      .rst_n(rst_n),
      .vppn_i(vaddr[31:13]),
      .asid_i(csr_i.asid[9:0]),
      .match_o(tlb_match[i]),
      .update_i(tlb_update_req_i.tlb_we[i]),
      .update_key_i(tlb_update_req_i.tlb_w_entry.key)
    );
  end

// TLB 表项值
  tlb_value_t   [TLB_ENTRY_NUM-1:0][1:0] tlb_value_q ;
  logic         [TLB_ENTRY_NUM-1:0]      is_4M_page_q;
  for(genvar i = 0 ; i < TLB_ENTRY_NUM ; i++) begin
    always_ff @(posedge clk) begin
      if(tlb_update_req_i.tlb_we[i]) begin
        tlb_value_q[i] <= tlb_update_req_i.tlb_w_entry.value;
        is_4M_page_q[i]   <= tlb_update_req_i.tlb_w_entry.key.ps == 6'd22;
      end
    end
  end

  logic        tlb_hit   ;
  tlb_s_resp_t tlb_result;
  assign tlb_hit = |tlb_match;
  always_comb begin
    tlb_result = '0;
    for(integer i = 0 ; i < TLB_ENTRY_NUM ; i++) begin
      if(tlb_match[i]) begin // ONTHOT
        tlb_result.found |= '1;
        tlb_result.index |= i;
        tlb_result.ps    |= is_4M_page_q[i] ? 6'd22 : 6'd12;
        tlb_result.value |= tlb_value_q[i][is_4M_page_q[i] ? vaddr[22]:vaddr[12]];
      end
    end
  end

  logic        da_mode      ;
  logic        pg_mode      ;
  tlb_s_resp_t da_fake_tlb  ;
  tlb_s_resp_t dmw0_fake_tlb;
  tlb_s_resp_t dmw1_fake_tlb;
  logic[2:0] dmw0_vseg,dmw1_vseg;
  logic[2:0] dmw0_kseg,dmw1_kseg;
  logic plv0, plv3;
  assign plv0 = csr_i.crmd[`PLV] == 2'd0;
  assign plv3 = csr_i.crmd[`PLV] == 2'd3;

  logic dmw0_hit, dmw1_hit;
  logic dmw_miss;
  always_comb begin
    da_mode               = csr_i.crmd[`DA];
    pg_mode               = csr_i.crmd[`PG];
    da_fake_tlb.dmw       = 1'b1;
    da_fake_tlb.found     = 1'b1;
    da_fake_tlb.index     = 5'd0;
    da_fake_tlb.ps        = 6'd12;
    da_fake_tlb.value.ppn = vaddr[31:12];
    da_fake_tlb.value.v   = '1;
    da_fake_tlb.value.d   = '1;
    da_fake_tlb.value.mat = FETCH_ADDR ? csr_i.crmd[`DATF] : csr_i.crmd[`DATM];
    da_fake_tlb.value.plv = '1;

    dmw0_vseg               = csr_i.dmw0[`VSEG];
    dmw0_kseg               = csr_i.dmw0[`PSEG];
    dmw0_fake_tlb.dmw       = dmw0_hit;
    dmw0_fake_tlb.found     = dmw0_hit;
    dmw0_fake_tlb.index     = 5'd0;
    dmw0_fake_tlb.ps        = 6'd12;
    dmw0_fake_tlb.value.ppn = {dmw0_kseg,vaddr[28:12]};
    dmw0_fake_tlb.value.v   = '1;
    dmw0_fake_tlb.value.d   = '1;
    dmw0_fake_tlb.value.mat = csr_i.dmw0[`DMW_MAT];
    dmw0_fake_tlb.value.plv = csr_i.dmw0[3] ? 2'b11 : 2'b00; // TODO: check me

    dmw1_vseg               = csr_i.dmw1[`VSEG];
    dmw1_kseg               = csr_i.dmw1[`PSEG];
    dmw1_fake_tlb.dmw       = dmw1_hit;
    dmw1_fake_tlb.found     = dmw1_hit;
    dmw1_fake_tlb.index     = 5'd0;
    dmw1_fake_tlb.ps        = 6'd12;
    dmw1_fake_tlb.value.ppn = {dmw1_kseg,vaddr[28:12]};
    dmw1_fake_tlb.value.v   = '1;
    dmw1_fake_tlb.value.d   = '1;
    dmw1_fake_tlb.value.mat = csr_i.dmw1[`DMW_MAT];
    dmw1_fake_tlb.value.plv = csr_i.dmw1[3] ? 2'b11 : 2'b00;
  end

  always_comb begin
    // 权限判断并不在这一级进行，由 M1 检查。
    // 本级只需要给出所谓虚拟访存结果即可
    dmw0_hit = vaddr[31:29] == dmw0_vseg &&
      ((csr_i.dmw0[3] && plv3) || (csr_i.dmw0[0] && plv0));
    dmw1_hit = vaddr[31:29] == dmw1_vseg &&
      ((csr_i.dmw1[3] && plv3) || (csr_i.dmw1[0] && plv0));
    dmw_miss = ~(dmw0_hit | dmw1_hit);
  end

  always_ff @(posedge clk) begin
    if(!m1_stall_i || flush_i || jmp_i) begin
      trans_result_o <= da_mode ? da_fake_tlb : (
        dmw_miss ? tlb_result : (
          dmw0_hit ? dmw0_fake_tlb : dmw1_fake_tlb
        )
      );
    end
  end

  assign ready_o = 1'b1;

endmodule
