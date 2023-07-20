`include "common.svh"
module tree_lru_update #(
	parameter int set_size = 2,
	parameter int set_info_len = set_size - 1
	)(
	input logic [set_size - 1 : 0] i_update_elm,
	input logic [set_info_len : 1] old_info,
	output logic [set_info_len : 1] new_info
);
	logic[set_size - 1 : 0] update_elm;
	generate
		for(genvar i = 0 ; i < set_size ;i++)
		begin
			assign update_elm[i] = i_update_elm[set_size - 1 - i];
		end
	endgenerate
	localparam int tree_depth = $clog2(set_size);
	logic[$clog2(set_info_len) : 0] ptr;
	logic[tree_depth - 1 : 0] level_stage;

	generate
		for( genvar id = 1 ; id < set_info_len + 1; id=id+1)
		begin
			localparam int level = $clog2(id) - (id >(1 << $clog2(id))) ? 1 : 0;
			localparam int shift = id - (1 << level);

			localparam int level_mask_len = (set_size >> level);
			logic[set_size - 1 : 0] level_mask = ({set_size{1'b1}} << ((set_size) - ((set_size) >> level)))
												 >> (level_mask_len * shift);// (set_size << 1) - ((set_size << 1) >> level)
			int block_num = (1 << level);
			logic[set_size - 1 : 0] l_mask;
			logic[set_size - 1 : 0] r_mask;
			initial
			begin
				l_mask = 0;
				r_mask = 0;
				for(int block = 0; block < block_num;block ++)
				begin
					l_mask = (l_mask << (level_mask_len))| {{(level_mask_len / 2){1'b1}},{(level_mask_len / 2){1'b0}}};
					r_mask = (r_mask << (level_mask_len)) | {{(level_mask_len / 2){1'b0}},{(level_mask_len / 2){1'b1}}};
				end
				l_mask = l_mask & level_mask;
				r_mask = r_mask & level_mask;
			end
			
			always_comb
			begin
				if(update_elm & l_mask)
				begin
					new_info[id] = 1'b1;
				end
				else if(update_elm & r_mask)
				begin
					new_info[id] = 1'b0;
				end
				else
				begin
					new_info[id] = old_info[id];
				end
			end
		end
	endgenerate

endmodule : tree_lru_update
