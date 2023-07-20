`include "common.svh"

module simpleDualPortRamByteen
 #(
	parameter int unsigned dataWidth = 32,
	parameter int unsigned ramSize = 1024,
	parameter type dataType = logic [dataWidth-1:0],
	parameter int unsigned latency = 1,
	parameter int readMuler = 4
) (
	input clk,    // Clock
	input rst_n,  // Asynchronous reset active low
	input logic[$clog2(ramSize) - 1 : 0] addressA,
	input [(dataWidth / 8) - 1 : 0] we,
	input logic[$clog2(ramSize) - $clog2(readMuler) - 1: 0]addressB,
	input dataType inData,
	output dataType [readMuler-1:0] outData
);

`ifdef _FPGA
xpm_memory_sdpram
#(
	.ADDR_WIDTH_A($clog2(ramSize)),
	.ADDR_WIDTH_B($clog2(ramSize) - $clog2(readMuler)),
	.AUTO_SLEEP_TIME(0),
	.BYTE_WRITE_WIDTH_A(8),
	.CLOCKING_MODE("common_clock"),
	.ECC_MODE("no_ecc"),
	.MEMORY_INIT_FILE("none"),
	.MEMORY_INIT_PARAM("0"),
	.MEMORY_OPTIMIZATION("true"),
	.USE_MEM_INIT(0),
	.MESSAGE_CONTROL(0),

	.MEMORY_PRIMITIVE("auto"),

	.MEMORY_SIZE(dataWidth * ramSize),

	.READ_DATA_WIDTH_B(readMuler * dataWidth),
	.READ_LATENCY_B(latency),
	.WRITE_DATA_WIDTH_A(dataWidth),
	.WRITE_MODE_B("read_first")
	)instanceSdpram(
	.clka(clk),
	.clkb(clk),

	.addra(addressA),
	.addrb(addressB),
	.rstb(~rst_n),
	.dina(inData),
	.doutb(outData),
	.wea(we),
	.enb(1'b1),
	.ena(1'b1),
	.sleep(1'b0),
	.injectsbiterra(1'b0),
	.injectdbiterra(1'b0),
	.regceb(1'b1)
	);
`endif

`ifndef _FPGA

	sim_dpram_byteen #(
		.WIDTH(dataWidth),
		.DEPTH(ramSize)
	) instanceSdpram (
	.clka(clk),
	.clkb(clk),

	.addra(addressA),
	.addrb(addressB),
	.rstb(1'b0),
	.dina(inData),
	.doutb(outData),
	.wea(we),
	.enb(1'b1),
	.ena(1'b1),
	.sleep(1'b0),
	.injectsbiterra(1'b0),
	.injectdbiterra(1'b0),
	.regceb(1'b1)
	);

`endif

endmodule // simpleDualPortRamByteen
