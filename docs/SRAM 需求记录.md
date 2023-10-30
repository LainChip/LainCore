# 双口 SRAM
对于所有的 simpleDualPortRam 均需要替换。
1. icache - 512words-32bits。 
   > 注意这里使用双端口 SRAM，会造成面积倍增，实际并没有必要，需要替换为单端口 SRAM

2. dcache - 1024words-32bits