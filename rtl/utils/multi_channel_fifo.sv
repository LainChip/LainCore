`include "common.svh"

module multi_channel_fifo #(
	parameter int DATA_WIDTH = 32,
	parameter int DEPTH = 8,
	parameter int BANK = 4,
	parameter int WRITE_PORT = 2,
	parameter int READ_PORT = 2,
	parameter type dtype = logic [DATA_WIDTH-1:0]
)(
	input clk,
	input rst_n,

	input flush_i,

	input logic write_valid_i,
	output logic write_ready_o,
	input logic [$clog2(WRITE_PORT + 1) - 1: 0] write_num_i,
	input dtype [WRITE_PORT - 1 : 0] write_data_i,

	output logic [READ_PORT - 1 : 0] read_valid_o,
	input logic read_ready_i,
	input logic [$clog2(READ_PORT + 1) - 1 : 0] read_num_i,
	output dtype [READ_PORT - 1 : 0] read_data_o
);

	// initial begin
    // 	$dumpfile("logs/vlt_dump.vcd");
    // 	$dumpvars();
    // end

	typedef logic [$clog2(BANK) - 1 : 0] ptr_t;
	ptr_t [READ_PORT - 1 : 0] read_index;
	ptr_t [BANK - 1 : 0] port_read_index,port_write_index;
	logic [BANK - 1 : 0] fifo_full,fifo_empty,fifo_push,fifo_pop;
	dtype [BANK - 1 : 0] data_in, data_out;
	logic [$clog2(BANK + 1) - 1 : 0] count_full;
	assign write_ready_o = count_full <= (BANK[$clog2(BANK + 1) - 1 : 0] - WRITE_PORT[$clog2(BANK + 1) - 1 : 0]);

	// FIFO 部分
	always_comb begin
		count_full = '0;
		for(integer i = 0 ; i < BANK; i += 1) begin
			count_full = count_full + {{($clog2(BANK + 1) - 1){1'b0}},fifo_full[i]};
		end
	end

	generate
		for(genvar i = 0 ; i < BANK; i += 1) begin
			// 指针更新策略
			always_ff @(posedge clk) begin : proc_port_read_index
				if(~rst_n || flush_i) begin
					port_read_index[i] <= i[$clog2(BANK) - 1 : 0];
				end else begin
					if(read_ready_i)
						port_read_index[i] <= port_read_index[i] - read_num_i[$clog2(BANK) - 1 : 0];
				end
			end
			always_ff @(posedge clk) begin : proc_port_write_index
				if(~rst_n || flush_i) begin
					port_write_index[i] <= i[$clog2(BANK) - 1 : 0];
				end else begin
					if(write_valid_i & write_ready_o)
						port_write_index[i] <= port_write_index[i] - write_num_i[$clog2(BANK) - 1 : 0];
				end
			end

			// FIFO 控制信号
			assign fifo_pop[i] = read_ready_i & (port_read_index[i] < read_num_i);
			assign fifo_push[i] = write_valid_i & write_ready_o & (port_write_index[i] < write_num_i);
			assign data_in[i] = write_data_i[port_write_index[i][$clog2(WRITE_PORT) - 1: 0]];

			// FIFO 生成
			la_fifo_v3 #(
				.DEPTH       (DEPTH),
				.DATA_WIDTH  (DATA_WIDTH),
				.dtype       (dtype)
			) instr_fifo (
				.clk         (clk     ),
				.rst_n       (rst_n   ),
				.flush_i     (flush_i ),
				.full_o      (fifo_full[i]),
				.empty_o     (fifo_empty[i]),
				.usage_o     (/* empty */),
				.data_i      (data_in[i]),
				.data_o      (data_out[i]),
				.push_i      (fifo_push[i]),
				.pop_i       (fifo_pop[i])
			);
		end
	endgenerate

	// 输出部分
	generate
		for(genvar i = 0 ; i < READ_PORT; i+= 1) begin
			// 指针更新策略
			always_ff @(posedge clk) begin : proc_read_index
				if(~rst_n || flush_i) begin
					read_index[i] <= i[$clog2(BANK) - 1 : 0];
				end else begin
					if(read_ready_i)
						read_index[i] <= read_index[i] + read_num_i[$clog2(BANK) - 1 : 0];
				end
			end
			assign read_data_o[i] = data_out[read_index[i]];
			assign read_valid_o[i] = ~fifo_empty[read_index[i]];
		end
	endgenerate

endmodule
