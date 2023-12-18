`include "common.svh"

// New wrapper for FPGA / Verilator / ASIC
// we_i also handle READ-WRITE contention in this module.
// Behavior is WRITE-FIRST.
module sync_dpram #(
  parameter int unsigned DATA_WIDTH = 32  ,
  parameter int unsigned DATA_DEPTH = 1024,
  parameter int unsigned BYTE_SIZE  = 32,
  parameter bit unsigned AUTO_RESET = 1
) (
  input                                    clk    ,
  input                                    rst_n  ,
  input  wire [    $clog2(DATA_DEPTH)-1:0] waddr_i,
  input  wire [(DATA_WIDTH/BYTE_SIZE)-1:0] we_i   ,
  input  wire [    $clog2(DATA_DEPTH)-1:0] raddr_i,
  input  wire                              re_i   ,
  input  wire [            DATA_WIDTH-1:0] wdata_i,
  output wire [            DATA_WIDTH-1:0] rdata_o,
  output wire                              ready_o
);

  wire [DATA_WIDTH-1:0] rdata0_q,rdata1_q;
  wire                  re      ;

  reg contention_q;

  assign rdata_o = contention_q ? rdata1_q : rdata0_q;
  assign re      = re_i && (!(|we_i) || (waddr_i != raddr_i));
  always_ff @(posedge clk) begin
    contention_q <= re_i && |we_i && (waddr_i == raddr_i);
  end

  logic [$clog2(DATA_DEPTH):0] rst_addr_q;
  if(AUTO_RESET) begin
    always_ff @(posedge clk) begin
      if(!rst_n) begin
        rst_addr_q <= '0;
      end else if(!ready_o) begin
        rst_addr_q <= rst_addr_q + {{($clog2(DATA_DEPTH)){1'd0}},1'd1};
      end
    end
  end else begin
    assign rst_addr_q = {1'd1, {($clog2(DATA_DEPTH)){1'd0}}};
  end
  assign ready_o = rst_addr_q[$clog2(DATA_DEPTH)];

  tdpsram_wrapper #(
    .DATA_WIDTH(DATA_WIDTH),
    .DATA_DEPTH(DATA_DEPTH),
    .BYTE_SIZE (BYTE_SIZE )
  ) tdpsram (
    // PORT 0 FOR READ
    .clk0    (clk     ),
    .rst_n0  (rst_n   ),
    .addr0_i (rst_addr_q[$clog2(DATA_DEPTH)] ? raddr_i : rst_addr_q[$clog2(DATA_DEPTH)-1:0]),
    .en0_i   (re || !rst_addr_q[$clog2(DATA_DEPTH)]),
    .we0_i   ({(DATA_WIDTH/BYTE_SIZE){!rst_addr_q[$clog2(DATA_DEPTH)]}}),
    .wdata0_i('0      ),
    .rdata0_o(rdata0_q),
    // PORT 1 FOR WRITE
    .clk1    (clk     ),
    .rst_n1  (rst_n   ),
    .addr1_i (waddr_i ),
    .en1_i   ((|we_i) && rst_addr_q[$clog2(DATA_DEPTH)]),
    .we1_i   (we_i    ),
    .wdata1_i(wdata_i ),
    .rdata1_o(rdata1_q)
  );

endmodule // dualPortRam
