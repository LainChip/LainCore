# 关于本项目

![核心架构图](docs/lain架构图.png)

Lain Core 是一款由 @gmlayer0、@SUYANG、@Arthuring、@Xlucidator 实现的静态双发射的 LoongArch32 Reduced 指令集（以下简称 LA32R）核心，拥有八级的流水线长度，支持两级动态分支预测，具有两路组相连的指令及数据 Cache。

性能方面，核心在 Coremark 仿真中取得 2.7 CM/Mhz 的性能成绩，并在龙芯杯团队赛的十个性能测试点上，取得 0.846 的平均 IPC。
功能方面，核心实现了所有 LA32R 的整数指令及特权指令，支持启动 Linux 操作系统。
核心支持 Verilator 仿真，并可在 FPGA 平台上综合运行。本核心也通过百芯计划完成流片验证，可正常工作。

本项目核心针对 FPGA 进行专门优化，并创新提出基于寄存器重命名的后端前递转发路径优化。Lain Core 在 NSCSCC2023 中，获得了 LA 赛道团队赛第二名，同时也是目前为止龙芯杯历史上运行频率最高的超标量核心。

## 代码仓库导读
本仓库中存储了 Lain Core 核心开发所使用的一些工具脚本(在 ./src 目录下)，以及 rtl 代码(在 ./rtl 目录下)。

### Lain Core 工具代码介绍
- ./src/compile_project.py

  Lain Core 采用的一套 python 脚本，会读取环境变量中的 `CHIPLAB_HOME` 并将核心部署到其环境中用于仿真。
  其还使用 compile_settings.json 对使用的模块版本进行管理，每个模块的文件头部会用特殊语法标记其版本，并在 compile_settings.json 中实际选择使用的版本。
  描述语法形如：
```
/*--JSON--{"module_name":"core_lsu_rport","module_ver":"2","module_type":"module"}--JSON--*/
```
  这里描述了一个名为  `core_lsu_rport` 的模块，其版本号为 2，类型为模块（module）。

- ./src/gen_sram_wrapper_*.py

  Lain Core 的设计考虑在不同的平台中使用（仿真器环境、FPGA 环境、流片环境）。在不同环境下，核心需要使用不同的模块作为存储器使用。

  好在 Lain Core 设计中只使用了单口及双口的 sram，而 sram 在不同平台下具有相似接近的行为，仅存在模块名和接口名称的区别。

  因此我们使用这样一个小工具，生成我们需要使用的，兼容不同平台，不同容量 sram 的生成工具生成核心使用的 sram。

- ./src/inst
  
  Lain Core 支持使用一套 python 脚本或 spinalhdl 工具生成核心使用的解码器及相关指令静态控制信息。这两套工具均使用类似定义的一组 json 描述指令集。
  
  在 `./src/inst` 目录中，存放默认使用的 la32r 整数指令集解码信息。其中 `general.json` 定义一些常量，以及处理器流水线通用的一些控制信号，及流水级顺序。

  对于常量的定义，直接使用一个键值对即可，由常量名映射到其值。这部分会被使用 `` `define `` 定义成常量使用。
  
  形如：
```
"_REG_R0_IMM": "2'b11"
```

  对于流水线顺序的定义，采用一个数组，按由靠前的流水级到靠后的流水级顺序排列所有的流水级，形如：
```
"stage_order": ["is","ex","m1","m2","wb"]
```

  描述了 is->ex->m1->m2->wb 的一个五阶段流水关系。

  关于流水线控制信号定义，也使用一个键值对的格式描述，如：
```
"imm_type": {
    "length": 3,
    "stage": "is",
    "default_value": "`_IMM_U5"
}
```
  这组定义描述了一个信号名为 `imm_type`，且会在 `is` 级使用（之后流水级不使用）的控制信号。其长度为 3，默认值（不手动指定时）为字符串 `` `_IMM_U5 ``

  控制信号会按照其不同流水线位置，分布在不同流水级之间，并自动生成流水控制信号在各级别之间传递转换的函数。

  在其它 `.json` 文件中，描述了指令使用的具体解码信息，及部分专用指令控制信号，形如 `alu.json` 中对于 `add.w` 指令的定义：
```
"add.w": {
    "opcode": "00000000000100000",
    "alu_grand_op":"`_ALU_GTYPE_INT",
    "alu_op":"`_ALU_STYPE_ADD",
    "reg_type_r0": "`_REG_R0_RK",
    "reg_type_r1": "`_REG_R1_RJ",
    "reg_type_w": "`_REG_W_RD",
    "latest_r0_m1": 1,
    "latest_r1_m1": 1,
    "fu_sel_m1": "`_FUSEL_M1_ALU"
}
```
  其中， opcode 字段定义了指令的解码信息。大部分 LA32R 指令采用可变长的前缀解码的形式，因此只用在 opcode 中描述其前缀码即可。
  对于解码时不关心的位，可以使用 x 跳过。

### Lain Core 核心代码介绍

Lain Core 使用 SystemVerilog 编写，代码存放在 rtl 文件夹下。核心中，与流水线关系较为密切的模块全部采用 core_*.sv 的命名格式。

对于一些在不同模块之间存在复用的基本模块，如 SRAM、寄存器堆、仲裁器，以及构建弹性流水线需要的队列、仲裁器，整数运算所使用的乘法器、除法器，全部存放在了 utils 目录下。

核心顶层位于 core.sv 文件中（为了接入 chiplab、megasoc，在 core.sv 之外还有进行接口名转换的另一层 wrapper），在这里例化了处理器的前后端模块，以及总线的仲裁器，对外暴漏一个 AXI 总线。

`core_frontend_renew` 及 `core_backend` 分别例化了处理器的前后端，其它功能单元也具体分布在这两个处理器关键部分中。前后端实现了较为松散的耦合度。

## 前递优化实现

数据前递是顺序核心提升 IPC 的一个重要结构设计。

对于超标量处理器，需要注意的是每个流水级目前都会存在两个转发源。

Lain Core 的转发实现逻辑与其它核心没有本质的区别，在每级流水线检查数据是否就绪以及是否本级一定需要让流水线数据就绪（若本级不就绪就放行指令会造成指令执行错误）。

若指令数据未就绪，则进行暂停检查及前递检查。

对于暂停检查，检查本级是否一定需要获取数据，若本级一定需要获取数据，则不允许指令流向下一流水级直到数据就绪。

对于前递检查，检查本级之后的所有流水级的写寄存器值和写寄存器号，追踪到最新的一条与当前读寄存器号一致的写寄存器请求进行转发前递，并保存最新的前递后的寄存器结果。

这种转发方案有一个显著的缺点，就是在每个流水级，都必须检查相应流水级之后的所有流水阶段的写寄存器情况，并进行优先级解码才能完成转发。若不监听所有流水级，则核心可能监听到错误的数据源。这样的实现会导致较长的组合逻辑链。

Lain Core 针对这个问题采用了一种比较特殊的转发设计：寄存器重命名。

Lain Core 在指令的发射检查阶段，为每个指令的所有写寄存器分配重名后的三位寄存器号，并记录寄存器号到发射重命名表（重命名分配采用类似 rob 分配的方法，使用一个计数器，每发射一对指令就增加 1）。

由于流水线长度有限，保持在流水线中而还没提交的指令总数也有限。重命名后的三位寄存器号一定不会在流水线中发生重复，也就是该寄存器号在流水线中是唯一的。

每条指令在提交，结果写回体系结构寄存器堆后，将自己重命名的寄存器号写入提交级的重命名表。

在发射阶段，只需要比较每个指令操作数对应的重命名级重命名表项值和提交级重命名表项值是否一致，即可判断体系结构寄存器堆中的值是否有效。

对于操作数还未就绪的寄存器，此时已经拿到了其重命名后的寄存器号。在管线中，一定存在唯一且确定的一个流水级的执行单元，写回的重命名寄存器号与之匹配，正存储着对应操作数的执行状态和数据。

因此，再进行数据转发时，只需要比较重命名后的寄存器号是否相等即可，相等即可转发，不再需要做优先级解码（重命名后的寄存器号唯一）。

这种实现，保证了重命名后寄存器号在管线中的唯一性，还为部分转发带来了可能。流水线级不再需要监视其后的每一级数据源，其需要监视的最小数据源仅有最后一级流水线（保证一定能拿到需要的数据）。

对于其它转发源，只需要进行可选的转发即可。

这项转发优化，将原有的转发源比较由 5位-5位 减少到 3位-3位，也规避优先级解码，整体逻辑深度在 FPGA 上有较大改善。允许部分转发，可以牺牲一点 IPC，换来较多的频率增益。

## Lain Core 采用的其它频率优化策略

- 插入 skid buffer / fifo 打断 ready 级联

流水线频率的一大瓶颈往往在于 ready 信号的级联。

每一级流水线反馈给前一级流水线的就绪信号，一般都是 `(!cur_valid_q || next_ready_i)`，即当前级无有效数据，或下一级可以接受数据。

这种设计，会导致流水线的 ready 信号一路从流水线的最后一级传递至流水线的起点，就构成了频率瓶颈。

Lain Core 中，在处理器核心的流水线中插入了多处 skid buffer，阻断 ready 信号的级联以提高性能。

- 寄存器重命名优化数据转发

这部分在上一小节已经提到了，处理器核采用了类似基于 ROB 的寄存器重命名的方法，优化数据前递转发时候的关键路径延迟，并允许设计者牺牲部分 IPC 换取频率优化。

这一点也为 Lain Core 的高频奠定了基础。

- 为 FPGA 优化的寄存器堆设计

Lain Core 中采用了基于 Banked 策略的多写口寄存器堆作为体系结构寄存器堆（ARF）的物理实现，也采用了基于 XOR 策略的多写口寄存器堆优化重命名表的部分实现（关于重命名实现，可以进一步参考乱序多核 wired 核心，两者采用相同实现策略）。

为了 FPGA 优化的 LUTRAM 原语也被用于实现多读口寄存器，并作为其它多写口寄存器实现的基础。

这一点也极大的帮助了 Lain Core 实现较高频率。

- 面积优化

Lain Core 的核心流水线部分，减少了不必要的 ALU 组件，尽可能缩小核心面积。减少数据通路上不必要的复位，以减少全局复位信号的线负载，减少布线时候的拥塞情况。

这一点优化也显著改善了 Lain Core 的频率情况。


