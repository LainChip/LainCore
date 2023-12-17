#!/bin/python3
# -*- coding: utf-8 -*-
# @Time    : 2023/11/6 下午6:48
# @Author  : Yang Su
# @File    : gen_sram_wapper.py
# @Software: PyCharm 
# @Comment :

smic_tdpram_config = [
    {
        'words': 1024,
        'bits': 32,
        'mux': 4,
        'bit_write': True
    },
    {
        'words': 512,
        'bits': 30,
        'mux': 4,
        'bit_write': False
    },
    {
        'words': 256,
        'bits': 21,
        'mux': 4,
        'bit_write': False
    },
    {
        'words': 256,
        'bits': 14,
        'mux': 4,
        'bit_write': False
    }
]

# 按照words和bits的值去重
# unique_configs = []
# seen_configs = set()

# for config in smic_tdpram_config:
#     config_tuple = (config['words'], config['bits'])  # 创建一个只包含 'words' 和 'bits' 的元组
#     if config_tuple not in seen_configs and config['bit_write']:  # 如果这个元组之前没有出现过且bit_write为True
#         seen_configs.add(config_tuple)  # 将这个元组添加到已经看到的集合中
#         unique_configs.append(config)  # 将当前的字典元素添加到结果列表中

# for config in smic_tdpram_config:
#     config_tuple = (config['words'], config['bits'])  # 创建一个只包含 'words' 和 'bits' 的元组
#     if config_tuple not in seen_configs and not config['bit_write']:  # 如果这个元组之前没有出现过且bit_write为False
#         seen_configs.add(config_tuple)  # 将这个元组添加到已经看到的集合中
#         unique_configs.append(config)  # 将当前的字典元素添加到结果列表中

# smic_tdpram_config = unique_configs

tdpram_wrapper = '''`include "common.svh"

module tdpsram_wrapper #(
  parameter int unsigned DATA_WIDTH = 32  ,
  parameter int unsigned DATA_DEPTH = 1024,
  parameter int unsigned BYTE_SIZE  = 32
) (
  input                                     clk0    ,
  input                                     rst_n0  ,
  input  wire  [    $clog2(DATA_DEPTH)-1:0] addr0_i ,
  input                                     en0_i   ,
  input        [(DATA_WIDTH/BYTE_SIZE)-1:0] we0_i   ,
  input  logic [            DATA_WIDTH-1:0] wdata0_i,
  output logic [            DATA_WIDTH-1:0] rdata0_o,

  input                                     clk1    ,
  input                                     rst_n1  ,
  input  wire  [    $clog2(DATA_DEPTH)-1:0] addr1_i ,
  input  wire                               en1_i   ,
  input        [(DATA_WIDTH/BYTE_SIZE)-1:0] we1_i   ,
  input  logic [            DATA_WIDTH-1:0] wdata1_i,
  output logic [            DATA_WIDTH-1:0] rdata1_o
);

`ifdef _FPGA
  logic [(DATA_WIDTH/BYTE_SIZE)-1:0][(BYTE_SIZE/8)-1:0]ext_we0, ext_we1;
  for(genvar i = 0 ; i < (DATA_WIDTH/BYTE_SIZE); i++) begin
    assign ext_we0[i] = we0_i[i] ? '1 : '0;
    assign ext_we1[i] = we1_i[i] ? '1 : '0;
  end
  xpm_memory_tdpram #(
    .ADDR_WIDTH_A       ($clog2(DATA_DEPTH)     ),
    .ADDR_WIDTH_B       ($clog2(DATA_DEPTH)     ),
    .AUTO_SLEEP_TIME    (0                      ), // DECIMAL
    .BYTE_WRITE_WIDTH_A (DATA_WIDTH == BYTE_SIZE ? DATA_WIDTH : 8),
    .BYTE_WRITE_WIDTH_B (DATA_WIDTH == BYTE_SIZE ? DATA_WIDTH : 8),
    .CASCADE_HEIGHT     (0                      ), // DECIMAL
    .CLOCKING_MODE      ("common_clock"         ),
    .ECC_MODE           ("no_ecc"               ),
    .IGNORE_INIT_SYNTH  (0                      ), // DECIMAL
    .MEMORY_INIT_FILE   ("none"                 ),
    .MEMORY_INIT_PARAM  ("0"                    ),
    .MEMORY_OPTIMIZATION("true"                 ),
    .MEMORY_PRIMITIVE   ("auto"                 ), // String
    .MEMORY_SIZE        (DATA_WIDTH * DATA_DEPTH),
    .MESSAGE_CONTROL    (0                      ), // DECIMAL
    .READ_DATA_WIDTH_A  (DATA_WIDTH             ),
    .READ_DATA_WIDTH_B  (DATA_WIDTH             ),
    .READ_LATENCY_A     (1                      ), // DECIMAL
    .READ_LATENCY_B     (1                      ), // DECIMAL
    .USE_MEM_INIT       (0                      ),
    .WRITE_DATA_WIDTH_A (DATA_WIDTH             ),
    .WRITE_DATA_WIDTH_B (DATA_WIDTH             ),
    .WRITE_MODE_A       ("write_first"          ), // String
    .WRITE_MODE_B       ("write_first"          ), // String
    .WRITE_PROTECT      (1                      )  // DECIMAL
  ) xpm_memory_tdpram_inst (
    .douta         (rdata0_o),
    .doutb         (rdata1_o),
    .addra         (addr0_i ),
    .addrb         (addr1_i ),
    .clka          (clk0    ),
    .clkb          (clk1    ),
    .dina          (wdata0_i),
    .dinb          (wdata1_i),
    .ena           (en0_i   ),
    .enb           (en1_i   ),
    .injectdbiterra('0      ),
    .injectdbiterrb('0      ),
    .injectsbiterra('0      ),
    .injectsbiterrb('0      ),
    .regcea        ('1      ),
    .regceb        ('1      ),
    .rsta          (~rst_n0  ), 
    .rstb          (~rst_n1  ),
    .sleep         ('0      ),
    .wea           (DATA_WIDTH == BYTE_SIZE ? we0_i : ext_we0),
    .web           (DATA_WIDTH == BYTE_SIZE ? we1_i : ext_we1)
  );
`endif

`ifdef _VERILATOR
  reg [(DATA_WIDTH/BYTE_SIZE)-1:0][BYTE_SIZE-1:0] sim_ram[DATA_DEPTH-1:0];
  reg [(DATA_WIDTH/BYTE_SIZE)-1:0][BYTE_SIZE-1:0] rdata0_split_q,rdata1_split_q,wdata0_split,wdata1_split;
  assign wdata0_split = wdata0_i;
  assign wdata1_split = wdata1_i;
  assign rdata0_o = rdata0_split_q;
  assign rdata1_o = rdata1_split_q;
  // PORT A
  always_ff @(posedge clk0) begin
    if(en0_i) begin
        for(integer i = 0 ; i < (DATA_WIDTH/BYTE_SIZE) ; i++) begin
            if(we0_i[i]) begin
                rdata0_split_q[i] <= wdata0_split[i];
                // sim_ram[addr0_i][i] <= wdata0_split[i]; ONLY 1 PORT IS FOR WRITE.
            end else begin
                rdata0_split_q[i] <= sim_ram[addr0_i][i];
            end
        end
    end
  end

  // PORT B
  always_ff @(posedge clk1) begin
    if(en1_i) begin
        for(integer i = 0 ; i < (DATA_WIDTH/BYTE_SIZE) ; i++) begin
            if(we1_i[i]) begin
                rdata1_split_q[i] <= wdata1_split[i];
                sim_ram[addr1_i][i] <= wdata1_split[i];
            end else begin
                rdata1_split_q[i] <= sim_ram[addr1_i][i];
            end
        end
    end
  end

  // CHECK CONFLICT OF MEM ADDR
  // always_ff @(posedge clk) begin
  //   if(rst_n && en0_i && en1_i && addr0_i == addr1_i) begin
  //       $display("Conflict of mem adddr.");
  //       $finish;
  //   end
  // end
`endif

`ifdef _ASIC
  generate
      wire [DATA_WIDTH-1:0] bwena, bwenb;
      for (genvar i = 0; i < DATA_WIDTH/BYTE_SIZE; i++) begin
        assign bwena[(i+1)*BYTE_SIZE - 1:i*BYTE_SIZE] = {BYTE_SIZE{we0_i[i]}};
        assign bwenb[(i+1)*BYTE_SIZE - 1:i*BYTE_SIZE] = {BYTE_SIZE{we1_i[i]}};
      end
'''

name_format = "{HEAD}_RAM_DP_W{W}_B{B}_M{M}"

head = 'S018DP'
prefix = ''

for ram in smic_tdpram_config:
    name = name_format.format(HEAD=head, W=ram['words'], B=ram['bits'], M=ram['mux'])
    if ram['bit_write']:
        name += '_BW'
        tdpram_wrapper += f"""
    {prefix}if (DATA_DEPTH == {ram['words']} && DATA_WIDTH == {ram['bits']} && BYTE_SIZE != DATA_WIDTH) begin
      {name} {name}_INST (
      .QA      (rdata0_o),
      .QB      (rdata1_o),
      .CLKA    (clk0    ),
      .CLKB    (clk1    ),
      .CENA    (~en0_i),
      .CENB    (~en1_i),
      .WENA    (~en0_i),
      .WENB    (~en1_i),
      .BWENA   (~bwena),
      .BWENB   (~bwenb),
      .AA      (addr0_i),
      .AB      (addr1_i),
      .DA      (wdata0_i),
      .DB      (wdata1_i)
      );
    end
"""
    else:
        tdpram_wrapper += f"""
    {prefix}if (DATA_DEPTH == {ram['words']} && DATA_WIDTH == {ram['bits']} && BYTE_SIZE == DATA_WIDTH) begin
      {name} {name}_INST (
      .QA      (rdata0_o),
      .QB      (rdata1_o),
      .CLKA    (clk0    ),
      .CLKB    (clk1    ),
      .CENA    (~en0_i),
      .CENB    (~en1_i),
      .WENA    (~we0_i),
      .WENB    (~we1_i),
      .AA      (addr0_i),
      .AB      (addr1_i),
      .DA      (wdata0_i),
      .DB      (wdata1_i)
      );
    end
"""
    prefix = 'else '

tdpram_wrapper += """
    else begin
      initial begin
        $display("Not support tdpram type %d %d %d", DATA_WIDTH, DATA_DEPTH, BYTE_SIZE);
        #100
        $stop;
      end
    end
  endgenerate

`endif

endmodule
"""

# print(tdpram_wrapper)

# 写入文件
with open('../rtl/utils/tdpsram_wrapper.sv', 'w') as file:
    file.write(tdpram_wrapper)
