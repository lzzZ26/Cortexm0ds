# FPGA工程建立步骤（Pango Design Suite / 紫光同创 PGL50H 盘古50K）

> 状态：**工程文件与RTL已就绪，未上板**（用户裁定：仿真正确即完成任务）。
> 板卡已定案：**盘古50K（PGL50H，Logos一代，84 APM乘法器，42,800 LUT5）**；
> 下列步骤同样适用于 PG2L100H（资源更宽裕，CORE_TYPE 选择见第5节决策矩阵）。
> 板级验证按以下步骤由团队在板卡到位后执行。

## 1. 前置

- 开发板：**盘古50K PGL50H**（已定案；PG2L100H 见第5节决策矩阵）
- Pango Design Suite（版本按板卡厂商要求）
- 固件：`sw/firmware/fir_demo/fir_demo.hex`（gcc编译产物，`cd sw/firmware/fir_demo && mingw32-make all`）

## 2. 建工程

1. 新建工程 → 器件选 **PGL50H**（封装/速度级按实物丝印）→ 语言 Verilog；
2. 添加源文件：
   - 本项目 RTL：`rtl/ic/*.v rtl/fir/*.v rtl/dma/*.v rtl/soc/*.v rtl/fpga/axi_rom.v`
   - 板级顶层：`fpga/pango/top_pgl.v`
   - 官方 RTL 清单：见 `Makefile.fir` 的 REF_RTL（core/ 与 mcu_system/ 下全部列出文件）
3. 添加约束 `fpga/pango/constraints.fdc`，引脚号按实物板卡原理图替换占位符；
4. 系统时钟：板载50MHz晶振**直连**（`assign clk_sys = clk_in;`）——计分项
   不使用厂商IP/原语（官方答疑#5），设计要求≥25MHz/目标50MHz，无需PLL；
5. 综合 → 布局布线 → 生成 bit 流；记录资源报告（LUT/FF/BRAM/DSP）到 `docs/指标记录.md`；
6. 烧录。

## 3. 板上验收清单（对应计划T15 Step5，届时逐项勾选并录屏）

- [ ] 上电后串口终端（9600-8N1）收到 `FIR-SoC Demo` 横幅
- [ ] 发送任意64字符，终端原样回显（UART回显=初赛验收项）
- [ ] 串口出现 `** ECHO PASS **`、`** DMA PASS **`、`** FIR DONE **`
- [ ] LED 按固件演示程序亮起（若固件未加流水灯，补在 fir_demo.c 的 GPIO0 写段）
- [ ] 记录此时资源占用与时钟频率到指标表

## 4. 注意

- `axi_rom.v` 依赖 `$readmemh` 初始化：PDS 综合时若报 initial 不可综合，
  用 **纯 RTL case-ROM 备选**（不引入厂商 IP/原语，答疑#5）：
  `python tools/gen_rom_rtl.py sw/firmware/fir_demo/fir_demo.hex -o rtl/fpga/rom_case.v`
  生成的 `rom_case` 为组合 case 语句（字地址→32位数据，小端口径与 axi_rom 一致），
  替换 $readmemh 初值读取即可，AXI 接口不变。
- 仿真已验证 ROM 路径（`mingw32-make -f Makefile.fir sim_tb_soc_smoke_rom`，
  CPU 从 axi_rom 启动输出 Hello world），FPGA 侧仅剩工具链与板级流程。

## 5. CORE_TYPE 决策矩阵（板卡乘法器预算）

`fir_top` 的 `CORE_TYPE` 参数选择取决于板卡 DSP/APM 数量：

| 板卡 | 乘法器预算 | 推荐 CORE_TYPE |
|---|---|---|
| **PGL50H（盘古50K，已定案）** | 84 APM | **3**（双核：para 82 走 DSP + sym 41 走 LUT；若 LUT 乘法器推断失败→备选手写乘法器结构；再不行→2） |
| PG2L100H（Logos-2） | ~180 APM | 3（双核全 DSP，零改动切换） |
| A7-35T（90 DSP） | 紧 | 2（82 乘法器 ≤90） |

说明：
- CORE_TYPE=3 时通用并行核（para，任意非对称系数、1样本/拍）为默认合规主路径；
  对称核（sym，41乘加）为可选资源优化分支，CPU 写 CTRL bit1=1 且 bit0=1（CLR）
  切换，模式位在 CLR 拍锁存。
- PGL50H 上通用核独占 82/84=97.6% APM，决赛资源利用率（DSP 项 30% 权重）
  必然偏低——如实记录到指标表；答辩口径："82 乘法器为满足'任意非对称系数+
  1样本/拍'的架构下限"。
- 对称核的 41 个乘法器用 `(* use_dsp = "no" *)` 属性禁止 PDS 推断为 DSP
  （`rtl/fir/fir_core_sym.v`）；PDS 若不认可该属性，改用备选手写
  carry-save 乘法器结构（接口不变）。
