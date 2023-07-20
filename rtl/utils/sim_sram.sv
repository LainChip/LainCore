`include "common.svh"
module sim_sram
#( 
    parameter int WIDTH = 32,
    parameter int DEPTH = 256
)
( 
    input  [$clog2(DEPTH) - 1 : 0] addra,
    input                          clka,
    input  [WIDTH - 1:0]           dina,
    output [WIDTH - 1:0]           douta,
    input                          ena,
    input                          wea
);

reg [WIDTH - 1:0] mem_reg [DEPTH - 1:0];
reg [WIDTH - 1:0] output_buffer;

always @(posedge clka) begin
    if (ena) begin
        if (wea) begin
            mem_reg[addra] <= dina;
        end
        else begin
            output_buffer <= mem_reg[addra];
        end
    end
end

assign douta = output_buffer;

endmodule