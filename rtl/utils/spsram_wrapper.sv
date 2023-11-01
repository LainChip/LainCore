
module spsram_wrapper #(
  parameter int unsigned DATA_WIDTH = 32  ,
  parameter int unsigned DATA_DEPTH = 1024,
  parameter int unsigned BYTE_SIZE  = 32
) (
  input                                     clk    ,
  input                                     rst_n  ,
  input  wire  [    $clog2(DATA_DEPTH)-1:0] addr_i ,
  input                                     en_i   ,
  input        [(DATA_WIDTH/BYTE_SIZE)-1:0] we_i   ,
  input  logic [            DATA_WIDTH-1:0] wdata_i,
  output logic [            DATA_WIDTH-1:0] rdata_o,
);

`ifdef _FPGA
  xpm_memory_tdpram #(
    .ADDR_WIDTH_A       ($clog2(DATA_DEPTH)     ),
    .ADDR_WIDTH_B       ($clog2(DATA_DEPTH)     ),
    .AUTO_SLEEP_TIME    (0                      ), // DECIMAL
    .BYTE_WRITE_WIDTH_A (BYTE_SIZE              ),
    .BYTE_WRITE_WIDTH_B (BYTE_SIZE              ),
    .CASCADE_HEIGHT     (0                      ), // DECIMAL
    .CLOCKING_MODE      ("common_clock"         ),
    .ECC_MODE           ("no_ecc"               ),
    .IGNORE_INIT_SYNTH  (0                      ), // DECIMAL
    .MEMORY_INIT_FILE   ("none"                 ),
    .MEMORY_INIT_PARAM  ("0"                    ),
    .MEMORY_OPTIMIZATION("true"                 ),
    .MEMORY_PRIMITIVE   ("auto"                 ), // String
    .MEMORY_SIZE        (DATA_WIDTH * DATA_DEPTH),
    .MESSAGE_CONTROL    (0                      ), // DECIMAL
    .RAM_DECOMP         ("auto"                 ), // String
    .READ_DATA_WIDTH_A  (DATA_WIDTH             ),
    .READ_DATA_WIDTH_B  (DATA_WIDTH             ),
    .READ_LATENCY_A     (1                      ), // DECIMAL
    .READ_LATENCY_B     (1                      ), // DECIMAL
    .USE_MEM_INIT       (0                      ),
    .WRITE_DATA_WIDTH_A (DATA_WIDTH             ),
    .WRITE_DATA_WIDTH_B (DATA_WIDTH             ),
    .WRITE_MODE_A       ("write_first"          ), // String
    .WRITE_MODE_B       ("write_first"          ), // String
    .WRITE_PROTECT      (1                      )  // DECIMAL
  ) xpm_memory_tdpram_inst (
    .douta         (rdata_o         ),
    .doutb         (/* NO CONNECT */),
    .addra         (addr_i          ),
    .addrb         ('0              ),
    .clka          (clk             ),
    .clkb          ('0              ),
    .dina          (wdata_i         ),
    .dinb          ('0              ),
    .ena           (en_i            ),
    .enb           ('0              ),
    .injectdbiterra('0              ),
    .injectdbiterrb('0              ),
    .injectsbiterra('0              ),
    .injectsbiterrb('0              ),
    .regcea        ('1              ),
    .regceb        ('0              ),
    .rsta          (~rst_n          ),
    .rstb          ('0              ),
    .sleep         ('0              ),
    .wea           (we_i            ),
    .web           ('0              )
  );
`endif

`ifdef _VERILATOR
  reg [(DATA_WIDTH/BYTE_SIZE)-1:0][BYTE_SIZE-1:0] sim_ram      [DATA_DEPTH-1:0];
  reg [(DATA_WIDTH/BYTE_SIZE)-1:0][BYTE_SIZE-1:0] rdata_split_q,wdata_split;
  assign wdata_split = wdata_i;
  assign rdata_o     = rdata_split_q;
  // PORT A
  always_ff @(posedge clk) begin
    if(en_i) begin
      for(integer i = 0 ; i < (DATA_WIDTH/BYTE_SIZE) ; i++) begin
        if(we_i[i]) begin
          rdata_split_q[i]   <= wdata_split[i];
          sim_ram[addr_i][i] <= wdata_split[i];
        end else begin
          rdata_split_q[i] <= sim_ram[addr_i][i];
        end
      end
    end
  end
`endif

endmodule