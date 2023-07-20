`include "../pipeline/pipeline.svh"

function logic check_inv(tlb_entry_t entry, tlb_inv_req_t inv_req);
  check_inv = '0;
  if(inv_req.clr_global && entry.key.g) begin
    check_inv = '1;
  end
  else if(inv_req.clr_nonglobal && !entry.key.g) begin
    if(inv_req.clr_nonglobal_check_asid) begin
      if(inv_req.asid == entry.key.asid) begin
        if(inv_req.clr_nonglobal_check_vpn) begin
          check_inv = (inv_req.vpn[18:10] == entry.key.vpn[18:10]) && (entry.key.ps != 6'd12 || inv_req.vpn[9:0] == entry.key.vpn[9:0]);
        end
        else begin
          check_inv = '1;
        end
      end
    end
    else begin
      check_inv = '1;
    end
  end
endfunction

module tlb #(
    parameter int TLB_ENTRY_NUM = 16
  )
  (
    input clk,
    input rst_n,
    // modify
    input logic tlb_we_i,
    input logic[$clog2(TLB_ENTRY_NUM) - 1 : 0] tlb_w_index_i,
    input tlb_entry_t tlb_w_entry_i,
    input tlb_inv_req_t tlb_inv_req_i,

    // tlb entries
    output tlb_entry_t[TLB_ENTRY_NUM - 1 : 0] entries_o
  );

  for(genvar i = 0 ; i < TLB_ENTRY_NUM ; i++) begin
    tlb_entry_t entry;
    assign entries_o[i] = entry;

    always_ff@(posedge clk) begin
      if(!rst_n) begin
        entry.key.e <= '0;
      end
      else begin
        if(tlb_we_i && tlb_w_index_i == i[$clog2(TLB_ENTRY_NUM) - 1 : 0]) begin
          entry <= tlb_w_entry_i;
        end
        else if(tlb_inv_req_i && check_inv(entry, tlb_inv_req_i)) begin
          entry.key.e <= '0;
        end
      end
    end
  end

endmodule
