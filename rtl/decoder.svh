`ifndef _DECODER_SVH_
`define _DECODER_SVH_


`define _LINK_TYPE_PCPLUS4 (2'b00)
`define _CSR_CRMD (14'h0)
`define _CSR_PRMD (14'h1)
`define _CSR_EUEN (14'h2)
`define _CSR_ECTL (14'h4)
`define _CSR_ESTAT (14'h5)
`define _CSR_ERA (14'h6)
`define _CSR_BADV (14'h7)
`define _CSR_EENTRY (14'hc)
`define _CSR_TLBIDX (14'h10)
`define _CSR_TLBEHI (14'h11)
`define _CSR_TLBELO0 (14'h12)
`define _CSR_TLBELO1 (14'h13)
`define _CSR_ASID (14'h18)
`define _CSR_PGDL (14'h19)
`define _CSR_PGDH (14'h1a)
`define _CSR_PGD (14'h1b)
`define _CSR_CPUID (14'h20)
`define _CSR_SAVE0 (14'h30)
`define _CSR_SAVE1 (14'h31)
`define _CSR_SAVE2 (14'h32)
`define _CSR_SAVE3 (14'h33)
`define _CSR_TID (14'h40)
`define _CSR_TCFG (14'h41)
`define _CSR_TVAL (14'h42)
`define _CSR_CNTC (14'h43)
`define _CSR_TICLR (14'h44)
`define _CSR_LLBCTL (14'h60)
`define _CSR_TLBRENTRY (14'h88)
`define _CSR_CTAG (14'h98)
`define _CSR_DMW0 (14'h180)
`define _CSR_DMW1 (14'h181)
`define _CSR_BRK (14'h100)
`define _CSR_DISABLE_CACHE (14'h101)
`define _INV_TLB_ALL (4'b1111)
`define _INV_TLB_MASK_G (4'b1000)
`define _INV_TLB_MASK_NG (4'b0100)
`define _INV_TLB_MASK_ASID (4'b0010)
`define _INV_TLB_MASK_VA (4'b0001)


typedef logic [1:0] reg_type_w_t;
typedef logic [2:0] mem_type_t;
typedef logic mem_read_t;
typedef logic [1:0] fu_sel_m2_t;
typedef logic need_lsu_t;
typedef logic [1:0] reg_type_r0_t;
typedef logic latest_r1_ex_t;
typedef logic [1:0] fu_sel_m1_t;
typedef logic reg_type_r1_t;
typedef logic [1:0] addr_imm_type_t;
typedef logic need_csr_t;
typedef logic latest_r0_m2_t;
typedef logic latest_r1_m2_t;
typedef logic [1:0] csr_rdcnt_t;
typedef logic invtlb_en_t;
typedef logic priv_inst_t;
typedef logic refetch_t;
typedef logic [1:0] alu_grand_op_t;
typedef logic [2:0] imm_type_t;
typedef logic [1:0] alu_op_t;
typedef logic latest_r1_m1_t;
typedef logic latest_r0_m1_t;
typedef logic break_inst_t;
typedef logic need_div_t;
typedef logic fu_sel_wb_t;
typedef logic need_bpu_t;
typedef logic target_type_t;
typedef logic [3:0] cmp_type_t;
typedef logic mem_write_t;
typedef logic llsc_inst_t;
typedef logic ertn_inst_t;
typedef logic latest_r0_ex_t;
typedef logic fu_sel_ex_t;
typedef logic tlbfill_en_t;
typedef logic need_mul_t;
typedef logic tlbrd_en_t;
typedef logic ibarrier_t;
typedef logic dbarrier_t;
typedef logic csr_op_en_t;
typedef logic tlbwr_en_t;
typedef logic mem_cacop_t;
typedef logic syscall_inst_t;
typedef logic wait_inst_t;
typedef logic tlbsrch_en_t;
typedef logic latest_rfalse_ex_t;
typedef logic latest_r0_wb_t;
typedef logic latest_rfalse_m1_t;
typedef logic latest_r1_wb_t;
typedef logic [31:0] debug_inst_t;

typedef logic invalid_inst_t;

`define _ALU_GTYPE_BW (2'd0)
`define _ALU_GTYPE_MUL (2'd3)
`define _ALU_GTYPE_LI (2'd1)
`define _ALU_GTYPE_INT (2'd1)
`define _ALU_GTYPE_CMP (2'd3)
`define _ALU_GTYPE_SFT (2'd2)
`define _REG_W_NONE (2'd0)
`define _REG_W_RD (2'd1)
`define _REG_W_RJD (2'd2)
`define _REG_W_BL1 (2'd3)
`define _MEM_TYPE_WORD (3'd1)
`define _MEM_TYPE_HALF (3'd2)
`define _MEM_TYPE_UWORD (3'd5)
`define _MEM_TYPE_UBYTE (3'd7)
`define _MEM_TYPE_NONE (3'd0)
`define _MEM_TYPE_UHALF (3'd6)
`define _MEM_TYPE_BYTE (3'd3)
`define _IMM_S16 (3'd3)
`define _IMM_U5 (3'd0)
`define _IMM_U12 (3'd0)
`define _IMM_S21 (3'd4)
`define _IMM_S20 (3'd2)
`define _IMM_S12 (3'd1)
`define _ALU_STYPE_LUI (2'd1)
`define _ALU_STYPE_SLL (2'd2)
`define _ALU_STYPE_LIEMPTYSLOT (2'd0)
`define _ALU_STYPE_INTEMPTYSLOT1 (2'd2)
`define _ALU_STYPE_SUB (2'd2)
`define _DIV_TYPE_MOD (2'd2)
`define _ALU_STYPE_PCPLUS4 (2'd2)
`define _ALU_STYPE_NOR (2'd0)
`define _DIV_TYPE_DIVU (2'd1)
`define _ALU_STYPE_INTEMPTYSLOT0 (2'd0)
`define _MUL_TYPE_MULHU (2'd2)
`define _ALU_STYPE_AND (2'd1)
`define _MUL_TYPE_MULL (2'd0)
`define _ALU_STYPE_PCADDUI (2'd3)
`define _ALU_STYPE_XOR (2'd3)
`define _ALU_STYPE_SLT (2'd0)
`define _ALU_STYPE_SRA (2'd0)
`define _DIV_TYPE_DIV (2'd0)
`define _ALU_STYPE_OR (2'd2)
`define _ALU_STYPE_SRL (2'd3)
`define _DIV_TYPE_MODU (2'd3)
`define _ALU_STYPE_SLTU (2'd1)
`define _MUL_TYPE_MULH (2'd1)
`define _ALU_STYPE_ADD (2'd0)
`define _FUSEL_EX_NONE (1'd0)
`define _FUSEL_EX_ALU (1'd1)
`define _FUSEL_WB_NONE (1'd0)
`define _FUSEL_WB_DIV (1'd1)
`define _FUSEL_M2_NONE (2'd0)
`define _FUSEL_M2_ALU (2'd1)
`define _FUSEL_M2_CSR (2'd2)
`define _FUSEL_M2_MEM (2'd3)
`define _RDCNT_NONE (2'd0)
`define _RDCNT_ID_VLOW (2'd1)
`define _RDCNT_VHIGH (2'd2)
`define _RDCNT_VLOW (2'd3)
`define _TARGET_REL (1'd0)
`define _TARGET_ABS (1'd1)
`define _REG_R0_NONE (2'd0)
`define _REG_R0_RK (2'd1)
`define _REG_R0_RD (2'd2)
`define _REG_R0_IMM (2'd3)
`define _FUSEL_M1_NONE (2'd0)
`define _FUSEL_M1_ALU (2'd1)
`define _FUSEL_M1_MEM (2'd2)
`define _REG_R1_NONE (1'd0)
`define _REG_R1_RJ (1'd1)
`define _ADDR_IMM_S26 (2'd0)
`define _ADDR_IMM_S12 (2'd1)
`define _ADDR_IMM_S14 (2'd2)
`define _ADDR_IMM_S16 (2'd3)
`define _CMP_LTU (4'd8)
`define _CMP_NONE (4'd0)
`define _CMP_LE (4'd13)
`define _CMP_E (4'd4)
`define _CMP_NOCONDITION (4'd14)
`define _CMP_NE (4'd10)
`define _CMP_GT (4'd3)
`define _CMP_GE (4'd7)
`define _CMP_LT (4'd9)
`define _CMP_GEU (4'd6)

typedef struct packed {
    debug_inst_t debug_inst;
    latest_r1_wb_t latest_r1_wb;
    latest_rfalse_m1_t latest_rfalse_m1;
    latest_r0_wb_t latest_r0_wb;
    latest_rfalse_ex_t latest_rfalse_ex;
    tlbsrch_en_t tlbsrch_en;
    wait_inst_t wait_inst;
    syscall_inst_t syscall_inst;
    mem_cacop_t mem_cacop;
    tlbwr_en_t tlbwr_en;
    csr_op_en_t csr_op_en;
    dbarrier_t dbarrier;
    ibarrier_t ibarrier;
    tlbrd_en_t tlbrd_en;
    need_mul_t need_mul;
    tlbfill_en_t tlbfill_en;
    fu_sel_ex_t fu_sel_ex;
    latest_r0_ex_t latest_r0_ex;
    ertn_inst_t ertn_inst;
    llsc_inst_t llsc_inst;
    mem_write_t mem_write;
    cmp_type_t cmp_type;
    target_type_t target_type;
    need_bpu_t need_bpu;
    fu_sel_wb_t fu_sel_wb;
    need_div_t need_div;
    break_inst_t break_inst;
    latest_r0_m1_t latest_r0_m1;
    latest_r1_m1_t latest_r1_m1;
    alu_op_t alu_op;
    imm_type_t imm_type;
    alu_grand_op_t alu_grand_op;
    refetch_t refetch;
    priv_inst_t priv_inst;
    invtlb_en_t invtlb_en;
    csr_rdcnt_t csr_rdcnt;
    latest_r1_m2_t latest_r1_m2;
    latest_r0_m2_t latest_r0_m2;
    need_csr_t need_csr;
    addr_imm_type_t addr_imm_type;
    reg_type_r1_t reg_type_r1;
    fu_sel_m1_t fu_sel_m1;
    latest_r1_ex_t latest_r1_ex;
    reg_type_r0_t reg_type_r0;
    need_lsu_t need_lsu;
    fu_sel_m2_t fu_sel_m2;
    mem_read_t mem_read;
    mem_type_t mem_type;
    reg_type_w_t reg_type_w;
    invalid_inst_t invalid_inst;
} is_t;

typedef struct packed {
    debug_inst_t debug_inst;
    latest_r1_wb_t latest_r1_wb;
    latest_rfalse_m1_t latest_rfalse_m1;
    latest_r0_wb_t latest_r0_wb;
    latest_rfalse_ex_t latest_rfalse_ex;
    tlbsrch_en_t tlbsrch_en;
    wait_inst_t wait_inst;
    syscall_inst_t syscall_inst;
    mem_cacop_t mem_cacop;
    tlbwr_en_t tlbwr_en;
    csr_op_en_t csr_op_en;
    dbarrier_t dbarrier;
    ibarrier_t ibarrier;
    tlbrd_en_t tlbrd_en;
    need_mul_t need_mul;
    tlbfill_en_t tlbfill_en;
    fu_sel_ex_t fu_sel_ex;
    latest_r0_ex_t latest_r0_ex;
    ertn_inst_t ertn_inst;
    llsc_inst_t llsc_inst;
    mem_write_t mem_write;
    cmp_type_t cmp_type;
    target_type_t target_type;
    need_bpu_t need_bpu;
    fu_sel_wb_t fu_sel_wb;
    need_div_t need_div;
    break_inst_t break_inst;
    latest_r0_m1_t latest_r0_m1;
    latest_r1_m1_t latest_r1_m1;
    alu_op_t alu_op;
    alu_grand_op_t alu_grand_op;
    refetch_t refetch;
    priv_inst_t priv_inst;
    invtlb_en_t invtlb_en;
    csr_rdcnt_t csr_rdcnt;
    latest_r1_m2_t latest_r1_m2;
    latest_r0_m2_t latest_r0_m2;
    addr_imm_type_t addr_imm_type;
    fu_sel_m1_t fu_sel_m1;
    latest_r1_ex_t latest_r1_ex;
    need_lsu_t need_lsu;
    fu_sel_m2_t fu_sel_m2;
    mem_read_t mem_read;
    mem_type_t mem_type;
    invalid_inst_t invalid_inst;
} ex_t;

typedef struct packed {
    debug_inst_t debug_inst;
    latest_r1_wb_t latest_r1_wb;
    latest_rfalse_m1_t latest_rfalse_m1;
    latest_r0_wb_t latest_r0_wb;
    tlbsrch_en_t tlbsrch_en;
    wait_inst_t wait_inst;
    syscall_inst_t syscall_inst;
    mem_cacop_t mem_cacop;
    tlbwr_en_t tlbwr_en;
    csr_op_en_t csr_op_en;
    dbarrier_t dbarrier;
    ibarrier_t ibarrier;
    tlbrd_en_t tlbrd_en;
    tlbfill_en_t tlbfill_en;
    ertn_inst_t ertn_inst;
    llsc_inst_t llsc_inst;
    mem_write_t mem_write;
    cmp_type_t cmp_type;
    need_bpu_t need_bpu;
    fu_sel_wb_t fu_sel_wb;
    need_div_t need_div;
    break_inst_t break_inst;
    latest_r0_m1_t latest_r0_m1;
    latest_r1_m1_t latest_r1_m1;
    alu_op_t alu_op;
    alu_grand_op_t alu_grand_op;
    refetch_t refetch;
    priv_inst_t priv_inst;
    invtlb_en_t invtlb_en;
    csr_rdcnt_t csr_rdcnt;
    latest_r1_m2_t latest_r1_m2;
    latest_r0_m2_t latest_r0_m2;
    fu_sel_m1_t fu_sel_m1;
    need_lsu_t need_lsu;
    fu_sel_m2_t fu_sel_m2;
    mem_read_t mem_read;
    mem_type_t mem_type;
    invalid_inst_t invalid_inst;
} m1_t;

typedef struct packed {
    debug_inst_t debug_inst;
    latest_r1_wb_t latest_r1_wb;
    latest_r0_wb_t latest_r0_wb;
    tlbsrch_en_t tlbsrch_en;
    wait_inst_t wait_inst;
    mem_cacop_t mem_cacop;
    tlbwr_en_t tlbwr_en;
    csr_op_en_t csr_op_en;
    tlbrd_en_t tlbrd_en;
    tlbfill_en_t tlbfill_en;
    ertn_inst_t ertn_inst;
    llsc_inst_t llsc_inst;
    mem_write_t mem_write;
    fu_sel_wb_t fu_sel_wb;
    need_div_t need_div;
    latest_r0_m1_t latest_r0_m1;
    alu_op_t alu_op;
    alu_grand_op_t alu_grand_op;
    invtlb_en_t invtlb_en;
    latest_r1_m2_t latest_r1_m2;
    latest_r0_m2_t latest_r0_m2;
    need_lsu_t need_lsu;
    fu_sel_m2_t fu_sel_m2;
    mem_read_t mem_read;
    mem_type_t mem_type;
} m2_t;

typedef struct packed {
    debug_inst_t debug_inst;
    latest_r1_wb_t latest_r1_wb;
    latest_r0_wb_t latest_r0_wb;
    fu_sel_wb_t fu_sel_wb;
    need_div_t need_div;
} wb_t;

typedef struct packed {
    debug_inst_t debug_inst;
    latest_r1_wb_t latest_r1_wb;
    latest_rfalse_m1_t latest_rfalse_m1;
    latest_r0_wb_t latest_r0_wb;
    latest_rfalse_ex_t latest_rfalse_ex;
    tlbsrch_en_t tlbsrch_en;
    wait_inst_t wait_inst;
    syscall_inst_t syscall_inst;
    mem_cacop_t mem_cacop;
    tlbwr_en_t tlbwr_en;
    csr_op_en_t csr_op_en;
    dbarrier_t dbarrier;
    ibarrier_t ibarrier;
    tlbrd_en_t tlbrd_en;
    need_mul_t need_mul;
    tlbfill_en_t tlbfill_en;
    fu_sel_ex_t fu_sel_ex;
    latest_r0_ex_t latest_r0_ex;
    ertn_inst_t ertn_inst;
    llsc_inst_t llsc_inst;
    mem_write_t mem_write;
    cmp_type_t cmp_type;
    target_type_t target_type;
    need_bpu_t need_bpu;
    fu_sel_wb_t fu_sel_wb;
    need_div_t need_div;
    break_inst_t break_inst;
    latest_r0_m1_t latest_r0_m1;
    latest_r1_m1_t latest_r1_m1;
    alu_op_t alu_op;
    imm_type_t imm_type;
    alu_grand_op_t alu_grand_op;
    refetch_t refetch;
    priv_inst_t priv_inst;
    invtlb_en_t invtlb_en;
    csr_rdcnt_t csr_rdcnt;
    latest_r1_m2_t latest_r1_m2;
    latest_r0_m2_t latest_r0_m2;
    need_csr_t need_csr;
    addr_imm_type_t addr_imm_type;
    reg_type_r1_t reg_type_r1;
    fu_sel_m1_t fu_sel_m1;
    latest_r1_ex_t latest_r1_ex;
    reg_type_r0_t reg_type_r0;
    need_lsu_t need_lsu;
    fu_sel_m2_t fu_sel_m2;
    mem_read_t mem_read;
    mem_type_t mem_type;
    reg_type_w_t reg_type_w;
    invalid_inst_t invalid_inst;
} decoder_info_t;

function automatic is_t get_is_from_decoder_info(decoder_info_t decoder_info);
    is_t ret;
    ret.debug_inst = decoder_info.debug_inst;
    ret.reg_type_w = decoder_info.reg_type_w;
    ret.mem_type = decoder_info.mem_type;
    ret.mem_read = decoder_info.mem_read;
    ret.fu_sel_m2 = decoder_info.fu_sel_m2;
    ret.need_lsu = decoder_info.need_lsu;
    ret.reg_type_r0 = decoder_info.reg_type_r0;
    ret.latest_r1_ex = decoder_info.latest_r1_ex;
    ret.fu_sel_m1 = decoder_info.fu_sel_m1;
    ret.reg_type_r1 = decoder_info.reg_type_r1;
    ret.addr_imm_type = decoder_info.addr_imm_type;
    ret.need_csr = decoder_info.need_csr;
    ret.latest_r0_m2 = decoder_info.latest_r0_m2;
    ret.latest_r1_m2 = decoder_info.latest_r1_m2;
    ret.csr_rdcnt = decoder_info.csr_rdcnt;
    ret.invtlb_en = decoder_info.invtlb_en;
    ret.priv_inst = decoder_info.priv_inst;
    ret.refetch = decoder_info.refetch;
    ret.alu_grand_op = decoder_info.alu_grand_op;
    ret.imm_type = decoder_info.imm_type;
    ret.alu_op = decoder_info.alu_op;
    ret.latest_r1_m1 = decoder_info.latest_r1_m1;
    ret.latest_r0_m1 = decoder_info.latest_r0_m1;
    ret.break_inst = decoder_info.break_inst;
    ret.need_div = decoder_info.need_div;
    ret.fu_sel_wb = decoder_info.fu_sel_wb;
    ret.need_bpu = decoder_info.need_bpu;
    ret.target_type = decoder_info.target_type;
    ret.cmp_type = decoder_info.cmp_type;
    ret.mem_write = decoder_info.mem_write;
    ret.llsc_inst = decoder_info.llsc_inst;
    ret.ertn_inst = decoder_info.ertn_inst;
    ret.latest_r0_ex = decoder_info.latest_r0_ex;
    ret.fu_sel_ex = decoder_info.fu_sel_ex;
    ret.tlbfill_en = decoder_info.tlbfill_en;
    ret.need_mul = decoder_info.need_mul;
    ret.tlbrd_en = decoder_info.tlbrd_en;
    ret.ibarrier = decoder_info.ibarrier;
    ret.dbarrier = decoder_info.dbarrier;
    ret.csr_op_en = decoder_info.csr_op_en;
    ret.tlbwr_en = decoder_info.tlbwr_en;
    ret.mem_cacop = decoder_info.mem_cacop;
    ret.syscall_inst = decoder_info.syscall_inst;
    ret.wait_inst = decoder_info.wait_inst;
    ret.tlbsrch_en = decoder_info.tlbsrch_en;
    ret.latest_rfalse_ex = decoder_info.latest_rfalse_ex;
    ret.latest_r0_wb = decoder_info.latest_r0_wb;
    ret.latest_rfalse_m1 = decoder_info.latest_rfalse_m1;
    ret.latest_r1_wb = decoder_info.latest_r1_wb;
    ret.invalid_inst = decoder_info.invalid_inst;
    return ret;
endfunction

function automatic ex_t get_ex_from_is(is_t is);
    ex_t ret;
    ret.debug_inst = is.debug_inst;
    ret.mem_type = is.mem_type;
    ret.mem_read = is.mem_read;
    ret.fu_sel_m2 = is.fu_sel_m2;
    ret.need_lsu = is.need_lsu;
    ret.latest_r1_ex = is.latest_r1_ex;
    ret.fu_sel_m1 = is.fu_sel_m1;
    ret.addr_imm_type = is.addr_imm_type;
    ret.latest_r0_m2 = is.latest_r0_m2;
    ret.latest_r1_m2 = is.latest_r1_m2;
    ret.csr_rdcnt = is.csr_rdcnt;
    ret.invtlb_en = is.invtlb_en;
    ret.priv_inst = is.priv_inst;
    ret.refetch = is.refetch;
    ret.alu_grand_op = is.alu_grand_op;
    ret.alu_op = is.alu_op;
    ret.latest_r1_m1 = is.latest_r1_m1;
    ret.latest_r0_m1 = is.latest_r0_m1;
    ret.break_inst = is.break_inst;
    ret.need_div = is.need_div;
    ret.fu_sel_wb = is.fu_sel_wb;
    ret.need_bpu = is.need_bpu;
    ret.target_type = is.target_type;
    ret.cmp_type = is.cmp_type;
    ret.mem_write = is.mem_write;
    ret.llsc_inst = is.llsc_inst;
    ret.ertn_inst = is.ertn_inst;
    ret.latest_r0_ex = is.latest_r0_ex;
    ret.fu_sel_ex = is.fu_sel_ex;
    ret.tlbfill_en = is.tlbfill_en;
    ret.need_mul = is.need_mul;
    ret.tlbrd_en = is.tlbrd_en;
    ret.ibarrier = is.ibarrier;
    ret.dbarrier = is.dbarrier;
    ret.csr_op_en = is.csr_op_en;
    ret.tlbwr_en = is.tlbwr_en;
    ret.mem_cacop = is.mem_cacop;
    ret.syscall_inst = is.syscall_inst;
    ret.wait_inst = is.wait_inst;
    ret.tlbsrch_en = is.tlbsrch_en;
    ret.latest_rfalse_ex = is.latest_rfalse_ex;
    ret.latest_r0_wb = is.latest_r0_wb;
    ret.latest_rfalse_m1 = is.latest_rfalse_m1;
    ret.latest_r1_wb = is.latest_r1_wb;
    ret.invalid_inst = is.invalid_inst;
    return ret;
endfunction

function automatic m1_t get_m1_from_ex(ex_t ex);
    m1_t ret;
    ret.debug_inst = ex.debug_inst;
    ret.mem_type = ex.mem_type;
    ret.mem_read = ex.mem_read;
    ret.fu_sel_m2 = ex.fu_sel_m2;
    ret.need_lsu = ex.need_lsu;
    ret.fu_sel_m1 = ex.fu_sel_m1;
    ret.latest_r0_m2 = ex.latest_r0_m2;
    ret.latest_r1_m2 = ex.latest_r1_m2;
    ret.csr_rdcnt = ex.csr_rdcnt;
    ret.invtlb_en = ex.invtlb_en;
    ret.priv_inst = ex.priv_inst;
    ret.refetch = ex.refetch;
    ret.alu_grand_op = ex.alu_grand_op;
    ret.alu_op = ex.alu_op;
    ret.latest_r1_m1 = ex.latest_r1_m1;
    ret.latest_r0_m1 = ex.latest_r0_m1;
    ret.break_inst = ex.break_inst;
    ret.need_div = ex.need_div;
    ret.fu_sel_wb = ex.fu_sel_wb;
    ret.need_bpu = ex.need_bpu;
    ret.cmp_type = ex.cmp_type;
    ret.mem_write = ex.mem_write;
    ret.llsc_inst = ex.llsc_inst;
    ret.ertn_inst = ex.ertn_inst;
    ret.tlbfill_en = ex.tlbfill_en;
    ret.tlbrd_en = ex.tlbrd_en;
    ret.ibarrier = ex.ibarrier;
    ret.dbarrier = ex.dbarrier;
    ret.csr_op_en = ex.csr_op_en;
    ret.tlbwr_en = ex.tlbwr_en;
    ret.mem_cacop = ex.mem_cacop;
    ret.syscall_inst = ex.syscall_inst;
    ret.wait_inst = ex.wait_inst;
    ret.tlbsrch_en = ex.tlbsrch_en;
    ret.latest_r0_wb = ex.latest_r0_wb;
    ret.latest_rfalse_m1 = ex.latest_rfalse_m1;
    ret.latest_r1_wb = ex.latest_r1_wb;
    ret.invalid_inst = ex.invalid_inst;
    return ret;
endfunction

function automatic m2_t get_m2_from_m1(m1_t m1);
    m2_t ret;
    ret.debug_inst = m1.debug_inst;
    ret.mem_type = m1.mem_type;
    ret.mem_read = m1.mem_read;
    ret.fu_sel_m2 = m1.fu_sel_m2;
    ret.need_lsu = m1.need_lsu;
    ret.latest_r0_m2 = m1.latest_r0_m2;
    ret.latest_r1_m2 = m1.latest_r1_m2;
    ret.invtlb_en = m1.invtlb_en;
    ret.alu_grand_op = m1.alu_grand_op;
    ret.alu_op = m1.alu_op;
    ret.latest_r0_m1 = m1.latest_r0_m1;
    ret.need_div = m1.need_div;
    ret.fu_sel_wb = m1.fu_sel_wb;
    ret.mem_write = m1.mem_write;
    ret.llsc_inst = m1.llsc_inst;
    ret.ertn_inst = m1.ertn_inst;
    ret.tlbfill_en = m1.tlbfill_en;
    ret.tlbrd_en = m1.tlbrd_en;
    ret.csr_op_en = m1.csr_op_en;
    ret.tlbwr_en = m1.tlbwr_en;
    ret.mem_cacop = m1.mem_cacop;
    ret.wait_inst = m1.wait_inst;
    ret.tlbsrch_en = m1.tlbsrch_en;
    ret.latest_r0_wb = m1.latest_r0_wb;
    ret.latest_r1_wb = m1.latest_r1_wb;
    return ret;
endfunction

function automatic wb_t get_wb_from_m2(m2_t m2);
    wb_t ret;
    ret.debug_inst = m2.debug_inst;
    ret.need_div = m2.need_div;
    ret.fu_sel_wb = m2.fu_sel_wb;
    ret.latest_r0_wb = m2.latest_r0_wb;
    ret.latest_r1_wb = m2.latest_r1_wb;
    return ret;
endfunction

`endif
