`include "common.svh"

// New wrapper for FPGA / Verilator / ASIC
// 1-latency-fixed
module sync_spram #(
  parameter int  unsigned DATA_WIDTH = 32                    ,
  parameter int  unsigned DATA_DEPTH = 1024                  ,
  parameter int  unsigned BYTE_SIZE  = 32
) (
  input                                     clk    ,
  input                                     rst_n  ,
  input  logic [    $clog2(DATA_DEPTH)-1:0] addr_i ,
  input  logic [(DATA_WIDTH/BYTE_SIZE)-1:0] we_i   ,
  input  logic [DATA_WIDTH-1:0]                           wdata_i,
  output logic [DATA_WIDTH-1:0]                           rdata_o
);

`ifdef _FPGA
  logic [(DATA_WIDTH/BYTE_SIZE)-1:0][BYTE_SIZE-1:0] rdata_split_raw,rdata_split,wdata_split_q;
  logic [(DATA_WIDTH/BYTE_SIZE)-1:0] we_q;
  assign rdata_o = rdata_split;
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
    .waddr         (addr_i ),
    .raddr         (addr_i ),
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
  always_ff @(posedge clk) begin
    wdata_split_q <= wdata_i;
    we_q <= we_i;
  end
  for (genvar i = 0 ; i < (DATA_WIDTH/BYTE_SIZE) ; i += 1) begin
    assign rdata_split[i] = we_q[i] ? wdata_split_q[i] : rdata_split_raw[i];
  end
`endif

`ifdef _VERILATOR
  reg [(DATA_WIDTH/BYTE_SIZE)-1:0][BYTE_SIZE - 1:0] sim_ram[DATA_DEPTH-1:0];
  wire[(DATA_WIDTH/BYTE_SIZE)-1:0][BYTE_SIZE - 1:0] wdata_split, rdata_split;
  assign wdata_split = wdata_i;
  assign rdata_o = rdata_split;
  for(genvar i = 0 ; i < (DATA_WIDTH/BYTE_SIZE) ; i += 1) begin
    always @(posedge clk) begin
      if (we_i[i]) begin
        sim_ram[addr_i][i] <= wdata_split[i];
      end
    end
    always @(posedge clk) begin
      if(re || !we_i[i]) begin
        rdata_split[i] <= sim_ram[addr_i][i];
      end else begin
        rdata_split[i] <= wdata_split[i];
      end
    end
  end
`endif

// ASIC BEGINS HERE, WE CHECK AND USE PROPER MODULE WE WANT HERE.
`ifdef _ASIC
  asic_spsram_wrapper#(
    .DATA_WIDTH,
    .DATA_DEPTH,
    .BYTE_SIZE
  )(
    .clk,
    .rst_n,
    .addr_i,
    .we_i,
    .wdata_i,
    .rdata_o
  );
`endif

endmodule // dualPortRam
