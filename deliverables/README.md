# 交付物清单与状态（对照Spec第4节）

| 交付物 | 格式要求 | 状态 | 位置/说明 |
|---|---|---|---|
| 技术报告 | DOC+PDF，≤80页 | 底稿完成（五大部分+复用决策表+指标+死锁分析）；DOC/PDF导出待团队（WPS） | docs/report/技术报告.md |
| 源代码包 | RTL源码，注释详尽、与详细设计一致 | 就绪 | deliverables/源代码包.zip（tools/package_src.sh生成） |
| 汇报PPT | ≤15页 | 大纲完成；成稿待团队 | docs/ppt/汇报PPT大纲.md |
| 讲解视频 | mp4，≤8分钟 | 分镜+讲稿完成；录制待团队 | docs/ppt/讲解视频脚本.md |
| 演示视频（决赛） | mp4，≤5分钟 | 分镜完成；录制待板卡/团队 | docs/ppt/演示视频分镜.md |

## 源码包内容（源代码包.zip）

```
rtl/           本项目RTL（ic仲裁/mux/译码、fir三模块、dma两模块、soc顶层、fpga ROM）
tb/            本项目12个自检TB + common基础设施（VIP/检查器/存储从机/BFM/时钟复位）
sw/firmware/fir_demo/  演示固件（C源码+makefile，复用官方CMSIS编译）
tools/         黄金模型生成器 + 打包脚本
fpga/          PDS板级顶层/约束/README
docs/          Spec/计划/走读笔记/指标记录/技术报告底稿/PPT与视频素材
               （团队过程文档superpowers/不打包）
Makefile.fir   仿真入口（13个make目标）
官方工程获取.txt  官方DesignStart工程下载指引（不随包分发，按许可）
```

## 源码包README（包内）

### 目录说明
见上表。官方文件（core/ mcu_system/ mcu/ software/ doc/）不随包分发，
从ARM官网下载Cortex-M0 DesignStart r1p0后与包内文件同目录放置。

### 编译运行方法
- 仿真（全量回归）：`mingw32-make -f Makefile.fir sim_tb_vip_smoke sim_tb_arb
  sim_tb_decode sim_tb_fir_core sim_tb_fir_top sim_tb_fir_core_sym
  sim_tb_dma_channel sim_tb_dma_top sim_tb_dma_chain sim_tb_soc_smoke
  sim_tb_soc sim_tb_axi_rom sim_tb_soc_smoke_rom`
- 固件重建：`cd sw/firmware/fir_demo && mingw32-make all`（生成fir_demo.hex）
- 黄金模型：`python tools/gen_fir_golden.py`

### 仿真复现步骤
1. 装齐工具链（版本见下）
2. 官方工程与本项目同目录（仓库根）
3. 跑全量回归，13个TB全部输出PASS

### 版本与工具链记录
- iverilog 12.0 / vvp / mingw32-make 4.2.1 / arm-none-eabi-gcc
  10.3-2021.10 / Python 3（黄金模型）
- 全部RTL为Verilog-2001可综合子集（iverilog -g2001与PDS兼容）
- 仿真时钟50MHz；UART0回显3.125M波特、UART2 stdout HSTM
