/*--JSON--{"module_name":"reg_file","module_ver":"2","module_type":"module"}--JSON--*/
module reg_file #(
    parameter int DATA_WIDTH = 32 
)(
    input logic clk,
    input logic  rst_n,
    // read port
    input   logic [3:0][4:0] r_addr_i,
    output  logic [3:0][DATA_WIDTH - 1 : 0] r_data_o,
    // write port
    input   logic [1:0][4:0] w_addr_i,
    input   logic [1:0][DATA_WIDTH - 1 : 0] w_data_i,
    input   logic [1:0] w_en_i
);
    localparam READ_PORT  = 4;
    localparam WRITE_PORT = 2;

    bank_mpregfiles_4r2w #(
        .WIDTH(DATA_WIDTH),
        .RESET_NEED(1'b1)
    ) mp_regfile (
        .clk,
        .rst_n,
        // read port
        .ra0_i(r_addr_i[0]),
        .ra1_i(r_addr_i[1]),
        .ra2_i(r_addr_i[2]),
        .ra3_i(r_addr_i[3]),
        .rd0_o(r_data_o[0]),
        .rd1_o(r_data_o[1]),
        .rd2_o(r_data_o[2]),
        .rd3_o(r_data_o[3]),
        // write port
        .wd0_i(w_data_i[0]),
        .wd1_i(w_data_i[1]),
        .wa0_i(w_addr_i[0]),
        .wa1_i(w_addr_i[1]),
        .we0_i(w_en_i[0] & ~(w_addr_i[0] == '0)),
        .we1_i(w_en_i[1] & ~(w_addr_i[1] == '0)),
        // signal
        .conflict_o()
    );

endmodule