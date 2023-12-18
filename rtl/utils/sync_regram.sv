`include "common.svh"

// New wrapper for FPGA / Verilator / ASIC
// regmem is 0-latency
module sync_regram #(
  parameter int unsigned DATA_WIDTH = 32  ,
  parameter int unsigned DATA_DEPTH = 1024,
  parameter bit NEED_RESET = 0
) (
  input                                 clk    ,
  input                                 rst_n  ,
  input  logic [$clog2(DATA_DEPTH)-1:0] waddr_i,
  input  logic                          we_i   ,
  input  logic [$clog2(DATA_DEPTH)-1:0] raddr_i,
  input  logic [        DATA_WIDTH-1:0] wdata_i,
  output logic [        DATA_WIDTH-1:0] rdata_o
);

  reg[DATA_DEPTH - 1 : 0][DATA_WIDTH - 1 : 0] regfile;
  for(genvar i = 0 ; i < DATA_DEPTH ; i++) begin
    always_ff @(posedge clk) begin
      if(NEED_RESET && ~rst_n) begin
        regfile[i[$clog2(DATA_DEPTH)-1:0]] <= '0;
      end else if(we_i && i[$clog2(DATA_DEPTH)-1:0] == waddr_i) begin
        regfile[i[$clog2(DATA_DEPTH)-1:0]] <= wdata_i;
      end
    end
  end
  assign rdata_o = regfile[raddr_i];

endmodule // dualPortRam
