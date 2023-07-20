`include "../pipeline/pipeline.svh"

module divider_manager(
    input logic clk,
    input logic rst_n,

    input logic[31:0] r0_i,
    input logic[31:0] r1_i,
    input logic unsigned_i,
    input logic push_valid_i,
    output logic push_ready_o,
    input logic[2:0] push_id_i,

    input logic wb_stall_i,
    input logic[2:0] pop_id_i,  // CONNECT TO M2
    output logic result_valid_o,
    output logic[31:0] result_o
  );

  logic div_finish;
  logic[31:0] mod_result, div_result;
  logic[2:0] calculating_id_q;
  logic calculating_mod_q;
  // VALID TABLE
  logic[7:0] valid_table_q;
  logic[7:0][31:0] result_q;
  always_ff@(posedge clk) begin
    if(push_valid_i & push_ready_o) begin
      valid_table_q[push_id_i] <= '0;
    end
    else begin
      if(div_finish) begin
        valid_table_q[calculating_id_q] <= '1;
        result_q[calculating_id_q] <= calculating_mod_q ? mod_result : div_result;
      end
    end
  end

  logic div_busy_q,div_busy;
  logic skid_q;
  logic[2:0] pop_id_skid_q;
  always_ff @(posedge clk) begin
    skid_q <= wb_stall_i;
    if(!skid_q) begin
      pop_id_skid_q <= pop_id_i;
      result_valid_o <= valid_table_q[pop_id_i];
    end
    else begin
      result_valid_o <= valid_table_q[pop_id_skid_q];
    end
  end
  always_ff @(posedge clk) begin
    if(~rst_n) begin
      div_busy_q <= '0;
    end
    else begin
      div_busy_q <= div_busy;
    end
  end
  always_comb begin
    if(div_busy_q) begin
      if(div_finish) begin
        div_busy = '0;
      end
    end
    else begin
      if(push_valid_i) begin
        div_busy = '1;
      end
    end
  end
  assign push_ready_o = ~div_busy_q;

  divider  divider_i (
             .clk(clk),
             .rst_n(rst_n),
             .div_valid(push_valid_i & push_ready_o),
             .div_ready(),
             .res_valid(div_finish),
             .res_ready(1'b1),
             .div_signed_i(unsigned_i),
             .Z_i(r1_i),
             .D_i(r0_i),
             .q_o(div_result),
             .s_o(mod_result)
           );

endmodule
