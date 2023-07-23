`include "pipeline.svh"
`include "lsu.svh"

module core_ifetch#(
    parameter int ATTACHED_INFO_WIDTH = 32,     // 用于捆绑bpu输出的信息，跟随指令流水
    parameter int WAY_CNT = `_IWAY_CNT                  // 指示cache的组相联度
  )(
    input clk,    // Clock
    input rst_n,  // Asynchronous reset active low

    input  logic [1:0] cacheop_i, // 输入两位的cache控制信号
    input  logic cacheop_valid_i, // 输入的cache控制信号有效
    output logic cacheop_ready_o,
    input  logic [1: 0] valid_i,
    output logic ready_o, // TO NPC/BPU

    input  logic [31:0] vpc_i,
    input  logic [ATTACHED_INFO_WIDTH - 1 : 0] attached_i,

    // MMU 访问信号, 在 VPC 后一拍
    input  logic [31:0] ppc_i,
    input  logic paddr_valid_i,
    input  logic uncached_i,

    output logic [31:0]vpc_o,
    output logic [31:0]ppc_o,
    input  logic ready_i, // FROM QUEUE
    output logic [1: 0] valid_o,
    output logic [ATTACHED_INFO_WIDTH - 1 : 0] attached_o,
    output logic [1: 0][31:0] inst_o,

    input  logic clr_i,

    input logic bus_busy_i,

    output cache_bus_req_t bus_req_o,
    input cache_bus_resp_t bus_resp_i
    // input trans_en_i
  );

  typedef logic[7:0] icache_fsm_t;
  localparam FSM_NORMAL = 8'b00000001;
  localparam FSM_RECVER = 8'b00000010;
  localparam FSM_RFADDR = 8'b00000100;
  localparam FSM_RFDATA = 8'b00001000;
  localparam FSM_PTADDR0 = 8'b00010000;
  localparam FSM_PTDATA0 = 8'b00100000;
  localparam FSM_PTADDR1 = 8'b01000000;
  localparam FSM_PTDATA1 = 8'b10000000;
  icache_fsm_t fsm_q,fsm;

  // 只有一个周期
  typedef struct packed {
            logic valid;
            logic[`_ITAG_LEN - 1 : 0] tag;
          } i_tag_t;

  function logic[`_ITAG_LEN - 1 : 0] itagaddr(logic[31:0] va);
    return va[`_ITAG_LEN + `_IIDX_LEN - 1: `_IIDX_LEN];
  endfunction
  function logic[7 : 0] itramaddr(logic[31:0] va);
    return va[`_IIDX_LEN - 1 -: 8];
  endfunction
  function logic[`_DIDX_LEN - 1 : 2] idramaddr(logic[31:0] va);
    return va[`_IIDX_LEN - 1 : 2];
  endfunction
  function logic icache_hit(i_tag_t tag,logic[31:0] pa);
    return tag.valid && (itagaddr(pa) == tag.tag);
  endfunction

  logic[31:0] f1_vpc_q;
  logic[1:0] f1_valid_q;
  logic[512:0][1:0][31:0] data_ram;
  i_tag_t[255:0] tag_ram;
  i_tag_t tag;
  logic[9:0] refill_addr_q; // TODO
  logic refill_data_ok_q;
  logic[1:0][31:0] refill_data_q;
  logic skid_q;
  always_ff @(posedge clk) begin
    if(~rst_n || clr_i) begin
      f1_valid_q <= '0;
    end else if(ready_o) begin
      f1_vpc_q <= vpc_i;
      f1_valid_q <= valid_i;
      attached_o <= attached_i;
    end
  end
  assign vpc_o = f1_vpc_q;
  assign ppc_o = ppc_i;
  assign valid_o = ready_o ? f1_valid_q : 2'b00;
  always_ff @(posedge clk) begin
    if(fsm_q == FSM_RFDATA && refill_data_ok_q) begin
      data_ram[refill_addr_q[9:1]] <= refill_data_q;
    end
  end
  always_ff @(posedge clk) begin
    if(fsm_q == FSM_RFDATA && refill_addr_q[0] && bus_resp_i.data_ok) begin
      refill_data_ok_q <= 1'b1;
    end
    else begin
      refill_data_ok_q <= 1'b0;
    end
  end
  always_ff @(posedge clk) begin
    if(bus_resp_i.data_ok) begin
      refill_data_q[1] <= refill_data_q[0];
      refill_data_q[0] <= bus_resp_i.r_data;
    end
  end
  logic[1:0][31:0] inst;
  assign inst = data_ram[idramaddr(f1_vpc_q)];
  assign tag = tag_ram[itagaddr(f1_vpc_q)];

  logic hit;
  assign hit = icache_hit(tag, ppc_i);

  logic uncached_finished_q,uncached_finished;
  always_ff @(posedge clk) begin
    if(!rst_n) begin
      fsm_q <= FSM_NORMAL;
      uncached_finished_q <= '0;
    end
    else begin
      fsm_q <= fsm;
      uncached_finished_q <= uncached_finished;
    end
  end
  always_comb begin
    fsm = fsm_q;
    uncached_finished = ready_i ? '0 : uncached_finished_q;
    case(fsm_q)
      default: begin
        fsm = FSM_NORMAL;
      end
      FSM_NORMAL: begin
        if(cacheop_valid_i) begin
          fsm = FSM_RECVER;
        end
        else if(paddr_valid_i && !uncached_i && !hit && |f1_valid_q) begin
          fsm = FSM_RFADDR;
        end
        else if(paddr_valid_i && uncached_i && !uncached_finished_q) begin
          if(f1_valid_q[0]) begin
            fsm = FSM_PTADDR0;
          end
          else if(f1_valid_q[1]) begin
            fsm = FSM_PTADDR1;
          end
        end
      end
      FSM_RECVER: begin
        fsm = FSM_NORMAL;
      end
      FSM_RFADDR: begin
        if(bus_resp_i.ready) begin
          fsm = FSM_RFDATA;
        end
      end
      FSM_RFDATA: begin
        if(bus_resp_i.data_ok && bus_resp_i.data_last) begin
          fsm = FSM_NORMAL;
        end
      end
      FSM_PTADDR0: begin
        if(bus_resp_i.ready) begin
          fsm = FSM_PTDATA0;
        end
      end
      FSM_PTDATA0: begin
        if(bus_resp_i.data_ok && bus_resp_i.data_last) begin
          if(!f1_valid_q[1]) begin
            fsm = FSM_NORMAL;
            uncached_finished = 1'b1;
          end
          else begin
            fsm = FSM_PTADDR1;
          end
        end
      end
      FSM_PTADDR1: begin
        if(bus_resp_i.ready) begin
          fsm = FSM_PTDATA1;
        end
      end
      FSM_PTDATA1: begin
        if(bus_resp_i.data_ok && bus_resp_i.data_last) begin
          fsm = FSM_NORMAL;
          uncached_finished = 1'b1;
        end
      end
    endcase
  end
  always_ff @(posedge clk) begin
    if(fsm_q == FSM_RFADDR) begin
      refill_addr_q <= {itramaddr(f1_vpc_q),2'd0};
    end
    else begin
      if(bus_resp_i.data_ok) begin
        refill_addr_q <= refill_addr_q + 1;
      end
    end
  end
  always_ff @(posedge clk) begin
    if(fsm_q != FSM_NORMAL) begin
      skid_q <= 1'b1;
    end
    else begin
      skid_q <= 1'b0;
    end
  end
  logic[1:0][31:0] i_remember_data;
  // DATA FETCH HERE
  always_ff @(posedge clk) begin
    if(bus_resp_i.data_ok) begin
      if(fsm_q == FSM_RFDATA && f1_vpc_q[3] == refill_addr_q[3] && bus_resp_i.data_ok) begin
        i_remember_data[refill_addr_q[2]] <= bus_resp_i.r_data;
      end
      else if(fsm_q == FSM_PTDATA0 && bus_resp_i.data_ok) begin
        i_remember_data[0] <= bus_resp_i.r_data;
      end
      else if(fsm_q == FSM_PTDATA1 && bus_resp_i.data_ok) begin
        i_remember_data[1] <= bus_resp_i.r_data;
      end
    end
  end

  // DATA OUTPUT LOGIC
  assign inst_o = skid_q ? i_remember_data : inst;

  // READY LOGIC
  assign cacheop_ready_o = fsm_q == FSM_NORMAL;
  assign ready_o = ready_i && fsm_q == FSM_NORMAL && ((hit & !uncached_i) | (~|f1_valid_q) | uncached_finished_q);

  // 产生总线赋值
  always_comb begin
    bus_req_o.valid       = 1'b0;
    bus_req_o.write       = 1'b0;
    bus_req_o.burst_size  = 4'b0011;
    bus_req_o.cached      = 1'b0;
    bus_req_o.data_size   = 2'b10;
    bus_req_o.addr        = {ppc_i[31:12],refill_addr_q[0],2'd0};

    bus_req_o.data_ok     = 1'b0;
    bus_req_o.data_last   = 1'b0;
    bus_req_o.data_strobe = 4'b0000;
    bus_req_o.w_data      = '0;
    if(fsm_q == FSM_RFADDR) begin
      bus_req_o.valid = 1'b1;
      bus_req_o.addr  = {ppc_i[31:4],4'd0};
    end
    else if(fsm_q == FSM_RFDATA || fsm_q == FSM_PTDATA0 || fsm_q == FSM_PTDATA1) begin
      bus_req_o.data_ok    = 1'b1;
      bus_req_o.addr  = {ppc_i[31:4],4'd0};
    end
    else if(fsm_q == FSM_PTADDR0 || fsm_q == FSM_PTADDR1) begin
      bus_req_o.valid      = 1'b1;
      bus_req_o.burst_size = 4'b0000;
      if(fsm_q == FSM_PTADDR1) begin
        bus_req_o.addr  = {ppc_i[31:3],3'b100};
      end
      else begin
        bus_req_o.addr  = {ppc_i[31:3],3'b000};
      end
    end
  end

endmodule
