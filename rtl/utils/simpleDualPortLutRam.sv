module simpleDualPortLutRam
  #(
     parameter int unsigned dataWidth = 32,
     parameter int unsigned ramSize = 1024,
     parameter type dataType = logic [dataWidth-1:0],
     parameter int unsigned latency = 1,
     parameter int readMuler = 1
   ) (
     input clk,    // Clock
     input rst_n,  // Asynchronous reset active low
     input logic[$clog2(ramSize) - 1 : 0] addressA,
     input we,
     input logic[$clog2(ramSize) - $clog2(readMuler) - 1: 0]addressB,
     input re,
     input dataType inData,
     output dataType [readMuler-1:0] outData
   );

`ifdef _FPGA
  xpm_memory_sdpram
    #(
      .ADDR_WIDTH_A($clog2(ramSize)),
      .ADDR_WIDTH_B($clog2(ramSize) - $clog2(readMuler)),
      .AUTO_SLEEP_TIME(0),
      .BYTE_WRITE_WIDTH_A(dataWidth),
      .CLOCKING_MODE("common_clock"),
      .ECC_MODE("no_ecc"),
      .MEMORY_INIT_FILE("none"),
      .MEMORY_INIT_PARAM("0"),
      .MEMORY_OPTIMIZATION("true"),
      .USE_MEM_INIT(0),
      .MESSAGE_CONTROL(0),

      .MEMORY_PRIMITIVE("distributed"),

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
      .enb(re),
      .ena(1'b1),
      .sleep(1'b0),
      .injectsbiterra(1'b0),
      .injectdbiterra(1'b0),
      .regceb(re)
    );

`endif

  `ifndef _FPGA
            sim_dpram #(
                        .WIDTH(dataWidth),
                        .DEPTH(ramSize),
						.LATENCY(latency)
                      )instanceSdpram(
                        .clka(clk),
                        .clkb(clk),

                        .addra(addressA),
                        .addrb(addressB),
                        .rstb(1'b0),
                        .dina(inData),
                        .doutb(outData),
                        .wea(we),
                        .enb(re),
                        .ena(we),
                        .sleep(1'b0),
                        .injectsbiterra(1'b0),
                        .injectdbiterra(1'b0),
                        .regceb(re)
                      );

`endif

        endmodule // simpleDualPortRam
