`include "pipeline.svh"


module core_iaddr_trans#(
    parameter bit ENABLE_TLB = 1'b0
  )(
    input logic clk,
    input logic rst_n,

    input logic valid_i,
    input logic[31:0] vaddr_i,

    input logic f_stall_i,
    output logic ready_o,
    output logic[31:0] paddr_o,
    output logic uncached_o,
    output fetch_excp_t fetch_excp_o,

    input csr_t csr_i,
    input logic flush_i, // trigger when address translation change.

    // TLB LOOKUP INTERFACE
    output logic[31:12] tlb_req_vppn,
    output logic tlb_req_valid_o,
    input logic tlb_req_ready_i,
    input tlb_s_resp_t tlb_resp_i
  );

  logic da_mode;
  logic[1:0] da_matf,dmw0_mat,dmw1_mat;
  logic[2:0] dmw0_vseg,dmw1_vseg,dmw0_pseg,dmw1_pseg; // TODO: FIXME
  logic dmw0_plv0,dmw1_plv0;
  logic dmw0_plv3,dmw1_plv3;
  logic plv0, plv3;
  always_comb begin
    da_mode = csr_i.crmd[`DA];
    da_matf = csr_i.crmd[`DATF];
    dmw0_vseg = csr_i.dmw0[`VSEG];
    dmw0_mat = csr_i.dmw0[`DMW_MAT];
    dmw1_vseg = csr_i.dmw1[`VSEG];
    dmw1_mat = csr_i.dmw1[`DMW_MAT];
    dmw0_pseg = csr_i.dmw0[`PSEG];
    dmw1_pseg = csr_i.dmw1[`PSEG];
    plv0 = csr_i.crmd[`PLV] == 2'd0;
    plv3 = csr_i.crmd[`PLV] == 2'd3;
    dmw0_plv0 = csr_i.dmw0[`PLV0];
    dmw0_plv3 = csr_i.dmw0[`PLV3];
    dmw1_plv0 = csr_i.dmw1[`PLV0];
    dmw1_plv3 = csr_i.dmw1[`PLV3];
  end

  if(ENABLE_TLB) begin
    // TODO: SUPPORT TLB
  end
  else begin
    logic[31:0] paddr_q;
    logic dmw0_hit, dmw1_hit;
    assign paddr_o = paddr_q;
    assign ready_o = 1'b1;
    logic uncached;
    always_ff@(posedge clk) begin
      if(!f_stall_i) begin
        paddr_q[28:0] <= vaddr_i[28:0];
        paddr_q[31:29] <= dmw0_hit ? dmw0_pseg : dmw1_pseg;
        fetch_excp_o.adef <= (|vaddr_i[1:0]) || (!da_mode && !dmw0_hit && !dmw1_hit);
        uncached_o <= uncached;
      end
      fetch_excp_o.tlbr <= '0;
      fetch_excp_o.pif <= '0;
      fetch_excp_o.ppi <= '0;
      fetch_excp_o.ipe <= '0;
    end
    // assign fetch_excp_o.adef = ;
    assign dmw0_hit = ((dmw0_plv0 & plv0) || (dmw0_plv3 & plv3)) && dmw0_vseg == vaddr_i[31:29];
    assign dmw1_hit = ((dmw1_plv0 & plv0) || (dmw1_plv3 & plv3)) && dmw1_vseg == vaddr_i[31:29];
    // assign fetch_excp_o.tlbr = '0;
    // assign fetch_excp_o.pif = '0;
    // assign fetch_excp_o.ppi = '0;
    assign tlb_req_vppn = '0;
    assign tlb_req_valid_o = '0;
    always_comb begin
      if(da_mode) begin
        uncached = da_matf != 2'd1;
      end
      else begin
        uncached = dmw0_hit ? (dmw0_mat != 2'd1) : (dmw1_mat != 2'd1);
      end
    end
  end

endmodule
