`include "lsu.svh"

module core_lsu_wport #(
    parameter int PIPE_MANAGE_NUM = 2          ,
    parameter int WAY_CNT         = `_DWAY_CNT ,
    parameter int SLEEP_CNT       = 4
  ) (
    input  wire clk,
    input  wire rst_n,
    input  rport_state_t        [PIPE_MANAGE_NUM - 1 : 0] rstate_i ,
    output wport_state_t        [PIPE_MANAGE_NUM - 1 : 0] wstate_o ,// todo
    output wport_wreq_t         wport_req_o,// todo
    output cache_bus_req_t      bus_req_o ,// todo
    input  cache_bus_resp_t     bus_resp_i,
    output wire                 bus_busy_o // todo
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
    simpleDualPortLutRam #(
                           .dataWidth(1),
                           .ramSize  (1 << 8),
                           .latency  (0),
                           .readMuler(1)
                         ) dirty_ram (
                           .clk      (clk        ),
                           .rst_n    (rst_n      ),
                           .addressA (dirty_waddr),
                           .we       (dirty_we[w]),
                           .addressB (dirty_raddr),
                           .re       (1'b1       ),
                           .inData   (dirty_wdata),
                           .outData  (dirty_rdata)
                         );
  end

  // TODO
  always_comb begin
    dirty_waddr = '0;
    dirty_we = '0;
    dirty_raddr = '0; // early 1 cycle
    dirty_wdata = '0;
  end

  wport_wreq_t wport_req;
  assign wport_req_o = wport_req;

  // 写请求汇总层：总计只有一个写请求
  logic[31:0] wreq_addr;
  logic[31:0] wreq_data;
  logic[ 3:0] wreq_strobe;
  logic[ 1:0] wreq_size;
  logic[WAY_CNT - 1 : 0] wreq_hit;
  logic       wreq_uncached;
  if(WAY_CNT == 2) begin
    always_comb begin
      wreq_addr = (rstate_i[0].hit_write_req_valid || rstate_i[0].uncached_write_valid) ?
                rstate_i[0].addr : rstate_i[1].addr;
      wreq_data = (rstate_i[0].hit_write_req_valid || rstate_i[0].uncached_write_valid) ?
                rstate_i[0].wdata : rstate_i[1].wdata;
      wreq_strobe = (rstate_i[0].hit_write_req_valid || rstate_i[0].uncached_write_valid) ?
                  rstate_i[0].wstrobe : rstate_i[1].wstrobe;
      wreq_size = (rstate_i[0].hit_write_req_valid || rstate_i[0].uncached_write_valid) ?
                rstate_i[0].rwsize : rstate_i[1].rwsize;
      // wreq_hit = (rstate_i[0].hit_write_req_valid || rstate_i[0].uncached_write_valid) ?
      wreq_hit = rstate_i[0].wsel | rstate_i[1].wsel;
      wreq_uncached = rstate_i[0].uncached_write_valid | rstate_i[1].uncached_write_valid;
    end
  end

  // 读取 REFILL（Uncached） 、写入 REFILL 汇总级

  // TODO: CONNECT US
  logic[31:0] op_addr_q; // 汇总后的处理地址
  logic[31:0] refill_addr_q;
  logic[1:0] op_type_q; // 0读 refill, 1写 refill, 2读uncached, 3缓存inv请求
  localparam logic[1:0] O_READ_REFILL = 0;
  localparam logic[1:0] O_WRITE_REFILL = 1;
  localparam logic[1:0] O_READ_UNCACHE = 2;
  localparam logic[1:0] O_CACHE_INV = 3;
  logic op_valid_q; // 由汇总层负责的握手信号
  logic[$clog2(WAY_CNT) - 1 : 0] refill_sel_q; // 由汇总层负责的 重填/回写 路选择信号
  logic[$clog2(PIPE_MANAGE_NUM) - 1 : 0] p_sel_q;
  dcache_tag_t oldtag_q;
  logic op_ready; // 由状态机控制的握手信号
  // TODO: CONNECT US

  // 写入 Uncached FIFO 控制层
  // TODO: 完成 FIFO 控制层

  // 核心状态机
  typedef logic[3:0] fsm_t;
  localparam fsm_t S_NORMAL = 0;
  localparam fsm_t S_WB_WADR = 1;
  localparam fsm_t S_WB_WDAT = 2;
  localparam fsm_t S_REFIL_RADR = 3;
  localparam fsm_t S_REFIL_RDAT = 4;
  localparam fsm_t S_PT_RADR = 5;
  localparam fsm_t S_PT_RDAT = 6;
  localparam fsm_t S_TAG_UPDATE = 7;
  localparam fsm_t S_WAIT_BUS = 8;
  fsm_t fsm_q, fsm;
  logic set_timer;
  always_ff @(posedge clk) begin
    if(!rst_n) begin
      fsm_q <= S_NORMAL;
    end
    else begin
      fsm_q <= fsm;
    end
  end
  always_comb begin
    fsm = fsm_q;
    case(fsm_q)
      S_NORMAL: begin
        if(op_valid_q) begin
          case(op_type_q)
            default/*O_READ_REFILL,O_WRITE_REFILL*/: begin
              if(bus_busy_o) begin
                fsm = S_WAIT_BUS;
              end
              else begin
                if(dirty_rdata[refill_sel_q]) begin
                  // 脏写回
                  fsm = S_WB_WADR;
                end
                else begin
                  fsm = S_REFIL_RADR;
                end
              end
            end
            O_READ_UNCACHE: begin
              if(bus_busy_o) begin
                fsm = S_WAIT_BUS;
              end
              else begin
                fsm = S_PT_RADR;
              end
            end
            O_CACHE_INV: begin
              if(bus_busy_o) begin
                fsm = S_WAIT_BUS;
              end
              else begin
                // todo: 明确不同类型的 op 在写回完成后的操作
                fsm = S_TAG_UPDATE;
              end
            end
          endcase
        end
      end
      S_WB_WADR: begin
        if(bus_resp_i.ready) begin
          fsm = S_WB_WDAT;
        end
      end
      S_WB_WDAT: begin
        if(bus_resp_i.data_ok && bus_req_o.data_last) begin
          // todo: 明确不同类型的 op 在写回完成后的操作
          if(op_type_q == O_CACHE_INV) begin
            fsm = S_TAG_UPDATE;
          end
          else begin
            fsm = S_REFIL_RADR;
          end
        end
      end
      S_REFIL_RADR: begin
        if(bus_resp_i.ready) begin
          fsm = S_REFIL_RDAT;
        end
      end
      S_REFIL_RDAT: begin
        if(bus_resp_i.data_ok && bus_resp_i.data_last) begin
          fsm = S_TAG_UPDATE;
        end
      end
      S_PT_RADR: begin
        if(bus_resp_i.ready) begin
          fsm = S_PT_RDAT;
        end
      end
      S_PT_RDAT: begin
        if(bus_resp_i.data_ok && bus_resp_i.data_last) begin
          fsm = S_NORMAL;
        end
      end
      S_TAG_UPDATE: begin
        fsm = S_NORMAL;
      end
    endcase
  end

  // 写回抢夺总线相关信号
  logic refill_take_over_q;
  always_ff @(posedge clk) begin
    if(fsm_q == S_NORMAL && fsm == S_WB_WADR) begin
      refill_take_over_q <= '1;
    end
    else if(fsm_q != S_WB_WADR && fsm_q != S_WB_WDAT) begin
      refill_take_over_q <= '0;
    end
  end
  assign wstate_o.dram_take_over = refill_take_over_q;

  // 写回相关计数器
  logic[3:2] cur_wb_ram_addr_q_q;
  logic[31:0] cur_wb_ram_addr_q;
  logic[31:0] cur_wb_bus_addr_q;
  logic[3:0][31:0] refill_fifo_q;
  logic refill_fifo_ready_q; // 写回时标记 fifo 中的数据是否已经就绪
  assign wstate_o.data_raddr = cur_wb_ram_addr_q[`_DIDX_LEN - 1 : 2];
  always_ff @(posedge clk) begin
    if(fsm_q == S_WB_WADR) begin
      refill_fifo_ready_q <= '1;
    end
    else begin
      refill_fifo_ready_q <= '0;
    end
  end
  always_ff @(posedge clk) begin
    if(set_timer) begin
      cur_wb_ram_addr_q <= {oldtag_q.addr, refill_addr_q[11:0]};
      cur_wb_bus_addr_q <= {oldtag_q.addr, refill_addr_q[11:0]};
    end
    else begin
      if(bus_resp_i.data_ok) begin
        cur_wb_bus_addr_q[3:2] <= cur_wb_bus_addr_q[3:2] + 2'd1;
      end
      cur_wb_ram_addr_q[3:2] <= cur_wb_ram_addr_q[3:2] + 2'd1;
      cur_wb_ram_addr_q_q[3:2] <= cur_wb_ram_addr_q[3:2];
    end
  end
  always_ff @(posedge clk) begin
    refill_fifo_q[cur_wb_ram_addr_q_q] <= rstate_i[1].rdata[refill_sel_q];
  end

  // 重填相关计数器
  logic[31:0] cur_refill_ram_addr_q;
  // 注意，rport 所持有的 read_ready 由此为依据进行赋值。
  always_ff @(posedge clk) begin
    if(set_timer) begin
      cur_refill_ram_addr_q <= refill_addr_q;
    end
    else begin
      if(bus_resp_i.data_ok) begin
        cur_refill_ram_addr_q[3:2] <= cur_refill_ram_addr_q[3:2] + 2'd1;
      end
    end
  end
  for(genvar p = 0 ; p < PIPE_MANAGE_NUM ; p++) begin
    assign wstate_o[p].read_ready = bus_resp_i.data_ok &&
           cur_refill_ram_addr_q[3:2] == rstate_i[p].addr[3:2] &&
           p_sel_q == p[$clog2(PIPE_MANAGE_NUM) - 1 : 0];
    assign wstate_o[p].rdata = bus_resp_i.r_data;
  end

  // 管理 dram 的写口
  always_comb begin
    wport_req.data_waddr = wreq_addr[`_DIDX_LEN - 1 : 2];
    wport_req.data_wdata = wreq_data;
    wport_req.data_we = '0;
    if(fsm_q == S_NORMAL) begin
      for(integer w = 0 ; w < WAY_CNT ; w++) begin
        wport_req.data_we[w] = wreq_hit[w] ? wreq_strobe : '0;
      end
    end
    else if(fsm_q == S_REFIL_RDAT) begin
      wport_req.data_we[refill_sel_q] = 4'b1111;
      wport_req.data_waddr = cur_refill_ram_addr_q[`_DIDX_LEN - 1 : 2];
      wport_req.data_wdata = bus_resp_i.r_data;
    end
  end

  // 管理 tag 的写口
  always_comb begin
    wport_req.tag_waddr = '0;
    wport_req.tag_wdata = '0;
    wport_req.tag_we = '0;
  end

endmodule
