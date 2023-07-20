`include "common.svh"

module tree_lru_new #(
	parameter int set_size = 2,
	parameter int set_info_len = set_size - 1
	)(
	input logic [set_info_len - 1 : 0] info,
	output logic [$clog2(set_size) - 1 : 0] o_index
);
	logic [$clog2(set_size) - 1 : 0] index;
	generate
		for(genvar i = 0 ; i < $clog2(set_size);i++)
		begin
			assign o_index[i] = index[$clog2(set_size) - 1 - i];
		end
	endgenerate

	logic [$clog2(set_size) - 1 : 0] ptr;

	always_comb
	begin
		ptr = 0;
		for(int i = 0 ; i < $clog2(set_size);i++)
		begin
			index[i] = info[ptr];
			ptr = info[ptr] + (1 << (i + 1)) - 1;
		end
	end

endmodule : tree_lru_new
