`include "common.svh"

module compress_fifo #(
  parameter int DATA_WIDTH = 32,
  parameter int DEPTH = 8,
  parameter int WRITE_PORT = 2, // DO NOT CHANGE.
  parameter int READ_PORT = 2,  // DO NOT CHANGE.
  parameter type dtype = logic [DATA_WIDTH-1:0]
)(
  input clk,
  input rst_n,

  input flush_i,

  input logic write_valid_i,
  output logic write_ready_o, // THIS SHOULD BE REGISTERED
  input logic [$clog2(WRITE_PORT + 1) - 1: 0] write_num_i,
  input dtype [WRITE_PORT - 1 : 0] write_data_i,

  output logic [READ_PORT - 1 : 0] read_valid_o, // THIS SHOULD BE REGISTERED
  input logic read_ready_i,
  input logic [$clog2(READ_PORT + 1) - 1 : 0] read_num_i,
  output dtype [READ_PORT - 1 : 0] read_data_o   // THIS SHOULD BE REGISTERED
);
localparam int PTR_LEN = $clog2(DEPTH);
typedef logic [PTR_LEN : 0] ptr_t;
logic[DEPTH - 1 : 0][DATA_WIDTH - 1 : 0] data_q;
ptr_t[WRITE_PORT - 1 : 0] w_ptr_q, w_ptr;
logic write_ready_q, write_ready;
ptr_t[READ_PORT - 1 : 0] r_ptr_q, r_ptr;
logic[PTR_LEN - 1 : 0] cnt_q, cnt;
logic[READ_PORT - 1 : 0] read_valid_q, read_valid;
logic[READ_PORT - 1 : 0][DATA_WIDTH - 1 : 0] read_data_q, read_data;
assign read_valid_o  = read_valid_q;
assign write_ready_o = write_ready_q;
assign read_data_o   = read_data_q;
always_ff @(posedge clk) begin
  if(!rst_n) begin
    for(integer i = 0 ; i < WRITE_PORT ; i++) begin
      w_ptr_q[i] <= i[PTR_LEN : 0];
    end
    for(integer i = 0 ; i < READ_PORT ; i ++) begin
      r_ptr_q[i] <= i[PTR_LEN : 0];
    end
    cnt_q <= '0;
  end else begin
    w_ptr_q       <= w_ptr;
    r_ptr_q       <= r_ptr;
    cnt_q         <= cnt;
    write_ready_q <= write_ready;
    read_valid_q  <= read_valid;
    read_data_q   <= read_data;
    if(write_ready_q & write_valid_i) begin
        for(integer i = 0 ; i < WRITE_PORT ; i++) begin
            if(i < write_num_i) begin
                data_q[w_ptr_q[i]] <= write_data_i[i];
            end
        end
    end
  end
end
always_comb begin
  w_ptr       = w_ptr_q;
  r_ptr       = r_ptr_q;
  cnt         = cnt_q;
  write_ready = write_ready_q;
  read_valid  = read_valid_q;
  read_data   = read_data_q;
  if(write_ready_q & write_valid_i) begin
    // 更新写指针
    for(integer i = 0 ; i < WRITE_PORT ; i++) begin
        w_ptr[i] += write_num_i;
    end
  end
  if(read_ready_i) begin
    // 更新读指针
    for(integer i = 0 ; i < READ_PORT ; i++) begin
        r_ptr[i] += read_num_i;
    end
  end
  // 更新计数值
  cnt = w_ptr[0] - r_ptr[0];
  // 根据计数值判断可写性
  write_ready = cnt <= (DEPTH - WRITE_PORT);
  read_valid[0] = cnt > 0;
  read_valid[1] = cnt > 1;
  for(integer i = 0 ; i < READ_PORT ; i++) begin
    read_data[i] = data_q[r_ptr_q[i]];
  end
end

endmodule