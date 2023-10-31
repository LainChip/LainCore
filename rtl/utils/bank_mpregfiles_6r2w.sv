module bank_mpregfiles_6r2w #(
    parameter int WIDTH = 32,
    parameter bit RESET_NEED = 1'b1,
    parameter bit ONLY_RESET_ZERO = 1'b1
)(
    input clk,
    input rst_n,
    input wire[4:0] ra0_i,
    input wire[4:0] ra1_i,
    input wire[4:0] ra2_i,
    input wire[4:0] ra3_i,
    input wire[4:0] ra4_i,
    input wire[4:0] ra5_i,

    input wire[4:0] wa0_i,
    input wire[4:0] wa1_i,
    input wire we0_i,
    input wire we1_i,

    output wire[WIDTH - 1 : 0] rd0_o,
    output wire[WIDTH - 1 : 0] rd1_o,
    output wire[WIDTH - 1 : 0] rd2_o,
    output wire[WIDTH - 1 : 0] rd3_o,
    output wire[WIDTH - 1 : 0] rd4_o,
    output wire[WIDTH - 1 : 0] rd5_o,

    input wire[WIDTH - 1 : 0] wd0_i,
    input wire[WIDTH - 1 : 0] wd1_i,

    output wire conflict_o
);

    // `ifndef _FPGA
    //     initial begin
    //     	$dumpfile("logs/vlt_dump.vcd");
    //     	$dumpvars();
    //     end
    // `endif

    logic[4:0] wa_0,wa_1;
    logic[WIDTH - 1 : 0] rd0_0,rd1_0,rd2_0,rd3_0,rd4_0,rd5_0;
    logic[WIDTH - 1 : 0] rd0_1,rd1_1,rd2_1,rd3_1,rd4_1,rd5_1;
    logic[WIDTH - 1 : 0] wd_0,wd_1;
    logic we_0,we_1;

    logic[3:0] rst_cnt_q;   // 2 banks and each manage 16 regs, at most 16 cycles
    if(RESET_NEED && !ONLY_RESET_ZERO) begin
        always @(posedge clk) begin
            if(~rst_n) begin
                rst_cnt_q <= rst_cnt_q + 4'd1;
            end else begin
                rst_cnt_q <= '0;
            end
        end
    end else begin
        assign rst_cnt_q = '0;
    end

    /* read port out mux */
    la_mux2 #(WIDTH)output_mux0(rd0_0,rd0_1,rd0_o,ra0_i[0]);
    la_mux2 #(WIDTH)output_mux1(rd1_0,rd1_1,rd1_o,ra1_i[0]);
    la_mux2 #(WIDTH)output_mux2(rd2_0,rd2_1,rd2_o,ra2_i[0]);
    la_mux2 #(WIDTH)output_mux3(rd3_0,rd3_1,rd3_o,ra3_i[0]);
    la_mux2 #(WIDTH)output_mux4(rd4_0,rd4_1,rd4_o,ra4_i[0]);
    la_mux2 #(WIDTH)output_mux5(rd5_0,rd5_1,rd5_o,ra5_i[0]);

    assign conflict_o = wa0_i[0] == wa1_i[0];

    /* write port in mux */
    la_mux2 #(WIDTH + 6)write_mux0({wa0_i[4:0],wd0_i,we0_i},{wa1_i[4:0],wd1_i,we1_i},{wa_0,wd_0,we_0},!we0_i || wa0_i[0]);
    la_mux2 #(WIDTH + 6)write_mux1({wa1_i[4:0],wd1_i,we1_i},{wa0_i[4:0],wd0_i,we0_i},{wa_1,wd_1,we_1}, we0_i && wa0_i[0]);
    // FIX: 0 端口有更高的优先级

    `ifdef _FPGA
    /* bank0 : manage even addr */
    fpga_ram_3r1w_32d qram_b0_0(
        .clk,
        .addr0(ra0_i[4:0]),
        .addr1(ra1_i[4:0]),
        .addr2(ra2_i[4:0]),
        .addrw({rst_cnt_q, 1'b0} ^ (wa_0 & {5{rst_n}})),
        .dout0(rd0_0),
        .dout1(rd1_0),
        .dout2(rd2_0),
        .din((rst_n || !RESET_NEED) ? wd_0 : '0),
        .wea(we_0 || (~rst_n && RESET_NEED))
    );
    fpga_ram_3r1w_32d qram_b0_1(
        .clk,
        .addr0(ra3_i[4:0]),
        .addr1(ra4_i[4:0]),
        .addr2(ra5_i[4:0]),
        .addrw({rst_cnt_q, 1'b0} ^ (wa_0 & {5{rst_n}})),
        .dout0(rd3_0),
        .dout1(rd4_0),
        .dout2(rd5_0),
        .din((rst_n || !RESET_NEED) ? wd_0 : '0),
        .wea(we_0 || (~rst_n && RESET_NEED))
    );

    /* bank1 : manage odd addr */
    fpga_ram_3r1w_32d qram_b1_0(
        .clk,
        .addr0(ra0_i[4:0]),
        .addr1(ra1_i[4:0]),
        .addr2(ra2_i[4:0]),
        .addrw({rst_cnt_q, ~rst_n} ^ (wa_1 & {5{rst_n}})),
        // or .addrw(rst_n ? wa_1 : {rst_cnt_q, 1'b1}),
        .dout0(rd0_1),
        .dout1(rd1_1),
        .dout2(rd2_1),
        .din((rst_n || !RESET_NEED) ? wd_1 : '0),
        .wea(we_1 || (~rst_n && RESET_NEED))
    );
    fpga_ram_3r1w_32d qram_b1_1(
        .clk,
        .addr0(ra3_i[4:0]),
        .addr1(ra4_i[4:0]),
        .addr2(ra5_i[4:0]),
        .addrw({rst_cnt_q, ~rst_n} ^ (wa_1 & {5{rst_n}})),
        .dout0(rd3_1),
        .dout1(rd4_1),
        .dout2(rd5_1),
        .din((rst_n || !RESET_NEED) ? wd_1 : '0),
        .wea(we_1 || (~rst_n && RESET_NEED))
    );
    `else
    // ASIC AND VERILATOR SITUATION.
    asic_ram_6r1w_16d #(WIDTH) ram_b0(
        .clk,
        .addr0(ra0_i[4:1]),
        .addr1(ra1_i[4:1]),
        .addr2(ra2_i[4:1]),
        .addr3(ra3_i[4:1]),
        .addr4(ra4_i[4:1]),
        .addr5(ra5_i[4:1]),
        .addrw(wa_0[4:1]),
        .dout0(rd0_0),
        .dout1(rd1_0),
        .dout2(rd2_0),
        .dout3(rd3_0),
        .dout4(rd4_0),
        .dout5(rd5_0),
        .din(wd_0),
        .wea(we_0 && !wa_0[0])
    );
    asic_ram_6r1w_16d #(WIDTH) ram_b1(
        .clk,
        .addr0(ra0_i[4:1]),
        .addr1(ra1_i[4:1]),
        .addr2(ra2_i[4:1]),
        .addr3(ra3_i[4:1]),
        .addr4(ra4_i[4:1]),
        .addr5(ra5_i[4:1]),
        .addrw(wa_1[4:1]),
        .dout0(rd0_1),
        .dout1(rd1_1),
        .dout2(rd2_1),
        .dout3(rd3_1),
        .dout4(rd4_1),
        .dout5(rd5_1),
        .din(wd_1),
        .wea(we_1 && wa_1[0])
    );
    `endif
endmodule