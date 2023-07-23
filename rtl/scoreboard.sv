module scoreboard (
    input logic clk,
    input logic rst_n,

    input logic invalidate_i,
    output logic issue_ready_o,

    input logic [3:0][4:0] is_r_addr_i,
    output logic [3:0][3:0] is_r_id_o,
    output logic [3:0] is_r_valid_o,

    input logic [1:0][4:0] is_w_addr_i,
    input logic [1:0] is_i,
    output logic [2:0] is_w_id_o,
    // 注意： 冲突逻辑交由 issue 模块处理，此模块不考虑可能的任何冲突情况，需要 issue 逻辑保证不会发射两条冲突的指令

    input logic [1:0][4:0] wb_w_addr_i,
    input logic [2:0] wb_w_id_i,
    input logic [1:0] wb_valid_i
  );

  logic invalidate_wait_q;
  logic [2:0] issueboard_tid_q,issueboard_tid;
  logic [1:0][3:0] issueboard_is_w_id;
  logic [3:0][3:0] issueboard_is_r_id;
  logic [3:0][2:0] commitboard_is_r_id;

  // output logic here
  for(genvar i = 0 ; i < 4 ; i ++) begin
    assign is_r_valid_o[i] = issueboard_is_r_id[i][3:1] == commitboard_is_r_id[i];
    assign is_r_id_o[i] = issueboard_is_r_id[i];
  end
  for(genvar i = 0 ; i < 2 ; i ++) begin
    assign issueboard_is_w_id[i] = {issueboard_tid_q,i[0]};
  end
  assign is_w_id_o = issueboard_tid_q;

  // 注意： tid == 0 是保留给 0 号寄存器使用的
  // 在复位，分配tid时，从 tid == 1 开始分配
  // 含义为 不进行转发（数据已就绪）
  // 这里只有一个timer，是两路指令合用的，用最低位区别其在上管线还是下管线。
  always_ff @(posedge clk) begin
    if(!rst_n) begin
      issueboard_tid_q <= 3'd1;
    end
    else begin
      issueboard_tid_q <= issueboard_tid;
    end
  end
  always_comb begin
    issueboard_tid = issueboard_tid_q;
    if(|is_i) begin
      if(issueboard_tid_q == '1) begin
        issueboard_tid = 3'd1;
      end
      else begin
        issueboard_tid = issueboard_tid_q + 1;
      end
    end
  end

  bank_mpregfiles_4r2w #(
                         .WIDTH(4),
                         .RESET_NEED(1'b1),
                         .ONLY_RESET_ZERO(1'b1)
                       ) issue_board (
                         .clk,
                         .rst_n,
                         // read port
                         .ra0_i(is_r_addr_i[0]),
                         .ra1_i(is_r_addr_i[1]),
                         .ra2_i(is_r_addr_i[2]),
                         .ra3_i(is_r_addr_i[3]),
                         .rd0_o(issueboard_is_r_id[0]),
                         .rd1_o(issueboard_is_r_id[1]),
                         .rd2_o(issueboard_is_r_id[2]),
                         .rd3_o(issueboard_is_r_id[3]),
                         // write port
                         .wd0_i(issueboard_is_w_id[0]), // TODO: WRITE DATA
                         .wd1_i(issueboard_is_w_id[1]),
                         .wa0_i(is_w_addr_i[0]),
                         .wa1_i(is_w_addr_i[1]),
                         .we0_i(is_i[0] && (is_w_addr_i[0] != '0)),
                         .we1_i(is_i[1] && (is_w_addr_i[1] != '0)),
                         // signal
                         .conflict_o()
                       );
  bank_mpregfiles_4r2w #(
                         .WIDTH(3),
                         .RESET_NEED(1'b1),
                         .ONLY_RESET_ZERO(1'b1)
                       ) commit_board (
                         .clk,
                         .rst_n,
                         // read port
                         .ra0_i(is_r_addr_i[0]),
                         .ra1_i(is_r_addr_i[1]),
                         .ra2_i(is_r_addr_i[2]),
                         .ra3_i(is_r_addr_i[3]),
                         .rd0_o(commitboard_is_r_id[0]),
                         .rd1_o(commitboard_is_r_id[1]),
                         .rd2_o(commitboard_is_r_id[2]),
                         .rd3_o(commitboard_is_r_id[3]),
                         // write port
                         .wd0_i(wb_w_id_i), // TODO: WRITE DATA
                         .wd1_i(wb_w_id_i),
                         .wa0_i(wb_w_addr_i[0]),
                         .wa1_i(wb_w_addr_i[1]),
                         .we0_i(wb_valid_i[0] && (wb_w_addr_i[0] != '0)),
                         .we1_i(wb_valid_i[1] && (wb_w_addr_i[1] != '0)),
                         // signal
                         .conflict_o()
                       );


  // 无效化逻辑部分
  // 当无效化开始后，不再允许发射新的指令
  // 状态机会一直等待，监听写会级，直到发现最晚无效指令，才允许后续指令继续发射。
  // 当周期，正在发射的信号不用撤回，避免组合逻辑链过长。
  logic hit_wait_tgt;

  logic[2:0] wait_id_q,waid_id;
  assign hit_wait_tgt = (wait_id_q == wb_w_id_i) && |wb_valid_i;
  always_ff @(posedge clk) begin
    if(!rst_n) begin
      wait_id_q <= '1;
    end
    else if(|is_i) begin
      if(wait_id_q == '1) begin
        wait_id_q <= 3'd1;
      end
      else begin
        wait_id_q <= wait_id_q + 1;
      end
    end
  end

  always_ff @(posedge clk) begin
    if(!rst_n) begin
      invalidate_wait_q <= '0;
    end else begin
      if(invalidate_i) begin
        invalidate_wait_q <= '1;
      end else if(hit_wait_tgt) begin
        invalidate_wait_q <= '0;
      end
    end
  end

  assign issue_ready_o = ~invalidate_wait_q;

endmodule
