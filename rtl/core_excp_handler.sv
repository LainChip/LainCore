`include "pipeline.svh"

module core_excp_handler(
    input logic clk,
    input logic rst_n,

    input csr_t csr_i,
    input logic valid_i,
    input logic ertn_inst_i,
    input excp_flow_t excp_flow_i,
    output logic[31:0] target_o,
    output logic trigger_o
  );

  always_comb begin
    target_o = csr_i.eentry;
    if(ertn_inst_i) begin
      target_o = csr_i.era;
    end
    else if(excp_flow_i.tlbr || excp_flow_i.itlbr) begin
      target_o = csr_i.tlbrentry;
    end
  end

  // trigger_o logic
  always_comb begin
    if(!valid_i) begin
        trigger_o = '0;
    end else begin
        trigger_o = |excp_flow_i | ertn_inst_i;
    end
  end

endmodule
