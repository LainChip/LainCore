`ifndef _LSU_TYPES_HEADER
`define _LSU_TYPES_HEADER

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

`define _COHERENT_INV_OP (3'd0)
`define _COHERENT_INVWB_OP (3'd1) // coherent master 期望写的时候，若为 unique，则写 hit。
                                  // coherent master 若为 shared，则向其他 coherent master 发出 invwb 请求
                                  // 以保证下级存储器中的值是最新的，收到请求的 coherent master 修改自身状态为 invalid。
                                  // 得到 coherent manager 响应后，修改自身值为 unique。
                                  // 为避免两个核心争夺同一个 cache line 的写权限，每个核心在获得 unique 权限后的 15 个 ticks内
                                  // 不再响应 coherent manager 的请求，以保证本地的写可以完成。
`define _COHERENT_REQ_OP (3'd2)
`define _COHERENT_REQRD_OP (3'd3) // coherent master 在读 miss 的时候，向其他 coherent master 发出 reqrd 请求，
                                  // 收到请求的 coherent master 若 hit，则修改自身状态为 shared，并将数据交给coherent master，标记为 shared。
                                  // 收到请求的 coherent master 若均 miss，则从下级存储器获得值，标记为 unique。
typedef struct packed{
    // 请求信号
    logic valid;
    logic[3:0] op;
    logic[31:2] addr;

    // 数据通道
    logic data_ok;
}coherence_bus_req_t; // 从 coherent interconnect controller 发出到 coherent master 的请求

typedef struct packed{
    // 响应信号
    logic ready;
    logic hit;
    logic dirty;

    // 数据
    logic data_ok;
    logic data_last;
    logic[31:0] wb_data;
}coherence_bus_resp_t; // coherent master 对请求的响应

// 暂不使用 AXI 接口对外包装

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
