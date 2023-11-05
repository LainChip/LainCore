`include "pipeline.svh"
`include "lsu.svh"
/*--JSON--{"module_name":"core_fetch","module_ver":"1","module_type":"module"}--JSON--*/

module core_fetch #(
  parameter int ATTACHED_INFO_WIDTH    = 32        , // 用于捆绑bpu输出的信息，跟随指令流水
  parameter int F2_ATTACHED_INFO_WIDTH = 32        , // 用于捆绑bpu输出的信息，跟随指令流水
  parameter int WAY_CNT                = `_IWAY_CNT  // 指示cache的组相联度
) (
  // GLOBAL
  input  logic                                    clk            ,
  input  logic                                    rst_n          ,
  input  logic                                    flush_i        ,
  input  logic                                    bus_busy_i     ,
  output cache_bus_req_t                          bus_req_o      , // TODO: CM
  input  cache_bus_resp_t                         bus_resp_i     , // TODO: CM
  // F1 STAGE
  output logic                                    npc_ready_o    ,
  input  logic [                       1:0]       valid_i        ,
  output logic                                    cacheop_ready_o,
  input  logic                                    cacheop_valid_i, // 输入的cache控制信号有效
  input  logic [                       1:0]       cacheop_i      ,
  input  logic [                      31:0]       cacheop_paddr_i,
  input  logic [                      31:0]       vpc_i          ,
  input  logic [   ATTACHED_INFO_WIDTH-1:0]       attached_i     ,
  // F1-F2 STAGE REGISTER Enable FOR TLB
  output logic                                    f1_f2_clken_o  ,
  // F2 STAGE
  input  logic                                    uncache_i      ,
  input  logic [F2_ATTACHED_INFO_WIDTH-1:0]       f2_attached_i  ,
  input  logic [                      31:0]       ppc_i          ,
  output logic [F2_ATTACHED_INFO_WIDTH-1:0]       f2_attached_o  ,
  output logic [   ATTACHED_INFO_WIDTH-1:0]       attached_o     ,
  output logic [                      31:0]       pc_o           ,
  output logic [                       1:0]       valid_o        ,
  output logic [                       1:0][31:0] inst_o         ,
  input  logic                                    ready_i          // TODO: CM
);

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

  // F2 CACHE CONTROLL REGISTERS
  logic [ATTACHED_INFO_WIDTH-1:0] attached_q     ;
  logic [                    1:0] fetch_valid_q  ;
  logic [                    1:0] cacheop_q      ;
  logic [                   31:0] cacheop_paddr_q;
  logic [                   31:0] vpc_q          ;
  logic                           cacheop_valid_q;
  always_ff @(posedge clk) begin
    if(f1_f2_clken_o) begin
      cacheop_q       <= cacheop_i;
      cacheop_paddr_q <= cacheop_paddr_i;
      attached_q      <= attached_i;
      vpc_q           <= vpc_i;
    end
  end
  always_ff @(posedge clk) begin
    if(!rst_n || flush_i) begin
      cacheop_valid_q <= '0;
      fetch_valid_q   <= '0;
    end else begin
      if(f1_f2_clken_o) begin
        cacheop_valid_q <= cacheop_valid_i;
        fetch_valid_q   <= valid_i & {!cacheop_valid_i, !cacheop_valid_i};
      end
    end
  end

  logic skid_busy_q;

  logic[31:0] sram_raddr, sram_waddr, sram_addr;
  logic sram_wreq;
  assign sram_addr = sram_wreq ? sram_waddr : sram_raddr;

  logic[31:0] f1_sram_raddr, f2_sram_raddr_q;
  assign sram_raddr    = f1_f2_clken_o ? f1_sram_raddr : f2_sram_raddr_q;
  assign f1_sram_raddr = cacheop_valid_i ? cacheop_paddr_i : vpc_i;
  always_ff @( posedge clk ) begin
    if(f1_f2_clken_o) begin
      f2_sram_raddr_q <= f1_sram_raddr;
    end
  end

  i_tag_t [WAY_CNT-1:0] sram_tags;
  i_tag_t               sram_wtag;
  logic[WAY_CNT - 1 : 0][63:0] sram_datas;
  logic [       63:0]       sram_wdata  ;
  logic [        1:0][31:0] sel_data    ;
  logic [WAY_CNT-1:0]       sram_tag_we ;
  logic [WAY_CNT-1:0]       sram_data_we;
  logic[WAY_CNT - 1 : 0] hits;
  logic hit;
  for(genvar w = 0 ; w < WAY_CNT ; w++) begin
    sync_spram #(
      .DATA_WIDTH(64),
      .DATA_DEPTH(1 << 9),
      .BYTE_SIZE(32)
    ) dram (
      .clk     (clk       ),
      .rst_n   (rst_n     ),
      .addr_i  (idramaddr(sram_addr)),
      .we_i    ({sram_data_we[w] & !sram_waddr[2],
          sram_data_we[w] &  sram_waddr[2]}),
      .en_i    (f1_f2_clken_o || skid_busy_q),
      .rdata_o (sram_datas[w]),
      .wdata_i (sram_wdata)
    );
    sync_spram #(
      .DATA_WIDTH($bits(i_tag_t)),
      .DATA_DEPTH(1 << 8        ),
      .BYTE_SIZE ($bits(i_tag_t))
    ) tram (
      .clk    (clk                         ),
      .rst_n  (rst_n                       ),
      .addr_i (itramaddr(sram_addr)        ),
      .we_i   (sram_tag_we[w]              ),
      .en_i   (f1_f2_clken_o || skid_busy_q),
      .wdata_i(sram_wtag                   ),
      .rdata_o(sram_tags[w]                )
    );
  end
  for(genvar i = 0; i < WAY_CNT ; i++) begin
    assign hits[i] = icache_hit(sram_tags[i], cacheop_valid_q ? cacheop_paddr_q : ppc_i);
  end
  assign hit = |hits;
  always_comb begin
    sel_data = sram_datas[0];
    for(integer i = 1 ; i < WAY_CNT ; i++) begin
      if(hits[i]) begin
        sel_data = sram_datas[i];
      end
    end
  end

  // SKID FLUSHABLE SIGNAL
  logic [1:0] skid_valid_q;
  always_ff @(posedge clk) begin
    if(flush_i) begin
      skid_valid_q <= '0;
    end else begin
      if(!skid_busy_q) begin
        skid_valid_q <= fetch_valid_q;
      end
    end
  end

  logic [WAY_CNT-1:0] rnd_way_sel_q;
  always_ff @(posedge clk) begin
    if(!rst_n) begin
      rnd_way_sel_q[0]           <= '1;
      rnd_way_sel_q[WAY_CNT-1:1] <= '0;
    end else begin
      rnd_way_sel_q <= {rnd_way_sel_q[WAY_CNT - 2 : 0], rnd_way_sel_q[WAY_CNT - 1]};
    end
  end

  // SKID NON-FLUSHABLE SIGNAL
  logic [   ATTACHED_INFO_WIDTH-1:0] skid_attached_q     ;
  logic [F2_ATTACHED_INFO_WIDTH-1:0] skid_f2_attached_q  ;
  logic [               WAY_CNT-1:0] skid_way_sel_q      ;
  logic                              f2_need_skid        ; // TODO: CM
  logic                              skid_uncache_q      ;
  logic                              skid_cacheop_valid_q;
  logic                              skid_hit_q          ;
  logic [                       1:0] skid_cacheop_q      ;
  logic [                      31:0] skid_op_addr_q, skid_vpc_q;
  always_ff @(posedge clk) begin
    if(!skid_busy_q) begin
      skid_attached_q      <= attached_q;
      skid_f2_attached_q   <= f2_attached_i;
      skid_uncache_q       <= uncache_i;
      skid_cacheop_valid_q <= cacheop_valid_q;
      skid_hit_q           <= hit && !uncache_i && !cacheop_valid_q;
      skid_cacheop_q       <= cacheop_q;
      skid_op_addr_q       <= cacheop_valid_q ? cacheop_paddr_q : ppc_i;
      skid_way_sel_q       <= rnd_way_sel_q;
      skid_vpc_q           <= vpc_q;
    end
  end

  // SKID GEN SINGNAL
  logic [1:0]       refill_cnt_q;
  logic [1:0][31:0] skid_data_q ;

  // MAIN FSM
  typedef logic[9:0] icache_fsm_t;
  localparam   FSM_NORMAL        = 10'b0000000001;
  localparam   FSM_CACOP         = 10'b0000000010;
  localparam   FSM_RFADDR        = 10'b0000000100;
  localparam   FSM_RFDATA        = 10'b0000001000;
  localparam   FSM_PTADDR0       = 10'b0000010000;
  localparam   FSM_PTDATA0       = 10'b0000100000;
  localparam   FSM_PTADDR1       = 10'b0001000000;
  localparam   FSM_PTDATA1       = 10'b0010000000;
  localparam   FSM_WAITBUS       = 10'b0100000000;
  localparam   FSM_RECOVER       = 10'b1000000000;
  icache_fsm_t fsm_q                             ;
  logic [1:0]  skid_data_valid_q                 ;
  always_ff @(posedge clk) begin
    if(flush_i || !skid_busy_q) begin
      skid_data_valid_q <= '0;
    end else begin
      if(fsm_q == FSM_NORMAL) begin
        if(skid_hit_q) begin
          skid_data_valid_q <= skid_valid_q;
        end
      end else if(fsm_q == FSM_RFDATA) begin
        if((&refill_cnt_q) && bus_resp_i.data_ok) begin
          skid_data_valid_q <= skid_valid_q;
        end
      end else if(fsm_q == FSM_PTDATA0) begin
        if(bus_resp_i.data_ok && !skid_valid_q[1]) begin
          skid_data_valid_q <= skid_valid_q;
        end
      end else if(fsm_q == FSM_PTDATA1) begin
        if(bus_resp_i.data_ok) begin
          skid_data_valid_q <= skid_valid_q;
        end
      end
    end
  end

  always_ff @(posedge clk) begin
    if(!skid_busy_q) begin
      skid_data_q[0] <= sel_data[0];
    end else if((fsm_q == FSM_RFDATA && (refill_cnt_q[1] == skid_op_addr_q[3]) && !refill_cnt_q[0]) ||
      (fsm_q == FSM_PTDATA0)) begin
      skid_data_q[0] <= bus_resp_i.r_data;
    end
  end

  always_ff @(posedge clk) begin
    if(!skid_busy_q) begin
      skid_data_q[1] <= sel_data[1];
    end else if((fsm_q == FSM_RFDATA && (refill_cnt_q[1] == skid_op_addr_q[3])) ||
      (fsm_q == FSM_PTDATA1)) begin
      skid_data_q[1] <= bus_resp_i.r_data;
    end
  end

  assign sram_wdata   = {bus_resp_i.r_data, bus_resp_i.r_data};
  assign sram_wreq    = (fsm_q == FSM_CACOP || fsm_q == FSM_RFDATA);
  assign sram_data_we = skid_way_sel_q & {WAY_CNT{(bus_resp_i.data_ok && (fsm_q == FSM_RFDATA))}};
  assign sram_waddr   = {skid_op_addr_q[31:4], refill_cnt_q, 2'b00};
  assign sram_tag_we  = {WAY_CNT{(fsm_q == FSM_CACOP)}} |
    (skid_way_sel_q & {WAY_CNT{(fsm_q == FSM_RFDATA)}});
  assign sram_wtag.tag   = itagaddr(skid_op_addr_q);
  assign sram_wtag.valid = fsm_q == FSM_RFDATA;

  always_ff @( posedge clk ) begin
    if(fsm_q == FSM_RFADDR) begin
      refill_cnt_q <= '0;
    end else begin
      refill_cnt_q <= refill_cnt_q + bus_resp_i.data_ok;
    end
  end
  always_ff @( posedge clk ) begin : skid_fsm
    if(!rst_n) begin
      fsm_q       <= FSM_NORMAL;
      skid_busy_q <= '0;
    end else begin
      if(skid_busy_q) begin
        case (fsm_q)
          /*FSM_NORMAL*/default: begin
            if(skid_cacheop_valid_q) begin
              fsm_q <= FSM_CACOP;
            end else if(skid_hit_q) begin
              fsm_q <= FSM_RECOVER;
            end else if(bus_busy_i) begin
              fsm_q <= FSM_WAITBUS;
            end else if(skid_uncache_q) begin
              fsm_q <= skid_valid_q[0] ? FSM_PTADDR0 : FSM_PTADDR1;
            end else begin
              fsm_q <= FSM_RFADDR;
            end
          end
          FSM_RFADDR : begin
            if(bus_resp_i.ready) begin
              fsm_q <= FSM_RFDATA;
            end
          end
          FSM_RFDATA : begin
            if((&refill_cnt_q) && bus_resp_i.data_ok) begin
              fsm_q <= FSM_RECOVER;
            end
          end
          FSM_PTADDR0 : begin
            if(bus_resp_i.ready) begin
              fsm_q <= FSM_PTDATA0;
            end
          end
          FSM_PTDATA0 : begin
            if(bus_resp_i.data_ok) begin
              fsm_q <= skid_valid_q[1] ? FSM_PTADDR1 : FSM_RECOVER;
            end
          end
          FSM_PTADDR1 : begin
            if(bus_resp_i.ready) begin
              fsm_q <= FSM_PTDATA1;
            end
          end
          FSM_PTDATA1 : begin
            if(bus_resp_i.data_ok) begin
              fsm_q <= FSM_RECOVER;
            end
          end
          FSM_RECOVER : begin
            if(ready_i) begin
              fsm_q       <= FSM_NORMAL;
              skid_busy_q <= '0;
            end
          end
          FSM_WAITBUS : begin
            if(!bus_busy_i) begin
              fsm_q <= FSM_NORMAL;
            end
          end
          FSM_CACOP : begin
            fsm_q <= FSM_RECOVER;
          end
        endcase
      end else begin
        if(f2_need_skid) begin
          skid_busy_q <= '1;
        end
      end
    end
  end

  // OUTPUT
  assign attached_o    = skid_busy_q ? skid_attached_q : attached_q;
  assign pc_o          = skid_busy_q ? skid_vpc_q : vpc_q;
  assign valid_o       = skid_busy_q ? skid_data_valid_q : (hit ? fetch_valid_q : '0);
  assign inst_o        = skid_busy_q ? skid_data_q : sel_data;
  assign f2_attached_o = skid_busy_q ? skid_f2_attached_q : f2_attached_i;

  // FLOW CONTROLL
  assign f1_f2_clken_o   = !skid_busy_q;
  assign npc_ready_o     = !skid_busy_q && !cacheop_valid_i;
  assign cacheop_ready_o = !skid_busy_q;
  assign f2_need_skid    = !flush_i && (((|fetch_valid_q) && (!ready_i || uncache_i || !hit)) || (cacheop_valid_q));

endmodule
