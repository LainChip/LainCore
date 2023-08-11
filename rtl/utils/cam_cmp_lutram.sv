// 注意：这个模块的查询是立即的，但更新需要两个周期

module cam_cmp_lutram #(parameter int PACKS_OF_5_BITS = 4) (
  input  logic                            clk            ,
  input  logic                            rst_n          ,
  input  logic                            update_i       , // 注意，update 之后两个周期才可以生效
  input  logic [PACKS_OF_5_BITS-1:0][4:0] set_key_i      ,
  input  logic                            set_key_valid_i,
  input  logic [PACKS_OF_5_BITS-1:0][4:0] cmp_key_i      ,
  output logic                            hit_o          ,
  output logic [PACKS_OF_5_BITS-1:0][4:0] key_o
);
  logic[PACKS_OF_5_BITS - 1 :0] sub_hit;
  assign hit_o = &sub_hit;
  logic [PACKS_OF_5_BITS-1:0][4:0] w_addr_q;
  // 注意：若 w_addr_q 被清零，则出现错误，每次 UPDATE 时一定要清零上次的结果
  assign key_o = w_addr_q;
  logic refill_v_q, refill_q;
  always_ff @(posedge clk) begin
    if(update_i) begin
      w_addr_q <= set_key_i;
      refill_q <= set_key_valid_i;
      refill_v_q <= '1;
    end else begin
      refill_q <= '0;
      refill_v_q <= '0;
    end
  end

  for(genvar i = 0 ; i < 4 ; i ++) begin
    dpram_32x1  dpram_32x1_inst (
      .CLK(clk),
      .RST(~rst_n),
      .WEN(update_i | refill_v_q),
      .A(cmp_ky_i[i]),
      .AW(w_addr_q[i]),
      .DI(refill_q),
      .DO(sub_hit[i])
    );
  end

endmodule
