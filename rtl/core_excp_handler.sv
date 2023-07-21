`include "pipeline.svh"

module core_excp_handler(
    input logic clk,
    input logic rst_n,

    input csr_t csr_value,
    input logic valid_i,
    input logic ertn_inst_i,
    input excp_flow_t m1_excp_flow,
    output logic[31:0] excp_target_o,
    output logic trigger_o
  );

  always_comb begin
    excp_target_o = csr_value.eentry;
    if(ertn_inst_i) begin
      excp_target_o = csr_value.era;
    end
    else if(m1_excp_flow.tlbr || m1_excp_flow.itlbr) begin
      excp_target_o = csr_value.tlbrentry;
    end
  end

  // trigger_o logic
  always_comb begin
    if(!valid_i) begin
        trigger_o = '0;
    end else begin
        trigger_o = |m1_excp_flow | ertn_inst_i;
    end
  end

endmodule
