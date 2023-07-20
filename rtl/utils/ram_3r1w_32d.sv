module ram_3r1w_32d#(
    parameter int WIDTH = 32
)( 
    input                          clk,
    input  [4 : 0] addr0,
    input  [4 : 0] addr1,
    input  [4 : 0] addr2,
    input  [4 : 0] addrw,
    output [WIDTH - 1:0]           dout0,
    output [WIDTH - 1:0]           dout1,
    output [WIDTH - 1:0]           dout2,
    input  [WIDTH - 1:0]           din,
    input                          wea
);

    for(genvar i = 0 ; i < WIDTH / 2; i++) begin
        qpram_32x2 ram_1(
            .CLK(clk),
            .CEN(1'b1), 
            .WEN(wea),
            .A0(addr0),
            .A1(addr1),
            .A2(addr2),
            .AW(addrw),
            .DI(  din[(WIDTH-1 - 2*i) -: 2]),
            .Q0(dout0[(WIDTH-1 - 2*i) -: 2]),
            .Q1(dout1[(WIDTH-1 - 2*i) -: 2]),
            .Q2(dout2[(WIDTH-1 - 2*i) -: 2])
        );
    end
    if((WIDTH % 2) != 0) begin
        qpram_32x2 ram_0(
            .CLK(clk),
            .CEN(1'b1), 
            .WEN(wea),
            .A0(addr0),
            .A1(addr1),
            .A2(addr2),
            .AW(addrw),
            .DI({1'b0,din[0]}),
            .Q0({1'b0,dout0[0]}),
            .Q1({1'b0,dout1[0]}),
            .Q2({1'b0,dout2[0]})
        );
    end

endmodule