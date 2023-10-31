`include "common.svh"

// New wrapper for FPGA / Verilator / ASIC
// we_i also handle READ-WRITE contention in this module.
// Behavior is WRITE-FIRST.
module sync_dpram #(
  parameter int  unsigned DATA_WIDTH = 32                    ,
  parameter int  unsigned DATA_DEPTH = 1024                  ,
  parameter int  unsigned BYTE_SIZE  = 32                    ,
  // DO NOT MODIFY THIS !
  parameter type          dataType   = logic [DATA_WIDTH-1:0]
) (
  input                                     clk    ,
  input                                     rst_n  ,
  input  logic [    $clog2(DATA_DEPTH)-1:0] waddr_i,
  input        [(DATA_WIDTH/BYTE_SIZE)-1:0] we_i   ,
  input  logic [    $clog2(DATA_DEPTH)-1:0] raddr_i,
  input  logic                              re_i   ,
  input  dataType                           wdata_i,
  output dataType                           rdata_o
);

  wire contention;
  assign contention = re_i && (waddr_i == raddr_i);
  assign re = re_i && !contention;
  // rdata may have 1-3ns~ delay
  dataType rdata_q;

  // rdata_o may have 3ns~ delay
  assign rdata_o = rdata_q;

`ifdef _FPGA
  wire[(DATA_WIDTH/BYTE_SIZE)-1:0][BYTE_SIZE - 1:0] wdata_split, rdata_split_raw, rdata_split_q;
  assign wdata_split = wdata_i;
  assign rdata_q = rdata_split_q;
  xpm_memory_sdpram #(
    .ADDR_WIDTH_A       ($clog2(DATA_DEPTH)     ),
    .ADDR_WIDTH_B       ($clog2(DATA_DEPTH)     ),
    .AUTO_SLEEP_TIME    (0                      ),
    .BYTE_WRITE_WIDTH_A (BYTE_SIZE              ),
    .CLOCKING_MODE      ("common_clock"         ),
    .ECC_MODE           ("no_ecc"               ),
    .MEMORY_INIT_FILE   ("none"                 ),
    .MEMORY_INIT_PARAM  ("0"                    ),
    .MEMORY_OPTIMIZATION("true"                 ),
    .USE_MEM_INIT       (0                      ),
    .MESSAGE_CONTROL    (0                      ),
    
    .MEMORY_PRIMITIVE   ("auto"                 ),
    
    .MEMORY_SIZE        (DATA_WIDTH * DATA_DEPTH),
    
    .READ_DATA_WIDTH_B  (DATA_WIDTH             ),
    .READ_LATENCY_B     (1                      ),
    .WRITE_DATA_WIDTH_A (DATA_WIDTH             ),
    .WRITE_MODE_B       ("read_first"           )
  ) instanceSdpram (
    .clka          (clk    ),
    .clkb          (clk    ),
    .waddr         (waddr_i),
    .raddr         (raddr_i),
    .rstb          (~rst_n ),
    .wdata         (wdata_i),
    .doutb         (rdata_split_raw),
    .wea           (we_i   ),
    .enb           (1'b1   ),
    .ena           (1'b1   ),
    .sleep         (1'b0   ),
    .injectsbiterra(1'b0   ),
    .injectdbiterra(1'b0   ),
    .regceb        (1'b1   )
  );
  for(genvar i = 0 ; i < (DATA_WIDTH/BYTE_SIZE) ; i += 1) begin
    reg [BYTE_SIZE - 1:0] wdata_q;
    reg sel_q;
    always @(posedge clk) begin
      sel_q <= !re && we_i[i];
      wdata_q <= wdata_split[i];
    end
    assign rdata_split_q[i] = sel_q ? wdata_q : rdata_split_raw[i];
  end
`endif

`ifdef _VERILATOR
  reg [(DATA_WIDTH/BYTE_SIZE)-1:0][BYTE_SIZE - 1:0] sim_ram[DATA_DEPTH-1:0];
  wire[(DATA_WIDTH/BYTE_SIZE)-1:0][BYTE_SIZE - 1:0] wdata_split, rdata_split_q;
  assign wdata_split = wdata_i;
  assign rdata_q = rdata_split_q;
  for(genvar i = 0 ; i < (DATA_WIDTH/BYTE_SIZE) ; i += 1) begin
    always @(posedge clk) begin
      if (we_i[i]) begin
        sim_ram[waddr_i][i] <= wdata_split[i];
      end
    end
    always @(posedge clk) begin
      if(re || !we_i[i]) begin
        rdata_split_q[i] <= sim_ram[raddr_i][i];
      end else begin
        rdata_split_q[i] <= wdata_split[i];
      end
    end
  end
`endif

// ASIC BEGINS HERE, WE CHECK AND USE PROPER MODULE WE WANT HERE.

endmodule // dualPortRam
