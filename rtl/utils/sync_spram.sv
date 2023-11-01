`include "common.svh"

// New wrapper for FPGA / Verilator / ASIC
// 1-latency-fixed
module sync_spram #(
  parameter int unsigned DATA_WIDTH = 32  ,
  parameter int unsigned DATA_DEPTH = 1024,
  parameter int unsigned BYTE_SIZE  = 32
) (
  input                                     clk    ,
  input                                     rst_n  ,
  input  logic [    $clog2(DATA_DEPTH)-1:0] addr_i ,
  input  logic [(DATA_WIDTH/BYTE_SIZE)-1:0] we_i   ,
  input  logic [            DATA_WIDTH-1:0] wdata_i,
  output logic [            DATA_WIDTH-1:0] rdata_o
);

  spsram_wrapper #(
    .DATA_WIDTH(DATA_WIDTH),
    .DATA_DEPTH(DATA_DEPTH),
    .BYTE_SIZE (BYTE_SIZE )
  ) spsram (
    .clk    (clk    ),
    .rst_n  (rst_n  ),
    .addr_i (addr_i ),
    .en_i   ('1     ),
    .we_i   (we_i   ),
    .wdata_i(wdata_i),
    .rdata_o(rdata_o)
  );

endmodule // dualPortRam
