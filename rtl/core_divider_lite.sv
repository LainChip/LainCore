`include "pipeline.svh"

/*--JSON--{"module_name":"core_divider_manager","module_ver":"2","module_type":"module"}--JSON--*/

module core_divider_manager(
    input logic clk,
    input logic rst_n,

    input logic[31:0] r0_i,
    input logic[31:0] r1_i,
    input logic[1:0] op_i,
    input logic push_valid_i,
    output logic push_ready_o,// CONNECT TO M2
    // input logic[2:0] push_id_i,

    // input logic wb_stall_i,
    // input logic[2:0] pop_id_i,
    output logic result_valid_o,
    output logic[31:0] result_o
  );
  logic div_core_busy;
  logic[31:0] mod_result, div_result;
  fast_div  fast_div_inst (
            .clk(clk),
            .rst_n(rst_n),
            .A(r1_i),
            .B(r0_i),
            .rem(mod_result),
            .quo(div_result),
            .start(push_valid_i && push_ready_o),
            .sign(~op_i[0]),
            .busy(div_core_busy)
          );
  // 加一周期用于选择 rem 或者 qua
  logic rvalid_q, rready_q, cal_mod_q;
  logic[31:0] result_q;
  assign push_ready_o = rready_q;
  assign result_valid_o = rvalid_q;
  assign result_o = result_q;
  always_ff @(posedge clk) begin
    if(push_valid_i && push_ready_o) begin
      rvalid_q <= '0;
      rready_q <= '0;
      cal_mod_q <= op_i[1];
    end else begin
      if(!div_core_busy) begin
        rvalid_q <= '1;
        rready_q <= '1;
        result_q <= cal_mod_q ? mod_result : div_result;
      end
    end
  end
endmodule
