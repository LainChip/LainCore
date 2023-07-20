`include "pipeline/pipeline.svh"

module core(
    input clk,
    input rst_n,
    input [7:0] int_i,
    LA_AXI_BUS.Master mem_bus
);

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



endmodule
