`ifndef _CSR_HEADER
`define _CSR_HEADER

`include "pipeline.svh"

//INSTR
`define _INSTR_RJ       9:5
`define _INSTR_CSR_NUM  23:10
//CRMD
`define _CRMD_PLV       1:0
`define _CRMD_IE        2
`define _CRMD_DA        3
`define _CRMD_PG        4
`define _CRMD_DATF      6:5
`define _CRMD_DATM      8:7
//PRMD
`define _PRMD_PPLV      1:0
`define _PRMD_PIE       2
//EUEN
`define _EUEN_FPE       0
//ECTL
`define _ECTL_LIE       12:0
`define _ECTL_LIE1      9:0
`define _ECTL_LIE2      12:11
//ESTAT
`define _ESTAT_IS        12:0
`define _ESTAT_ECODE     21:16
`define _ESTAT_ESUBCODE  30:22
//EENTRY
`define _EENTRY_VA       31:6
//TLBIDX
`define _TLBIDX_INDEX     $clog2(`_TLB_ENTRY_NUM)-1:0
`define _TLBIDX_PS        29:24
`define _TLBIDX_NE        31
//TLBEHI
`define _TLBEHI_VPPN      31:13
//TLBELO
`define _TLBELO_TLB_V      0
`define _TLBELO_TLB_D      1
`define _TLBELO_TLB_PLV    3:2
`define _TLBELO_TLB_MAT    5:4
`define _TLBELO_TLB_G      6
`define _TLBELO_TLB_PPN    27:8
`define _TLBELO_TLB_PPN_EN 27:8   //todo
//ASID
`define _ASID  9:0
//CPUID
`define _COREID    8:0
//LLBCTL
`define _LLBCT_ROLLB     0
`define _LLBCT_WCLLB     1
`define _LLBCT_KLO       2
//TCFG
`define _TCFG_EN        0
`define _TCFG_PERIODIC  1
`define _TCFG_INITVAL   31:2
//TICLR
`define _TICLR_CLR       0
//TLBRENTRY
`define _TLBRENTRY_PA 31:6
//DMW
`define _DMW_PLV0      0
`define _DMW_PLV3      3 
`define _DMW_MAT       5:4
`define _DMW_PSEG      27:25
`define _DMW_VSEG      31:29
//PGDL PGDH PGD
`define _PGD_BASE      31:12

`define _ECODE_INT  6'h0
`define _ECODE_PIL  6'h1
`define _ECODE_PIS  6'h2
`define _ECODE_PIF  6'h3
`define _ECODE_PME  6'h4
`define _ECODE_PPI  6'h7
`define _ECODE_ADEF 6'h8
`define _ECODE_ADEM 6'h8
`define _ECODE_ALE  6'h9
`define _ECODE_SYS  6'hb
`define _ECODE_BRK  6'hc
`define _ECODE_INE  6'hd
`define _ECODE_IPE  6'he
`define _ECODE_FPD  6'hf
`define _ECODE_TLBR 6'h3f

`define _ESUBCODE_ADEF  9'h0
`define _ESUBCODE_ADEM  9'h1

`endif
