`timescale 1ns/1ps
`ifndef _COMMON_HEADER
`define _COMMON_HEADER

`define __AXI_CONVERTER_VER_1
`define __DLSU_VER_1
`define __NPC_VER_1
`define __ALU_VER_1
`define __MULTIPLIER_VER_2
`define __DIVIDER_VER_1
`define __NPC_VER_1

// `define _DIFFTEST_ENABLE
`define _FPGA

`define _CACHE_BUS_DATA_LEN (32)
`define _AXI_BURST_SIZE (4'b0011)
`define _SIMPLIFY_MUL (1)    // 0 for using multiplier 

`endif
