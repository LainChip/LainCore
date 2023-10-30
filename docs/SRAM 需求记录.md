# 双口 SRAM
对于所有的 simpleDualPortRam 均需要替换。
1. icache - 512words-64bits。 
   > 注意这里使用双端口 SRAM，会造成面积倍增，实际并没有必要，需要替换为单端口 SRAM
   单端口 byteen - 563x415
   单端口 non-byteen - 321x415 x2 == 642x415 (PASS!)

2. dcache - 1024words-32bits