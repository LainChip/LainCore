`ifndef _CACHED_LSU_V3_HEADER
`define _CACHED_LSU_V3_HEADER

        // 全新设计思路，分离流水线部分以及管理部分
        // 流水线部分只负责和管线部分交互，完全不在乎 RAM 管理部分如何对 RAM 进行维护和管理。
        // 流水线部分高度可配置，支持组相连 / 直接映射。
        // CACHE 的管理部分不支持 byte-wide operation， CACHE 需要手动控制写操作进行融合。

`define _DWAY_CNT 2
`define _DBANK_CNT 2
`define _DIDX_LEN 12
`define _DTAG_LEN 20
`define _DCAHE_OP_READ 1
`define _DCAHE_OP_WRITE 2
`define _DCAHE_OP_HIT_INV 3
`define _DCAHE_OP_DIRECT_INV 4
`define _IWAY_CNT 1
`define _IIDX_LEN 12
`define _ITAG_LEN 20

        typedef struct packed{
          // 请求信号
          logic       valid     ; // 拉高时说明cache的请求有效，请求有效后，valid信号应该被拉低
          logic       write     ; // 拉高时说明cache请求进行写入
          logic [3:0] burst_size; // 0 for no burst, n for n + 1 times burst
          logic       cached    ; // 0 for uncached, 1 for cached, when cached and coherence exchange imple,
          // cached is although responsible for shareable between masters.
          logic [1:0] data_size; // n for (1 << n) bytes in a transfer
          logic[31:0] addr;                        // cache请求的物理地址

          // 数据
          logic data_ok  ; // 写入时，此信号用于说明cache已准备好提供数据。 读取时，此信号说明cache已准备好接受数据。
          logic data_last; // 拉高时标记最后一个元素，只有读到此信号才认为传输事务结束
          logic[3 :0] data_strobe;
          logic[31:0] w_data; // cache请求的写数据
        }cache_bus_req_t;

typedef struct packed{
          // 响应信号
          logic ready; // 说明cache的请求被响应，响应后ready信号也应该被拉低

          // 数据
          logic data_ok  ; // 拉高时说明总线数据有效
          logic data_last; // 最后一个有效数据
          logic[31:0] r_data; // 总线返回的数据
        }cache_bus_resp_t;

typedef struct packed {
          logic valid;
          logic[`_DTAG_LEN - 1 : 0] addr;
        } dcache_tag_t;

typedef struct packed {
          logic pending_write;

          logic rvalid;
          logic[31:0] raddr;

          logic we_valid;
          logic uncached;
          logic[3:0] strobe;
          logic[1:0] size;
          logic[`_DWAY_CNT - 1 : 0] we_sel;
          logic[31:0] wdata;

          logic op_valid;
          logic[3:0]  op_type;
          logic[31:0] op_addr;
          dcache_tag_t[`_DWAY_CNT - 1 : 0] old_tags;
        } dram_manager_req_t;

typedef struct packed {
          logic pending_write; // means that rdata_d1 is not the most newest value now.

          // dcache_tag_t[`_DWAY_CNT - 1 : 0] tag_d0; // NO USAGE NOW
          dcache_tag_t[`_DWAY_CNT - 1 : 0] tag_d1;
          // dcache_tag_t etag_d0; // TODO
          // dcache_tag_t etag_d1;

          logic[`_DWAY_CNT - 1 : 0][31:0] rdata_d1;
          logic r_valid_d1;

          logic we_ready;
          logic[31:0] r_uncached;

          logic op_ready;
        } dram_manager_resp_t;

typedef struct packed {
          // 仅有这两个请求有可能同时出现
          logic cache_refill_valid;
          logic uncached_read;

          // 不可能同时出现的请求
          logic hit_write_req_valid; // 不需要暂停
          logic cache_op_inv;
          logic miss_write_req_valid;
          logic uncached_write_valid;

          // 请求相关地址以及数据
          logic [31:0] addr;
          logic [1:0] rwsize;
          logic [`_DWAY_CNT - 1 : 0] wsel;
          logic [3:0] wstrobe;
          logic [31:0] wdata;

          // take over 写回用
          logic [`_DWAY_CNT - 1 : 0][31:0] rdata; // c
          dcache_tag_t [`_DWAY_CNT - 1 : 0] tag_rdata; // c
        } rport_state_t;

typedef struct packed {
          // 仅有这两个请求有可能同时出现
          logic uop_ready; // c
          // logic cache_refill_ready; // 合并至 uop_ready 信号
          // 握手要求： ready 拉高后，一周期 valid 拉低。
          logic read_ready; // 标识当前数据有效 c
          logic [31:0] rdata; // c

          // 不可能同时出现的请求
          logic uncached_write_ready; // c

          logic dram_take_over; // c
          logic[`_DIDX_LEN - 1 : 2] data_raddr; // c
        } wport_state_t;

typedef struct packed {
          logic[7:0] tag_waddr; // c
          dcache_tag_t tag_wdata; // c
          logic[`_DWAY_CNT - 1 : 0] tag_we; // c

          logic[`_DIDX_LEN - 1 : 2] data_waddr; // c
          logic[31:0] data_wdata; // c
          logic[`_DWAY_CNT - 1 : 0][3:0] data_we; // c
        } wport_wreq_t;

// 有 256 个 CACHE 行
typedef struct packed {
          logic [ `_DWAY_CNT-1:0]                                          tag_we    ;
          logic [            7:0]                                          tag_waddr ;
          dcache_tag_t                                                tag_wdata ;

          logic [`_DBANK_CNT-1:0][                    `_DWAY_CNT-1:0][3:0] data_we   ;
          logic [`_DBANK_CNT-1:0][`_DIDX_LEN-1:2+$clog2(`_DBANK_CNT)]      data_waddr;
          logic [`_DBANK_CNT-1:0][                              31:0]      data_wdata;
        } dram_manager_snoop_t;

function logic[`_DTAG_LEN - 1 : 0] tagaddr(input logic[31:0] va);
  return va[`_DTAG_LEN + `_DIDX_LEN - 1: `_DIDX_LEN];
endfunction
function logic[7 : 0] tramaddr(input logic[31:0] va);
  return va[`_DIDX_LEN - 1 -: 8];
endfunction
function logic[`_DIDX_LEN - 1 : 2] dramaddr(input logic[31:0] va);
  return va[`_DIDX_LEN - 1 : 2];
endfunction
function logic[`_DIDX_LEN - 1 : 3] bdramaddr(input logic[31:0] va);
  return va[`_DIDX_LEN - 1 : 3];
endfunction
function logic cache_hit(input dcache_tag_t tag,input logic[31:0] pa);
  return tag.valid && (tagaddr(pa) == tag.addr);
endfunction
function logic dcache_hit(input dcache_tag_t tag,input logic[31:0] pa);
  return tag.valid && (tagaddr(pa) == tag.addr);
endfunction
function logic[31:0] mkstrobe(input logic[31:0] data, input logic[3:0] mask);
  return data & {{8{mask[3]}},{8{mask[2]}},{8{mask[1]}},{8{mask[0]}}};
endfunction
function logic[3:0] mkwstrobe(input logic[2:0] select,input logic[31:0] va);
  case(select[1:0])
    default : begin
      mkwstrobe = 4'b0000;
    end
    2'b01 : begin
      mkwstrobe = 4'b1111;
    end
    2'b10 : begin
      mkwstrobe = va[1] ? 4'b1100 : 4'b0011;
    end
    2'b11 : begin
      case(va[1:0])
        default : begin
          mkwstrobe = 4'b0001;
        end
        2'b01 : begin
          mkwstrobe = 4'b0010;
        end
        2'b10 : begin
          mkwstrobe = 4'b0100;
        end
        2'b11 : begin
          mkwstrobe = 4'b1000;
        end
      endcase
    end
  endcase
endfunction

function logic[31:0] mkrsft(input logic[31:0] raw, input logic[31:0] va, input logic[2:0] op);
  // M1 RDATA 电路
  logic ext_sign;
  case(op[1:0])
    default : begin
      ext_sign = raw[15] & ~op[2];
    end
    2'b10 : begin
      // HALF
      ext_sign = va[1] ? (raw[31] & ~op[2]) :
        (raw[15] & ~op[2]);
    end
    2'b11 : begin
      ext_sign = va[1] ? (va[0] ? (raw[31] & ~op[2]) : (raw[23] & ~op[2])) :
        (va[0] ? (raw[15] & ~op[2]) : (raw[7] & ~op[2]));
    end
  endcase
  if(op[1]) begin
    mkrsft = {{16{ext_sign}}, va[1] ? raw[31:16] : raw[15:0]};
    if(op[0]) begin
      mkrsft[7:0]=va[0]?mkrsft[15:8] : mkrsft[7:0];
      mkrsft[15:8] = {8{ext_sign}};
    end
  end
  else begin
    mkrsft = raw;
  end
endfunction
function logic[31:0] mkwsft(input logic[31:0] raw, input logic[31:0] va);
  // M1 WDATA 电路
  mkwsft = raw;
  case(va[1:0])
    default : begin
      mkwsft = raw;
    end
    2'b01 : begin
      mkwsft[15:8] = raw[7:0];
    end
    2'b10 : begin
      mkwsft[31:16] = raw[15:0];
    end
    2'b11 : begin
      mkwsft[31:24] = raw[7:0];
    end
  endcase
endfunction

typedef struct packed {
          logic ar_valid   ;
          logic[31:0] ar_addr;
          logic[3:0] ar_len;
          logic ar_uncached;
          logic[2:0] ar_size;
          logic aw_valid   ;
          logic[31:0] aw_addr;
          logic[3:0] aw_id;
          logic[3:0] aw_len;
          logic aw_uncached;
          logic[2:0] aw_size;
          logic dr_ready   ;
          logic dw_valid   ;
          logic dw_last    ;
          logic[31:0] dw_data;
          logic[3:0] dw_strobe;
          logic b_ready    ;
        } axi_req_t;

typedef struct packed {
          logic ar_ready;
          logic aw_ready;
          logic dr_valid;
          logic dr_last ;
          logic[31:0] dr_data;
          logic dw_ready;
          logic b_valid ;
        } axi_resp_t;


`endif
