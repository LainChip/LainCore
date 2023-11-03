`include "pipeline.svh"
`include "lsu.svh"
/*--JSON--{"module_name":"core_fetch","module_ver":"1","module_type":"module"}--JSON--*/

module core_fetch #(
  parameter int ATTACHED_INFO_WIDTH = 32        , // 用于捆绑bpu输出的信息，跟随指令流水
  parameter int WAY_CNT             = `_IWAY_CNT  // 指示cache的组相联度
) (
  // GLOBAL
  input  logic                                 clk            ,
  input  logic                                 rst_n          ,
  input  logic                                 flush_i        ,
  input  logic                                 bus_busy_i     ,
  output cache_bus_req_t                       bus_req_o      ,
  input  cache_bus_resp_t                      bus_resp_i     ,
  // F1 STAGE
  output logic                                 ready_o        ,
  input  logic [                    1:0]       valid_i        ,
  input  logic                                 cacheop_valid_i, // 输入的cache控制信号有效
  input  logic [                    1:0]       cacheop_i      ,
  input  logic [                   31:0]       cacheop_paddr_i,
  input  logic [                   31:0]       vpc_i          ,
  input  logic [ATTACHED_INFO_WIDTH-1:0]       attached_i     ,
  // F1-F2 STAGE REGISTER Enable FOR TLB
  output logic                                 f1_f2_clken_o  ,
  // F2 STAGE
  input  logic                                 uncache_i      ,
  input  logic [                   31:0]       ppc_i          ,
  output logic [ATTACHED_INFO_WIDTH-1:0]       attached_o     ,
  output logic [                   31:0]       pc_o           ,
  output logic [                    1:0]       valid_o        ,
  output logic [                    1:0][31:0] inst_o         ,
  input  logic                                 ready_i
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
  logic [ 1:0] cacheop_q      ;
  logic [31:0] cacheop_paddr_q;
  logic        cacheop_valid_q;
  always_ff @(posedge clk) begin
    if(f1_f2_clken_o) begin
      cacheop_q       <= cacheop_i;
      cacheop_paddr_q <= cacheop_paddr_i;
      cacheop_valid_q <= cacheop_valid_i;
    end
  end

  logic skid_busy_q;

  logic[31:0] sram_raddr, sram_waddr, sram_addr;
  logic  sram_wreq                                      ;
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
  logic [       63:0] sram_wdata ;
  logic [       63:0] sel_data   ;
  logic [WAY_CNT-1:0] sram_tag_we, sram_data_we;
  logic[WAY_CNT - 1 : 0] hits;
  logic hit;
  for(genvar i = 0; i < WAY_CNT ; i++) begin
    assign hits[i] = icache_hit(sram_tags[i], cacheop_q ? cacheop_paddr_q : ppc_i);
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

  // SKID BUF
  logic              f2_need_skid        ;
  logic              skid_uncache_q      ;
  logic              skid_cacheop_valid_q;
  logic [ 1:0]       skid_hit_q          ;
  logic [ 1:0]       skid_valid_q        ;
  logic [ 1:0]       skid_cacheop_q      ;
  logic [31:0]       skid_op_addr_q      ;
  logic [ 1:0][31:0] skid_data_q         ;

  // MAIN FSM
  typedef logic[9:0] icache_fsm_t;
  localparam   FSM_NORMAL  = 10'b0000000001;
  localparam   FSM_CACOP   = 10'b0000000010;
  localparam   FSM_RFADDR  = 10'b0000000100;
  localparam   FSM_RFDATA  = 10'b0000001000;
  localparam   FSM_PTADDR0 = 10'b0000010000;
  localparam   FSM_PTDATA0 = 10'b0000100000;
  localparam   FSM_PTADDR1 = 10'b0001000000;
  localparam   FSM_PTDATA1 = 10'b0010000000;
  localparam   FSM_WAITBUS = 10'b0100000000;
  localparam   FSM_RECOVER = 10'b1000000000;
  icache_fsm_t fsm_q                       ;
  always_ff @( posedge clk ) begin : skid_fsm
    if(!rst_n) begin
      fsm_q          <= FSM_NORMAL;
      skid_busy_q    <= '0;
    end else begin
      if(skid_busy_q) begin
        case (fsm_q)
          /*FSM_NORMAL*/default: begin
            if(skid_cacheop_valid_q) begin
              fsm_q <= FSM_CACOP;
            end else if(bus_busy_i) begin
              fsm_q <= FSM_WAITBUS;
            end if(skid_uncache_q) begin
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
            if((&skid_op_addr_q[3:2]) && refill_valid_q) begin
              fsm_q <= FSM_RECOVER;
            end
          end
        endcase
      end else begin
        if(f2_need_skid) begin
          skid_busy_q    <= '1;
        end
      end
    end
  end

  // OUTPUT

endmodule
