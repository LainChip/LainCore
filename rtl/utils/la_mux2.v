module la_mux2 #(
    parameter WIDTH = 32
)(
    input wire[WIDTH - 1 : 0] d0_i,
    input wire[WIDTH - 1 : 0] d1_i,
    output wire[WIDTH - 1 : 0] r_o,
    input wire sel_i
);

    assign r_o = sel_i ? d1_i : d0_i;

endmodule
