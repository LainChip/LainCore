module qpram_32x2(
    input  wire        CLK,
    input  wire        CEN, 
    input  wire        WEN,
    input  wire [4:0] A0,
    input  wire [4:0] A1,
    input  wire [4:0] A2,
    input  wire [4:0] AW,
    input  wire [1:0] DI,
    output wire [1:0] Q0,
    output wire [1:0] Q1,
    output wire [1:0] Q2
);

wire [1:0] Q3;

`ifdef _FPGA
    RAM32M #(
    .INIT_A(64'h0000000000000000), // Initial contents of A Port
    .INIT_B(64'h0000000000000000), // Initial contents of B Port
    .INIT_C(64'h0000000000000000), // Initial contents of C Port
    .INIT_D(64'h0000000000000000), // Initial contents of D Port
    .IS_WCLK_INVERTED(1'b0) // Specifies active high/low WCLK
    ) RAM32M_inst (
    .DOA(Q0), // Read port A 2-bit output
    .DOB(Q1), // Read port B 2-bit output
    .DOC(Q2), // Read port C 2-bit output
    .DOD(Q3), // Read/write port D 2-bit output
    .ADDRA(A0), // Read port A 5-bit address input
    .ADDRB(A1), // Read port B 5-bit address input
    .ADDRC(A2), // Read port C 5-bit address input
    .ADDRD(AW), // Read/write port D 5-bit address input
    .DIA(DI), // RAM 2-bit data write input addressed by ADDRD,
    // read addressed by ADDRA
    .DIB(DI), // RAM 2-bit data write input addressed by ADDRD,
    // read addressed by ADDRB
    .DIC(DI), // RAM 2-bit data write input addressed by ADDRD,
    // read addressed by ADDRC
    .DID(DI), // RAM 2-bit data write input addressed by ADDRD,
    // read addressed by ADDRD
    .WCLK(CLK), // Write clock input
    .WE(WEN) // Write enable input
    );

`endif

`ifndef _FPGA

    reg [1:0] ram [31:0];
    assign Q0 = ram[A0];
    assign Q1 = ram[A1];
    assign Q2 = ram[A2];
    assign Q3 = ram[AW];
    always @(posedge CLK) begin
        if(WEN) begin
            ram[AW] <= DI;
        end
    end

`endif

endmodule