`include "pipeline.svh"

module core_daddr_trans#(
  parameter bit ENABLE_TLB = 1'b0,
  parameter bit FETCH_ADDR = 1'b0,
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
  output logic tlb_req_valid_o,

  input logic tlb_req_ready_i,
  input tlb_s_resp_t tlb_resp_i,

  output tlb_s_resp_t tlb_raw_result_o
);

logic        da_mode      ;
logic        pg_mode      ;
tlb_s_resp_t da_fake_tlb  ;
tlb_s_resp_t dmw0_fake_tlb;
tlb_s_resp_t dmw1_fake_tlb;
logic[2:0] dmw0_vseg,dmw1_vseg;
logic[2:0] dmw0_kseg,dmw1_kseg;
logic plv0, plv3;

always_comb begin
  da_mode               = csr_i.crmd[`DA];
  pg_mode               = csr_i.crmd[`PG];
  da_fake_tlb.dmw       = 1'b1;
  da_fake_tlb.found     = 1'b1;
  da_fake_tlb.index     = 5'd0;
  da_fake_tlb.ps        = 6'd12;
  da_fake_tlb.value.ppn = vaddr_i[31:12];
  da_fake_tlb.value.v   = '1;
  da_fake_tlb.value.d   = '1;
  da_fake_tlb.value.mat = csr_i.crmd[`DATM];
  da_fake_tlb.value.plv = '1;

  dmw0_vseg               = csr_i.dmw0[`VSEG];
  dmw0_kseg               = csr_i.dmw0[`PSEG];
  dmw0_fake_tlb.dmw       = 1'b1;
  dmw0_fake_tlb.found     = 1'b1;
  dmw0_fake_tlb.index     = 5'd0;
  dmw0_fake_tlb.ps        = 6'd12;
  dmw0_fake_tlb.value.ppn = {dmw0_kseg,vaddr_i[28:12]};
  dmw0_fake_tlb.value.v   = '1;
  dmw0_fake_tlb.value.d   = '1;
  dmw0_fake_tlb.value.mat = csr_i.dmw0[`DMW_MAT];
  dmw0_fake_tlb.value.plv = csr_i.dmw0[`PLV];

  dmw1_vseg               = csr_i.dmw1[`VSEG];
  dmw1_kseg               = csr_i.dmw1[`PSEG];
  dmw1_fake_tlb.dmw       = 1'b1;
  dmw1_fake_tlb.found     = 1'b1;
  dmw1_fake_tlb.index     = 5'd0;
  dmw1_fake_tlb.ps        = 6'd12;
  dmw1_fake_tlb.value.ppn = '0;
  dmw1_fake_tlb.value.v   = '1;
  dmw1_fake_tlb.value.d   = '1;
  dmw1_fake_tlb.value.mat = csr_i.dmw1[`DMW_MAT];
  dmw1_fake_tlb.value.plv = csr_i.dmw1[`PLV];
  plv0                    = csr_i.crmd[`PLV] == 2'd0;
  plv3                    = csr_i.crmd[`PLV] == 2'd3;
end

  logic[31:0] paddr;
  logic dmw0_hit, dmw1_hit;
  logic[2:0] dmw_hit_result;
  logic dmw_miss;
  always_comb begin
    dmw0_hit       = vaddr_i[31:29] == csr_i.dmw0[`VSEG];
    // 权限判断并不在这一级进行，由 M1 检查。
    // 本级只需要给出所谓虚拟访存结果即可
    dmw1_hit       = vaddr_i[31:29] == csr_i.dmw1[`VSEG];
    dmw_miss       = ~(dmw0_hit | dmw1_hit);
    dmw_hit_result = dmw0_hit ? csr_i.dmw0[`PSEG] : csr_i.dmw1[`PSEG];
  end

  assign paddr[28:0]  = vaddr_i[28:0];
  assign paddr[31:29] = pg_mode ? dmw_hit_result : vaddr_i[31:29];
  // assign paddr[31:29] = dmw_hit_result;

  always_ff @(posedge clk) begin
    if(!m1_stall_i) begin
      tlb_raw_result_o.dmw       <= '1;
      tlb_raw_result_o.value.ppn <= paddr[31:12];
      tlb_raw_result_o.index     <= '0;
      tlb_raw_result_o.found     <= '1;
      tlb_raw_result_o.ps        <= 6'd12;
      tlb_raw_result_o.value.v   <= 1;
      tlb_raw_result_o.value.d   <= 1;
      tlb_raw_result_o.value.mat <= da_mode ? da_fake_tlb:
        (dmw1_hit ? dmw1_fake_tlb.value.mat : dmw0_fake_tlb.value.mat);
      tlb_raw_result_o.value.plv <= da_mode ? da_fake_tlb:
        (dmw1_hit ? dmw1_fake_tlb.value.plv : dmw0_fake_tlb.value.plv);
    end
  end
  assign ready_o = 1'b1;

endmodule
