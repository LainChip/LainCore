`include "lsu.svh"

module core_lsu_pm #(
  parameter int WAY_CNT = `_DWAY_CNT
) (
  input logic clk,
  input logic rst_n,

  input logic [31:0] ex_vaddr_i,
  input logic ex_read_i,
  input logic [31:0] m1_vaddr_i,
  input logic [31:0] m1_paddr_i,
  input logic [ 3:0] m1_strobe_i,
  input logic m1_read_i,
  input logic m1_uncached_i,
  output logic m1_busy_o, // M1 级的 LSU 允许 stall
  input logic m1_stall_i,

  output logic [31:0] m1_rdata_o,
  output logic m1_rvalid_o,  // 结果早出级

  input logic [31:0] m2_vaddr_i,
  input logic [31:0] m2_paddr_i,
  input logic [31:0] m2_wdata_i,
  input logic [ 3:0] m2_strobe_i,
  input logic [ 2:0] m2_type_i,
  input logic m2_valid_i,
  input logic m2_uncached_i,
  input logic [1:0] m2_size_i, // uncached 专用
  output logic m2_busy_o, // M2 级别的 LSU 允许 stall
  input logic m2_stall_i,
  input logic [2:0] m2_op_i, // TODO: CONNECT ME

  output logic [31:0] m2_rdata_o,
  output logic m2_rvalid_o,  // 需要 fmt 的结果级

  output dram_manager_req_t dm_req_o,
  input dram_manager_resp_t dm_resp_i,
  input dram_manager_snoop_t dm_snoop_i
);
// 接入 M2 级别的有效信号时需要注意内存序陷阱。
// 第二条管线的内存序靠后，一定需要后一个执行。
// 也即产生 BANK CONFLICT 时，优先执行后者。
// 若两者同时产生了 CACHE 冲突，优先执行后者。
// 对 DCACHE FLUSH 类 cacop，不需要刷新管线。
// 对 ICACHE FLUSH 类 cacop，需要刷新管线。
// 最后统一的妥协就是单发射 cacop。


// M1 级接线，具有时序逻辑。
// M1 级共三个状态：
// NORMAL，即为正常状态，可以接受请求
// WAIT，即为等待 dram_manager 状态，等待 r_valid_d1 置高，且依然需要监视 snoop 端口
// SNOOP，读端口上的数据已经就绪，等待 cpu 管线撤回 stall 信号，持续监视 snoop 端口

// M1 状态机电路
logic[2:0] m1_fsm_q, m1_fsm;
logic m1_rvalid;
// EX 级接线（真的就是单纯的接线）
always_comb begin
  dm_req_o.rvalid = m1_busy_o ? m1_rvalid : ex_read_i;
  dm_req_o.raddr  = m1_busy_o ? m1_vaddr_i : ex_vaddr_i;
end
localparam logic[2:0]M1_FSM_NORMAL = 3'b001;
localparam logic[2:0]M1_FSM_WAIT = 3'b010;
localparam logic[2:0]M1_FSM_SNOOP = 3'b100;
assign m1_rvalid = m1_fsm_q == M1_FSM_WAIT;
always_ff@(posedge clk) begin
  if(~rst_n) begin
    m1_fsm_q <= M1_FSM_NORMAL;
  end
  else begin
    m1_fsm_q <= m1_fsm;
  end
end
always_comb begin
  m1_fsm = m1_fsm_q;
  casez(m1_fsm_q)
    3'b??1 : begin
      if(m1_read_i && !dm_resp_i.r_valid_d1) begin
        m1_fsm = M1_FSM_WAIT;
      end
      else if(m1_stall_i) begin
        m1_fsm = M1_FSM_SNOOP;
      end
    end
    3'b?10 : begin
      if(dm_resp_i.r_valid_d1) begin
        if(!m1_stall_i) begin
          m1_fsm = M1_FSM_NORMAL;
        end
        else begin
          m1_fsm = M1_FSM_SNOOP;
        end
      end
    end
    3'b100 : begin
      if(!m1_stall_i) begin
        m1_fsm = M1_FSM_NORMAL;
      end
    end
    default : begin
      // 非合法值
      m1_fsm = M1_FSM_NORMAL;
    end
  endcase
end

// M1 嗅探电路
logic[WAY_CNT - 1 : 0][31:0] m1_data_q,m1_data,m2_data_q,m2_data;
dcache_tag_t[WAY_CNT - 1 : 0] m1_tag_q,m1_tag,m2_tag_q,m2_tag;
always_ff @(posedge clk) begin
  m1_data_q <= m1_data;
  m1_tag_q  <= m1_tag;
end
always_comb begin
  m1_data = ((m1_fsm_q & (M1_FSM_NORMAL | M1_FSM_WAIT)) != 0) ? dm_resp_i.rdata_d1 : m1_data_q;
  for(integer b = 0 ; b < `_DBANK_CNT ; b++) begin
    for(integer i = 0 ; i < WAY_CNT ; i++) begin
      for(integer s = 0 ; s < 4 ; s++) begin
        if(dm_snoop_i.data_we[b][i][s] &&
          {dm_snoop_i.data_waddr[b[$clog2(`_DBANK_CNT) - 1: 0]], b[$clog2(`_DBANK_CNT) - 1: 0]} == dramaddr(m1_vaddr_i)) begin
          m1_data[i][7+8*s-:8] = dm_snoop_i.data_wdata[b[$clog2(`_DBANK_CNT) - 1: 0]][7 + 8 * s -: 8];
        end
      end
    end
  end
end
always_comb begin
  m1_tag = ((m1_fsm_q & (M1_FSM_NORMAL | M1_FSM_WAIT)) != 0) ? dm_resp_i.tag_d1 : m1_tag_q;
  for(integer i = 0 ; i < WAY_CNT ; i++) begin
    if(dm_snoop_i.tag_we[i] && dm_snoop_i.tag_waddr == tramaddr(m1_vaddr_i)) begin
      m1_tag[i] = dm_snoop_i.tag_wdata;
    end
  end
end

// M1 output 电路
if(WAY_CNT == 1) begin
  always_comb begin
    // 早出条件较为苛刻，要求之前没有未完成的写请求，缓存命中，非不可缓存。
    m1_rdata_o = dm_resp_i.rdata_d1[0];
    m1_rvalid_o = dm_resp_i.r_valid_d1 && cache_hit(dm_resp_i.tag_d1[0], m1_paddr_i)
      && !dm_resp_i.pending_write && !m1_uncached_i
      && (m1_paddr_i[1:0] == '0) && &m1_strobe_i;
  end
end
else begin
  always_comb begin
    m1_rdata_o = '0;
    m1_rvalid_o = '0;
  end
end
logic wb_pending_write_q;
logic m2_pending_write;
assign m2_pending_write = ((m2_op_i == `_DCAHE_OP_WRITE) && m2_valid_i) || m2_busy_o;
always_ff @(posedge clk) begin
  wb_pending_write_q <= m2_pending_write;
end
assign dm_req_o.pending_write = wb_pending_write_q | m2_pending_write;
// assign dm_req_o.pending_write = 1'b1;

// M1 busy 电路
always_comb begin
  m1_busy_o = (m1_fsm_q == M1_FSM_WAIT) || (m1_fsm_q == M1_FSM_NORMAL && m1_read_i && !dm_resp_i.r_valid_d1);
end

// 注意：这部分需要在 M1 - M2 级之间进行流水。
logic [WAY_CNT-1:0] m1_hit,m2_hit_q,m2_hit;
logic               m1_miss,m2_miss_q,m2_miss;
logic[31:0] m2_wdata;

// M1 HIT MISS 电路
for(genvar i = 0 ; i < WAY_CNT ; i++) begin
  assign m1_hit[i] = cache_hit(m1_tag[i], m1_paddr_i);
end
assign m1_miss = ~|m1_hit;

// M2 控制流水线寄存器
always_ff @(posedge clk) begin
  m2_hit_q  <= m2_hit;
  m2_miss_q <= m2_miss;
  m2_data_q <= m2_data;
  m2_tag_q  <= m2_tag;
end

// M2 状态机
// 这个状态机需要做得事情很有限，所有 CACHE 操作请求都通过 request 的形式提交给 RAM 管理者进行，
// 本地只需要轮询本地寄存器等待结果被从 snoop 中捕捉到就可以了。
logic[6:0] m2_fsm_q,m2_fsm;
localparam logic[6:0] M2_FSM_NORMAL      = 7'b0000001;// 1
localparam logic[6:0] M2_FSM_CREAD_MISS  = 7'b0000010;// 2
localparam logic[6:0] M2_FSM_UREAD_WAIT  = 7'b0000100;// 4
localparam logic[6:0] M2_FSM_CWRITE_MISS = 7'b0001000;// 8
localparam logic[6:0] M2_FSM_WRITE_WAIT  = 7'b0010000;// 对于写请求，无论是否可缓存，均用此状态等待。
// 当等待写完成时，若 cached 请求突然 miss，也需要转移状态到 CWRITE_MISS 等待重填。
localparam logic[6:0] M2_FSM_CACHE_OP    = 7'b0100000;
localparam logic[6:0] M2_FSM_WAIT_STALL  = 7'b1000000;
always_ff@(posedge clk) begin
  if(!rst_n) begin
    m2_fsm_q <= M2_FSM_NORMAL;
  end
  else begin
    m2_fsm_q <= m2_fsm;
  end
end
always_comb begin
  m2_busy_o = (m2_fsm_q & (M2_FSM_NORMAL | M2_FSM_WAIT_STALL)) == 0;
  m2_fsm    = m2_fsm_q;
  case (m2_fsm_q)
    M2_FSM_NORMAL : begin
      if(m2_valid_i && !m2_uncached_i && m2_miss_q) begin
        if(m2_op_i == `_DCAHE_OP_READ) begin
          m2_fsm    = M2_FSM_CREAD_MISS;
          m2_busy_o = 1'b1;
        end
        else if(m2_op_i == `_DCAHE_OP_WRITE) begin
          m2_fsm    = M2_FSM_CWRITE_MISS;
          m2_busy_o = 1'b1;
        end
      end
      else if(m2_valid_i && m2_uncached_i && m2_op_i == `_DCAHE_OP_READ) begin
        m2_fsm    = M2_FSM_UREAD_WAIT;
        m2_busy_o = 1'b1;
      end
      else if(m2_valid_i && m2_op_i == `_DCAHE_OP_WRITE && !dm_resp_i.we_ready) begin
        m2_fsm    = M2_FSM_WRITE_WAIT;
        m2_busy_o = 1'b1;
      end
      else if(m2_valid_i && ((m2_op_i == `_DCAHE_OP_HIT_INV && !m2_miss_q) || m2_op_i != `_DCAHE_DIRECT_INV)) begin
        m2_fsm    = M2_FSM_CACHE_OP;
        m2_busy_o = 1'b1;
      end
    end
    M2_FSM_CREAD_MISS : begin
      if(!m2_miss_q) begin
        if(m2_stall_i) begin
          m2_fsm = M2_FSM_WAIT_STALL;
        end
        else begin
          m2_fsm = M2_FSM_NORMAL;
        end
      end
    end
    M2_FSM_CWRITE_MISS : begin
      if(!m2_miss_q) begin
        if(dm_resp_i.we_ready) begin
          if(m2_stall_i) begin
            m2_fsm = M2_FSM_WAIT_STALL;
          end
          else begin
            m2_fsm = M2_FSM_NORMAL;
          end
        end
        else begin
          m2_fsm = M2_FSM_WRITE_WAIT;
        end
      end
    end
    M2_FSM_WRITE_WAIT : begin
      if(m2_miss_q && !m2_uncached_i) begin
        m2_fsm = M2_FSM_CWRITE_MISS;
      end
      else begin
        if(dm_resp_i.we_ready) begin
          if(m2_stall_i) begin
            m2_fsm = M2_FSM_WAIT_STALL;
          end
          else begin
            m2_fsm = M2_FSM_NORMAL;
          end
        end
      end
    end
    M2_FSM_WAIT_STALL : begin
      if(!m2_stall_i) begin
        m2_fsm = M2_FSM_NORMAL;
      end
    end
    M2_FSM_CACHE_OP : begin
      if(dm_resp_i.op_ready) begin
        if(m2_stall_i) begin
          m2_fsm = M2_FSM_WAIT_STALL;
        end
        else begin
          m2_fsm = M2_FSM_NORMAL;
        end
      end
    end
    M2_FSM_UREAD_WAIT : begin
      if(dm_resp_i.op_ready) begin
        if(m2_stall_i) begin
          m2_fsm = M2_FSM_WAIT_STALL;
        end
        else begin
          m2_fsm = M2_FSM_NORMAL;
        end
      end
    end
    default : begin
      m2_fsm = M2_FSM_NORMAL;
    end
  endcase
end

// M2 数据维护
always_comb begin
  if(!m2_stall_i) begin
    m2_data = m1_data;
  end
  else begin
    m2_data = m2_data_q;
    for(integer b = 0 ; b < `_DBANK_CNT ; b++) begin
      for(integer i = 0 ; i < WAY_CNT ; i++) begin
        for(integer s = 0 ; s < 4;s++) begin
          if(m2_miss_q && dm_snoop_i.data_we[b][i][s] &&
            {dm_snoop_i.data_waddr[b[$clog2(`_DBANK_CNT) - 1: 0]], b[$clog2(`_DBANK_CNT) - 1: 0]} == dramaddr(m2_vaddr_i)) begin
            m2_data[i][7+8*s-:8] = dm_snoop_i.data_wdata[b[$clog2(`_DBANK_CNT) - 1: 0]][7 + 8 * s -: 8];
          end
        end
      end
    end
    if(m2_fsm_q == M2_FSM_UREAD_WAIT) begin
      m2_data[0] = dm_resp_i.r_uncached;
    end
  end
end
// M2 TAG 维护
always_comb begin
  if(!m2_stall_i) begin
    m2_tag = m1_tag;
  end
  else begin
    m2_tag = m2_tag_q;
    for(integer i = 0 ; i < WAY_CNT ; i++) begin
      if(dm_snoop_i.tag_we[i] && dm_snoop_i.tag_waddr == tramaddr(m2_vaddr_i)) begin
        m2_tag[i] = dm_snoop_i.tag_wdata;
      end
    end
  end
end

// M2 MISS / HIT 维护
always_comb begin
  if(!m2_stall_i) begin
    m2_hit  = m1_hit;
    m2_miss = m1_miss;
  end
  else begin
    // 时刻监控对 tag 的读写，以维护新的 hit / miss
    m2_hit = m2_hit_q;
    for(integer i = 0 ; i < WAY_CNT ; i++) begin
      if(dm_snoop_i.tag_we[i] && dm_snoop_i.tag_waddr == tramaddr(m2_vaddr_i)) begin
        m2_hit[i] = cache_hit(dm_snoop_i.tag_wdata, m2_paddr_i);
      end
    end
    m2_miss = ~|m2_hit;
  end
end

// M2 写数据维护
always_comb begin
  m2_wdata = mkstrobe(mkwsft(m2_wdata_i, m2_vaddr_i),m2_strobe_i);
end

// 产生向 DM 的请求
always_comb begin
  dm_req_o.we_valid = m2_valid_i && (m2_op_i == `_DCAHE_OP_WRITE) && (m2_uncached_i || !m2_miss_q) &&
    (m2_fsm_q & (M2_FSM_WRITE_WAIT | M2_FSM_NORMAL)) != 0;
  dm_req_o.uncached = m2_uncached_i;
  dm_req_o.strobe   = m2_strobe_i;
  dm_req_o.size     = m2_size_i;
  dm_req_o.we_sel   = m2_hit_q;
  dm_req_o.wdata    = m2_wdata;
  // dm_req_o.op_type  = m2_op_i;
  if((m2_fsm_q & (M2_FSM_CREAD_MISS | M2_FSM_CWRITE_MISS)) != 0) begin
    dm_req_o.op_type = 4'b0001;
  end else begin
    dm_req_o.op_type = 4'b0010;
  end
  // TODO: SUPPORT CACOP HERE.
  dm_req_o.op_valid = (m2_fsm_q & (M2_FSM_CACHE_OP | M2_FSM_UREAD_WAIT | M2_FSM_CREAD_MISS | M2_FSM_CWRITE_MISS)) != 0;
  dm_req_o.op_addr  = m2_paddr_i;
  dm_req_o.old_tags = m2_tag_q;
end

// 输出管理

// output logic [31:0] m2_rdata_o,
// output logic m2_rvalid_o,  // 需要 fmt 的结果级
always_comb begin
  m2_rdata_o  = mkrsft(m2_data_q, m2_vaddr_i, m2_type_i);
  m2_rvalid_o = !m2_busy_o && m2_valid_i && m2_op_i == `_DCAHE_OP_READ;
end

endmodule
