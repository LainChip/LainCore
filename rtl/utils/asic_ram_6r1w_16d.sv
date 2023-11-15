// THIS MODULE IS ASIC & SIMULATOR ONLY

module asic_ram_6r1w_16d #(
    parameter int WIDTH = 32,
    parameter bit RESET_NEED = 1'b1,
    parameter bit ONLY_RESET_ZERO = 1'b1
)( 
    input                          clk,
    input                          rst_n,
    input  [3 : 0] addr0,
    input  [3 : 0] addr1,
    input  [3 : 0] addr2,
    input  [3 : 0] addr3,
    input  [3 : 0] addr4,
    input  [3 : 0] addr5,
    input  [3 : 0] addrw,
    output [WIDTH - 1:0]           dout0,
    output [WIDTH - 1:0]           dout1,
    output [WIDTH - 1:0]           dout2,
    output [WIDTH - 1:0]           dout3,
    output [WIDTH - 1:0]           dout4,
    output [WIDTH - 1:0]           dout5,
    input  [WIDTH - 1:0]           din,
    input                          wea
);

    reg [WIDTH - 1:0] ram[15:0];
    assign dout0 = ram[addr0];
    assign dout1 = ram[addr1];
    assign dout2 = ram[addr2];
    assign dout3 = ram[addr3];
    assign dout4 = ram[addr4];
    assign dout5 = ram[addr5];
    for(genvar i = 0 ; i < 16; i+=1) begin
        always @(posedge clk) begin
            if(RESET_NEED && (!ONLY_RESET_ZERO || i == 0) && !rst_n) begin
                ram[i[3:0]] <= '0;
            end else if(wea && i[3:0] == addrw) begin
                ram[i[3:0]] <= din;
            end
        end
    end

endmodule