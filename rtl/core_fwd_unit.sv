`include "pipeline.svh"


module dyn_fwd_single#(
  parameter int SRC_NUM = 3
)(
  input fwd_data_t [SRC_NUM-1:0][1:0] fwd_bus_i,
  input logic[3:0] r_id_i,
  input logic r_ready_i,
  input logic[31:0] r_d_i,

  output logic[31:0] r_d_o,
  output logic r_ready_o
);

function logic[32:0] oh_waysel(logic[SRC_NUM - 1 : 0] way_sel, logic[SRC_NUM - 1 : 0][32:0] data);
  oh_waysel = 0;
  for(integer i = 0 ; i < SRC_NUM ; i++) begin
    oh_waysel |= (way_sel[i] & data[i][32]) ? data[i] : '0;
  end
  return oh_waysel;
endfunction

logic[1:0][SRC_NUM - 1 : 0] sel_oh;
logic[1:0][SRC_NUM - 1 : 0][32:0] src_data;
for(genvar b = 0 ; b < 2 ; b ++) begin
  for(genvar i = 0 ; i < SRC_NUM ; i++) begin
    assign sel_oh[b][i] = fwd_bus_i[i][b].id == r_id_i[3:1];
    assign src_data[b][i] = {fwd_bus_i[i][b].valid, fwd_bus_i[i][b].data};
  end
end
logic[SRC_NUM - 1 : 0] ture_oh;
assign ture_oh = r_id_i[0] ? sel_oh[1] : sel_oh[0];
assign {r_ready_o,r_d_o} = r_ready_i ? {r_ready_i,r_d_i} : oh_waysel(ture_oh, src_data[r_id_i[0]]);

endmodule

module core_fwd_unit #(parameter int SRC_NUM = 3) (
  input  fwd_data_t [SRC_NUM-1:0][1:0] fwd_bus_i,
  input  pipeline_data_t               d_i      ,
  output pipeline_data_t               d_o
);

    for(genvar p = 0; p < 2; p ++) begin
      dyn_fwd_single#(SRC_NUM)dyn_fwd_i(fwd_bus_i,d_i.r_flow.r_id[p],
        d_i.r_flow.r_ready[p],
        d_i.r_data[p],
        d_o.r_data[p],
        d_o.r_flow.r_ready[p]);
    end
    assign d_o.r_flow.r_id   = d_i.r_flow.r_id;
    assign d_o.r_flow.r_addr = d_i.r_flow.r_addr;

  endmodule
