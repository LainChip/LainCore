`include "common.svh"
`include "lsu.svh"

module axi_converter#(
    parameter int CACHE_PORT_NUM = 1
)(
    input clk,
	input rst_n,
	LA_AXI_BUS.Master   axi_bus_if, // 来自pulp_axi 库
    input  cache_bus_req_t  [CACHE_PORT_NUM - 1 : 0]req_i,       // cache的访问请求
    output cache_bus_resp_t [CACHE_PORT_NUM - 1 : 0]resp_o       // cache的访问应答
);

	logic take;
	logic[CACHE_PORT_NUM - 1 : 0] arr_req_valid,arr_sel_comb,arr_sel_r;
	logic[$clog2(CACHE_PORT_NUM) - 1 : 0] arr_sel_r_index;
	always_comb begin
		arr_sel_r_index = '0;
		for(integer i = 0 ; i < CACHE_PORT_NUM ; i += 1) begin
			if(arr_sel_r[i]) begin
				arr_sel_r_index = i[$clog2(CACHE_PORT_NUM) - 1 : 0];
			end
		end
	end

	typedef struct packed{
		logic write;
		logic[3:0] burst_size;
		logic[1:0] data_size;
		logic cached;
		logic[31:0] addr;
	}inner_cache_req_info_t;

	inner_cache_req_info_t sel_req_r,sel_req_comb;

	typedef struct packed{
		logic data_ok;                           // 写入时，此信号用于说明cache已准备好提供数据。 读取时，此信号说明cache已准备好接受数据。
    	logic data_last;                         // 拉高时标记最后一个元素，只有读到此信号才认为传输事务结束
        logic[(`_CACHE_BUS_DATA_LEN / 8) - 1 : 0]data_strobe;
        logic[`_CACHE_BUS_DATA_LEN - 1:0] w_data; // cache请求的写数据
	}inner_data_info_t;

	inner_data_info_t sel_data_comb;
	logic sel_data_ready;

	localparam STATE_IDLE = 4'b0001;
	localparam STATE_ADDR = 4'b0010;
	localparam STATE_DATA = 4'b0100;
	localparam STATE_RESP = 4'b1000;
	logic[3:0] fsm_state, fsm_next_state; // one hot

	// use a round robin arbiter to select between multi request.
	arbiter_round_robin #(.REQ_NUM(CACHE_PORT_NUM)) arbiter(
		.clk,
		.rst_n,
		.req_i(arr_req_valid),
		.take_sel_i(take),
		.sel_o(arr_sel_comb)
	);

	generate
		for(genvar i = 0 ; i < CACHE_PORT_NUM ; i += 1) begin
			assign arr_req_valid[i] = req_i[i].valid;
			assign resp_o[i].ready = arr_sel_comb[i] & take;
		end
	endgenerate

	// 将被选择的请求暂存到寄存器
	always_comb begin
		sel_req_comb = '0;
		for(integer i = 0 ; i < CACHE_PORT_NUM ; i += 1) begin
			sel_req_comb |= arr_sel_comb[i] ? {req_i[i].write,req_i[i].burst_size,req_i[i].data_size,req_i[i].cached,req_i[i].addr} : '0;
		end
	end
	always_ff @(posedge clk) begin : proc_sel_req_r
		if(~rst_n) begin
			sel_req_r <= '0;
			arr_sel_r <= '0;
		end else
		if(take) begin
			sel_req_r <= sel_req_comb;
			arr_sel_r <= arr_sel_comb;
		end
	end
	assign take = fsm_state == STATE_IDLE;

	// 状态转移维护
	always_comb begin
		fsm_next_state = fsm_state;
		case(fsm_state)
			STATE_IDLE: begin
				if(take && |(arr_sel_comb)) begin
					fsm_next_state = STATE_ADDR;
				end
			end
			STATE_ADDR: begin
				if((axi_bus_if.ar_ready & (~sel_req_r.write)) | (axi_bus_if.aw_ready & (sel_req_r.write))) begin
					fsm_next_state = STATE_DATA;
				end
			end
			STATE_DATA: begin
				if(axi_bus_if.r_last & (axi_bus_if.r_valid && (axi_bus_if.r_id == arr_sel_r_index)) & axi_bus_if.r_ready & (~sel_req_r.write)) begin
					fsm_next_state = STATE_IDLE;
				end else if(axi_bus_if.w_last & axi_bus_if.w_valid & axi_bus_if.w_ready & (sel_req_r.write)) begin
					fsm_next_state = STATE_RESP;
				end
			end
			STATE_RESP: begin
				if(axi_bus_if.b_valid && (axi_bus_if.b_id == arr_sel_r_index) && axi_bus_if.b_ready) begin
					fsm_next_state = STATE_IDLE;
				end
			end
			default:begin
				fsm_next_state = STATE_IDLE;
			end
		endcase
	end
	always_ff @(posedge clk) begin : proc_fsm_state
		if(~rst_n) begin
			fsm_state <= STATE_IDLE;
		end else begin
			fsm_state <= fsm_next_state;
		end
	end

	// 暂存来自请求侧的请求，减少后端axi r w 的逻辑复杂度
	always_comb begin
		sel_data_comb = '0;
		for(integer i = 0 ; i < CACHE_PORT_NUM; i+= 1) begin
			if(arr_sel_r[i]) begin
				sel_data_comb |= {req_i[i].data_ok,req_i[i].data_last,req_i[i].data_strobe,req_i[i].w_data};
			end
		end
	end
	// always_ff @(posedge clk) begin : proc_sel_data_ready
	// 	if(~rst_n || take) begin
	// 		sel_data_ready <= '0;
	// 	end else if(!sel_data_ready || (axi_bus_if.w_ready && sel_req_r.write)) begin
	// 		sel_data_ready <= sel_data_comb.data_ok;
	// 	end
	// end
	// always_ff @(posedge clk) begin : proc_sel_data_r
	// 	if(~rst_n) begin
	// 		sel_data_r <= '0;
	// 	end else if(~sel_data_ready | axi_bus_if.w_ready) begin
	// 		sel_data_r <= sel_data_comb;
	// 	end
	// end

	// 对数据信号握手进行回复
	generate
		for(genvar i = 0 ; i < CACHE_PORT_NUM ; i += 1) begin
			assign resp_o[i].data_ok = (((axi_bus_if.w_ready) & (sel_req_r.write)) | ((axi_bus_if.r_valid && (axi_bus_if.r_id == arr_sel_r_index)) && (~sel_req_r.write))) & arr_sel_r[i] & (fsm_state == STATE_DATA);
			assign resp_o[i].data_last = axi_bus_if.r_last & arr_sel_r[i] & (~sel_req_r.write) & (fsm_state == STATE_DATA);
			assign resp_o[i].r_data = axi_bus_if.r_data;
		end
	endgenerate
	
	// axi信号控制
	always_comb begin
		axi_bus_if.ar_id = '0;
		axi_bus_if.ar_id[$clog2(CACHE_PORT_NUM) - 1 : 0] = arr_sel_r_index;
		axi_bus_if.ar_addr = sel_req_r.addr;
		axi_bus_if.ar_len = sel_req_r.burst_size;
		axi_bus_if.ar_size = {1'b0,sel_req_r.data_size};
		axi_bus_if.ar_burst = 2'b01; // WARP TYPE
		axi_bus_if.ar_lock = 1'b0;
		// axi_bus_if.ar_cache = {2'b00,sel_req_r.cached,1'b0};
		axi_bus_if.ar_cache = 4'b0000;
		axi_bus_if.ar_prot = 3'b000;
		axi_bus_if.ar_qos = '0;
		axi_bus_if.ar_region = '0;
		axi_bus_if.ar_user = '0;
		axi_bus_if.ar_valid = fsm_state[1] & (~sel_req_r.write);

		axi_bus_if.aw_id = '0;
		axi_bus_if.aw_id[$clog2(CACHE_PORT_NUM) - 1 : 0] = arr_sel_r_index;
		axi_bus_if.aw_addr = sel_req_r.addr;
		axi_bus_if.aw_len = sel_req_r.burst_size;
		axi_bus_if.aw_size = {1'b0,sel_req_r.data_size};
		axi_bus_if.aw_burst = 2'b01; // WARP TYPE
		axi_bus_if.aw_lock = 1'b0;
		// axi_bus_if.aw_cache = {2'b00,sel_req_r.cached,1'b0};
		axi_bus_if.aw_cache = 4'b0000;
		axi_bus_if.aw_prot = 3'b000;
		axi_bus_if.aw_qos = '0;
		axi_bus_if.aw_region = '0;
		axi_bus_if.aw_user = '0;
		axi_bus_if.aw_atop = '0;
		axi_bus_if.aw_valid = fsm_state[1] & (sel_req_r.write);

		axi_bus_if.w_data = sel_data_comb.w_data;
		axi_bus_if.w_strb = sel_data_comb.data_strobe;
		axi_bus_if.w_valid =  sel_data_comb.data_ok & (sel_req_r.write) & (fsm_state[2]);
		axi_bus_if.w_last = sel_data_comb.data_last & (sel_req_r.write) & (fsm_state[2]);

		axi_bus_if.r_ready = sel_data_comb.data_ok & (~sel_req_r.write) & (fsm_state[2]);
		axi_bus_if.b_ready = fsm_state[3] & (sel_req_r.write);
	end

endmodule
