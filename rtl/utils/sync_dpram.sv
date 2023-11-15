`include "common.svh"

// New wrapper for FPGA / Verilator / ASIC
// we_i also handle READ-WRITE contention in this module.
// Behavior is WRITE-FIRST.
module sync_dpram #(
  parameter int unsigned DATA_WIDTH = 32  ,
  parameter int unsigned DATA_DEPTH = 1024,
  parameter int unsigned BYTE_SIZE  = 32
) (
  input                                    clk    ,
  input                                    rst_n  ,
  input  wire [    $clog2(DATA_DEPTH)-1:0] waddr_i,
  input  wire [(DATA_WIDTH/BYTE_SIZE)-1:0] we_i   ,
  input  wire [    $clog2(DATA_DEPTH)-1:0] raddr_i,
  input  wire                              re_i   ,
  input  wire [            DATA_WIDTH-1:0] wdata_i,
  output wire [            DATA_WIDTH-1:0] rdata_o
);

  wire [DATA_WIDTH-1:0] rdata0_q,rdata1_q;
  wire                  re      ;

  reg contention_q;

  assign rdata_o = contention_q ? rdata1_q : rdata0_q;
  assign re      = re_i && (waddr_i != raddr_i);
  always_ff @(posedge clk) begin
    contention_q <= re_i && (waddr_i == raddr_i);
  end

  tdpsram_wrapper #(
    .DATA_WIDTH(DATA_WIDTH),
    .DATA_DEPTH(DATA_DEPTH),
    .BYTE_SIZE (BYTE_SIZE )
  ) tdpsram (
    // PORT 0 FOR READ
    .clk0    (clk     ),
    .rst_n0  (rst_n   ),
    .addr0_i (raddr_i ),
    .en0_i   (re      ),
    .we0_i   (1'b0    ),
    .wdata0_i('0      ),
    .rdata0_o(rdata0_q),
    // PORT 1 FOR WRITE
    .clk1    (clk     ),
    .rst_n1  (rst_n   ),
    .addr1_i (waddr_i ),
    .en1_i   (1'b1    ),
    .we1_i   (we_i    ),
    .wdata1_i(wdata_i ),
    .rdata1_o(rdata1_q)
  );

endmodule // dualPortRam
