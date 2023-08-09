`include "pipeline.svh"

// 注意： 这个模块并不会在复位时候清空 tlb 表项
// 当启用 OPT 之后，需要两个周期完成表项的更新。
module tlb_match_single #(
  parameter bit ENABLE_OPT = 1'b0,
  parameter bit ENABLE_RST = 1'b1
) (
  input  logic        clk         ,
  input  logic        rst_n       ,
  input  logic [18:0] vppn_i      ,
  input  logic [ 9:0] asid_i      ,
  output logic        match_o     , // 纯组合逻辑输出
  input  logic        update_i    ,
  input  tlb_key_t    update_key_i
);

  logic match_high10,match_low10,match_asid;
  tlb_key_t key_q;
  logic is_4m_page_q;
  always_ff @(posedge clk) begin
    if(ENABLE_RST && !rst_n) begin
      key_q.e <= '0;
    end else begin
      if(update_i) begin
        key_q        <= update_key_i;
        is_4m_page_q <= update_key_i.ps == 6'd22;
      end
    end
  end
  if(ENABLE_OPT) begin
    // TODO: checkme
    cam_cmp_lutram #(.PACKS_OF_5_BITS(2)) cmp_high10 (
      .clk            (clk                               ),
      .rst_n          (rst_n                             ),
      .update_i       (update_i || (ENABLE_RST && !rst_n)),
      .set_key_i      ({'0, update_key_i.vppn[18:10]}               ),
      .set_key_valid_i(rst_n                             ),
      .cmp_key_i      ({'0, vppn_i[18:10]}               ),
      .hit_o          (match_high10                      )
    );
    cam_cmp_lutram #(.PACKS_OF_5_BITS(2)) cmp_low10 (
      .clk            (clk                               ),
      .rst_n          (rst_n                             ),
      .update_i       (update_i || (ENABLE_RST && !rst_n)),
      .set_key_i      (update_key_i.vppn[9:0]            ),
      .set_key_valid_i(rst_n                             ),
      .cmp_key_i      (vppn_i[9:0]                       ),
      .hit_o          (match_low10                       )
    );
    cam_cmp_lutram #(.PACKS_OF_5_BITS(2)) cmp_asid (
      .clk            (clk                               ),
      .rst_n          (rst_n                             ),
      .update_i       (update_i || (ENABLE_RST && !rst_n)),
      .set_key_i      (update_key_i.asid[9:0]            ),
      .set_key_valid_i(rst_n                             ),
      .cmp_key_i      (vppn_i[9:0]                       ),
      .hit_o          (match_asid                        )
    );
  end else begin
    assign match_high10 = key_q.vppn[18:10] == vppn_i[18:10];
    assign match_low10  = key_q.vppn[9:0] == vppn_i[9:0];
    assign match_asid   = key_q.asid == asid_i;
  end
  always_comb begin
    if(key_q.e &&
      match_high10 && // 4M match
      (/*key_q.ps == 6'd22 */is_4m_page_q || match_low10) && // is 4M page || 4K match
      (key_q.g || match_asid) // 7-1 两级逻辑
    ) begin
      match_o = '1;
    end else begin
      match_o = '0;
    end
  end

endmodule
