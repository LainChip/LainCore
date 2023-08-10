// 8.5：这个模块靠近 CPU 管线。
// 每个 rport 支持处理命中的读指令，其内部有独立的 bram 存储数据以及 lutram 存储 tag / valid
// 比较特别的是， rport 并不持有 bram 以及 lutram 的写端口，而是统一的交给 wport 处理。
// 处理器中仅有一个 wport，对于命中的指令也可以连续处理。
// 每一条写指令仅会进入两个 rport 中的一个。对于 rport，只需要当作正常读指令处理就可以了。
// 存在一些特殊的 cacop 指令，需要与 wport 进行握手。处理类似写指令。

// 由于时间，调试难度，收益等综合考虑，放弃基于 BANK 的多端口 cache。

`include "lsu.svh"
// `default_nettype none

module core_lsu_rport #(parameter int WAY_CNT = `_DWAY_CNT) (
  input  wire          clk          ,
  input  wire          rst_n        ,
  input  wire [31:0]   ex_vaddr_i   ,
  input  wire          ex_read_i    ,
  input  wire [31:0]   m1_vaddr_i   ,
  input  wire [31:0]   m1_paddr_i   ,
  input  wire [ 3:0]   m1_strobe_i  ,
  input  wire          m1_read_i    ,
  input  wire          m1_uncached_i,
  output wire          m1_busy_o    , // M1 级的 LSU 允许 stall
  input  wire          m1_stall_i   ,
  output wire [31:0]   m1_rdata_o   ,
  output wire          m1_rvalid_o  , // 结果早出级
  input  wire [31:0]   m2_vaddr_i   ,
  input  wire [31:0]   m2_paddr_i   ,
  input  wire [31:0]   m2_wdata_i   ,
  input  wire [ 3:0]   m2_strobe_i  ,
  input  wire [ 2:0]   m2_type_i    ,
  input  wire          m2_valid_i   ,
  input  wire          m2_uncached_i,
  input  wire [ 1:0]   m2_size_i    , // uncached 专用
  output reg           m2_busy_o    , // M2 级别的 LSU 允许 stall
  input  wire          m2_stall_i   ,
  input  wire [ 2:0]   m2_op_i      , // TODO: CONNECT ME
  output wire [31:0]   m2_rdata_o   ,
  output wire          m2_rvalid_o  , // 需要 fmt 的结果级
  output rport_state_t rstate_o     ,
  input  wport_state_t wstate_i     ,
  input  wport_wreq_t  wreq_i         // 需要做 snoop
);

  assign m1_busy_o = '0;

  // TODO: EARLY OUT
  assign m1_rvalid_o = '0;
  assign m1_rdata_o  = '0;

  // CORE TODO: BUSY LOGIC
  // assign m2_busy_o = '0;
  // assign m2_rdata_o = '0;
  // assign m2_rvalid_o = '0;

  // ram 区域，用 distrubute ram 生成 tag-valid
  // 用 bram 生成数据
  logic[`_DIDX_LEN - 1 : 0] raw_data_raddr;
  logic[WAY_CNT - 1 : 0][31:0] raw_data_rdata;
  logic[7:0] raw_tag_raddr;
  dcache_tag_t [WAY_CNT-1:0] raw_tag_rdata;
  assign raw_data_raddr = wstate_i.dram_take_over ? wstate_i.data_raddr : dramaddr(ex_vaddr_i);
  assign rstate_o.rdata = raw_data_rdata;
  assign raw_tag_raddr  = tramaddr(ex_vaddr_i);
  for(genvar w = 0 ; w < WAY_CNT ; w ++) begin
    // 数据ram == 4k each
    simpleDualPortRamByteen #(
      .dataWidth(32),
      .ramSize(1 << (`_DIDX_LEN - 2)),
      .readMuler(1),
      .latency(1)
    ) data_ram (
      .clk,
      .rst_n,
      .addressA(wreq_i.data_waddr),
      .we(wreq_i.data_we[w]),
      .addressB(raw_data_raddr),
      .inData(wreq_i.data_wdata),
      .outData(raw_data_rdata[w])
    );
    // tag ram
    simpleDualPortLutRam #(
      .dataWidth($bits(dcache_tag_t)),
      .ramSize  (1 << 8             ),
      .latency  (1                  ),
      .readMuler(1                  )
    ) tag_ram (
      .clk     (clk             ),
      .rst_n   (rst_n           ),
      .addressA(wreq_i.tag_waddr),
      .we      (wreq_i.tag_we[w]),
      .addressB(raw_tag_raddr   ),
      .re      (1'b1            ),
      .inData  (wreq_i.tag_wdata),
      .outData (raw_tag_rdata[w])
    );
  end
  //   fast tag ram
  /*logic[$clog2(WAY_CNT) - 1 : 0] raw_fsel_rdata,raw_fsel_wdata; // TODO: CONNECT US
  logic raw_fsel_we; // TODO: CONNECT US
  dcache_tag_t raw_ftag_rdata;
  simpleDualPortLutRam #(
  .dataWidth($bits(dcache_tag_t) + $clog2(WAY_CNT)),
  .ramSize  (1 << 8),
  .latency  (0),
  .readMuler(1)
  ) ftag_ram (
  .clk     (clk       ),
  .rst_n   (rst_n     ),
  .addressA(wreq_i.tag_waddr),
  .we      (raw_fsel_we),
  .addressB(raw_tag_raddr),
  .re      (1'b1      ),
  .inData  ({raw_fsel_wdata,wreq_i.tag_wdata}),
  .outData ({raw_fsel_rdata,raw_ftag_rdata})
  );*/
  // m1 snoop area
  logic[WAY_CNT - 1 : 0][31:0] m1_data_rdata,m1_data_rdata_q;
  dcache_tag_t [WAY_CNT-1:0] m1_tag_rdata,m1_tag_rdata_q;
  logic[WAY_CNT - 1 : 0][3:0] wb_data_we;
  logic[`_DIDX_LEN - 1 : 0] wb_data_waddr;
  logic[31:0] wb_data_wdata;
  always_ff @(posedge clk) begin
    wb_data_we    <= wreq_i.data_we;
    wb_data_waddr <= wreq_i.data_waddr;
    wb_data_wdata <= wreq_i.data_wdata;
  end
  always_ff @(posedge clk) begin
    m1_data_rdata_q <= m1_data_rdata;
    m1_tag_rdata_q  <= m1_tag_rdata;
  end
  logic m1_stall_q;
  always_ff @(posedge clk) begin
    m1_stall_q <= m1_stall_i;
  end
  for(genvar w = 0 ; w < WAY_CNT ; w++) begin
    always_comb begin
      m1_data_rdata[w] = m1_stall_q ? m1_data_rdata_q[w] : raw_data_rdata[w];
      for(integer i = 0 ; i < 4 ; i++) begin
        if(wreq_i.data_we[w][i] &&
          wreq_i.data_waddr == dramaddr(m1_vaddr_i)) begin
          m1_data_rdata[w][7+8*i-:8] = wreq_i.data_wdata[7+8*i-:8];
        end
        if(wb_data_we[w][i] &&
          wb_data_waddr == dramaddr(m1_vaddr_i)) begin
          m1_data_rdata[w][7+8*i-:8] = wb_data_wdata[7+8*i-:8];
        end
      end
    end
    always_comb begin
      if(m1_stall_q) begin
        m1_tag_rdata[w] = m1_tag_rdata_q[w];
        if(wreq_i.tag_we[w] && wreq_i.tag_waddr == tramaddr(m1_vaddr_i)) begin
          m1_tag_rdata[w] = wreq_i.tag_wdata;
        end
      end else begin
        m1_tag_rdata[w] = raw_tag_rdata[w];
      end
    end
  end

  logic[WAY_CNT - 1 : 0] m1_hit;
  logic m1_miss;
  // m1 hit miss area
  assign m1_miss = ~(|m1_hit);
  for(genvar w = 0; w < WAY_CNT ; w++) begin
    assign m1_hit[w] = dcache_hit(m1_tag_rdata[w], m1_paddr_i) && !m1_uncached_i;
  end

  // m2 core
  logic[WAY_CNT - 1 : 0] hit_q;
  logic miss_q;
  always_ff @(posedge clk) begin
    if(!m2_stall_i) begin
      hit_q  <= m1_hit;
      miss_q <= m1_miss;
    end
  end

  // m2 fsm
  typedef logic[2:0] fsm_t;
  localparam fsm_t S_NORMAL        = 0;
  localparam fsm_t S_UNCACHE_READ  = 1;
  localparam fsm_t S_REFILL_READ   = 2;
  localparam fsm_t S_UNCACHE_WRITE = 3;
  localparam fsm_t S_REFILL_WRITE  = 4;
  localparam fsm_t S_CACHE_INVOP   = 5;
  localparam fsm_t S_WAIT_STALL    = 6;
  fsm_t fsm_q,fsm;
  always_ff @(posedge clk) begin
    if(~rst_n) begin
      fsm_q <= S_NORMAL;
    end
    else begin
      fsm_q <= fsm;
    end
  end

  always_comb begin
    fsm       = fsm_q;
    m2_busy_o = '0;
    case(fsm_q)
      default/*S_NORMAL*/: begin
        // WARNING: 所有修改都需要同步到下面的 WAIT 状态中去。
        if(m2_valid_i) begin
          if(!m2_uncached_i) begin
            if(miss_q) begin
              if(m2_op_i == `_DCAHE_OP_READ) begin
                fsm       = S_REFILL_READ;
                m2_busy_o = '1;
              end
              else if(m2_op_i == `_DCAHE_OP_WRITE) begin
                fsm       = S_REFILL_WRITE;
                m2_busy_o = '1;
              end
            end
            else begin
              if(m2_op_i == `_DCAHE_OP_DIRECT_INV || m2_op_i == `_DCAHE_OP_HIT_INV) begin
                fsm       = S_CACHE_INVOP; // 直接无效化对应行的每一路，以降低复杂度
                m2_busy_o = '1;
              end
            end
          end
          else begin
            if(m2_op_i == `_DCAHE_OP_READ) begin
              fsm       = S_UNCACHE_READ;
              m2_busy_o = '1;
            end
            else if(m2_op_i == `_DCAHE_OP_WRITE &&
              !wstate_i.uncached_write_ready) begin
              fsm       = S_UNCACHE_WRITE;
              m2_busy_o = '1;
            end
          end
        end
      end
      S_UNCACHE_READ : begin
        m2_busy_o = '1;
        if(wstate_i.read_ready) begin
          fsm = S_WAIT_STALL;
        end
      end
      S_UNCACHE_WRITE : begin
        m2_busy_o = '1;
        if(wstate_i.uncached_write_ready) begin
          fsm = S_WAIT_STALL;
        end
      end
      S_REFILL_READ : begin
        m2_busy_o = '1;
        if(wstate_i.uop_ready) begin
          fsm = S_WAIT_STALL;
        end
      end
      S_REFILL_WRITE : begin
        m2_busy_o = '1;
        if(wstate_i.uop_ready) begin
          fsm = S_WAIT_STALL;
        end
      end
      S_CACHE_INVOP : begin
        m2_busy_o = '1;
        if(wstate_i.uop_ready) begin
          fsm = S_WAIT_STALL;
        end
      end
      S_WAIT_STALL : begin
        if(!m2_stall_i) begin
          fsm = S_NORMAL;
        end
      end
    endcase
  end
  // assign m2_busy_o = fsm_q != S_WAIT_STALL || fsm_q != S_NORMAL;

  // m2 snoop area
  // 注意：正常流水下，m2 只需要从 m1 流水选择有效的即可。
  // 暂停的情况下，m2 需要及时的捕捉 read_ready 信号。
  logic[WAY_CNT - 1 : 0][31:0] m2_data_rdata_q;
  dcache_tag_t [WAY_CNT-1:0] m2_tag_rdata_q,m2_tag_rdata;
  always_ff @(posedge clk) begin
    if(!m2_stall_i) begin
      m2_data_rdata_q <= m1_data_rdata;
      m2_tag_rdata_q  <= m2_tag_rdata;
    end
  end
  logic m2_stall_q;
  always_ff @(posedge clk) begin
    m2_stall_q <= m2_stall_i;
  end
  always_comb begin
    if(!m2_stall_i) begin
      m2_tag_rdata = m1_tag_rdata;
    end
    else begin
      m2_tag_rdata = m2_tag_rdata_q;
      for(integer w = 0 ; w < WAY_CNT ; w++) begin
        if(wreq_i.tag_we[w] && wreq_i.tag_waddr == tramaddr(m2_vaddr_i)) begin
          m2_tag_rdata[w] = wreq_i.tag_wdata;
        end
      end
    end
  end
  logic[31:0] data_rdata,data_rdata_q;
  always_ff @(posedge clk) begin
    if(fsm_q == S_UNCACHE_READ || fsm_q == S_REFILL_READ) begin
      if(wstate_i.read_ready) begin
        data_rdata_q <= wstate_i.rdata;
      end
    end
    else begin
      data_rdata_q <= '0;
    end
  end
  always_comb begin
    data_rdata = data_rdata_q;
    for(integer i = 0 ; i < WAY_CNT ; i++) begin
      data_rdata |= hit_q[i] ? m2_data_rdata_q[i] : '0;
    end
  end
  // data 再进行一个 fmt 即可直接输出
  assign m2_rdata_o  = mkrsft(data_rdata, m2_vaddr_i, m2_type_i);
  assign m2_rvalid_o = !m2_busy_o && m2_valid_i && m2_op_i == `_DCAHE_OP_READ; // TODO: CHECKME

  // typedef struct packed {
  //   // 仅有这两个请求有可能同时出现
  //   logic cache_refill_valid;
  //   logic uncached_read;

  //   // 不可能同时出现的请求
  //   logic hit_write_req_valid; // 不需要暂停
  //   logic cache_op_inv;
  //   logic miss_write_req_valid;
  //   logic uncached_write_valid;

  //   // 请求相关地址以及数据
  //   logic [31:0] addr;
  //   logic [1:0] rwsize;
  //   logic [`_DWAY_CNT - 1 : 0] wsel;
  //   logic [3:0] wstrobe;
  //   logic [31:0] wdata;

  //   // take over 写回用
  //   logic [`_DWAY_CNT - 1 : 0][31:0] rdata;
  // } rport_state_t;

  always_comb begin
    rstate_o.cache_refill_valid = fsm_q == S_REFILL_READ;
    rstate_o.uncached_read      = fsm_q == S_UNCACHE_READ;

    rstate_o.hit_write_req_valid  = (fsm_q == S_NORMAL && m2_valid_i && !m2_uncached_i && !miss_q && m2_op_i == `_DCAHE_OP_WRITE);
    rstate_o.uncached_write_valid = (fsm_q == S_NORMAL && m2_valid_i && m2_uncached_i && m2_op_i == `_DCAHE_OP_WRITE) || (fsm_q == S_UNCACHE_WRITE);
    rstate_o.cache_op_inv         = (fsm_q == S_CACHE_INVOP/* && m2_valid_i*/ /*TODO: CHECK HIT*/);
    rstate_o.miss_write_req_valid = (fsm_q == S_REFILL_WRITE /*&& m2_valid_i && !m2_uncached_i && miss_q && m2_op_i == `_DCAHE_OP_WRITE*/);
    rstate_o.addr    = m2_paddr_i;
    rstate_o.rwsize  = m2_size_i;
    rstate_o.wsel    = (m2_valid_i && m2_op_i == `_DCAHE_OP_WRITE) ? hit_q : '0;
    rstate_o.wstrobe = m2_strobe_i;
    rstate_o.wdata   = mkstrobe(mkwsft(m2_wdata_i, m2_vaddr_i),m2_strobe_i);

    rstate_o.tag_rdata = m2_tag_rdata_q;
  end

endmodule
