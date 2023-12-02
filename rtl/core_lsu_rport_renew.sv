`include "lsu.svh"
// `default_nettype none
/*--JSON--{"module_name":"core_lsu_rport","module_ver":"2","module_type":"module"}--JSON--*/

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

  // EX-M1
  // 实例化 bram lutram 存储 tag 以及 data
  logic[`_DIDX_LEN - 1 : 2] raw_data_raddr;    // TODO: CHECK ME
  logic[WAY_CNT - 1 : 0][31:0] raw_data_rdata; // TODO: CHECK ME
  logic[7:0] raw_tag_raddr;                    // TODO: CHECK ME
  dcache_tag_t [WAY_CNT-1:0] raw_tag_rdata;    // TODO: CHECK ME
  assign raw_data_raddr = wstate_i.dram_take_over ? wstate_i.data_raddr : dramaddr(ex_vaddr_i);
  assign rstate_o.rdata = raw_data_rdata;
  assign m1_busy_o = '0;
  assign m1_rvalid_o = '0;
  assign m1_rdata_o = '0;
  assign raw_tag_raddr  = tramaddr(ex_vaddr_i);
  for(genvar w = 0 ; w < WAY_CNT ; w ++) begin
    // 数据ram == 4k each
    sync_dpram #(
      .DATA_WIDTH(32),
      .DATA_DEPTH(1 << (`_DIDX_LEN - 2)),
      .BYTE_SIZE(8)
    ) data_ram (
      .clk,
      .rst_n,
      .waddr_i(wreq_i.data_waddr),
      .we_i   (wreq_i.data_we[w]),
      .raddr_i(raw_data_raddr),
      .re_i   (1'b1),
      .wdata_i(wreq_i.data_wdata),
      .rdata_o(raw_data_rdata[w])
    );
    // tag ram
    dcache_tag_t raw_tag_rdata_d;
    sync_regram #(
      .DATA_WIDTH($bits(dcache_tag_t)),
      .DATA_DEPTH(1 << 8             )
    ) tag_ram (
      .clk    (clk             ),
      .rst_n  (rst_n           ),
      .waddr_i(wreq_i.tag_waddr),
      .we_i   (wreq_i.tag_we[w]),
      .raddr_i(raw_tag_raddr   ),
      .wdata_i(wreq_i.tag_wdata),
      .rdata_o(raw_tag_rdata_d)
    );
    always_ff @(posedge clk) begin
      raw_tag_rdata[w] <= raw_tag_rdata_d;
    end
  end

  logic m1_stall_q, m2_stall_q;
  always_ff @(posedge clk) begin
    m1_stall_q <= m1_stall_i;
    m2_stall_q <= m2_stall_i;
  end

  // M1 级别进行地址比较，产生 hit miss，等待流水至 M2 级
  // M1 级别还需要进行转发，对于 新写入 dataram 或者 tag 的数据，及时的转发至前级，
  // 保证对于 sw-lw 这种指令流，lw可以看到sw的修改
  logic[WAY_CNT - 1 : 0][31:0] m1_data_rdata,m1_data_rdata_q;
  dcache_tag_t [WAY_CNT-1:0] m1_tag_rdata,m1_tag_rdata_q;
  logic[WAY_CNT - 1 : 0][3:0] wb_data_we;
  logic[`_DIDX_LEN - 1 : 0] wb_data_waddr;

  logic[WAY_CNT - 1 : 0] wb_tag_we;
  logic[31:0] wb_data_wdata;
  logic[7:0] wb_tag_waddr;
  dcache_tag_t wb_tag_wdata;
  always_ff @(posedge clk) begin
    wb_data_we    <= wreq_i.data_we;
    wb_data_waddr <= wreq_i.data_waddr;
    wb_data_wdata <= wreq_i.data_wdata;
  end

  always_ff @(posedge clk) begin
    m1_data_rdata_q <= m1_data_rdata;
    m1_tag_rdata_q  <= m1_tag_rdata;
  end
  always_comb begin
    m1_data_rdata = m1_stall_q ? m1_data_rdata_q : raw_data_rdata;
    for(integer w = 0 ; w < WAY_CNT ;w++) begin
      for(integer b = 0 ; b < 4 ; b++) begin
        if(wb_data_we[w][b] && (wb_data_waddr == dramaddr(m1_vaddr_i))) begin
          m1_data_rdata[w][7 + 8 * b -: 8] = wb_data_wdata[7 + 8 * b -: 8];
        end
        if(wreq_i.data_we[w][b] &&
          wreq_i.data_waddr == dramaddr(m1_vaddr_i)) begin
          // 这个优先级更高
          m1_data_rdata[w][7 + 8 * b -: 8] = wreq_i.data_wdata[7 + 8 * b -: 8];
        end
      end
    end
  end
  for(genvar w = 0 ; w < WAY_CNT ; w++) begin
    always_comb begin
      m1_tag_rdata[w] = m1_stall_q ? m1_tag_rdata_q[w] : raw_tag_rdata[w];
      // if(wb_tag_we[w] && wb_tag_waddr == tramaddr(m1_vaddr_i)) begin
      //   m1_tag_rdata[w] = wb_tag_wdata;
      // end else
      if(wreq_i.tag_we[w] && wreq_i.tag_waddr == tramaddr(m1_vaddr_i)) begin
        m1_tag_rdata[w] = wreq_i.tag_wdata;
      end
    end
  end

  // 地址比较
  logic[WAY_CNT - 1 : 0] m1_hit;
  logic m1_miss;
  // m1 hit miss area
  assign m1_miss = ~(|m1_hit);
  for(genvar w = 0; w < WAY_CNT ; w++) begin
    assign m1_hit[w] = dcache_hit(m1_tag_rdata[w], m1_paddr_i) && !m1_uncached_i;
  end

  // M2 核心状态机
  logic[WAY_CNT - 1 : 0] hit_q;
  (*MAX_FANOUT=400*) logic miss_q;
  always_ff @(posedge clk) begin
    if(!m2_stall_i) begin
      hit_q  <= m1_hit;
      miss_q <= m1_miss;
    end
  end

  typedef logic[2:0] fsm_t;
  localparam fsm_t S_NORMAL        = 0;
  localparam fsm_t S_UNCACHE_READ  = 1;
  localparam fsm_t S_REFILL_READ   = 2;
  localparam fsm_t S_UNCACHE_WRITE = 3;
  localparam fsm_t S_REFILL_WRITE  = 4;
  localparam fsm_t S_CACHE_INVOP   = 5; // CACHE 指令相关
  localparam fsm_t S_WAIT_STALL    = 6;
  (*MAX_FANOUT=400*) fsm_t fsm_q,fsm;
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
        if(m2_valid_i) begin
          if(!m2_uncached_i) begin // cacheable
            if(miss_q) begin
              if(m2_op_i == `_DCAHE_OP_READ) begin
                fsm       = S_REFILL_READ;
                m2_busy_o = '1;
              end
              else if(m2_op_i == `_DCAHE_OP_WRITE) begin
                fsm       = S_REFILL_WRITE;
                m2_busy_o = '1;
              end else if(m2_op_i == `_DCAHE_OP_DIRECT_INVWB || // 优化写法
                (m2_op_i   == `_DCAHE_OP_DIRECT_INV)) begin
                fsm       = S_CACHE_INVOP; // 直接无效化对应行的每一路，以降低复杂度
                m2_busy_o = '1;
              end
            end
            else begin
              if(m2_op_i == `_DCAHE_OP_DIRECT_INVWB ||
                (m2_op_i   == `_DCAHE_OP_DIRECT_INV) ||
                (m2_op_i   == `_DCAHE_OP_HIT_INV)) begin
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
        if(wstate_i.uop_ready) begin
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
  dcache_tag_t [WAY_CNT-1:0] m2_tag_rdata_q/*m2_tag_rdata*/;
  always_ff @(posedge clk) begin
    if(!m2_stall_i) begin
      m2_data_rdata_q <= m1_data_rdata;
      m2_tag_rdata_q  <= m1_tag_rdata;
    end
  end
  // always_comb begin
  //   if(!m2_stall_i) begin
  //     m2_tag_rdata = m1_tag_rdata;
  //   end
  //   else begin
  //     m2_tag_rdata = m2_tag_rdata_q;
  //     // for(integer w = 0 ; w < WAY_CNT ; w++) begin
  //     //   if(wreq_i.tag_we[w] && wreq_i.tag_waddr == tramaddr(m2_vaddr_i)) begin
  //     //     m2_tag_rdata[w] = wreq_i.tag_wdata;
  //     //   end
  //     // end
  //   end
  // end
  logic[31:0] data_rdata,data_rdata_q;
  always_ff @(posedge clk) begin
    if(fsm_q == S_UNCACHE_READ || fsm_q == S_REFILL_READ) begin
      if(wstate_i.read_ready) begin
        data_rdata_q <= wstate_i.rdata;
      end
    end
    else if(fsm == S_NORMAL) begin
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

  always_comb begin
    rstate_o.cache_refill_valid = fsm_q == S_REFILL_READ;
    rstate_o.uncached_read      = fsm_q == S_UNCACHE_READ;
    rstate_o.uncached_write_valid = (fsm_q == S_NORMAL && m2_valid_i && !m2_stall_i && m2_uncached_i && m2_op_i == `_DCAHE_OP_WRITE) || (fsm_q == S_UNCACHE_WRITE);
    // rstate_o.cache_op_inv         = (fsm_q == S_CACHE_INVOP && m2_op_i == `_DCAHE_OP_DIRECT_INV/* && m2_valid_i*/ /*TODO: CHECK ME*/);
    rstate_o.cache_op_inv         = '0;
    rstate_o.cache_op_invwb       = (fsm_q == S_CACHE_INVOP && (m2_op_i == `_DCAHE_OP_DIRECT_INVWB || m2_op_i == `_DCAHE_OP_HIT_INV)/* && m2_valid_i*/ /*TODO: CHECK ME*/);
    rstate_o.miss_write_req_valid = (fsm_q == S_REFILL_WRITE /*&& m2_valid_i && !m2_uncached_i && miss_q && m2_op_i == `_DCAHE_OP_WRITE*/);
    rstate_o.addr                 = m2_paddr_i;
    if(m2_op_i == `_DCAHE_OP_HIT_INV) begin
      rstate_o.addr[$clog2(WAY_CNT)-1:0] = '0;
      for(integer i = 0 ; i < WAY_CNT ; i++) begin
        if(hit_q[i]) begin
          rstate_o.addr[$clog2(WAY_CNT)-1:0] = i[$clog2(WAY_CNT) - 1 : 0];
        end
      end
    end
    rstate_o.rwsize  = m2_size_i;
    rstate_o.tag_rdata = m2_tag_rdata_q;

    rstate_o.hit_write_req_valid  = (fsm_q == S_NORMAL && m2_valid_i && !m2_stall_i && !m2_uncached_i && !miss_q && m2_op_i == `_DCAHE_OP_WRITE);
    rstate_o.wsel    = (fsm_q == S_NORMAL && m2_valid_i && m2_op_i == `_DCAHE_OP_WRITE && !m2_uncached_i && !miss_q) ? hit_q : '0;
    rstate_o.wstrobe = m2_strobe_i;
    rstate_o.wdata   = mkstrobe(mkwsft(m2_wdata_i, m2_vaddr_i),m2_strobe_i);

  end


endmodule
