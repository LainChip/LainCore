`ifndef _CACHED_LSU_V3_HEADER
`define _CACHED_LSU_V3_HEADER

        // 全新设计思路，分离流水线部分以及管理部分
        // 流水线部分只负责和管线部分交互，完全不在乎 RAM 管理部分如何对 RAM 进行维护和管理。
        // 流水线部分高度可配置，支持组相连 / 直接映射。
        // CACHE 的管理部分不支持 byte-wide operation， CACHE 需要手动控制写操作进行融合。

`define _DWAY_CNT 1
`define _DBANK_CNT 2
`define _DIDX_LEN 12
`define _DTAG_LEN 20
`define _DCAHE_OP_READ 1
`define _DCAHE_OP_WRITE 2
`define _IWAY_CNT 1
`define _IIDX_LEN 12
`define _ITAG_LEN 20

        typedef struct packed{
          // 请求信号
          logic valid;                             // 拉高时说明cache的请求有效，请求有效后，valid信号应该被拉低
          logic write;                             // 拉高时说明cache请求进行写入
          logic [3:0] burst_size;                   // 0 for no burst, n for n + 1 times burst
          logic cached;                            // 0 for uncached, 1 for cached, when cached and coherence exchange imple,
          // cached is although responsible for shareable between masters.
          logic [1:0] data_size;                    // n for (1 << n) bytes in a transfer
          logic[31:0] addr;                        // cache请求的物理地址

          // 数据
          logic data_ok;                           // 写入时，此信号用于说明cache已准备好提供数据。 读取时，此信号说明cache已准备好接受数据。
          logic data_last;                         // 拉高时标记最后一个元素，只有读到此信号才认为传输事务结束
          logic[3 :0] data_strobe;
          logic[31:0] w_data; // cache请求的写数据
        }cache_bus_req_t;

typedef struct packed{
          // 响应信号
          logic ready;                               // 说明cache的请求被响应，响应后ready信号也应该被拉低

          // 数据
          logic data_ok;                             // 拉高时说明总线数据有效
          logic data_last;                           // 最后一个有效数据
          logic[31:0] r_data; // 总线返回的数据
        }cache_bus_resp_t;

typedef struct packed {
          logic valid;
          logic[`_DTAG_LEN - 1 : 0] addr;
        } dcache_tag_t;

typedef struct packed {
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

// 有 256 个 CACHE 行
typedef struct packed {
          logic [`_DWAY_CNT - 1 : 0] tag_we;
          logic [7:0] tag_waddr;
          dcache_tag_t tag_wdata;

          logic [`_DBANK_CNT - 1 : 0][`_DWAY_CNT - 1 : 0][3:0] data_we;
          logic [`_DBANK_CNT - 1 : 0][`_DIDX_LEN - 1 : 2 + $clog2(`_DBANK_CNT)] data_waddr;
          logic [`_DBANK_CNT - 1 : 0][31:0] data_wdata;
        } dram_manager_snoop_t;

function logic[`_DTAG_LEN - 1 : 0] tagaddr(logic[31:0] va);
  return va[`_DTAG_LEN + `_DIDX_LEN - 1: `_DIDX_LEN];
endfunction
function logic[7 : 0] tramaddr(logic[31:0] va);
  return va[`_DIDX_LEN - 1 -: 8];
endfunction
function logic[`_DIDX_LEN - 1 : 2] dramaddr(logic[31:0] va);
  return va[`_DIDX_LEN - 1 : 2];
endfunction
function logic[`_DIDX_LEN - 1 : 3] bdramaddr(logic[31:0] va);
  return va[`_DIDX_LEN - 1 : 3];
endfunction
function logic cache_hit(dcache_tag_t tag,logic[31:0] pa);
  return tag.valid && (tagaddr(pa) == tag.addr);
endfunction
function logic[31:0] mkstrobe(logic[31:0] data, logic[3:0] mask);
  return data & {{8{mask[3]}},{8{mask[2]}},{8{mask[1]}},{8{mask[0]}}};
endfunction
function logic[31:0] mkrsft(logic[31:0] raw, logic[31:0] va);
  // M1 WDATA 电路
  mkrsft = raw;
  case(va[1:0])
    default: begin
      mkrsft = raw;
    end
    2'b01: begin
      mkrsft[7:0] = raw[15:8];
    end
    2'b10: begin
      mkrsft[15:0] = raw[31:16];
    end
    2'b11: begin
      mkrsft[7:0] = raw[31:24];
    end
  endcase
endfunction
function logic[31:0] mkwsft(logic[31:0] raw, logic[31:0] va);
  // M1 WDATA 电路
  mkwsft = raw;
  case(va[1:0])
    default: begin
      mkwsft = raw;
    end
    2'b01: begin
      mkwsft[15:8] = raw[7:0];
    end
    2'b10: begin
      mkwsft[31:16] = raw[15:0];
    end
    2'b11: begin
      mkwsft[31:24] = raw[7:0];
    end
  endcase
endfunction

typedef struct packed {
          logic ar_valid;
          logic[31:0] ar_addr;
          logic[3:0] ar_len;
          logic ar_uncached;
          logic[2:0] ar_size;
          logic aw_valid;
          logic[31:0] aw_addr;
          logic[3:0] aw_id;
          logic[3:0] aw_len;
          logic aw_uncached;
          logic[2:0] aw_size;
          logic dr_ready;
          logic dw_valid;
          logic dw_last;
          logic[31:0] dw_data;
          logic[3:0] dw_strobe;
          logic b_ready;
        } axi_req_t;

typedef struct packed {
          logic ar_ready;
          logic aw_ready;
          logic dr_valid;
          logic dr_last;
          logic[31:0] dr_data;
          logic dw_ready;
          logic   b_valid;
        } axi_resp_t;


`endif
