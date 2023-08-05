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

  always_comb begin
    wport_req.tag_waddr = '0;
    wport_req.tag_wdata = '0;
    wport_req.tag_we = '0;
    wport_req.data_waddr = '0;
    wport_req.data_wdata = '0;
    wport_req.data_we = '0;
  end

  // 读取 REFILL（Uncached） 、写入 REFILL 汇总级

  // TODO: CONNECT US
  logic[31:0] op_addr_q; // 汇总后的处理地址
  logic[1:0] op_type_q; // 0读 refill, 1写 refill, 2读uncached, 3缓存inv请求
  localparam logic[1:0] O_READ_REFILL = 0;
  localparam logic[1:0] O_WRITE_REFILL = 1;
  localparam logic[1:0] O_READ_UNCACHE = 2;
  localparam logic[1:0] O_CACHE_INV = 3;
  logic op_valid_q; // 由汇总层负责的握手信号
  logic[$clog2(WAY_CNT) - 1 : 0] refill_sel_q; // 由汇总层负责的 重填/回写 路选择信号
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

  // 写回相关计数器
  logic[31:0] cur_wb_ram_addr_q;
  logic[31:0] cur_wb_bus_addr_q;

  // 重填相关计数器
  logic[31:0] cur_refill_ram_addr;

endmodule
