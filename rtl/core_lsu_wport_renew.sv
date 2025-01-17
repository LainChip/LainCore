`include "lsu.svh"
/*--JSON--{"module_name":"core_lsu_wport","module_ver":"2","module_type":"module"}--JSON--*/

module core_lsu_wport #(
    parameter int PIPE_MANAGE_NUM = 2          ,
    parameter int WAY_CNT         = `_DWAY_CNT ,
    parameter int SLEEP_CNT       = 4
  ) (
    input  wire clk,
    input  wire rst_n,
    input  rport_state_t        [PIPE_MANAGE_NUM - 1 : 0] rstate_i , // uncached write left
    output wport_state_t        [PIPE_MANAGE_NUM - 1 : 0] wstate_o , // uncached write left
    output wport_wreq_t         wport_req_o,
    output cache_bus_req_t      bus_req_o ,// todo
    input  cache_bus_resp_t     bus_resp_i,
    output reg                  bus_busy_o // todo
  );

  // 内部存有一个 dirty_ram
  // 对于替换，使用 lfsr 替换方法，避免存储 plru 带来的额外硬件开支。
  // 为了避免字符串搜索情况下对目标串的替代，我们加一个额外的
  // victim_cache(16 * 4-way * 4 bytes == 256 bytes) 用于解决这个问题。

  // dirty ram
  logic[7:0] dirty_waddr,dirty_raddr;
  logic[WAY_CNT - 1 : 0] dirty_we, dirty_rdata;
  logic dirty_wdata;
  for(genvar w = 0 ; w < WAY_CNT ; w++) begin
    sync_regram #(
                  .DATA_WIDTH(1),
                  .DATA_DEPTH(1 << 8),
                  .NEED_RESET(0)
                ) dirty_ram (
                  .clk      (clk        ),
                  .rst_n    (rst_n      ),
                  .waddr_i  (dirty_waddr),
                  .we_i     (dirty_we[w]),
                  .raddr_i  (dirty_raddr),
                  .wdata_i  (dirty_wdata),
                  .rdata_o  (dirty_rdata[w])
                );
  end

  wport_wreq_t wport_req;
  assign wport_req_o = wport_req;

  // 写请求汇总层：总计只有一个写请求
  logic[31:0] wreq_addr;
  logic[31:0] wreq_data;
  logic[ 3:0] wreq_strobe;
  logic[ 1:0] wreq_size;
  logic[WAY_CNT - 1 : 0] wreq_hit;
  logic wreq_uncached;
  if(WAY_CNT == 2) begin
    always_comb begin
      wreq_addr = (rstate_i[0].hit_write_req_valid || rstate_i[0].uncached_write_valid || rstate_i[0].miss_write_req_valid) ?
                rstate_i[0].addr : rstate_i[1].addr;
      wreq_data = (rstate_i[0].hit_write_req_valid || rstate_i[0].uncached_write_valid || rstate_i[0].miss_write_req_valid) ?
                rstate_i[0].wdata : rstate_i[1].wdata;
      wreq_strobe = (rstate_i[0].hit_write_req_valid || rstate_i[0].uncached_write_valid || rstate_i[0].miss_write_req_valid) ?
                  rstate_i[0].wstrobe : rstate_i[1].wstrobe;
      wreq_size = (rstate_i[0].uncached_write_valid) ?
                rstate_i[0].rwsize : rstate_i[1].rwsize;
      // wreq_hit = (rstate_i[0].hit_write_req_valid || rstate_i[0].uncached_write_valid) ?
      wreq_hit      = (rstate_i[0].hit_write_req_valid || rstate_i[0].uncached_write_valid) ?
                rstate_i[0].wsel : rstate_i[1].wsel;
      wreq_uncached = rstate_i[0].uncached_write_valid | rstate_i[1].uncached_write_valid;
    end
  end

  // 读取 REFILL（Uncached） 、写入 REFILL 汇总级

  logic[31:0] op_addr_q,op_addr;// 汇总后的处理地址
  logic[31:0] refill_addr_q,refill_addr;
  logic[4:0] op_type_q,op_type;// 0读 refill, 1写 refill, 2读uncached, 3缓存inv请求
  logic[1:0] op_size_q,op_size;// 对于 uncached 读，需要判断其读长度
  logic op_valid_q,op_valid; // 由汇总层负责的握手信号
  logic[$clog2(WAY_CNT) - 1 : 0] refill_sel_q,refill_sel; // 由汇总层负责的 重填/回写 路选择信号
  dcache_tag_t oldtag_q,oldtag;
  logic        op_ready; // 由状态机控制的握手信号 TODO: CHECK

  // ONEHOT ENCODING
  localparam logic[4:0] O_READ_REFILL = 1;
  localparam logic[4:0] O_WRITE_REFILL = 2;
  localparam logic[4:0] O_READ_UNCACHE = 4;
  localparam logic[4:0] O_CACHE_INV = 8;  // 区别两类 INV 指令
  localparam logic[4:0] O_CACHE_INVWB = 16;

  always_ff @(posedge clk) begin
    if(!rst_n) begin
      op_addr_q <= 'x;
      refill_addr_q <= 'x;
      op_type_q <= '0;
      op_size_q <= 'x;
      op_valid_q <= '0;
      refill_sel_q <= '0;
      oldtag_q <= 'x;
    end else begin
      op_addr_q <= op_addr;
      refill_addr_q <= refill_addr;
      op_type_q <= op_type;
      op_size_q <= op_size;
      op_valid_q <= op_valid;
      refill_sel_q <= refill_sel;
      oldtag_q <= oldtag;
    end
  end
  always_comb begin
    op_valid = op_valid_q;
    op_addr = op_addr_q;
    refill_addr = refill_addr_q;
    op_type = op_type_q;
    op_size = op_size_q;
    refill_sel = refill_sel_q;
    oldtag = oldtag_q;
    if(op_valid_q) begin
      if(op_ready) begin
        op_valid = '0;
      end
    end else begin
      for(integer i = 0 ; i < PIPE_MANAGE_NUM ; i++) begin
        if(rstate_i[i].cache_refill_valid || rstate_i[i].uncached_read ||
        rstate_i[i].cache_op_inv ||
        rstate_i[i].cache_op_invwb || rstate_i[i].miss_write_req_valid) begin
          op_addr = rstate_i[i].addr;
          refill_addr = rstate_i[i].uncached_read ? rstate_i[i].addr : {rstate_i[i].addr[31:4], 4'd0};
          op_size = rstate_i[i].rwsize;
          op_valid = '1;
          oldtag = rstate_i[i].tag_rdata[refill_sel_q ^ 1]; // FIXME: ^ 1 -> + 1
          refill_sel = refill_sel_q ^ 1;
          op_type = 0;
          if(rstate_i[i].cache_refill_valid) begin
            op_type = O_READ_REFILL;
          end
          if(rstate_i[i].uncached_read) begin
            op_type = O_READ_UNCACHE;
          end
          if(rstate_i[i].cache_op_inv) begin
            op_type = O_CACHE_INV;
            oldtag = rstate_i[i].tag_rdata[rstate_i[i].addr[$clog2(WAY_CNT) - 1 : 0]];
            refill_sel = rstate_i[i].addr[$clog2(WAY_CNT) - 1 : 0];
          end
          if(rstate_i[i].cache_op_invwb) begin
            op_type = O_CACHE_INVWB;
            oldtag = rstate_i[i].tag_rdata[rstate_i[i].addr[$clog2(WAY_CNT) - 1 : 0]];
            refill_sel = rstate_i[i].addr[$clog2(WAY_CNT) - 1 : 0];
          end
          if(rstate_i[i].miss_write_req_valid) begin
            op_type = O_WRITE_REFILL;
          end
        end
      end
    end
  end

  // TODO: CHECK US
  // 写入 Uncached FIFO 控制层
  // TODO: 完成 FIFO 控制层
  localparam logic[1:0] S_FEMPTY = 2'd0;
  localparam logic[1:0] S_FADR   = 2'd1;
  localparam logic[1:0] S_FDAT   = 2'd2;
  logic[1:0] fifo_fsm_q,fifo_fsm;
  always_ff @(posedge clk) begin
    if(~rst_n)
      fifo_fsm_q <= S_FEMPTY;
    else
      fifo_fsm_q <= fifo_fsm;
  end
  // 写回 FIFO 状态机
  typedef struct packed {
            logic [31:0] addr  ;
            logic [31:0] data  ;
            logic [ 3:0] strobe;
            logic [ 1:0] size  ;
          } pw_fifo_t;
  pw_fifo_t [3:0] pw_fifo;
  pw_fifo_t       pw_req,pw_handling;

  logic pw_w_e,pw_r_e,pw_empty;
  logic uncac_fifo_full;
  logic[2:0] pw_w_ptr,pw_r_ptr,pw_cnt;
  assign pw_cnt          = pw_w_ptr - pw_r_ptr;
  // assign pw_empty        = pw_cnt == '0;
  // assign uncac_fifo_full = pw_cnt == 3'd4;
  always_ff @(posedge clk) begin
    if(~rst_n) begin
      pw_w_ptr <= '0;
    end
    else if(pw_w_e && !(pw_empty && pw_r_e)) begin
      pw_w_ptr <= pw_w_ptr + 1'd1;
    end
  end
  always_ff @(posedge clk) begin
    if(~rst_n) begin
      pw_r_ptr <= '0;
    end
    else if(pw_r_e && !pw_empty) begin
      pw_r_ptr <= pw_r_ptr + 1'd1;
    end
  end
  always_ff @(posedge clk) begin
    if(!rst_n) begin
      pw_empty <= '1;
    end else begin
      if(pw_empty) begin
        if(pw_w_e && !pw_r_e) begin
          pw_empty <= '0;
        end
      end else begin
        if(pw_r_e && (pw_cnt == 1) && !pw_w_e) begin
          pw_empty <= '1;
        end
      end
    end
  end
  always_ff @(posedge clk) begin
    if(!rst_n) begin
      uncac_fifo_full <= '0;
    end else begin
      if(uncac_fifo_full) begin
        if(pw_r_e && !pw_w_e) begin
          uncac_fifo_full <= '0;
        end
      end else begin
        if(!pw_r_e && (pw_cnt == 3) && pw_w_e) begin
          uncac_fifo_full <= '1;
        end
      end
    end
  end
  always_ff @(posedge clk) begin
    if(pw_r_e) begin
      if(!pw_empty)
        pw_handling <= pw_fifo[pw_r_ptr[1:0]];
      else
        pw_handling <= pw_req;
    end
  end
  always_ff @(posedge clk) begin
    if(pw_w_e) begin
      pw_fifo[pw_w_ptr[1:0]] <= pw_req;
    end
  end
  // W-R使能
  // pw_r_e pw_w_e
  assign pw_r_e = (fifo_fsm_q == S_FDAT && fifo_fsm == S_FADR) ||
         (fifo_fsm_q == S_FEMPTY && fifo_fsm == S_FADR);
  always_comb begin
    pw_req.addr   = wreq_addr;
    pw_req.data   = wreq_data;
    pw_req.strobe = wreq_strobe;
    pw_req.size   = wreq_size;
    pw_w_e        = !uncac_fifo_full && wreq_uncached;
  end
  for(genvar p = 0 ; p < PIPE_MANAGE_NUM ; p++) begin
    assign wstate_o[p].uncached_write_ready = !uncac_fifo_full;
  end
  always_comb begin
    fifo_fsm = fifo_fsm_q;
    case(fifo_fsm_q)
      default/*S_FEMPTY*/: begin
        if(pw_w_e) begin
          fifo_fsm = S_FADR;
        end
      end
      S_FADR : begin
        if(bus_resp_i.ready) begin
          fifo_fsm = S_FDAT;
        end
      end
      S_FDAT : begin
        if(bus_resp_i.data_ok) begin
          if(pw_empty && !pw_w_e) begin
            // 没有后续请求
            fifo_fsm = S_FEMPTY;
          end
          else begin
            // 有后续请求
            fifo_fsm = S_FADR;
          end
        end
      end
    endcase
  end

  // 核心状态机
  typedef logic[3:0] fsm_t;
  localparam fsm_t S_NORMAL     = 0;
  localparam fsm_t S_WB_WADR    = 1;
  localparam fsm_t S_WB_WDAT    = 2;
  localparam fsm_t S_REFIL_RADR = 3;
  localparam fsm_t S_REFIL_RDAT = 4;
  localparam fsm_t S_PT_RADR    = 5;
  localparam fsm_t S_PT_RDAT    = 6;
  localparam fsm_t S_TAG_UPDATE = 7;
  localparam fsm_t S_WAIT_BUS   = 8;
  fsm_t fsm_q, fsm;
  logic            set_ram_timer       ; // 重设 ram 计数器
  logic            set_bus_timer       ; // 重设 写回 buf 计数器
  always_ff @(posedge clk) begin
    if(!rst_n) begin
      fsm_q <= S_NORMAL;
    end
    else begin
      fsm_q <= fsm;
    end
  end
  always_comb begin
    fsm       = fsm_q;
    op_ready  = '0;
    set_ram_timer = '0;
    set_bus_timer = '0;
    case(fsm_q)
      default/*S_NORMAL*/: begin
        if(op_valid_q) begin
          case(op_type_q)
            default/*O_READ_REFILL,O_WRITE_REFILL*/: begin
              if(bus_busy_o) begin
                fsm = S_WAIT_BUS;
              end
              else begin
                if(oldtag_q.valid && dirty_rdata[refill_sel_q]) begin
                  // 脏写回
                  set_ram_timer = '1;
                  fsm       = S_WB_WADR;
                end
                else begin
                  fsm = S_REFIL_RADR;
                end
              end
            end
            O_READ_UNCACHE : begin
              if(bus_busy_o) begin
                fsm = S_WAIT_BUS;
              end
              else begin
                fsm = S_PT_RADR;
              end
            end
            O_CACHE_INV : begin
              if(bus_busy_o) begin
                fsm = S_WAIT_BUS;
              end
              else begin
                fsm = S_TAG_UPDATE;
              end
            end
            O_CACHE_INVWB : begin
              if(bus_busy_o) begin
                fsm = S_WAIT_BUS;
              end
              else begin
                if(oldtag_q.valid && dirty_rdata[refill_sel_q]) begin
                  // 脏写回
                  set_ram_timer = '1;
                  fsm       = S_WB_WADR;
                end
                else begin
                  fsm = S_TAG_UPDATE;
                end
              end
            end
          endcase
        end
      end
      S_WAIT_BUS : begin
        if(!bus_busy_o) begin
          fsm = S_NORMAL;
        end
      end
      S_WB_WADR : begin
        set_bus_timer = '1;
        if(bus_resp_i.ready) begin
          fsm = S_WB_WDAT;
        end
      end
      S_WB_WDAT : begin
        if(bus_resp_i.data_ok && bus_req_o.data_last) begin
          // todo: 明确不同类型的 op 在写回完成后的操作
          if(op_type_q == O_CACHE_INVWB) begin
            fsm = S_TAG_UPDATE;
          end
          else begin
            fsm = S_REFIL_RADR;
          end
        end
      end
      S_REFIL_RADR : begin
        set_bus_timer = '1;
        if(bus_resp_i.ready) begin
          fsm       = S_REFIL_RDAT;
        end
      end
      S_REFIL_RDAT : begin
        if(bus_resp_i.data_ok && bus_resp_i.data_last) begin
          fsm = S_TAG_UPDATE;
        end
      end
      S_PT_RADR : begin
        if(bus_resp_i.ready) begin
          fsm = S_PT_RDAT;
        end
      end
      S_PT_RDAT : begin
        if(bus_resp_i.data_ok && bus_resp_i.data_last) begin
          op_ready = '1;
          fsm = S_NORMAL;
        end
      end
      S_TAG_UPDATE : begin
        op_ready = '1;
        fsm = S_NORMAL;
      end
    endcase
  end

  // 写回抢夺总线相关信号
  logic refill_take_over_q,refill_take_over_q_q;
  always_ff @(posedge clk) begin
    if(fsm_q == S_NORMAL && fsm == S_WB_WADR) begin
      refill_take_over_q <= '1;
    end
    else if(fsm_q != S_WB_WADR && fsm_q != S_WB_WDAT) begin
      refill_take_over_q <= '0;
    end
    refill_take_over_q_q <= refill_take_over_q;
  end
  assign wstate_o[0].dram_take_over = '0;
  assign wstate_o[1].dram_take_over = refill_take_over_q;

  // 写回相关计数器
  logic[3:2] cur_wb_ram_addr_q_q;
  logic[31:0] cur_wb_ram_addr_q;
  logic[31:0] cur_wb_bus_addr_q;
  logic[3:0][31:0] refill_fifo_q;
  logic refill_fifo_ready_q; // 写回时标记 fifo 中的数据是否已经就绪
  assign wstate_o[0].data_raddr = '0;
  assign wstate_o[1].data_raddr = cur_wb_ram_addr_q[`_DIDX_LEN - 1 : 2];
  always_ff @(posedge clk) begin
    if(fsm_q == S_WB_WADR) begin
      refill_fifo_ready_q <= '1;
    end
    else if(fsm_q != S_WB_WADR && fsm_q != S_WB_WDAT) begin
      refill_fifo_ready_q <= '0;
    end
  end
  always_ff @(posedge clk) begin
    if(set_ram_timer) begin
      cur_wb_ram_addr_q <= {oldtag_q.addr, refill_addr_q[11:2], 2'b00};
    end
    else begin
      cur_wb_ram_addr_q[3:2]   <= cur_wb_ram_addr_q[3:2] + 2'd1;
    end
    cur_wb_ram_addr_q_q[3:2] <= cur_wb_ram_addr_q[3:2];
  end
  always_ff @(posedge clk) begin
    if(set_bus_timer) begin
      cur_wb_bus_addr_q <= {oldtag_q.addr, refill_addr_q[11:2], 2'b00};
    end else begin
      if(bus_resp_i.data_ok) begin
        cur_wb_bus_addr_q[3:2] <= cur_wb_bus_addr_q[3:2] + 2'd1;
      end
    end
  end
  always_ff @(posedge clk) begin
    if(refill_take_over_q_q) begin
      refill_fifo_q[cur_wb_ram_addr_q_q[3:2]] <= rstate_i[1].rdata[refill_sel_q];
    end
  end

  for(genvar p = 0 ; p < PIPE_MANAGE_NUM ; p++) begin
    assign wstate_o[p].read_ready = bus_resp_i.data_ok &&
        (cur_wb_bus_addr_q[3:2] == rstate_i[p].addr[3:2] && fsm_q == S_REFIL_RDAT) ||
        fsm_q == S_PT_RDAT;
    assign wstate_o[p].rdata = bus_resp_i.r_data;
  end

  // 管理 dram 的写口
  // TODO: check
  always_comb begin
    wport_req.data_waddr = dramaddr(wreq_addr);
    wport_req.data_wdata = wreq_data;
    wport_req.data_we    = '0;
    if(fsm_q == S_NORMAL) begin
      for(integer w = 0 ; w < WAY_CNT ; w++) begin
        wport_req.data_we[w] = wreq_hit[w] ? wreq_strobe : '0;
      end
    end
    else if(fsm_q == S_REFIL_RDAT) begin
      wport_req.data_we[refill_sel_q] = 4'b1111;
      wport_req.data_waddr            = dramaddr(cur_wb_bus_addr_q);
      wport_req.data_wdata            = bus_resp_i.r_data;
    end
    else if(fsm_q == S_TAG_UPDATE && op_type_q == O_WRITE_REFILL) begin
      wport_req.data_we[refill_sel_q] = wreq_strobe;
    end
  end
  // 管理 dirty ram 的写口
  // TODO: check
  always_comb begin
    dirty_waddr = tramaddr(wreq_addr);
    dirty_we    = '0;
    dirty_raddr = tramaddr(op_addr_q); // early 1 cycle
    dirty_wdata = 1'b1;
    if(fsm_q == S_NORMAL) begin
      dirty_we = wreq_hit;
    end
    else if(fsm_q == S_TAG_UPDATE) begin
      dirty_we[refill_sel_q] = '1;
      dirty_waddr = tramaddr(op_addr_q);
      if(op_type_q == O_WRITE_REFILL) begin
        dirty_wdata = 1'b1;
      end
      else begin
        dirty_wdata = 1'b0;
      end
    end
  end

  // 管理 tag 的写口
  // TODO: check
  always_comb begin
    wport_req.tag_waddr       = tramaddr(op_addr_q);
    wport_req.tag_wdata.valid = '1;
    if(op_type_q == O_CACHE_INV || op_type_q == O_CACHE_INVWB) begin
      wport_req.tag_wdata.valid = '0;
    end
    wport_req.tag_wdata.addr = tagaddr(op_addr_q);
    wport_req.tag_we         = '0;
    if(fsm_q == S_TAG_UPDATE) begin
      wport_req.tag_we[refill_sel_q] = '1;
    end
  end

  // 管理与 rport 之间的握手信号
  for(genvar p = 0 ; p < PIPE_MANAGE_NUM ; p ++) begin
    always_comb begin
      wstate_o[p].uop_ready = op_ready;
    end
  end


  // CACHE 总线交互机制
  always_comb begin
    // TODO:根据 FSM 状态及总线状态及时的赋值
    bus_busy_o           = '0;
    bus_req_o.valid      = 1'b0;
    bus_req_o.write      = 1'b0;
    bus_req_o.burst_size = 4'b0011;
    bus_req_o.cached     = 1'b0;
    bus_req_o.data_size  = 2'b10;
    bus_req_o.addr       = refill_addr_q; // TODO: FIND BETTER VALUE HERE.

    bus_req_o.data_ok     = 1'b0;
    bus_req_o.data_last   = 1'b0;
    bus_req_o.data_strobe = 4'b1111;
    bus_req_o.w_data      = refill_fifo_q[cur_wb_bus_addr_q[3:2]]; // TODO: FIND BETTER VALUE HERE.
    if(fifo_fsm_q != S_FEMPTY) begin
      bus_busy_o = '1;
      if(fifo_fsm_q == S_FADR) begin
        bus_req_o.valid      = 1'b1;
        bus_req_o.write      = 1'b1;
        bus_req_o.burst_size = 4'b0000;
        bus_req_o.data_size  = pw_handling.size;
        bus_req_o.addr       = pw_handling.addr;
      end
      else begin
        // S_FDAT
        bus_req_o.data_ok     = 1'b1;
        bus_req_o.data_last   = 1'b1;
        bus_req_o.data_strobe = pw_handling.strobe;
        bus_req_o.w_data      = pw_handling.data;
      end
    end
    else if(fsm_q == S_REFIL_RADR) begin
      // REFILL 的请求
      bus_req_o.valid = 1'b1;
    end
    else if(fsm_q == S_REFIL_RDAT) begin
      bus_req_o.data_ok = 1'b1;
    end
    else if(fsm_q == S_WB_WADR) begin
      // 写回的请求
      bus_busy_o      = '1;
      bus_req_o.valid = 1'b1;
      bus_req_o.write = 1'b1;
      // if(ctrl == C_WRITE || ctrl == C_READ) begin
      bus_req_o.addr  = {oldtag_q.addr,refill_addr_q[11:0]};
    end
    else if(fsm_q == S_WB_WDAT) begin
      bus_busy_o      = '1;
      bus_req_o.data_ok   = refill_fifo_ready_q;
      bus_req_o.data_last = cur_wb_bus_addr_q[3:2] == 2'b11;
    end
    else if(fsm_q == S_PT_RADR) begin
      bus_req_o.valid      = 1'b1;
      bus_req_o.burst_size = 4'b0000;
      bus_req_o.data_size  = op_size_q;
    end
    else if(fsm_q == S_PT_RDAT) begin
      bus_req_o.data_ok = 1'b1;
    end;
  end
endmodule
