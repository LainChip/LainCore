`include "pipeline.svh"
`include "lsu.svh"

module core #(parameter bit ENABLE_TLB = 1'b0)(
    input clk,
    input rst_n,
    input [7:0] int_i,
    LA_AXI_BUS.Master mem_bus,
    output [31:0] debug0_wb_pc,
    output [ 3:0] debug0_wb_rf_wen,
    output [ 4:0] debug0_wb_rf_wnum,
    output [31:0] debug0_wb_rf_wdata,
    output [31:0] debug0_wb_inst,
    output [31:0] debug1_wb_pc,
    output [ 3:0] debug1_wb_rf_wen,
    output [ 4:0] debug1_wb_rf_wnum,
    output [31:0] debug1_wb_rf_wdata,
    output [31:0] debug1_wb_inst
  );


  frontend_req_t frontend_req;
  frontend_resp_t frontend_resp;
  cache_bus_resp_t ibus_resp,dbus_resp;
  cache_bus_req_t ibus_req,dbus_req;
  // axi converter
  axi_converter #(
                  .CACHE_PORT_NUM(2)
                ) axi_converter (
                  .clk(clk),
                  .rst_n(rst_n),
                  .axi_bus_if(mem_bus),
                  .req_i({dbus_req,ibus_req}),
                  .resp_o({dbus_resp,ibus_resp})
                );

  core_frontend_renew #(
    .ENABLE_TLB(ENABLE_TLB)
  ) core_frontend_inst (
                   .clk(clk),
                   .rst_n(rst_n),
                   .frontend_req_o(frontend_req),
                   .frontend_resp_i(frontend_resp),
                   .bus_resp_i(ibus_resp),
                   .bus_req_o(ibus_req)
                 );

  core_backend #(
    .ENABLE_TLB(ENABLE_TLB)
  ) core_backend_inst (
                  .clk(clk),
                  .rst_n(rst_n),
		        		  .int_i(int_i),
                  .frontend_req_i(frontend_req),
                  .frontend_resp_o(frontend_resp),
                  .bus_resp_i(dbus_resp),
                  .bus_req_o(dbus_req),
                  .debug0_wb_pc,
                  .debug0_wb_rf_wen,
                  .debug0_wb_rf_wnum,
                  .debug0_wb_rf_wdata,
                  .debug0_wb_inst,
                
                  .debug1_wb_pc,
                  .debug1_wb_rf_wen,
                  .debug1_wb_rf_wnum,
                  .debug1_wb_rf_wdata,
                  .debug1_wb_inst
                );

endmodule
