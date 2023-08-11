`include "pipeline.svh"
`include "csr.svh"

module core_csr #(
  parameter bit ENABLE_TLB = 1'b1,
  parameter int TLB_ENTRY_NUM    = `_TLB_ENTRY_NUM
)(
  input logic clk,
  input logic rst_n,
  input logic[7:0] int_i,
  input excp_flow_t excp_i, // M2 EXCPTION IN
  input logic ertn_i,
  input logic valid_i,
  input logic commit_i,

  input logic m1_stall_i,
  input logic m2_stall_i,

  input logic[13:0] csr_r_addr_i, // M1 in
  input logic[1:0] rdcnt_i,
  input logic csr_we_i,
  input logic[13:0] csr_w_addr_i, // M2 in
  input logic[31:0] csr_w_mask_i,
  input logic[31:0] csr_w_data_i,
  input logic[31:0] badv_i,

  input logic[31:0] tlb_op_vaddr_i,  // M1
  input logic[9:0] tlb_op_asid_i,    // M1

  input tlb_op_t tlb_op_i,           // M2
  input logic[4:0] tlb_inv_op_i,     // M2
  output tlb_update_req_t tlb_update_req_o,

  input logic llbit_set_i,
  input logic llbit_i,

  input logic[31:0] pc_i,
  input logic[31:0] vaddr_i,

  input logic m1_commit_i,
  output logic m1_int_o,

  input logic m2_commit_i,

  output logic[31:0] csr_r_data_o,
  output csr_t csr_o
);

logic m1_commit_i_q;
always_ff @(posedge clk) begin
  if(!m2_stall_i) begin
    m1_commit_i_q <= m1_commit_i && m1_int_o && !m1_stall_i;
  end
end

// TLB 控制模块，执行 TLB 相关指令，产生 tlb_update_req_o 信号控制外部 ADDR_TRANS 模块。
// 注意，TLB 指令在 M2 级执行，同级会发出 REFETCH 信号。
// REFETCH 后，需要在前端进行阻塞， addr trans 模块中应有相应 flag 标识当前地址翻译结果是否有效。
// 当地址翻译结果无效时，新的输入不会被响应，直到 flag 被置为高。
logic[4:0] tlbfill_rnd_idx_q;
always_ff @(posedge clk) begin
  tlbfill_rnd_idx_q <= tlbfill_rnd_idx_q + 1;
end

// FOR TLB INST
logic[4:0] tlb_srch_idx_q;
logic       tlb_srch_valid_q;
tlb_entry_t tlb_r_entry_q   ;

if(ENABLE_TLB) begin
  tlb_entry_t [TLB_ENTRY_NUM-1:0] tlb_entrys;
  logic[TLB_ENTRY_NUM-1:0] tlb_need_inv, tlb_we;
  // tlb_entrys 更新逻辑
  // 只需要响应三条指令：invtlb, tlbfill, tlbwr
  // 注：不进行硬件复位
  tlb_entry_t      tlb_w_entry   ;
  tlb_update_req_t tlb_update_req;
  assign tlb_update_req_o = tlb_update_req;

  logic tlb_srch_valid;
  logic[4:0] tlb_srch_idx;
  always_ff @(posedge clk) begin
    tlb_srch_valid_q <= tlb_srch_valid;
    tlb_srch_idx_q   <= tlb_srch_idx;
  end
  always_comb begin
    tlb_srch_valid = '0;
    tlb_srch_idx   = '0;
    for(integer i = 0 ; i < TLB_ENTRY_NUM ; i ++) begin
      if(tlb_entrys[i].key.e &&
        (tlb_entrys[i].key.vppn[18:10] == csr_o.tlbehi[31:23]) &&
        (tlb_entrys[i].key.vppn[9:0]  == csr_o.tlbehi[22:13] || tlb_entrys[i].key.ps == 6'd22) &&
        (tlb_entrys[i].key.asid == csr_o.asid[9:0] || tlb_entrys[i].key.g)) begin
        tlb_srch_valid = '1;
        tlb_srch_idx   = i;
      end
    end
  end

  always_ff @(posedge clk) begin
    tlb_r_entry_q <= tlb_entrys[csr_o.tlbidx[$clog2(TLB_ENTRY_NUM) - 1 : 0]];
  end
  always_comb begin
    tlb_update_req.tlb_we      = tlb_need_inv;
    tlb_update_req.tlb_w_entry = tlb_w_entry;
    // 写 tlb 的指令不能等
    if(/*!m2_stall_i && */tlb_op_i.tlbfill) begin
      tlb_update_req.tlb_we[tlbfill_rnd_idx_q[$clog2(TLB_ENTRY_NUM)-1:0]] = '1;
    end
    if(/*!m2_stall_i && */tlb_op_i.tlbwr) begin
      tlb_update_req.tlb_we[csr_o.tlbidx[$clog2(TLB_ENTRY_NUM)-1:0]] = '1;
    end
  end
  always_comb begin
    tlb_w_entry.key.vppn = csr_o.tlbehi[31:13];
    tlb_w_entry.key.ps   = csr_o.tlbidx[29:24]; // P72
    tlb_w_entry.key.g    = csr_o.tlbelo0[6] && csr_o.tlbelo1[6];
    tlb_w_entry.key.asid = csr_o.asid[9:0];
    tlb_w_entry.key.e    = tlb_op_i.invtlb ? '0 :
      (!csr_o.tlbidx[31] || csr_o.estat[21]); // P73

    tlb_w_entry.value[0].ppn = csr_o.tlbelo0[27:8]; // P74
    tlb_w_entry.value[0].v   = csr_o.tlbelo0[0];
    tlb_w_entry.value[0].d   = csr_o.tlbelo0[1];
    tlb_w_entry.value[0].plv = csr_o.tlbelo0[3:2];
    tlb_w_entry.value[0].mat = csr_o.tlbelo0[5:4];

    tlb_w_entry.value[1].ppn = csr_o.tlbelo1[27:8]; // P74
    tlb_w_entry.value[1].v   = csr_o.tlbelo1[0];
    tlb_w_entry.value[1].d   = csr_o.tlbelo1[1];
    tlb_w_entry.value[1].plv = csr_o.tlbelo1[3:2];
    tlb_w_entry.value[1].mat = csr_o.tlbelo1[5:4];
  end
  for(genvar i = 0 ; i < TLB_ENTRY_NUM ; i ++) begin
    logic tlb_inv_addr_match_q, tlb_inv_asid_match_q;
    always_ff @(posedge clk) begin
      if(tlb_update_req.tlb_we[i] && !m2_stall_i) begin
        tlb_entrys[i] <= tlb_update_req.tlb_w_entry;
      end
    end
    always_ff @(posedge clk) begin
      if(!m2_stall_i) begin
        tlb_inv_addr_match_q <= (tlb_entrys[i].key.vppn[18:10] == tlb_op_vaddr_i[31:23]) &&
          ((tlb_entrys[i].key.vppn[9:0] == tlb_op_vaddr_i[22:13]) || (tlb_entrys[i].key.ps == 6'd22));
        tlb_inv_asid_match_q <= tlb_entrys[i].key.asid == tlb_op_asid_i;
      end
    end
    always_comb begin
      tlb_need_inv[i] = '0;
      if(/*!m2_stall_i && */tlb_op_i.invtlb) begin
        if(tlb_inv_op_i == 0 || tlb_inv_op_i == 1) begin
          tlb_need_inv[i] = '1;
        end
        if(tlb_inv_op_i == 2) begin
          tlb_need_inv[i] = tlb_entrys[i].key.g;
        end
        if(tlb_inv_op_i == 3) begin
          tlb_need_inv[i] = !tlb_entrys[i].key.g;
        end
        if(tlb_inv_op_i == 4) begin
          tlb_need_inv[i] = !tlb_entrys[i].key.g && tlb_inv_asid_match_q;
        end
        if(tlb_inv_op_i == 5) begin
          tlb_need_inv[i] = !tlb_entrys[i].key.g && tlb_inv_asid_match_q && tlb_inv_addr_match_q;
        end
        if(tlb_inv_op_i == 6) begin
          tlb_need_inv[i] = (tlb_entrys[i].key.g || tlb_inv_asid_match_q) && tlb_inv_addr_match_q;
        end
      end
    end
  end
end

//timer_64
logic[63:0] timer_64_q;
always_ff @(posedge clk) begin
  if(!rst_n) begin
    timer_64_q <= 64'd0;
  end
  else begin
    timer_64_q <= timer_64_q + 64'b1;
  end
end

logic csr_we;
logic[31:0] csr_w_data;
assign csr_we     = !m2_stall_i && csr_we_i;
assign csr_w_data = (csr_r_data_o & ~csr_w_mask_i) | (csr_w_data_i & csr_w_mask_i);

// EXCPTION JUDGE OH
logic excp_int;
assign excp_int = !m2_stall_i && excp_i.m1int;
logic excp_pil;
assign excp_pil = !m2_stall_i && excp_i.pil;
logic excp_pis;
assign excp_pis = !m2_stall_i && excp_i.pis;
logic excp_pif;
assign excp_pif = !m2_stall_i && excp_i.pif;
logic excp_pme;
assign excp_pme = !m2_stall_i && excp_i.pme;
logic excp_ppi;
assign excp_ppi = !m2_stall_i && (excp_i.ppi || excp_i.ippi);
logic excp_adem;
assign excp_adem = !m2_stall_i && excp_i.adem;
logic excp_ale;
assign excp_ale = !m2_stall_i && excp_i.ale;
logic excp_sys;
assign excp_sys = !m2_stall_i && excp_i.sys;
logic excp_brk;
assign excp_brk = !m2_stall_i && excp_i.brk;
logic excp_ine;
assign excp_ine = !m2_stall_i && excp_i.ine;
logic excp_ipe;
assign excp_ipe = !m2_stall_i && excp_i.ipe;
logic excp_tlbr; // TODO: FIXME
assign excp_tlbr = !m2_stall_i && (excp_i.itlbr || excp_i.tlbr);
logic excp_adef;
assign excp_adef = !m2_stall_i && excp_i.adef;

logic excp_tlb;
assign excp_tlb = excp_tlbr | excp_pil | excp_pis | excp_pif | excp_pme | excp_ppi;

logic excp_valid;
assign excp_valid = excp_int | excp_tlbr | excp_pil | excp_pis | excp_pif | excp_pme | excp_ppi |
  excp_adem | excp_ale | excp_sys | excp_brk | excp_ine | excp_ipe | excp_adef;

logic ertn_valid;
assign ertn_valid = !m2_stall_i && ertn_i;
logic ertn_tlbr_valid;
assign ertn_tlbr_valid = ertn_valid && /*(csr_o.estat_q[21:16] == 6'h3f)*//*简化一下逻辑*/ csr_o.estat[21];

logic [5:0] ecode   ;
logic [8:0] esubcode;
always_comb begin
  ecode    = '0;
  esubcode = '0;
  case(1'b1)
    excp_int : begin
      ecode = 6'h0;
    end
    excp_pil : begin
      ecode = 6'h1;
    end
    excp_pis : begin
      ecode = 6'h2;
    end
    excp_pif : begin
      ecode = 6'h3;
    end
    excp_pme : begin
      ecode = 6'h4;
    end
    excp_ppi : begin
      ecode = 6'h7;
    end
    excp_adef : begin
      ecode = 6'h8;
    end
    excp_adem : begin
      esubcode = 9'd1;
      ecode    = 6'h8;
    end
    excp_ale : begin
      ecode = 6'h9;
    end
    excp_sys : begin
      ecode = 6'hb;
    end
    excp_brk : begin
      ecode = 6'hc;
    end
    excp_ine : begin
      ecode = 6'hd;
    end
    excp_ipe : begin
      ecode = 6'he;
    end
    excp_tlbr : begin
      ecode = 6'h3f;
    end
  endcase
end
logic [31:0] era, badva; // TODO
assign era   = pc_i;
assign badva = (excp_adef || excp_pif || excp_i.ippi || excp_i.itlbr/* TODO: ADD SITUATION WHICH VA IS PC*/) ? pc_i : vaddr_i;

logic tlbsrch_en; // TODO
assign tlbsrch_en = !m2_stall_i && tlb_op_i.tlbsrch;

logic tlbrd_valid_wr_en, tlbrd_invalid_wr_en;

logic va_error;
assign va_error            = excp_tlbr | excp_adef | excp_adem | excp_ale | excp_pil | excp_pis | excp_pif | excp_pme | excp_ppi;
assign tlbrd_valid_wr_en   = !m2_stall_i && tlb_op_i.tlbrd && tlb_r_entry_q.key.e;
assign tlbrd_invalid_wr_en = !m2_stall_i && tlb_op_i.tlbrd && !tlb_r_entry_q.key.e;
// csr register
logic [31:0] crmd_q     ;
logic [31:0] prmd_q     ;
logic [31:0] euen_q     ;
logic [31:0] ectl_q     ;
logic [31:0] estat_q    ;
logic [31:0] era_q      ;
logic [31:0] badv_q     ;
logic [31:0] eentry_q   ;
logic [31:0] tlbidx_q   ;
logic [31:0] tlbehi_q   ;
logic [31:0] tlbelo0_q  ;
logic [31:0] tlbelo1_q  ;
logic [31:0] asid_q     ;
logic [31:0] pgdl_q     ;
logic [31:0] pgdh_q     ;
logic [31:0] cpuid_q    ;
logic [31:0] save0_q    ;
logic [31:0] save1_q    ;
logic [31:0] save2_q    ;
logic [31:0] save3_q    ;
logic [31:0] tid_q      ;
logic [31:0] tcfg_q     ;
logic [31:0] tval_q     ;
logic [31:0] cntc_q     ;
logic [31:0] ticlr_q    ;
logic [31:2] llbctl_q   ;
logic [31:0] tlbrentry_q;
logic [31:0] ctag_q     ;
logic [31:0] dmw0_q     ;
logic [31:0] dmw1_q     ;

// crmd
logic crmd_we,crmd_re;
assign crmd_we = csr_we && (csr_w_addr_i == `_CSR_CRMD);
always_ff @(posedge clk) begin
  if(!rst_n) begin
    crmd_q[`_CRMD_PLV]  <= 2'b0;
    crmd_q[`_CRMD_IE]   <= 1'b0;
    crmd_q[`_CRMD_DA]   <= 1'b1;
    crmd_q[`_CRMD_PG]   <= 1'b0;
    crmd_q[`_CRMD_DATF] <= 2'b0;
    crmd_q[`_CRMD_DATM] <= 2'b0;
    crmd_q[31:9]        <= 23'b0;
  end
  else begin
    if(excp_tlbr) begin
      crmd_q[`_CRMD_DA] <= 1'b1;
      crmd_q[`_CRMD_PG] <= 1'b0;
    end
    if(excp_valid) begin
      crmd_q[`_CRMD_PLV] <= 2'b0;
      crmd_q[`_CRMD_IE]  <= 1'b0;
    end
    if(ertn_valid) begin
      crmd_q[`_CRMD_PLV] <= prmd_q[`_PRMD_PPLV];
      crmd_q[`_CRMD_IE]  <= prmd_q[`_PRMD_PIE];
    end
    if(ertn_tlbr_valid) begin
      crmd_q[`_CRMD_DA] <= 1'b0;
      crmd_q[`_CRMD_PG] <= 1'b1;
    end
    if(crmd_we) begin
      crmd_q[`_CRMD_PLV]  <= csr_w_data[ `_CRMD_PLV];
      crmd_q[`_CRMD_IE]   <= csr_w_data[  `_CRMD_IE];
      crmd_q[`_CRMD_DA]   <= csr_w_data[  `_CRMD_DA];
      crmd_q[`_CRMD_PG]   <= csr_w_data[  `_CRMD_PG];
      crmd_q[`_CRMD_DATF] <= csr_w_data[`_CRMD_DATF];
      crmd_q[`_CRMD_DATM] <= csr_w_data[`_CRMD_DATM];
    end

  end
end
assign csr_o.crmd = crmd_q;

// prmd
logic prmd_we,prmd_re;
assign prmd_we = csr_we && (csr_w_addr_i == `_CSR_PRMD);
always_ff @(posedge clk) begin
  if(!rst_n) begin
    prmd_q[31:0] <= '0;
  end
  else begin
    if (excp_valid) begin
      prmd_q[`_PRMD_PPLV] <= crmd_q[`_CRMD_PLV];
      prmd_q[`_PRMD_PIE]  <= crmd_q[ `_CRMD_IE];
    end
    if(prmd_we) begin
      prmd_q[`_PRMD_PPLV] <= csr_w_data[`_PRMD_PPLV];
      prmd_q[`_PRMD_PIE]  <= csr_w_data[ `_PRMD_PIE];
    end
  end
end
assign csr_o.prmd = prmd_q;

// euen
logic euen_we,euen_re;
assign euen_we = csr_we && (csr_w_addr_i == `_CSR_EUEN);
always_ff @(posedge clk) begin
  if(!rst_n) begin
    euen_q <= '0;
  end
  else begin
    if(euen_we) begin
      euen_q[`_EUEN_FPE] <= csr_w_data[`_EUEN_FPE];
    end
  end
end
assign csr_o.euen = euen_q;

// ectl
logic ectl_we,ectl_re;
assign ectl_we = csr_we && (csr_w_addr_i == `_CSR_ECTL);
always_ff @(posedge clk) begin
  if(!rst_n) begin
    ectl_q <= '0;
  end
  else begin
    if(ectl_we) begin
      ectl_q[`_ECTL_LIE1] <= csr_w_data[`_ECTL_LIE1];
      ectl_q[`_ECTL_LIE2] <= csr_w_data[`_ECTL_LIE2];
    end
  end
end
assign csr_o.ectl = ectl_q;

// estat
logic estat_we,estat_re;
logic timer_en;
//ticlr
logic ticlr_we,ticlr_re;
logic tcfg_we,tcfg_re;
logic[7:0] int_q;
logic timer_intr_q;
always_ff @(posedge clk) begin
  timer_intr_q <= (timer_en && (tval_q == 32'd1 || tval_q == 32'd0));
end
always_ff @(posedge clk) begin
  int_q <= int_i;
end
assign estat_we = csr_we && (csr_w_addr_i == `_CSR_ESTAT);
logic estat_we_q;
logic[1:0] estat_sft_intr_q;
always_ff @(posedge clk) begin
  estat_we_q       <= estat_we;
  estat_sft_intr_q <= csr_w_data[1:0];
end
always_ff @(posedge clk) begin
  if (!rst_n) begin
    estat_q[1:0]   <= 2'b0;
    estat_q[10]    <= 1'b0;
    estat_q[12]    <= 1'b0;
    estat_q[15:13] <= 3'b0;
    estat_q[31]    <= 1'b0;

    timer_en <= 1'b0;
  end
  else begin
    if (ticlr_we && csr_w_data[`_TICLR_CLR]) begin
      estat_q[11] <= 1'b0;
    end
    else if (tcfg_we) begin
      timer_en <= csr_w_data[`_TCFG_EN];
    end
    // else if (timer_en && (tval_q == 32'b0)) begin
    else if (timer_intr_q && m1_commit_i_q && !m2_stall_i) begin
      estat_q[11] <= 1'b1;
      timer_en    <= tcfg_q[`_TCFG_PERIODIC];
    end

    // estat_q[9:2] <= int_i;
    if(m1_commit_i_q && !m2_stall_i) begin
      estat_q[9:2] <= int_q;
    end
    if (excp_valid) begin
      estat_q[`_ESTAT_ECODE]    <= ecode;
      estat_q[`_ESTAT_ESUBCODE] <= esubcode;
    end
    if (estat_we_q) begin // TODO: USE _Q ONLY FOR CHIPLAB.
      estat_q[1:0] <= estat_sft_intr_q;
    end
  end
end
// 注意：这里需要对 estate[1:0] 及 estate[11] 进行前递，以保证相关中断可以被足够及时的触发。
assign csr_o.estat = estat_q;
assign m1_int_o    = ({
    (ticlr_we && csr_w_data[`_TICLR_CLR]) ? '0 :
    (timer_intr_q ? 1'b1 : estat_q[11]) ,
    (int_q),
    estat_we ? csr_w_data[1:0] : (estat_we_q ? estat_sft_intr_q : estat_q[1:0])}
  & {ectl_q[11], ectl_q[9:0]}) != 0 && crmd_q[2];
// era
logic era_we,era_re;
assign era_we = csr_we && (csr_w_addr_i == `_CSR_ERA);
always_ff @(posedge clk) begin
  if (!rst_n) begin
    era_q <= '0;  // need not
  end
  else begin
    if (excp_valid) begin
      era_q <= era;
    end
    if (era_we) begin
      era_q <= csr_w_data;
    end
  end
end
assign csr_o.era = era_q;

// badv
logic badv_we,badv_re;
assign badv_we = csr_we && (csr_w_addr_i == `_CSR_BADV);
always_ff @(posedge clk) begin
  if (!rst_n) begin
    badv_q <= '0; // need not
  end
  else begin
    if (va_error) begin
      badv_q <= badva;
    end
    if (badv_we) begin
      badv_q <= csr_w_data;
    end
  end
end
assign csr_o.badv = badv_q;

// eentry
logic eentry_we,eentry_re;
assign eentry_we = csr_we && (csr_w_addr_i == `_CSR_EENTRY);
always_ff @(posedge clk) begin
  if(!rst_n) begin
    eentry_q[5:0] <= 6'b0;
  end
  else begin
    if(eentry_we) begin
      eentry_q[`_EENTRY_VA] <= csr_w_data[`_EENTRY_VA];
    end
  end
end
assign csr_o.eentry = eentry_q;

// tlbidx
logic tlbidx_we,tlbidx_re;
assign tlbidx_we = csr_we && (csr_w_addr_i == `_CSR_TLBIDX);
always_ff @(posedge clk) begin
  if(!rst_n) begin
    tlbidx_q[23:5]           <= 19'b0;
    tlbidx_q[30]             <= 1'b0;
    tlbidx_q[`_TLBIDX_INDEX] <= '0;
  end
  else begin
    if(tlbidx_we) begin
      tlbidx_q[`_TLBIDX_INDEX] <= csr_w_data[`_TLBIDX_INDEX];
      tlbidx_q[`_TLBIDX_PS]    <= csr_w_data[`_TLBIDX_PS];
      tlbidx_q[`_TLBIDX_NE]    <= csr_w_data[`_TLBIDX_NE];
    end
    else if (!m2_stall_i && tlb_op_i.tlbsrch) begin
      if (tlb_srch_valid_q) begin
        tlbidx_q[`_TLBIDX_INDEX] <= tlb_srch_idx_q;
        tlbidx_q[`_TLBIDX_NE]    <= 1'b0;
      end
      else begin
        tlbidx_q[`_TLBIDX_NE] <= 1'b1;
      end
    end
    else if (tlbrd_valid_wr_en) begin
      tlbidx_q[`_TLBIDX_PS] <= tlb_r_entry_q.key.ps;
      tlbidx_q[`_TLBIDX_NE] <= ~tlb_r_entry_q.key.e;
    end
    else if (tlbrd_invalid_wr_en) begin
      tlbidx_q[`_TLBIDX_PS] <= 6'b0;
      tlbidx_q[`_TLBIDX_NE] <= ~tlb_r_entry_q.key.e;
    end
  end
end
assign csr_o.tlbidx = tlbidx_q;

// tlbehi
logic tlbehi_we,tlbehi_re;
assign tlbehi_we = csr_we && (csr_w_addr_i == `_CSR_TLBEHI);
always_ff @(posedge clk) begin
  if(!rst_n) begin
    tlbehi_q <= /*DEFAULT VALUE*/'0;
  end
  else begin
    if(tlbehi_we) begin
      tlbehi_q[`_TLBEHI_VPPN] <= csr_w_data[`_TLBEHI_VPPN];
    end
    else if (tlbrd_valid_wr_en) begin
      tlbehi_q[`_TLBEHI_VPPN] <= tlb_r_entry_q.key.vppn;
    end
    else if (tlbrd_invalid_wr_en) begin
      tlbehi_q[`_TLBEHI_VPPN] <= '0;
    end
    else if (excp_tlb) begin
      tlbehi_q[`_TLBEHI_VPPN] <= badva[`_TLBEHI_VPPN];
    end
  end
end
assign csr_o.tlbehi = tlbehi_q;

//tlbelo0
logic tlbelo0_we,tlbelo0_re;
assign tlbelo0_we = csr_we && (csr_w_addr_i == `_CSR_TLBELO0);
always_ff @(posedge clk) begin
  if(!rst_n) begin
    tlbelo0_q <= /*DEFAULT VALUE*/'0;
  end
  else begin
    if(tlbelo0_we) begin
      tlbelo0_q                   <= csr_w_data;
      tlbelo0_q[`_TLBELO_TLB_V]   <= csr_w_data[`_TLBELO_TLB_V];
      tlbelo0_q[`_TLBELO_TLB_D]   <= csr_w_data[`_TLBELO_TLB_D];
      tlbelo0_q[`_TLBELO_TLB_PLV] <= csr_w_data[`_TLBELO_TLB_PLV];
      tlbelo0_q[`_TLBELO_TLB_MAT] <= csr_w_data[`_TLBELO_TLB_MAT];
      tlbelo0_q[`_TLBELO_TLB_G]   <= csr_w_data[`_TLBELO_TLB_G];
      tlbelo0_q[`_TLBELO_TLB_PPN] <= csr_w_data[`_TLBELO_TLB_PPN];
    end
    else if (tlbrd_valid_wr_en) begin
      tlbelo0_q[`_TLBELO_TLB_V]   <= tlb_r_entry_q.value[0].v;
      tlbelo0_q[`_TLBELO_TLB_D]   <= tlb_r_entry_q.value[0].d;
      tlbelo0_q[`_TLBELO_TLB_PLV] <= tlb_r_entry_q.value[0].plv;
      tlbelo0_q[`_TLBELO_TLB_MAT] <= tlb_r_entry_q.value[0].mat;
      tlbelo0_q[`_TLBELO_TLB_G]   <= tlb_r_entry_q.key.g;
      tlbelo0_q[`_TLBELO_TLB_PPN] <= tlb_r_entry_q.value[0].ppn;
    end
    else if (tlbrd_invalid_wr_en) begin
      tlbelo0_q[`_TLBELO_TLB_V]   <= '0;
      tlbelo0_q[`_TLBELO_TLB_D]   <= '0;
      tlbelo0_q[`_TLBELO_TLB_PLV] <= '0;
      tlbelo0_q[`_TLBELO_TLB_MAT] <= '0;
      tlbelo0_q[`_TLBELO_TLB_G]   <= '0;
      tlbelo0_q[`_TLBELO_TLB_PPN] <= '0;
    end
  end
end
assign csr_o.tlbelo0 = tlbelo0_q;

//tlblo1
logic tlbelo1_we,tlbelo1_re;
assign tlbelo1_we = csr_we && (csr_w_addr_i == `_CSR_TLBELO1);
always_ff @(posedge clk) begin
  if(!rst_n) begin
    tlbelo1_q <= /*DEFAULT VALUE*/'0;
  end
  else begin
    if(tlbelo1_we) begin
      tlbelo1_q                   <= csr_w_data;
      tlbelo1_q[`_TLBELO_TLB_V]   <= csr_w_data[`_TLBELO_TLB_V];
      tlbelo1_q[`_TLBELO_TLB_D]   <= csr_w_data[`_TLBELO_TLB_D];
      tlbelo1_q[`_TLBELO_TLB_PLV] <= csr_w_data[`_TLBELO_TLB_PLV];
      tlbelo1_q[`_TLBELO_TLB_MAT] <= csr_w_data[`_TLBELO_TLB_MAT];
      tlbelo1_q[`_TLBELO_TLB_G]   <= csr_w_data[`_TLBELO_TLB_G];
      tlbelo1_q[`_TLBELO_TLB_PPN] <= csr_w_data[`_TLBELO_TLB_PPN];
    end
    else if (tlbrd_valid_wr_en) begin
      tlbelo1_q[`_TLBELO_TLB_V]   <= tlb_r_entry_q.value[1].v;
      tlbelo1_q[`_TLBELO_TLB_D]   <= tlb_r_entry_q.value[1].d;
      tlbelo1_q[`_TLBELO_TLB_PLV] <= tlb_r_entry_q.value[1].plv;
      tlbelo1_q[`_TLBELO_TLB_MAT] <= tlb_r_entry_q.value[1].mat;
      tlbelo1_q[`_TLBELO_TLB_G]   <= tlb_r_entry_q.key.g;
      tlbelo1_q[`_TLBELO_TLB_PPN] <= tlb_r_entry_q.value[1].ppn;
    end
    else if (tlbrd_invalid_wr_en) begin
      tlbelo1_q[`_TLBELO_TLB_V]   <= '0;
      tlbelo1_q[`_TLBELO_TLB_D]   <= '0;
      tlbelo1_q[`_TLBELO_TLB_PLV] <= '0;
      tlbelo1_q[`_TLBELO_TLB_MAT] <= '0;
      tlbelo1_q[`_TLBELO_TLB_G]   <= '0;
      tlbelo1_q[`_TLBELO_TLB_PPN] <= '0;
    end
  end
end
assign csr_o.tlbelo1 = tlbelo1_q;

//asid
logic asid_we,asid_re;
assign asid_we = csr_we && (csr_w_addr_i == `_CSR_ASID);
always_ff @(posedge clk) begin
  if(!rst_n) begin
    asid_q[31:10] <= /*DEFAULT VALUE*/22'h280;
  end
  else begin
    if (asid_we) begin
      asid_q[`_ASID] <= csr_w_data[`_ASID];
    end
    else if (tlbrd_valid_wr_en) begin
      asid_q[`_ASID] <= tlb_r_entry_q.key.asid;
    end
    else if (tlbrd_invalid_wr_en) begin
      asid_q[`_ASID] <= 10'b0;
    end
  end
end
assign csr_o.asid = asid_q;

// pgd
logic pgd_re;

//pgdl
logic pgdl_we,pgdl_re;
assign pgdl_we = csr_we && (csr_w_addr_i == `_CSR_PGDL);
always_ff @(posedge clk) begin
  if(!rst_n) begin
    pgdl_q <= /*DEFAULT VALUE*/'0;
  end
  else begin
    if(pgdl_we) begin
      pgdl_q[`_PGD_BASE] <= csr_w_data[`_PGD_BASE];
    end
  end
end
assign csr_o.pgdl = pgdl_q;

//pgdh
logic pgdh_we,pgdh_re;
assign pgdh_we = csr_we && (csr_w_addr_i == `_CSR_PGDH);
always_ff @(posedge clk) begin
  if(!rst_n) begin
    pgdh_q <= /*DEFAULT VALUE*/'0;
  end
  else begin
    if(pgdh_we) begin
      pgdh_q[`_PGD_BASE] <= csr_w_data[`_PGD_BASE];
    end
  end
end
assign csr_o.pgdh = pgdh_q;

//cpuid
logic cpuid_we,cpuid_re;
assign cpuid_we = csr_we && (csr_w_addr_i == `_CSR_CPUID);
always_ff @(posedge clk) begin
  if(!rst_n) begin
    cpuid_q <= /*DEFAULT VALUE*/'0;
  end
  // else begin
  //   if(cpuid_we) begin
  //     cpuid_q <= csr_w_data; //TODO
  //   end
  // end
end
assign csr_o.cpuid = cpuid_q;

//savd0
logic save0_we,save0_re;
assign save0_we = csr_we && (csr_w_addr_i == `_CSR_SAVE0);
always_ff @(posedge clk) begin
  if(!rst_n) begin
    save0_q <= /*DEFAULT VALUE*/'0;
  end
  else begin
    if(save0_we) begin
      save0_q <= csr_w_data;
    end
  end
end
assign csr_o.save0 = save0_q;
logic save1_we,save1_re;
assign save1_we = csr_we && (csr_w_addr_i == `_CSR_SAVE1);
always_ff @(posedge clk) begin
  if(!rst_n) begin
    save1_q <= /*DEFAULT VALUE*/'0;
  end
  else begin
    if(save1_we) begin
      save1_q <= csr_w_data;
    end
  end
end
assign csr_o.save1 = save1_q;
logic save2_we,save2_re;
assign save2_we = csr_we && (csr_w_addr_i == `_CSR_SAVE2);
always_ff @(posedge clk) begin
  if(!rst_n) begin
    save2_q <= /*DEFAULT VALUE*/'0;
  end
  else begin
    if(save2_we) begin
      save2_q <= csr_w_data;
    end
  end
end
assign csr_o.save2 = save2_q;
logic save3_we,save3_re;
assign save3_we = csr_we && (csr_w_addr_i == `_CSR_SAVE3);
always_ff @(posedge clk) begin
  if(!rst_n) begin
    save3_q <= /*DEFAULT VALUE*/'0;
  end
  else begin
    if(save3_we) begin
      save3_q <= csr_w_data;
    end
  end
end
assign csr_o.save3 = save3_q;

//tid
logic tid_we,tid_re;
assign tid_we = csr_we && (csr_w_addr_i == `_CSR_TID);
always_ff @(posedge clk) begin
  if(!rst_n) begin
    tid_q <= /*DEFAULT VALUE*/'0;
  end
  else begin
    if(tid_we) begin
      tid_q <= csr_w_data;
    end
  end
end
assign csr_o.tid = tid_q;

//tcfg
assign tcfg_we = csr_we && (csr_w_addr_i == `_CSR_TCFG);
always_ff @(posedge clk) begin
  if(!rst_n) begin
    tcfg_q[`_TCFG_EN] <= /*DEFAULT VALUE*/'0;
  end
  else begin
    if(tcfg_we) begin
      tcfg_q[`_TCFG_EN]       <= csr_w_data[`_TCFG_EN];
      tcfg_q[`_TCFG_PERIODIC] <= csr_w_data[`_TCFG_PERIODIC];
      tcfg_q[`_TCFG_INITVAL]  <= csr_w_data[`_TCFG_INITVAL];
    end
  end
end
assign csr_o.tcfg = tcfg_q;

//tval
logic tval_we,tval_re;
assign tval_we = csr_we && (csr_w_addr_i == `_CSR_TVAL);
always_ff @(posedge clk) begin
  if(!rst_n) begin
    tval_q <= /*DEFAULT VALUE*/'0;
  end
  else begin
    if(tcfg_we) begin
      tval_q <= {csr_w_data[`_TCFG_INITVAL], 2'b0};
    end
    else if (timer_en) begin
      if (tval_q != 32'b0) begin
        tval_q <= tval_q - 32'b1;
      end
      else if (/*tval_q == 32'b0 &&*/ m1_commit_i_q && !m2_stall_i) begin
        tval_q <= tcfg_q[`_TCFG_PERIODIC] ? {tcfg_q[`_TCFG_INITVAL], 2'b0} : 32'hffffffff;
      end
    end
  end
end
assign csr_o.tval = tval_q;

//cntc
logic cntc_we,cntc_re;
assign cntc_we = csr_we && (csr_w_addr_i == `_CSR_CNTC);
always_ff @(posedge clk) begin
  if(!rst_n) begin
    cntc_q <= /*DEFAULT VALUE*/'0;
  end
  else begin
    if(cntc_we) begin
      cntc_q <= csr_w_data;
    end
  end
end
assign csr_o.cntc = cntc_q;

assign ticlr_we = csr_we && (csr_w_addr_i == `_CSR_TICLR);
always_ff @(posedge clk) begin
  if(!rst_n) begin
    ticlr_q <= /*DEFAULT VALUE*/'0;
  end
  // else begin
  //   if(ticlr_we) begin
  //     ticlr_q <= csr_w_data;
  //   end
  // end
  // TODO
end
assign csr_o.ticlr = ticlr_q;

//llbctl TODO
//llbit
logic llbit_q  ;
logic llbctl_we,llbctl_re;
assign llbctl_we = csr_we && (csr_w_addr_i == `_CSR_LLBCTL);
always_ff @(posedge clk) begin
  if(!rst_n) begin
    llbctl_q[`_LLBCT_KLO] <= /*DEFAULT VALUE*/'0;
    llbctl_q[31:3]        <= 29'b0;
    // llbctl_q[`_LLBCT_WCLLB] <= 1'b0;
    llbit_q               <= 1'b0;
  end
  else begin
    if (ertn_valid) begin
      if(llbctl_q[`_LLBCT_KLO]) begin
        llbctl_q[`_LLBCT_KLO] <= 1'b0;
      end
      else begin
        llbit_q <= 1'b0;
      end
    end
    else if(llbctl_we) begin
      llbctl_q[`_LLBCT_KLO] <= csr_w_data[`_LLBCT_KLO];
      if (csr_w_data[`_LLBCT_WCLLB] == 1'b1) begin
        llbit_q <= 1'b0;
      end
    end
    else if (llbit_set_i) begin
      llbit_q <= llbit_i;
    end
  end
end
assign csr_o.llbctl = llbctl_q;
assign csr_o.llbit  = llbit_q;

//tlbrentry
logic tlbrentry_we,tlbrentry_re;
assign tlbrentry_we = csr_we && (csr_w_addr_i == `_CSR_TLBRENTRY);
always_ff @(posedge clk) begin
  if(!rst_n) begin
    tlbrentry_q[5:0] <= /*DEFAULT VALUE*/'0;
  end
  else begin
    if(tlbrentry_we) begin
      tlbrentry_q[`_TLBRENTRY_PA] <= csr_w_data[`_TLBRENTRY_PA];
    end
  end
end
assign csr_o.tlbrentry = tlbrentry_q;

//ctag
logic ctag_we,ctag_re;
assign ctag_we = csr_we && (csr_w_addr_i == `_CSR_CTAG);
always_ff @(posedge clk) begin
  if(!rst_n) begin
    ctag_q <= /*DEFAULT VALUE*/'0;
  end
  else begin
    if(ctag_we) begin
      ctag_q <= csr_w_data;
    end
  end
end
assign csr_o.ctag = ctag_q;

//dmw0
logic dmw0_we,dmw0_re;
assign dmw0_we = csr_we && (csr_w_addr_i == `_CSR_DMW0);
always_ff @(posedge clk) begin
  if(!rst_n) begin
    dmw0_q <= /*DEFAULT VALUE*/'0;
  end
  else begin
    if(dmw0_we) begin
      dmw0_q[`_DMW_PLV0] <= csr_w_data[`_DMW_PLV0];
      dmw0_q[`_DMW_PLV3] <= csr_w_data[`_DMW_PLV3];
      dmw0_q[`_DMW_MAT]  <= csr_w_data[`_DMW_MAT];
      dmw0_q[`_DMW_PSEG] <= csr_w_data[`_DMW_PSEG];
      dmw0_q[`_DMW_VSEG] <= csr_w_data[`_DMW_VSEG];
    end
  end
end
assign csr_o.dmw0 = dmw0_q;

//dmw1
logic dmw1_we,dmw1_re;
assign dmw1_we = csr_we && (csr_w_addr_i == `_CSR_DMW1);
always_ff @(posedge clk) begin
  if(!rst_n) begin
    dmw1_q <= /*DEFAULT VALUE*/'0;
  end
  else begin
    if(dmw1_we) begin
      dmw1_q[`_DMW_PLV0] <= csr_w_data[`_DMW_PLV0];
      dmw1_q[`_DMW_PLV3] <= csr_w_data[`_DMW_PLV3];
      dmw1_q[`_DMW_MAT]  <= csr_w_data[`_DMW_MAT];
      dmw1_q[`_DMW_PSEG] <= csr_w_data[`_DMW_PSEG];
      dmw1_q[`_DMW_VSEG] <= csr_w_data[`_DMW_VSEG];
    end
  end
end
assign csr_o.dmw1 = dmw1_q;

// 读取逻辑
assign crmd_re      = rdcnt_i == '0 && csr_r_addr_i[8:0] == `_CSR_CRMD;
assign prmd_re      = rdcnt_i == '0 && csr_r_addr_i[8:0] == `_CSR_PRMD;
assign euen_re      = rdcnt_i == '0 && csr_r_addr_i[8:0] == `_CSR_EUEN;
assign ectl_re      = rdcnt_i == '0 && csr_r_addr_i[8:0] == `_CSR_ECTL;
assign estat_re     = rdcnt_i == '0 && csr_r_addr_i[8:0] == `_CSR_ESTAT;
assign era_re       = rdcnt_i == '0 && csr_r_addr_i[8:0] == `_CSR_ERA;
assign badv_re      = rdcnt_i == '0 && csr_r_addr_i[8:0] == `_CSR_BADV;
assign eentry_re    = rdcnt_i == '0 && csr_r_addr_i[8:0] == `_CSR_EENTRY;
assign tlbidx_re    = rdcnt_i == '0 && csr_r_addr_i[8:0] == `_CSR_TLBIDX;
assign tlbehi_re    = rdcnt_i == '0 && csr_r_addr_i[8:0] == `_CSR_TLBEHI;
assign tlbelo0_re   = rdcnt_i == '0 && csr_r_addr_i[8:0] == `_CSR_TLBELO0;
assign tlbelo1_re   = rdcnt_i == '0 && csr_r_addr_i[8:0] == `_CSR_TLBELO1;
assign asid_re      = rdcnt_i == '0 && csr_r_addr_i[8:0] == `_CSR_ASID;
assign pgdl_re      = rdcnt_i == '0 && csr_r_addr_i[8:0] == `_CSR_PGDL;
assign pgdh_re      = rdcnt_i == '0 && csr_r_addr_i[8:0] == `_CSR_PGDH;
assign pgd_re       = rdcnt_i == '0 && csr_r_addr_i[8:0] == `_CSR_PGD;
assign cpuid_re     = rdcnt_i == '0 && csr_r_addr_i[8:0] == `_CSR_CPUID;
assign save0_re     = rdcnt_i == '0 && csr_r_addr_i[8:0] == `_CSR_SAVE0;
assign save1_re     = rdcnt_i == '0 && csr_r_addr_i[8:0] == `_CSR_SAVE1;
assign save2_re     = rdcnt_i == '0 && csr_r_addr_i[8:0] == `_CSR_SAVE2;
assign save3_re     = rdcnt_i == '0 && csr_r_addr_i[8:0] == `_CSR_SAVE3;
assign tid_re       = rdcnt_i == '0 && csr_r_addr_i[8:0] == `_CSR_TID;
assign tcfg_re      = rdcnt_i == '0 && csr_r_addr_i[8:0] == `_CSR_TCFG;
assign tval_re      = rdcnt_i == '0 && csr_r_addr_i[8:0] == `_CSR_TVAL;
assign cntc_re      = rdcnt_i == '0 && csr_r_addr_i[8:0] == `_CSR_CNTC;
assign ticlr_re     = rdcnt_i == '0 && csr_r_addr_i[8:0] == `_CSR_TICLR;
assign llbctl_re    = rdcnt_i == '0 && csr_r_addr_i[8:0] == `_CSR_LLBCTL;
assign tlbrentry_re = rdcnt_i == '0 && csr_r_addr_i[8:0] == `_CSR_TLBRENTRY;
assign ctag_re      = rdcnt_i == '0 && csr_r_addr_i[8:0] == `_CSR_CTAG;
assign dmw0_re      = rdcnt_i == '0 && csr_r_addr_i[8:0] == `_CSR_DMW0;
assign dmw1_re      = rdcnt_i == '0 && csr_r_addr_i[8:0] == `_CSR_DMW1;
logic cntid_re,cntl_re,cnth_re;
assign cntid_re = rdcnt_i == `_RDCNT_ID_VLOW;
assign cntl_re  = rdcnt_i == `_RDCNT_VLOW;
assign cnth_re  = rdcnt_i == `_RDCNT_VHIGH;

always_ff @(posedge clk) begin
  if(!m2_stall_i) begin
    if(crmd_re) begin
      csr_r_data_o <= crmd_q;
    end
    if(prmd_re) begin
      csr_r_data_o <= prmd_q;
    end
    if(euen_re) begin
      csr_r_data_o <= euen_q;
    end
    if(ectl_re) begin
      csr_r_data_o <= ectl_q;
    end
    if(estat_re) begin
      csr_r_data_o <= estat_q;
    end
    if(era_re) begin
      csr_r_data_o <= era_q;
    end
    if(badv_re) begin
      csr_r_data_o <= badv_q;
    end
    if(eentry_re) begin
      csr_r_data_o <= eentry_q;
    end
    if(tlbidx_re) begin
      csr_r_data_o <= tlbidx_q;
    end
    if(tlbehi_re) begin
      csr_r_data_o <= tlbehi_q;
    end
    if(tlbelo0_re) begin
      csr_r_data_o <= tlbelo0_q;
    end
    if(tlbelo1_re) begin
      csr_r_data_o <= tlbelo1_q;
    end
    if(asid_re) begin
      csr_r_data_o <= asid_q;
    end
    if(pgdl_re) begin
      csr_r_data_o <= pgdl_q;
    end
    if(pgdh_re) begin
      csr_r_data_o <= pgdh_q;
    end
    if(pgd_re) begin
      csr_r_data_o <= {(badv_q[31] ? pgdh_q[31:12] : pgdl_q[31:12]), 12'd0};
    end
    if(cpuid_re) begin
      csr_r_data_o <= cpuid_q;
    end
    if(save0_re) begin
      csr_r_data_o <= save0_q;
    end
    if(save1_re) begin
      csr_r_data_o <= save1_q;
    end
    if(save2_re) begin
      csr_r_data_o <= save2_q;
    end
    if(save3_re) begin
      csr_r_data_o <= save3_q;
    end
    if(tid_re || cntid_re) begin
      csr_r_data_o <= tid_q;
    end
    if(tcfg_re) begin
      csr_r_data_o <= tcfg_q;
    end
    if(tval_re) begin
      csr_r_data_o <= tval_q;
    end
    if(cntc_re) begin
      csr_r_data_o <= cntc_q;
    end
    if(ticlr_re) begin
      csr_r_data_o <= ticlr_q;
    end
    if(llbctl_re) begin
      csr_r_data_o <= {llbctl_q, 1'b0, llbit_q};
    end
    if(tlbrentry_re) begin
      csr_r_data_o <= tlbrentry_q;
    end
    if(ctag_re) begin
      csr_r_data_o <= ctag_q;
    end
    if(dmw0_re) begin
      csr_r_data_o <= dmw0_q;
    end
    if(dmw1_re) begin
      csr_r_data_o <= dmw1_q;
    end
    if(cntl_re) begin
      csr_r_data_o <= timer_64_q[31:0];
    end
    if(cnth_re) begin
      csr_r_data_o <= timer_64_q[63:32];
    end
  end
end

endmodule
