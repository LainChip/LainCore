`include "common.svh"

module sim_dpram
  #(
     parameter int WIDTH = 32,
     parameter int DEPTH = 256,
     parameter int LATENCY = 1
   )
   (
     input                          clka,
     input                          clkb,
     input  [$clog2(DEPTH) - 1 : 0] addra,
     input  [$clog2(DEPTH) - 1 : 0] addrb,
     input                          rstb,
     input  [WIDTH - 1:0]           dina,
     output [WIDTH - 1:0]           doutb,
     input                          wea,
     input                          ena,
     input                          enb,
     input                          sleep,
     input                          injectsbiterra,
     input                          injectdbiterra,
     input                          regceb
   );

  reg  [WIDTH - 1:0] ram [DEPTH - 1:0];

  logic [$clog2(DEPTH) - 1 : 0] rd_addr_buf;

  if(LATENCY == 1) begin
    always @(posedge clkb) begin
      if (enb) begin
        rd_addr_buf <= addrb;
      end
    end
  end
  else begin
    assign rd_addr_buf = addrb;
  end

  always @(posedge clka) begin
    if (ena && wea) begin
      ram[addra] <= dina;
    end
  end

  assign doutb = ram[rd_addr_buf];
endmodule
