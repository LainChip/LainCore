module reg_file #(parameter int DATA_WIDTH = 32) (
  input  logic                       clk     ,
  input  logic                       rst_n   ,
  // read port
  input  logic [3:0][           4:0] r_addr_i,
  output logic [3:0][DATA_WIDTH-1:0] r_data_o,
  // write port
  input  logic [1:0][           4:0] w_addr_i,
  input  logic [1:0][DATA_WIDTH-1:0] w_data_i,
  input  logic [1:0]                 w_en_i
);
  localparam READ_PORT  = 4;
  localparam WRITE_PORT = 2;

  bank_mpregfiles_4r2w #(
    .WIDTH     (DATA_WIDTH),
    .RESET_NEED(1'b1      )
  ) mp_regfile (
    .clk                                         ,
    .rst_n                                       ,
    // read port
    .ra0_i     (r_addr_i[0]                     ),
    .ra1_i     (r_addr_i[1]                     ),
    .ra2_i     (r_addr_i[2]                     ),
    .ra3_i     (r_addr_i[3]                     ),
    .rd0_o     (r_data_o[0]                     ),
    .rd1_o     (r_data_o[1]                     ),
    .rd2_o     (r_data_o[2]                     ),
    .rd3_o     (r_data_o[3]                     ),
    // write port
    .wd0_i     (w_data_i[0]                     ),
    .wd1_i     (w_data_i[1]                     ),
    .wa0_i     (w_addr_i[0]                     ),
    .wa1_i     (w_addr_i[1]                     ),
    .we0_i     (w_en_i[0] & ~(w_addr_i[0] == '0)),
    .we1_i     (w_en_i[1] & ~(w_addr_i[1] == '0)),
    // signal
    .conflict_o(                                )
  );

    `ifdef _DIFFTEST_ENABLE
  logic[31:0][31:0] ref_regs;
  for(genvar i = 0 ; i < 32 ; i ++) begin
    always_ff @(posedge clk) begin
      if(!rst_n) begin
        ref_regs[i] <= '0;
      end else if(w_en_i[0] && w_addr_i[0] == i[4:0] && i != 0) begin
        ref_regs[i] <= w_data_i[0];
      end else if(w_en_i[1] && w_addr_i[1] == i[4:0] && i != 0) begin
        ref_regs[i] <= w_data_i[1];
      end
    end
  end
  DifftestGRegState DifftestGRegState (
    .clock (clk         ),
    .coreid(0           ),
    .gpr_0 (ref_regs[0] ),
    .gpr_1 (ref_regs[1] ),
    .gpr_2 (ref_regs[2] ),
    .gpr_3 (ref_regs[3] ),
    .gpr_4 (ref_regs[4] ),
    .gpr_5 (ref_regs[5] ),
    .gpr_6 (ref_regs[6] ),
    .gpr_7 (ref_regs[7] ),
    .gpr_8 (ref_regs[8] ),
    .gpr_9 (ref_regs[9] ),
    .gpr_10(ref_regs[10]),
    .gpr_11(ref_regs[11]),
    .gpr_12(ref_regs[12]),
    .gpr_13(ref_regs[13]),
    .gpr_14(ref_regs[14]),
    .gpr_15(ref_regs[15]),
    .gpr_16(ref_regs[16]),
    .gpr_17(ref_regs[17]),
    .gpr_18(ref_regs[18]),
    .gpr_19(ref_regs[19]),
    .gpr_20(ref_regs[20]),
    .gpr_21(ref_regs[21]),
    .gpr_22(ref_regs[22]),
    .gpr_23(ref_regs[23]),
    .gpr_24(ref_regs[24]),
    .gpr_25(ref_regs[25]),
    .gpr_26(ref_regs[26]),
    .gpr_27(ref_regs[27]),
    .gpr_28(ref_regs[28]),
    .gpr_29(ref_regs[29]),
    .gpr_30(ref_regs[30]),
    .gpr_31(ref_regs[31])
  );
      `endif
endmodule