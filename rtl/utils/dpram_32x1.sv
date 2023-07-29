module dpram_32x1(
    input  wire        CLK,
    input  wire        RST,
    input  wire        WEN,
    input  wire [4:0] A,
    input  wire [4:0] AW,
    input  wire  DI,
    output wire  DO
);

wire [1:0] Q3;

`ifdef _FPGA
    RAM32X1D #(
    .INIT(32'h00000000),    // Initial contents of RAM
    .IS_WCLK_INVERTED(1'b0) // Specifies active high/low WCLK
    ) RAM32X1D_inst (
    .DPO(DO),     // Read-only 1-bit data output
    .SPO(),     // Rw/ 1-bit data output
    .A0(A[0]),       // Rw/ address[0] input bit
    .A1(A[1]),       // Rw/ address[1] input bit
    .A2(A[2]),       // Rw/ address[2] input bit
    .A3(A[3]),       // Rw/ address[3] input bit
    .A4(A[4]),       // Rw/ address[4] input bit
    .D(DI),         // Write 1-bit data input
    .DPRA0(AW[0]), // Read-only address[0] input bit
    .DPRA1(AW[1]), // Read-only address[1] input bit
    .DPRA2(AW[2]), // Read-only address[2] input bit
    .DPRA3(AW[3]), // Read-only address[3] input bit
    .DPRA4(AW[4]), // Read-only address[4] input bit
    .WCLK(CLK),   // Write clock input
    .WE(WEN)        // Write enable input
    );
`endif

`ifndef _FPGA

    reg [31:0] d_q;
    assign DO = d_q[A];
    always_ff @(posedge CLK) begin
        if(RST) begin
            d_q <= '0;
        end
        else if(WEN) begin
            d_q[AW] <= DI;
        end
    end

`endif

endmodule
