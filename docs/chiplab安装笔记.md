整体安装可以按照官网教程走，对于缺失的system-newlib文件夹，已上传网盘，对于nemu，也请使用网盘上的版本。



特别需要注意的有几个问题，：

1. 对于verilator，ubuntu默认源的版本比较旧，很多年没有更新了，需要从verilator的官网clone源码，从源码编译安装。教程参考verilator的官方文档，在这里。

https://verilator.org/guide/latest/install.html

```
​sudo apt-get install git perl python3 make autoconf g++ flex bison ccache
​sudo apt-get install libgoogle-perftools-dev numactl perl-doc
​sudo apt-get install libfl2  # Ubuntu only (ignore if gives error)
​sudo apt-get install libfl-dev  # Ubuntu only (ignore if gives error)
​sudo apt-get install zlibc zlib1g zlib1g-dev  # Ubuntu only (ignore if gives error)
```

（以上为verilator编译需要的库）



2. 对于nemu，ubuntu运行它可能会提示缺少文件，这是因为没有安装要求的运行库

   ubuntu上必须要安装这些库：

```
sudo apt install libsdl2-2.0-0
sudo apt install readline-common
sudo apt install libreadline-dev
```


3. 对于交叉编译器，提供的是一个x86版本，需要自行编译x64版本

```c
sudo apt-get install binutils-dev
```

   
