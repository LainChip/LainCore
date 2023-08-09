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

  // MMU 地址信号, 在 VPC 同一拍
  input  logic [31:0] vpc_i,
  input  logic [31:0] ppc_i,
  input  logic [ATTACHED_INFO_WIDTH - 1 : 0] attached_i,

  input  logic paddr_valid_i, // 这个值必须始终为 1，不然目前的 cache 无法处理。
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

// 只有一个周期
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

logic[31:0] f1_vpc_q,f1_ppc_q;
logic[1:0] f1_valid_q;
// logic[511:0][1:0][31:0] data_ram;
// i_tag_t[255:0] tag_ram;
logic[8:0] dram_raddr;
logic dram_we;
logic[8:0] dram_waddr;
logic[1:0][31:0] dram_wdata;
always_ff @(posedge clk) begin
  if(~rst_n || clr_i) begin
    f1_valid_q <= '0;
  end else if(ready_o) begin
    f1_vpc_q   <= vpc_i;
    f1_ppc_q   <= ppc_i;
    f1_valid_q <= valid_i;
    attached_o <= attached_i;
  end
end
logic[9:0] refill_addr_q;// TODO
logic[1:0] refill_addr_q_q;
always_ff @(posedge clk) begin
  refill_addr_q_q <= refill_addr_q;
end
logic refill_data_ok_q;
logic[1:0][31:0] refill_data_q;
logic skid_q;

i_tag_t tram_rdata,tram_wdata;
i_tag_t f1_tag;
logic[7:0] tram_raddr;
logic tram_we;
logic[7:0] tram_waddr;
assign vpc_o   = f1_vpc_q;
assign ppc_o   = f1_ppc_q;
assign valid_o = ready_o ? f1_valid_q : 2'b00;
// always_ff @(posedge clk) begin
//   if(fsm_q == FSM_RFDATA && refill_data_ok_q) begin
//     data_ram[dram_waddr] <= refill_data_q;
//   end
// end
assign dram_we    = refill_data_ok_q;
assign dram_waddr = {refill_addr_q[9:2],refill_addr_q_q[1]};
assign dram_wdata = refill_data_q;
assign dram_raddr = idramaddr(vpc_i);
assign tram_raddr = itramaddr(vpc_i);
logic[1:0][31:0] inst;
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
    refill_data_q[0] <= refill_data_q[1];
    refill_data_q[1] <= bus_resp_i.r_data;
  end
end
// assign inst = data_ram[idramaddr(f1_vpc_q)];
always_comb begin
  // 更新 tag 的逻辑
  tram_waddr       = itramaddr(f1_vpc_q);
  tram_we          = fsm_q == FSM_RECVER || fsm_q == FSM_RFADDR;
  tram_wdata.valid = 1'b1;
  tram_wdata.tag   = itagaddr(f1_ppc_q);
end
for(genvar w = 0 ; w < WAY_CNT ; w++) begin
  simpleDualPortRam #(
    .dataWidth(64),
    .ramSize  (1 << 9),
    .latency  (1),
    .readMuler(1)
  ) dram (
    .clk     (clk       ),
    .rst_n   (rst_n     ),
    .addressA(dram_waddr),
    .we      (dram_we   ),
    .addressB(dram_raddr),
    .inData  (dram_wdata),
    .outData (inst)
  );
  simpleDualPortLutRam #(
    .dataWidth($bits(i_tag_t)),
    .ramSize  (1 << 8        ),
    .latency  (0             ),
    .readMuler(1)
  ) tram (
    .clk     (clk       ),
    .rst_n   (rst_n     ),
    .addressA(tram_waddr),
    .we      (tram_we   ),
    .addressB(tram_raddr),
    .re      (1'b1      ),
    .inData  (tram_wdata),
    .outData (tram_rdata)
  );
end
// assign tag = tag_ram[itagaddr(f1_vpc_q)];
// assign tag = '0;

// 与 VPC 同级
logic hit_early, hit_q, hit;
assign hit_early = icache_hit(tram_rdata, ppc_i);
always_ff @(posedge clk) begin
  hit_q <= hit;
end

always_comb begin
  hit = ready_o ? hit_early : hit_q;
  if(fsm_q == FSM_RFADDR) begin
    hit = 1'b1; // TODO: WAY ASSOCIATIVE
  end
end
logic uncached_finished_q,uncached_finished;
always_ff @(posedge clk) begin
  if(!rst_n) begin
    fsm_q               <= FSM_NORMAL;
    uncached_finished_q <= '0;
  end
  else begin
    fsm_q               <= fsm;
    uncached_finished_q <= uncached_finished;
  end
end
always_comb begin
  fsm               = fsm_q;
  uncached_finished = ready_i ? '0 : uncached_finished_q;
  case(fsm_q)
    default : begin
      fsm = FSM_NORMAL;
    end
    FSM_NORMAL : begin
      if(cacheop_valid_i) begin
        fsm = FSM_RECVER;
      end
      else if(paddr_valid_i && !uncached_i && !hit_q && |f1_valid_q) begin
        if(bus_busy_i) begin
          fsm = FSM_WAITBUS;
        end else begin
          fsm = FSM_RFADDR;
        end
      end
      else if(paddr_valid_i && uncached_i && !uncached_finished_q) begin
        if(bus_busy_i) begin
          fsm = FSM_WAITBUS;
        end else if(f1_valid_q[0]) begin
          fsm = FSM_PTADDR0;
        end
        else if(f1_valid_q[1]) begin
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
      fsm = FSM_NORMAL;
    end
    FSM_RFADDR : begin
      if(bus_resp_i.ready) begin
        fsm = FSM_RFDATA;
      end
    end
    FSM_RFDATA : begin
      if(refill_data_ok_q && refill_addr_q_q[1]) begin
        fsm = FSM_NORMAL;
      end
    end
    FSM_PTADDR0 : begin
      if(bus_resp_i.ready) begin
        fsm = FSM_PTDATA0;
      end
    end
    FSM_PTDATA0 : begin
      if(bus_resp_i.data_ok && bus_resp_i.data_last) begin
        if(!f1_valid_q[1]) begin
          fsm               = FSM_NORMAL;
          uncached_finished = 1'b1;
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
        fsm               = FSM_NORMAL;
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
      refill_addr_q[1:0] <= refill_addr_q[1:0] + 1;
    end
  end
end
always_ff @(posedge clk) begin
  if(!ready_o) begin
    skid_q <= 1'b1;
  end
  else begin
    skid_q <= 1'b0;
  end
end
logic[1:0][31:0] i_remember_data;
// DATA FETCH HERE
always_ff @(posedge clk) begin
  if((fsm_q == FSM_PTDATA0 ||
      (fsm_q == FSM_RFDATA && !refill_addr_q[0] && refill_addr_q[1] == f1_vpc_q[3])) &&
    bus_resp_i.data_ok) begin
    i_remember_data[0] <= bus_resp_i.r_data;
  end
  else if((fsm_q == FSM_PTDATA1 ||
      (fsm_q == FSM_RFDATA && refill_addr_q[0] && refill_addr_q[1] == f1_vpc_q[3])) && bus_resp_i.data_ok) begin
    i_remember_data[1] <= bus_resp_i.r_data;
  end
  else begin
    // SKID
    if(!skid_q) begin
      i_remember_data <= inst_o;
    end
  end
end

// DATA OUTPUT LOGIC
assign inst_o = skid_q ? i_remember_data : inst;

// READY LOGIC
assign cacheop_ready_o = fsm_q == FSM_NORMAL;
assign ready_o         = ready_i && fsm_q == FSM_NORMAL &&
  ((hit_q & !uncached_i) | (~|f1_valid_q) | uncached_finished_q);

// 产生总线赋值
always_comb begin
  bus_req_o.valid      = 1'b0;
  bus_req_o.write      = 1'b0;
  bus_req_o.burst_size = 4'b0011;
  bus_req_o.cached     = 1'b0;
  bus_req_o.data_size  = 2'b10;
  bus_req_o.addr       = {f1_ppc_q[31:12],refill_addr_q[0],2'd0};

  bus_req_o.data_ok     = 1'b0;
  bus_req_o.data_last   = 1'b0;
  bus_req_o.data_strobe = 4'b0000;
  bus_req_o.w_data      = '0;
  if(fsm_q == FSM_RFADDR) begin
    bus_req_o.valid = 1'b1;
    bus_req_o.addr  = {f1_ppc_q[31:4],4'd0};
  end
  else if(fsm_q == FSM_RFDATA || fsm_q == FSM_PTDATA0 || fsm_q == FSM_PTDATA1) begin
    bus_req_o.data_ok = 1'b1;
    bus_req_o.addr    = {f1_ppc_q[31:4],4'd0};
  end
  else if(fsm_q == FSM_PTADDR0 || fsm_q == FSM_PTADDR1) begin
    bus_req_o.valid      = 1'b1;
    bus_req_o.burst_size = 4'b0000;
    if(fsm_q == FSM_PTADDR1) begin
      bus_req_o.addr = {f1_ppc_q[31:3],3'b100};
    end
    else begin
      bus_req_o.addr = {f1_ppc_q[31:3],3'b000};
    end
  end
end

endmodule
