`include "pipeline.svh"
`include "lsu.svh"
/*--JSON--{"module_name":"core_ifetch","module_ver":"2","module_type":"module"}--JSON--*/
module core_ifetch #(
  parameter int ATTACHED_INFO_WIDTH = 32        , // 用于捆绑bpu输出的信息，跟随指令流水
  parameter bit ENABLE_TLB          = 1'b1      ,
  parameter bit EARLY_BRAM          = 1'b0      , // 用于提前一级 BRAM 地址，降低关键路径延迟
  parameter int WAY_CNT             = `_IWAY_CNT  // 指示cache的组相联度
) (
  input                                        clk            , // Clock
  input                                        rst_n          , // Asynchronous reset active low
  input  logic [                    1:0]       cacheop_i      , // 输入两位的cache控制信号
  input  logic                                 cacheop_valid_i, // 输入的cache控制信号有效
  input  logic [                   31:0]       cacheop_paddr_i,
  input  logic [                    1:0]       valid_i        , // F1 级别的有效信息
  // MMU 地址信号, 在 VPC 同一拍
  input  logic [                   31:0]       npc_i          , // F1 级前一级的 NPC
  input  logic [                   31:0]       vpc_i          , // F1 级别的 VPC
  input  logic [                   31:0]       ppc_i          , // F1 级别的 PPC
  input  logic                                 uncached_i     , // F1 级别的 UNCACHED 信息
  input  logic [ATTACHED_INFO_WIDTH-1:0]       attached_i     , // F1 级别的附加信息
  output logic [                    1:0]       valid_o        ,
  output logic [ATTACHED_INFO_WIDTH-1:0]       attached_o     ,
  output logic [                    1:0][31:0] inst_o         ,
  input  logic                                 flush_i        , // 无效化 F2 级别的所有未完成操作
  output logic [                   31:0]       pc_o           ,
  input  logic                                 bus_busy_i     ,
  input  logic                                 f1_stall_i     ,
  input  logic                                 f2_stall_i     ,
  output logic                                 f2_stall_req_o ,
  output cache_bus_req_t                       bus_req_o      ,
  input  cache_bus_resp_t                      bus_resp_i
);

  logic f1_stall_q,f2_stall_q;
  always_ff @(posedge clk) begin
    f1_stall_q <= f1_stall_i && !flush_i; /*TODO: CHECK ME - 当跳转发生后，NPC 会改变，下一周期更新一下 skid_buf*/
    f2_stall_q <= f2_stall_i;
  end

  typedef logic[8:0] icache_fsm_t;
  localparam   FSM_NORMAL  = 9'b000000001;
  localparam   FSM_RECVER  = 9'b000000010;
  localparam   FSM_RFADDR  = 9'b000000100;
  localparam   FSM_RFDATA  = 9'b000001000;
  localparam   FSM_PTADDR0 = 9'b000010000;
  localparam   FSM_PTDATA0 = 9'b000100000;
  localparam   FSM_PTADDR1 = 9'b001000000;
  localparam   FSM_PTDATA1 = 9'b010000000;
  localparam   FSM_WAITBUS = 9'b100000000;
  icache_fsm_t fsm_q,fsm;

  logic cacheop_valid_q; // 指示 F2 级别是 cacheop 指令
  logic[1:0] fetch_v_q;// 指示 F2 级别需要读的指令位置
  logic uncached_q; // 指示 F2 级别的取值需要是 uncached 类型的
  logic[1:0] cacheop_q;  // 指示 F2 级别的 cacheop 类型
  logic[31:0] ppc_q,vpc_q;// 指示 F2 级别的 PC 地址

  always_ff @(posedge clk) begin
    if(!rst_n || flush_i) begin
      cacheop_valid_q <= '0;
      fetch_v_q       <= '0;
    end else begin
      if(!f2_stall_i) begin
        if(cacheop_valid_i && ENABLE_TLB) begin
          cacheop_valid_q <= '1;
          fetch_v_q       <= '0;
          uncached_q      <= '0;
          cacheop_q       <= cacheop_i;
          ppc_q           <= cacheop_paddr_i;
        end else if(f1_stall_i) begin
          cacheop_valid_q <= '0;
          fetch_v_q       <= '0;
        end else begin
          cacheop_valid_q <= '0;
          fetch_v_q       <= valid_i;
          uncached_q      <= uncached_i;
          ppc_q           <= ppc_i;
          vpc_q           <= vpc_i;
        end
      end
    end
  end

  typedef struct packed {
    logic valid;
    logic[`_ITAG_LEN - 1 : 0] tag;
  } i_tag_t;

  function logic[`_ITAG_LEN - 1 : 0] itagaddr(input logic[31:0] va);
    return va[`_ITAG_LEN + `_IIDX_LEN - 1: `_IIDX_LEN];
  endfunction
  function logic[7 : 0] itramaddr(input logic[31:0] va);
    return va[`_IIDX_LEN - 1 -: 8];
  endfunction
  function logic[`_IIDX_LEN - 1 : 3] idramaddr(input logic[31:0] va);
    return va[`_IIDX_LEN - 1 : 3];
  endfunction
  function logic icache_hit(input i_tag_t tag,input logic[31:0] pa);
    return tag.valid && (itagaddr(pa) == tag.tag);
  endfunction

  logic[8:0] dram_raddr;
// 当开启 EARLY_BRAM 时，在 NPC ，否之在 F1 级
  logic[WAY_CNT - 1 : 0][1:0][31:0] dram_rdata;
// 当开启 EARLY_BRAM 时，在 F1 级，否之在 F2 级（且不需要转发）
  logic[9:0] dram_waddr;
  logic[WAY_CNT - 1 : 0] dram_we;
  logic[31:0] dram_wdata;

  logic[7:0] tram_raddr;
  i_tag_t[WAY_CNT - 1 : 0] tram_rdata;
  logic[7:0] tram_waddr;
  logic[WAY_CNT - 1 : 0] tram_we;
  i_tag_t tram_wdata;

  logic[ 9:0] refill_addr_q;
  logic[ 1:0] refill_addr_q_q;
  logic[31:0] refill_data_q;
  logic refill_valid_q;

// 读地址赋值
  if(EARLY_BRAM) begin
    assign dram_raddr = npc_i[11:3];
  end else begin
    assign dram_raddr = vpc_i[11:3];
  end
  assign tram_raddr = (cacheop_valid_i && ENABLE_TLB) ? cacheop_paddr_i[11:4] : vpc_i[11:4];

  logic[WAY_CNT - 1 : 0][1:0][31:0] f2_data_q;
  if(EARLY_BRAM) begin
    // 用 skid buf 锁住其输出的数据，当然，注意要及时的转发
    logic[WAY_CNT - 1 : 0][1:0][31:0] f2_data;
    logic[WAY_CNT - 1 : 0][1:0][31:0] f1_skid_buf_q;
    always_ff @(posedge clk) begin
      if(!f1_stall_q) begin
        f1_skid_buf_q <= f2_data;
      end
    end
    for(genvar w = 0 ; w < WAY_CNT ; w++) begin
      always_ff @(posedge clk) begin
      end
      always_comb begin
        if(dram_we[w] && (dram_waddr[9:1] == ppc_i[11:3]) && !dram_waddr[0]) begin
          f2_data[w][0] = dram_wdata; // 前递转发
        end else begin
          f2_data[w][0] = f1_stall_q?f1_skid_buf_q[w][0] : dram_rdata[w][0];
        end
        if(dram_we[w] && (dram_waddr[9:1] == ppc_i[11:3]) && dram_waddr[0]) begin
          f2_data[w][1] = dram_wdata; // 前递转发
        end else begin
          f2_data[w][1] = f1_stall_q?f1_skid_buf_q[w][1] : dram_rdata[w][1];
        end
      end
    end
  end else begin
    assign f2_data_q = dram_rdata;
  end

  for(genvar w = 0 ; w < WAY_CNT ; w++) begin
    simpleDualPortRam #(
      .dataWidth(32),
      .ramSize  (1 << 9),
      .latency  (1),
      .readMuler(1)
    ) dram_0 (
      .clk     (clk       ),
      .rst_n   (rst_n     ),
      .addressA(dram_waddr[9:1]),
      .we      (dram_we[w] && !dram_waddr[0]),
      .addressB(dram_raddr),
      .inData  (dram_wdata),
      .outData (dram_rdata[w][0])
    );
    simpleDualPortRam #(
      .dataWidth(32),
      .ramSize  (1 << 9),
      .latency  (1),
      .readMuler(1)
    ) dram_1 (
      .clk     (clk       ),
      .rst_n   (rst_n     ),
      .addressA(dram_waddr[9:1]),
      .we      (dram_we[w] && dram_waddr[0]),
      .addressB(dram_raddr),
      .inData  (dram_wdata),
      .outData (dram_rdata[w][1])
    );
    simpleDualPortLutRam #(
      .dataWidth($bits(i_tag_t)),
      .ramSize  (1 << 8        ),
      .latency  (0             ),
      .readMuler(1             )
    ) tram (
      .clk     (clk          ),
      .rst_n   (rst_n        ),
      .addressA(tram_waddr   ),
      .we      (tram_we[w]   ),
      .addressB(tram_raddr   ),
      .re      (1'b1         ),
      .inData  (tram_wdata   ),
      .outData (tram_rdata[w])
    );
  end

// 重填地址相关逻辑
// 对输入再加一级寄存器以降低延迟
// 因此对地址信号也加一拍
  always_ff @(posedge clk) begin
    if(fsm_q == FSM_RFADDR) begin
      refill_addr_q <= {itramaddr(ppc_q),2'd0};
    end
    else begin
      if(bus_resp_i.data_ok) begin
        refill_addr_q[1:0] <= refill_addr_q[1:0] + 1;
      end
    end
  end
  always_ff @(posedge clk) begin
    refill_addr_q_q <= refill_addr_q;
    refill_valid_q  <= bus_resp_i.data_ok && (fsm_q == FSM_RFDATA);
  end
// 每一拍写一次
  always_ff @(posedge clk) begin
    if(bus_resp_i.data_ok) begin
      refill_data_q <= bus_resp_i.r_data;
    end
  end

  logic[WAY_CNT - 1 : 0] way_sel_q,way_sel;// 重填路选择
// 重填数据赋值
  always_comb begin
    dram_waddr = {refill_addr_q[9:2],refill_addr_q_q};
    dram_wdata = refill_data_q;
    for(integer w = 0 ; w < WAY_CNT ; w++) begin
      dram_we[w] = refill_valid_q && way_sel_q[w];
    end
  end

// 命中状态信号流水
  logic[WAY_CNT - 1:0]f1_hit, hit_q, hit;
  logic f1_miss, miss_q, miss;
  assign f1_miss = !(|f1_hit);
  always_ff @(posedge clk) begin
    if(!rst_n) begin
      way_sel_q <= 1;
    end else begin
      way_sel_q <= way_sel;
    end
    hit_q  <= hit;
    miss_q <= miss;
  end
  for(genvar w = 0 ; w < WAY_CNT ; w++) begin
    assign f1_hit[w] = icache_hit(tram_rdata[w],
      (cacheop_valid_i && ENABLE_TLB) ? cacheop_paddr_i : ppc_i);
  end
  always_comb begin
    hit  = f2_stall_i ? hit_q : f1_hit;
    miss = f2_stall_i ? miss_q : f1_miss;
    if(fsm_q == FSM_RFADDR) begin
      miss = 1'b0;
    end
  end
// TODO: 修改路选择逻辑（优化，更好的替换方式）
  always_comb begin
    way_sel = way_sel_q;
    if(!f2_stall_i) begin
      if(cacheop_valid_i) begin
        if(cacheop_i == 2) begin
          way_sel = hit;
        end else begin
          way_sel                                       = '0;
          way_sel[cacheop_paddr_i[$clog2(WAY_CNT)-1:0]] = '1;
        end
      end else begin
        if(WAY_CNT == 1) begin
          way_sel = '1;
        end else begin
          if(way_sel == 0) begin
            way_sel = 1;
          end else begin
            way_sel = {way_sel_q[WAY_CNT - 2 : 0],way_sel_q[WAY_CNT - 1]};
          end
        end
      end
    end
  end

// 重填 TAG 赋值
  always_comb begin
    // 更新 tag 的逻辑
    tram_waddr = itramaddr(ppc_q);
    tram_we    = '0;
    if(fsm_q == FSM_RECVER || fsm_q == FSM_RFADDR) begin
      //   if(cacheop_valid_q && (cacheop_q == 2'd2)) begin
      // tram_we |= hit_q;
      //   end else begin
      tram_we |= way_sel_q;
      //   end
    end
    tram_wdata.valid = 1'b1;
    tram_wdata.tag   = itagaddr(ppc_q);
    if(cacheop_valid_q) begin
      case(cacheop_q)
        default : begin
          tram_wdata.valid = 1'b0;
        end
        2 : begin
          tram_wdata.valid = !hit_q;
        end
      endcase
    end
  end

// 主状态机
  logic f2_op_finished_q,f2_op_finished;
  always_ff @(posedge clk) begin
    if(!rst_n) begin
      fsm_q            <= FSM_NORMAL;
      f2_op_finished_q <= '0;
    end
    else begin
      fsm_q            <= fsm;
      f2_op_finished_q <= f2_op_finished;
    end
  end
  always_comb begin
    fsm            = fsm_q;
    f2_op_finished = f2_stall_i ? f2_op_finished_q : '0;
    case(fsm_q)
      default : begin
        fsm = FSM_NORMAL;
      end
      FSM_NORMAL : begin
        if(cacheop_valid_q && !f2_op_finished_q) begin
          fsm = FSM_RECVER;
        end
        else if(!uncached_q && miss_q && |fetch_v_q) begin
          if(bus_busy_i) begin
            fsm = FSM_WAITBUS;
          end else begin
            fsm = FSM_RFADDR;
          end
        end
        else if(uncached_q && !f2_op_finished_q) begin
          if(bus_busy_i) begin
            fsm = FSM_WAITBUS;
          end else if(fetch_v_q[0]) begin
            fsm = FSM_PTADDR0;
          end
          else if(fetch_v_q[1]) begin
            fsm = FSM_PTADDR1;
          end
        end
      end
      FSM_WAITBUS : begin
        if(!bus_busy_i) begin
          fsm = FSM_NORMAL;
        end
      end
      FSM_RECVER : begin
        fsm            = FSM_NORMAL;
        f2_op_finished = 1'b1;
      end
      FSM_RFADDR : begin
        if(bus_resp_i.ready) begin
          fsm = FSM_RFDATA;
        end
      end
      FSM_RFDATA : begin
        if((&refill_addr_q_q[1:0]) && refill_valid_q) begin
          fsm = EARLY_BRAM ? FSM_NORMAL : FSM_WAITBUS; 
          // UGLY FIX： 多暂停一拍允许后续指令看到refill 的数据。
        end
      end
      FSM_PTADDR0 : begin
        if(bus_resp_i.ready) begin
          fsm = FSM_PTDATA0;
        end
      end
      FSM_PTDATA0 : begin
        if(bus_resp_i.data_ok && bus_resp_i.data_last) begin
          if(!fetch_v_q[1]) begin
            fsm            = FSM_NORMAL;
            f2_op_finished = 1'b1;
          end
          else begin
            fsm = FSM_PTADDR1;
          end
        end
      end
      FSM_PTADDR1 : begin
        if(bus_resp_i.ready) begin
          fsm = FSM_PTDATA1;
        end
      end
      FSM_PTDATA1 : begin
        if(bus_resp_i.data_ok && bus_resp_i.data_last) begin
          fsm            = FSM_NORMAL;
          f2_op_finished = 1'b1;
        end
      end
    endcase
  end
  logic[1:0][31:0] skid_data_buf_q;
// 数据捕获
  always_ff @(posedge clk) begin
    if((fsm_q == FSM_PTDATA0 ||
        (fsm_q == FSM_RFDATA && !refill_addr_q[0] && refill_addr_q[1] == ppc_q[3])) &&
      bus_resp_i.data_ok) begin
      skid_data_buf_q[0] <= bus_resp_i.r_data;
    end
    else if((fsm_q == FSM_PTDATA1 ||
        (fsm_q == FSM_RFDATA && refill_addr_q[0] && refill_addr_q[1] == ppc_q[3])) && bus_resp_i.data_ok) begin
      skid_data_buf_q[1] <= bus_resp_i.r_data;
    end
    else begin
      // SKID
      if(!f2_stall_q) begin
        skid_data_buf_q <= inst_o;
      end
    end
  end

// 路选择逻辑
  logic[1:0][31:0] f2_sel_data;
  always_comb begin
    f2_sel_data = '0;
    for(integer w = 0 ; w < WAY_CNT ; w++) begin
      if(hit_q[w]) begin
        f2_sel_data |= f2_data_q[w];
      end
    end
  end
  assign inst_o         = f2_stall_q ? skid_data_buf_q : f2_sel_data;
  assign valid_o        = fetch_v_q & {!f2_stall_i, !f2_stall_i};
  assign f2_stall_req_o = fsm_q != FSM_NORMAL || fsm != FSM_NORMAL;
  assign pc_o           = vpc_q;
  always_ff @(posedge clk) begin
    if(!f2_stall_i) begin
      attached_o <= attached_i;
    end
  end
// 产生总线赋值
  always_comb begin
    bus_req_o.valid      = 1'b0;
    bus_req_o.write      = 1'b0;
    bus_req_o.burst_size = 4'b0011;
    bus_req_o.cached     = 1'b0;
    bus_req_o.data_size  = 2'b10;
    bus_req_o.addr       = {ppc_q[31:12],refill_addr_q[0],2'd0};

    bus_req_o.data_ok     = 1'b0;
    bus_req_o.data_last   = 1'b0;
    bus_req_o.data_strobe = 4'b0000;
    bus_req_o.w_data      = '0;
    if(fsm_q == FSM_RFADDR) begin
      bus_req_o.valid  = 1'b1;
      bus_req_o.cached = 1'b1;
      bus_req_o.addr   = {ppc_q[31:4],4'd0};
    end
    else if(fsm_q == FSM_RFDATA || fsm_q == FSM_PTDATA0 || fsm_q == FSM_PTDATA1) begin
      bus_req_o.data_ok = 1'b1;
    end
    else if(fsm_q == FSM_PTADDR0 || fsm_q == FSM_PTADDR1) begin
      bus_req_o.valid      = 1'b1;
      bus_req_o.burst_size = 4'b0000;
      if(fsm_q == FSM_PTADDR1) begin
        bus_req_o.addr = {ppc_q[31:3],3'b100};
      end
      else begin
        bus_req_o.addr = {ppc_q[31:3],3'b000};
      end
    end
  end

endmodule
