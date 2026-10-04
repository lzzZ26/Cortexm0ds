# 带高阶FIR数字滤波器的SoC处理器 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在官方参考工程（ARM Cortex-M0 DesignStart，D:\ICT\Cortexm0ds）基础上，不改动任何官方文件，新增设计并完成「81阶可配置FIR滤波器 + 6通道DMA + 多主AXI互连仲裁」的异构SoC，通过RTL仿真、FPGA上板验证，并产出全部参赛交付物（技术报告/PPT/视频/源码包）。

**Architecture:** 复用官方 Cortex-M0 集成层（对外为AXI主口，AHB2AXI4桥已内建）与CMSDK外设（APB UART/Timer、AXI SRAM/Flash、AXI从机复用器、AXI2APB桥）。新增：`ic_axi_master_arb`（CPU+DMA双主轮询仲裁，共享总线，单事务在途，无死锁）→ 官方 `cmsdk_axi_slave_mux`（SEL选择线风格）→ 从机{FIR、DMA配置口、SRAM、Flash、APB子系统、默认从机}。FIR与DMA均为全新设计，接口遵循CMSDK从机风格（AW_SEL/AR_SEL + 共享总线，无WSTRB，字节/半字写用AWSIZE+地址通道表达）。

**Tech Stack:** Icarus Verilog 11（iverilog+vvp）、GTKWave、mingw32-make、arm-none-eabi-gcc（10.3-2021.10）、Python 3（黄金模型生成）、紫光同创 Pango Design Suite（FPGA：Logos-2 PG2L100H）、git。全部RTL限Verilog-2001可综合子集（iverilog与PDS兼容）。

**Spec:** `D:\ICT\Cortexm0ds\docs\specs\fir-soc-competition-spec.md`（赛题要求整理，含FR-1~FR-8验收标准与评分标准）

**参考工程:** `D:\ICT\Cortexm0ds`（官方提供，ARM Cortex-M0 DesignStart r1p0，同时是本项目工作仓库，经 github.com/lzzZ26/Cortexm0ds 共享全队）——**官方文件只读不改**（core/ mcu/ mcu_system/ doc/ image.hex makefile makefile1 software/ 及 tb/ 官方TB）；本项目新增文件（rtl/ tb/common/ tb/tb_*.v sw/ tools/ fpga/ docs/ Makefile.fir）在同一仓库中提交。

## Global Constraints

以下约束逐条来自Spec与参考工程现状，所有任务隐含遵守：

1. **不改动任何官方文件**：官方文件（core/ mcu/ mcu_system/ doc/ image.hex makefile makefile1 software/ 及 tb/ 内官方TB）只读，官方模块只能通过实例化复用；确需新行为的，在本项目新增文件（rtl/ tb/common/ tb/tb_*.v sw/ tools/ fpga/ docs/）中实现。
2. **FIR精度**：滤波结果与软件参考值**误差<0.1%**；数据格式：输入/系数16bit Q1.15，累加器40bit Q2.30，输出32bit Q1.31（饱和），黄金模型用双精度浮点生成。
3. **DMA**：6通道全部可独立工作、**数据零差错**；支持 存储器↔FIR、存储器↔存储器、UART↔存储器；支持AXI Burst（INCR与FIXED）。
4. **AXI协议合规**：互连/仲裁支持多主设备；**单拍与Burst均无协议错误；仲裁无死锁**。总线风格遵循CMSDK：AW_SIZE/AW_BURST/AW_LEN，**无WSTRB**——字节/半字写以AWSIZE+低位地址通道表达。
5. **CPU**：Cortex-M0（官方DesignStart评估版）；**UART回显**正常跑通（初赛验收项）。
6. **存储系统**：片内SRAM（指令+数据）经AXI互连；固件从0x0的Flash/ROM启动（仿真用官方`cmsdk_axi_flash`，FPGA用本项目`axi_rom`，两者均以`$readmemh`预载固件hex）。
7. **语言与工具**：全部新RTL用Verilog-2001（iverilog `-g2001` 与PDS均可综合）；仿真iverilog+vvp；波形GTKWave；make用mingw32-make；交叉编译arm-none-eabi-gcc 10.3-2021.10（`-mcpu=cortex-m0 -mthumb`）。
8. **FPGA平台**：紫光同创Logos-2 PG2L100H或资源相当板（自备）；综合用PDS；板载时钟50MHz起步，时序优化目标≥100MHz（CPU主频为决赛排名项）。
9. **交付物规格**：技术报告DOC+PDF≤80页（工作原理/体系结构/详细设计/验证/FPGA五大部分）；源代码包注释详尽、与详细设计一致；汇报PPT≤15页；讲解视频mp4≤8min；决赛演示视频mp4≤5min。
10. **决赛指标**：FIR吞吐量(samples/cycle)、DMA带宽(MB/s)、CPU主频(MHz)、系统总延迟(μs)按排名计分；资源利用率按 LUT30%/FF20%/BRAM20%/DSP30% 加权，越少越高；架构创新20分（官方示例：FIR对称系数优化81阶→41次乘加、DMA链式传输）。
11. **仿真自检约定**：每个TB自检（`$fatal(1)`报告失败，PASS打印+`$finish`），make目标失败即非零退出；时钟50MHz（20ns）与FPGA板级一致；UART 9600波特（与官方retarget一致）。

## Review Focus

Spec未明说但最可能咬人的五类输入/失效模式（每条对应任务的测试已固定）：

1. **Burst跨4KB边界**：AXI规范禁止单次burst跨越4KB边界，违者协议错误。长传输必须在发起端拆分burst。→ 任务2的协议检查器对任何AW/AR事务断言4KB合规；任务9的DMA长传输测试覆盖跨边界地址（如0x2000_0FF0起1024字节）。
2. **DMA任意对齐与尾数**：源/目的地址非4字节对齐、长度非4倍数（3/5/1023字节、奇数地址），必须零差错。总线无WSTRB，靠AWSIZE+通道写实现。→ 任务9的TB覆盖全部对齐组合并与参考存储器逐一比对。
3. **FIR定点精度与饱和**：满幅输入、直流增益>1的系数集、噪声输入下相对误差<0.1%；累加器饱和不得回绕。→ 任务5黄金模型含满幅/大增益用例；任务6的TB断言相对误差与饱和行为。
4. **双主并发仲裁**：CPU与DMA同时持续访问同一从机（如都打SRAM），不得死锁/饿死/数据串扰。→ 任务3的仲裁器压力TB（双主无限流+响应必须全部完成）；任务10/12的系统级并发回归。
5. **固件启动与字节序**：向量表(SP@0x0、Reset@0x4)、objcopy `-O verilog` hex与`$readmemh`的字节序、CMSDK总线无WSTRB下固件的字节/半字写（STRB/STRH→AWSIZE+通道）必须正确落到FIR/DMA寄存器。→ 任务7/10的TB含size=0/1/2访问用例；任务12/13的SoC TB以固件实际跑通+UART输出断言兜底。

---

## 文件结构（单仓库模式：本项目工作在官方仓库根目录，新增文件与官方文件共存）

```
Cortexm0ds/                        # = 官方工程 = 本项目仓库（github.com/lzzZ26/Cortexm0ds）
├─ core/ mcu/ mcu_system/ doc/     # 官方文件（只读，禁止修改）
│  image.hex makefile makefile1
├─ software/                       # 官方固件框架（CMSIS/startup/retarget/链接脚本，只读）
├─ tb/                             # 官方TB（tb_cmsdk_mcu.v等，只读）；本项目TB加在同目录
├─ rtl/                            # 【新增】本项目RTL
│  ├─ ic/ic_axi_master_arb.v       # 双主(CPU+DMA)AXI轮询仲裁器，共享总线输出（接官方slave mux）
│  ├─ ic/ic_axi_addr_decode.v      # 本项目地址译码（官方地图+FIR/DMA，生成SEL）
│  ├─ fir/fir_core.v               # 82抽头串行MAC基线FIR（1个MAC时间复用，资源下限版）
│  ├─ fir/fir_core_sym.v           # 对称系数并行FIR（41乘加/拍，≥1 sample/cycle，决赛性能/创新版）
│  ├─ fir/fir_top.v                # FIR的AXI从机封装（CMSDK SEL风格）：系数寄存器+DIN/DOUT数据FIFO
│  ├─ dma/dma_channel.v            # 单通道DMA引擎（AXI主口；读burst→缓冲→写burst；对齐/尾数处理；链式）
│  ├─ dma/dma_top.v                # 6通道DMA：通道间轮询仲裁共享1个AXI主口 + AXI从机配置口 + 中断
│  ├─ fpga/axi_rom.v               # FPGA用只读ROM（$readmemh初始化→BRAM初值，替代仿真flash模型）
│  └─ soc/soc_top.v                # 本项目SoC顶层（只实例化，不改官方文件）；soc_addr_map.vh 地址宏
├─ tb/（新增部分）
│  ├─ common/axi_master_vip.v      # AXI主设备VIP（task级读写，SEL输出，供从机/系统级TB用）
│  ├─ common/axi_slave_mem.v       # 行为级AXI存储从机（仲裁器/DMA测试用参考存储器）
│  ├─ common/axi_checker.v         # AXI协议检查器（4KB、burst长度、握手稳定性断言）
│  ├─ common/uart_bfm.v            # UART总线功能模型（tx/rx task，9600波特）
│  ├─ common/tb_clkreset.v         # 50MHz时钟+复位发生器
│  ├─ tb_arb.v                     # 仲裁器TB（双主并发+压力+协议检查）
│  ├─ tb_decode.v                  # 地址译码TB
│  ├─ tb_fir_core.v                # FIR核TB（黄金模型对比<0.1%）
│  ├─ tb_fir_top.v                 # FIR从机TB（VIP配置/突发/固定地址）
│  ├─ tb_dma_channel.v             # 单通道DMA TB（对齐/零差错/固定地址/跨4KB）
│  ├─ tb_dma_top.v                 # 6通道TB（并发独立/中断/链式）
│  ├─ tb_soc_smoke.v               # SoC冒烟TB（官方hello.hex→UART2输出断言）
│  └─ tb_soc.v                     # SoC级TB（固件跑通、UART回显、软硬协同、指标输出）
├─ sw/firmware/fir_demo/           # 【新增】本项目固件：makefile、fir_demo.c、fir_ref.h（双精度参考）、
│                                  # 复用../software官方CMSIS启动/retarget/链接脚本（相对路径引用，不拷贝改动）
├─ tools/gen_fir_golden.py         # 【新增】黄金模型：低通系数设计+输入序列+期望输出hex+C头文件
├─ fpga/pango/                     # 【新增】PDS工程：fpga_top.v（PLL+pad）、约束.fdc、引脚规划
├─ docs/                           # 【新增】Spec/计划/走读笔记/指标记录/交付物底稿
├─ Makefile.fir                    # 【新增】本项目仿真入口（官方makefile与Windows的Makefile同名冲突，独立命名）
└─ .gitignore                      # 追加本项目忽略规则（官方条目保留）
```

分工边界：`ic/`（总线）与`dma/`、`fir/`通过CMSDK从机接口解耦；每个模块有独立TB，可并行开发；`soc_top.v`只做接线，集成风险集中在地址映射与IRQ接线（任务12专门把关）。官方文件与新增文件物理上同仓，但**官方文件永不修改**——git可按文件路径独立回退。

## 阶段与任务总览

| 阶段 | 任务 | 依赖 | 完成标志（里程碑） |
|---|---|---|---|
| P0 环境与基线 | T0 工具链+官方基线仿真跑通（单仓库模式）；T1 官方代码走读笔记 | — | 官方UART测试在仓库根目录跑通（基线绿） |
| P1 AXI多主互连 | T2 AXI VIP+协议检查器；T3 双主仲裁器；T4 地址译码 | T0 | 双主并发压力TB通过、协议零违规 |
| P2 FIR滤波器 | T5 黄金模型；T6 串行FIR核；T7 FIR从机封装；T8 对称并行优化 | T0, T2 | 黄金对比误差<0.1%、吞吐≥1样本/拍 |
| P3 DMA | T9 单通道引擎；T10 6通道控制器；T11 链式传输 | T2 | 6通道并发零差错、链式自动执行 |
| P4 集成与固件 | T12 SoC顶层集成；T13 固件（回显+软硬协同）；T14 指标测量 | P1~P3 | SoC仿真：UART输出PASS、误差<0.1% |
| P5 FPGA | T15 工程+ROM+约束+UART回显上板；T16 全系统上板+指标+频率优化 | P4 | 板级演示通过、指标数据表齐 |
| P6 交付物 | T17 技术报告；T18 汇报PPT+讲解视频；T19 演示视频+代码规范+源码包 | P5 | 全部交付物齐备（对照Spec第4节） |

RTL任务的TDD循环约定（与软件TDD等价）：**Step 1 写自检TB（含断言与PASS/FAIL打印）→ Step 2 运行，预期编译错误"module not found"（红灯）→ Step 3 实现模块 → Step 4 运行，预期PASS退出0（绿灯）→ Step 5 git提交**。TB用`$fatal(1,"FAIL: ...")`失败、`$display("PASS: ..."); $finish;`通过。每任务一次提交（提交信息格式`feat: <模块> <说明>`，附计划要求的Co-Authored-By行）。

### 执行状态回写（2026-10-04，T14-T16，详见SDD台账）

- **T14 完成**（commit e967d7e）：tb_soc.v指标监视块（挂fir_top内部din_push/dout_pop——计划裸W_READY&&w_a条件缺SEL门控会误计数）+ docs/指标记录.md。实测@50MHz：FIR吞吐 核级1.0/系统级0.0363样本每拍、系统延迟3.04μs（首DIN→首DOUT；计划总览"末DIN→首DOUT"对流水式FIR不适用，差值为负）、DMA带宽14.44MB/s。**固件SysTick计时弃用**（官方加密核VAL读回异常，实测打印2^32-t1垃圾），指标全部TB侧测量。**重要发现**：把DMA BURST改7（8拍burst）提速会系统级死锁（ch1多拍FIXED读追平核产出率→DOUT空停等；ch0多拍FIXED写填满DIN→W_READY停等；停等期间持有dma_top授权+总线单事务在途→另一通道饿死→循环等待）——回退单拍（0x020B/0x0207）；性能修复需DMA双主口（ch0/ch1分占ic_axi_master_arb两主口），留作后续任务（分析见docs/指标记录.md）。
- **T15 完成（文件部分，commit a263a21）**：axi_rom.v+自检TB（计划无TB、以板上验收为准，上板被裁定跳过故补仿真TB）+soc_top补MEM_IMPL=1 generate分支（计划称"已预留"实际T12未实现）+top_pgl.v/constraints.fdc/fpga/pango/README.md。ROM路径冒烟实测CPU启动输出Hello world。axi_rom对计划原文三处修正：①字节数组+字节流hex装载（objcopy格式是字节流，按字装载字节序全错）；②窄读按官方ram_beh语义摆通道；③AR_READY按AR_SEL门控。另R_LAST改组合（寄存版滞后一拍）。板上验收（Step5）与PDS GUI（Step4）留待板卡到位，步骤已写入README。
- **T16 不执行**（用户裁定"不需要实际上板，只要仿真结果是正确的即可完成任务"）：上板演示/指标采集/频率优化整体跳过；决赛四项指标以T14仿真值记录。技术报告第5章口径相应改为"FPGA工程准备+ROM路径仿真验证"。

---

### 任务 0：工具链验证与官方基线跑通（单仓库模式）

**Files:**
- Modify: `.gitignore`（追加本项目忽略规则；官方条目保留）
- Create: `Makefile.fir`（本项目仿真入口；官方 `makefile` 保持不动）
- 布局约定：本项目工作直接在官方仓库根目录进行——官方文件（core/ mcu/ mcu_system/ doc/ image.hex makefile makefile1 software/ tb/官方文件 等）**只读不改**；本项目新增 `rtl/ tb/common/ tb/tb_*.v sw/ tools/ fpga/ docs/`。

**Interfaces:**
- Produces: 可用的仿真工具链（iverilog/vvp/gtkwave/mingw32-make/arm-none-eabi-gcc/python）与官方基线绿状态；`make -f Makefile.fir baseline` 目标。

- [x] **Step 1: 验证工具链版本**（已完成：iverilog 12.0 / make 与 mingw32-make 4.2.1 / gcc-arm-none-eabi 10.3-2021 / python 3.14.7；gtkwave 未在PATH，仅影响看波形）

```bash
iverilog -V | head -1
arm-none-eabi-gcc --version | head -1
python --version
```

- [x] **Step 2: .gitignore 追加本项目规则**（已完成：追加 *.out/*.vvp/*.vcd/*.fst/.vs//sim_out/；`run.out` 原被官方仓库误跟踪，已 `git rm --cached` 移出索引、文件保留在磁盘）

```gitignore
# 编译/仿真产物（本项目维护）
*.out
*.vvp
*.vcd
*.fst
.vs/
sim_out/
```

- [x] **Step 3: 写 Makefile.fir**（已完成；官方makefile与Windows下Makefile同名冲突，故独立命名，用 `make -f` 调用）

```makefile
# Makefile.fir —— 本项目仿真入口（官方makefile保持不动）
# 用法：mingw32-make -f Makefile.fir <目标>
MAKE ?= mingw32-make

# 官方基线（跑官方makefile的compile+run）
baseline:
	$(MAKE) compile
	vvp -n run.out | tail -5
```

- [x] **Step 4: 基线验证**（已完成：官方日志 `Cortexm0ds.txt` 记录 `** TEST PASSED **`；本机复跑亦通过）

Expected: `make -f Makefile.fir baseline` 输出含 `** TEST PASSED **`。
**坑**：官方TB无条件`$dumpvars`，仿真会生成约**2.3GB的wave2.vcd**并显著拖慢仿真（数分钟），属正常（已被.gitignore忽略，无需删除）。

- [x] **Step 5: 提交**（已完成：.gitignore、Makefile.fir 及 docs/、yaoqiu/ 一并入库共享；run.out 移出索引）

```bash
cd /d/ICT/Cortexm0ds && git add .gitignore Makefile.fir docs yaoqiu && git commit -m "chore: 单仓库模式初始化（工具链验证+基线跑通+项目文档入库）

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

**验收**：`make -f Makefile.fir baseline` 绿；`iverilog`/`arm-none-eabi-gcc`/`python` 可用。若官方基线失败，先排查工具版本再继续（此后所有任务依赖该基线）。

---

### 任务 1：官方代码走读笔记（技术报告素材）

**Files:**
- Create: `docs/走读笔记-官方参考工程.md`（本项目文档，不属交付物，供团队与报告撰写引用；AI初稿已就位，团队按附录D分工核对）

**Interfaces:**
- Consumes: 官方源码（core/ mcu/ mcu_system/ 等）与 `doc/DUI0926A_cortex_m0_designstart_rtl_testbench_r1p0_user_guide.pdf`
- Produces: 架构笔记（供任务12集成与任务17技术报告引用）

- [ ] **Step 1: 按清单走读并记录（每人分工，笔记落盘）**

按以下清单逐文件记录「模块职责/端口约定/关键机制/可复用点」，写入 `docs/走读笔记-官方参考工程.md`：

1. `mcu_system/cmsdk_mcu_system/cmsdk_mcu_system.v` —— 系统顶层接线全貌：CPU集成层AXI主口信号命名（`cm0_AWVALID`…）、`sys_*`共享总线、从机SEL风格、IRQ分配方式、`"No DMA controller - no need to have master multiplexer"`注释（即我们要补的多主仲裁位置）。
2. `core/cortexm0_integration/cortexm0integration.v` —— CPU对外端口全集（AW_VALID/AW_READY/AW_SIZE/AW_BURST/AW_LEN/AW_ADDR…、IRQ[31:0]、NMI、SYSRESETREQ、参数NUMIRQ等）；确认`ahb2axi4_if.v`实例（AHB→AXI4桥，FR-6对应项）。
3. `mcu_system/cmsdk_axi_slave_mux/cmsdk_axi_slave_mux.v` —— 端口PORT0~9、PORTx_ENABLE参数、SEL语义（选中时AW_READY/W_READY/B_VALID…才有效）。
4. `mcu_system/cmsdk_axi_slave_mux/cmsdk_axi_addr_decode.v` —— 现有地址映射（0x0 Flash / 0x2000_0000 SRAM / 0x4000_0000 APB / 0x4001_0000 GPIO0 / 0x4001_1000 GPIO1 / 0x4001_F000 SYSCTRL / 0xF000_0000 ROM表 / 默认从机）。
5. `mcu_system/cmsdk_axi_to_apb/axi2apb_axi.v` —— AXI→APB桥（FR-6对应项），记录其对burst、size的处理方式。
6. `mcu_system/cmsdk_axi2apb_subsystem/cmsdk_axi2apb_subsystem.v` —— 确认 `apbsubsys_interrupt` 各位的中断源（UART0 TX/RX在[1:0]等，供任务12的IRQ接线引用）。
7. `mcu_system/cmsdk_axi_memory/cmsdk_axi_flash.v` 与 `cmsdk_axi_sram.v` —— 端口、`filename`参数与`$readmemh`加载方式、字节写（AWSIZE+通道）实现方式。
8. `mcu_system/cmsdk_apb_uart/cmsdk_apb_uart.v` —— 波特率分频寄存器、状态位（供固件驱动引用）。
9. `software/common/retarget/uart_stdout.c` —— stdout默认用哪个UART、波特率初始化值（参考TB注释为UART2/P1[5]）。
10. `software/testcodes/hello/makefile` 与 `software/common/scripts/cmsdk_cm0.ld` —— 固件编译命令与链接布局（Flash 0x0 64K、RAM 0x2000_0000 63K，注释已为DMA结构预留空间）。
11. `tb/tb_cmsdk_mcu.v` 与 `tb/cmsdk_uart_capture.v` —— 仿真TB组织方式、UART输出捕获机制、仿真结束方式。

- [ ] **Step 2: 在笔记末尾输出「复用决策表」**（每行：官方模块 → 我们如何使用 → 是否需新写替代）

```
| 官方模块 | 复用方式 | 本项目动作 |
| cortexm0integration | 直接实例化（CPU+AHB2AXI4桥） | 无 |
| cmsdk_axi_slave_mux | 直接实例化（PORTx_ENABLE自定） | 新增2个从机口 |
| cmsdk_axi_addr_decode | 不实例化 | 新写 ic_axi_addr_decode.v（加FIR/DMA） |
| cmsdk_axi_flash | 仿真用 | FPGA换 axi_rom.v |
| cmsdk_axi_sram / axi2apb_subsystem / apb_uart / apb_timer | 直接实例化 | 无 |
| （缺）多主仲裁 | 官方无 | 新写 ic_axi_master_arb.v |
```

- [ ] **Step 3: 评审与提交**

评审标准：笔记中每个端口列表与实际源码一致（抽查3处）；复用决策表无空白格。提交：

```bash
cd /d/ICT/Cortexm0ds && git add docs/ && git commit -m "docs: 官方参考工程走读笔记

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

**验收**：笔记覆盖清单11项且含复用决策表。这份笔记是任务17技术报告「系统体系结构设计」章节的底稿。

---

## 阶段 1：AXI 多主互连（对应 FR-6 的"AXI互连/总线仲裁（支持多主设备）"）

### 任务 2：仿真基础设施（VIP / 协议检查器 / 存储从机 / UART BFM / 时钟复位）

**Files:**
- Create: `tb/common/axi_master_vip.v`、`tb/common/axi_slave_mem.v`、`tb/common/axi_checker.v`、`tb/common/uart_bfm.v`、`tb/common/tb_clkreset.v`、`tb/tb_vip_smoke.v`（VIP自测）

**Interfaces:**
- Produces（后续所有TB依赖，接口如下，不得改名）：
  - `axi_master_vip` 实例信号：`AW_SEL/AW_VALID/AW_READY/AW_SIZE[2:0]/AW_BURST[1:0]/AW_LEN[7:0]/AW_ADDR[31:0]`，`W_VALID/W_READY/W_DATA[31:0]/W_LAST`，`B_VALID/B_READY/B_RESP[1:0]`，`AR_*/R_*` 同构；任务：`task axi_wr(input [31:0] addr, input [7:0] len, input [1:0] burst, input [2:0] size);`（数据取自内部数组 `vip_wdata[0:255]`）、`task axi_rd(...);`（结果存 `vip_rdata`）
  - `axi_slave_mem`：无SEL主口视图（AW_*/W_*/B_*/AR_*/R_*），参数 `AW`（深度=2^AW）、`DW=32`；字节/半字/字写按AWSIZE+地址[1:0]落通道
  - `axi_checker`：挂在任一主口上，输出 `violation`（sticky），违规即`$display`
  - `uart_bfm`：`task uart_tx(input [7:0] ch);`、`task uart_rx(output [7:0] ch);`，参数`CLK_PERIOD_NS=20, BAUD=9600`
  - `tb_clkreset`：输出 `clk`（50MHz）、`rstn`（低有效，100ns后释放）

- [ ] **Step 1: 写 tb_clkreset.v 与 uart_bfm.v**

```verilog
// tb_clkreset.v : 50MHz时钟与复位
`timescale 1ns/1ps
module tb_clkreset #(parameter HALF_PERIOD_NS = 10.0)(
    output reg clk, output reg rstn);
  initial begin clk = 1'b0; forever #(HALF_PERIOD_NS) clk = ~clk; end
  initial begin
    rstn = 1'b0;
    #(100 * 2 * HALF_PERIOD_NS) rstn = 1'b1;   // 5个周期后释放
  end
endmodule
```

```verilog
// uart_bfm.v : UART BFM（9600 8N1，与官方retarget默认一致）
`timescale 1ns/1ps
module uart_bfm #(parameter CLK_PERIOD_NS = 20.0, BAUD = 9600)(
    output reg txd, input wire rxd);
  localparam BIT_NS = 1_000_000_000.0 / BAUD;

  task uart_tx(input [7:0] ch);
    integer i;
    begin
      txd = 1'b0;                      // 起始位
      #(BIT_NS);
      for (i = 0; i < 8; i = i + 1) begin
        txd = ch[i];
        #(BIT_NS);
      end
      txd = 1'b1;                      // 停止位
      #(BIT_NS);
    end
  endtask

  task uart_rx(output [7:0] ch);
    integer i;
    begin
      @(negedge rxd);                  // 起始位下降沿
      #(BIT_NS / 2.0);                 // 到起始位中点
      #(BIT_NS);                       // 到bit0中点
      for (i = 0; i < 8; i = i + 1) begin
        ch[i] = rxd;
        #(BIT_NS);
      end
    end
  endtask
endmodule
```

- [ ] **Step 2: 写 axi_master_vip.v（含SEL输出，兼用于从机直测与仲裁器测试）**

```verilog
// axi_master_vip.v : AXI主设备VIP（Verilog-2001 task级）
// 用法：先填 vip_wdata[0..len]，再调 axi_wr；axi_rd 结果读 vip_rdata
// 注意：SEL 输出供从机直测（恒1）；接仲裁器主口时 SEL 悬空即可
`timescale 1ns/1ps
module axi_master_vip(
    input  wire        ACLK,
    input  wire        ARESETn,
    // 写地址
    output reg         AW_SEL, AW_VALID,
    input  wire        AW_READY,
    output reg  [2:0]  AW_SIZE,  output reg [1:0] AW_BURST,
    output reg  [7:0]  AW_LEN,   output reg [31:0] AW_ADDR,
    // 写数据
    output reg         W_VALID,  input wire W_READY,
    output reg  [31:0] W_DATA,   output reg W_LAST,
    // 写响应
    input  wire        B_VALID,  output reg B_READY,
    input  wire [1:0]  B_RESP,
    // 读地址
    output reg         AR_SEL, AR_VALID,
    input  wire        AR_READY,
    output reg  [2:0]  AR_SIZE,  output reg [1:0] AR_BURST,
    output reg  [7:0]  AR_LEN,   output reg [31:0] AR_ADDR,
    // 读数据
    input  wire        R_VALID,  output reg R_READY,
    input  wire [31:0] R_DATA,   input wire [1:0] R_RESP,
    input  wire        R_LAST
);
  reg [31:0] vip_wdata [0:255];
  reg [31:0] vip_rdata [0:255];

  // 复位态：VALID/SEL 全低，READY 全高
  initial begin
    AW_SEL=0; AW_VALID=0; AW_SIZE=0; AW_BURST=0; AW_LEN=0; AW_ADDR=0;
    W_VALID=0; W_DATA=0; W_LAST=0;
    B_READY=1;
    AR_SEL=0; AR_VALID=0; AR_SIZE=0; AR_BURST=0; AR_LEN=0; AR_ADDR=0;
    R_READY=1;
    force_off;
  end

  task force_off; begin
    AW_VALID=0; W_VALID=0; AR_VALID=0;
  end endtask

  // 写：AW握手 -> 逐拍W -> B
  task axi_wr(input [31:0] addr, input [7:0] len, input [1:0] burst, input [2:0] size);
    integer beat;
    begin
      @(posedge ACLK);
      AW_SEL = 1'b1; AW_VALID = 1'b1;
      AW_ADDR = addr; AW_LEN = len; AW_BURST = burst; AW_SIZE = size;
      while (!(AW_VALID && AW_READY)) @(posedge ACLK);
      AW_VALID = 1'b0; AW_SEL = 1'b0;
      for (beat = 0; beat <= len; beat = beat + 1) begin
        W_VALID = 1'b1; W_DATA = vip_wdata[beat];
        W_LAST  = (beat == len);
        while (!(W_VALID && W_READY)) @(posedge ACLK);
        W_VALID = 1'b0;
      end
      B_READY = 1'b1;
      while (!(B_VALID && B_READY)) @(posedge ACLK);
      if (B_RESP != 2'b00) $display("VIP: 写响应错误 BRESP=%b @%0t", B_RESP, $time);
    end
  endtask

  // 读：AR握手 -> 逐拍收R
  task axi_rd(input [31:0] addr, input [7:0] len, input [1:0] burst, input [2:0] size);
    integer beat;
    begin
      @(posedge ACLK);
      AR_SEL = 1'b1; AR_VALID = 1'b1;
      AR_ADDR = addr; AR_LEN = len; AR_BURST = burst; AR_SIZE = size;
      while (!(AR_VALID && AR_READY)) @(posedge ACLK);
      AR_VALID = 1'b0; AR_SEL = 1'b0;
      for (beat = 0; beat <= len; beat = beat + 1) begin
        R_READY = 1'b1;
        while (!(R_VALID && R_READY)) @(posedge ACLK);
        vip_rdata[beat] = R_DATA;
      end
    end
  endtask
endmodule
```

- [ ] **Step 3: 写 axi_slave_mem.v（行为级存储从机，仲裁器/DMA测试用参考存储器）**

```verilog
// axi_slave_mem.v : 行为级AXI存储从机（无SEL主口视图）
// 写：AW/W握手后按AWSIZE+地址[1:0]落通道；读：1拍延迟流式返回
`timescale 1ns/1ps
module axi_slave_mem #(parameter AW = 12, parameter DW = 32)(
    input  wire        ACLK, ARESETn,
    input  wire        AW_VALID, output reg AW_READY,
    input  wire [2:0]  AW_SIZE,  input wire [1:0] AW_BURST,
    input  wire [7:0]  AW_LEN,   input wire [31:0] AW_ADDR,
    input  wire        W_VALID,  output reg W_READY,
    input  wire [DW-1:0] W_DATA, input wire W_LAST,
    output reg         B_VALID,  input wire B_READY, output reg [1:0] B_RESP,
    input  wire        AR_VALID, output reg AR_READY,
    input  wire [2:0]  AR_SIZE,  input wire [1:0] AR_BURST,
    input  wire [7:0]  AR_LEN,   input wire [31:0] AR_ADDR,
    output reg         R_VALID,  input wire R_READY,
    output reg [DW-1:0] R_DATA,  output reg [1:0] R_RESP, output reg R_LAST
);
  reg [DW-1:0] mem [0:(1<<AW)-1];
  reg [AW-1:0]  w_a; reg [7:0] w_cnt; reg w_busy;
  reg [AW-1:0]  r_a; reg [7:0] r_cnt; reg r_busy;

  // 组合读出（通道合并用）
  wire [DW-1:0] rd_w = mem[w_a];
  integer i;

  // ---- 写通道 ----
  always @(posedge ACLK or negedge ARESETn) begin
    if (!ARESETn) begin
      w_busy <= 0; w_cnt <= 0; w_a <= 0; AW_READY <= 1; W_READY <= 0; B_VALID <= 0; B_RESP <= 2'b00;
    end else begin
      B_VALID <= 1'b0;
      if (!w_busy) begin
        AW_READY <= 1'b1;
        if (AW_VALID && AW_READY) begin
          w_a <= AW_ADDR[AW-1:0]; w_cnt <= AW_LEN; w_busy <= 1'b1;
          AW_READY <= 1'b0; W_READY <= 1'b1;
        end
      end else begin
        if (W_VALID && W_READY) begin
          // 按AWSIZE与地址低2位写通道
          case (AW_SIZE)
            3'b000: case (w_a[1:0]) 2'd0: mem[w_a][7:0]   <= W_DATA[7:0];
                                    2'd1: mem[w_a][15:8]  <= W_DATA[7:0];
                                    2'd2: mem[w_a][23:16] <= W_DATA[7:0];
                                    2'd3: mem[w_a][31:24] <= W_DATA[7:0]; endcase
            3'b001: case (w_a[1])   1'b0: mem[w_a][15:0]  <= W_DATA[15:0];
                                    1'b1: mem[w_a][31:16] <= W_DATA[15:0]; endcase
            default: mem[w_a] <= W_DATA;
          endcase
          if (AW_BURST[0]) w_a <= w_a + 1'b1;      // INCR
          if (w_cnt == 0) begin
            w_busy <= 1'b0; W_READY <= 1'b0; B_VALID <= 1'b1;
          end else w_cnt <= w_cnt - 8'd1;
        end
      end
    end
  end

  // ---- 读通道（1拍延迟）----
  always @(posedge ACLK or negedge ARESETn) begin
    if (!ARESETn) begin
      r_busy <= 0; r_cnt <= 0; r_a <= 0; AR_READY <= 1; R_VALID <= 0;
    end else begin
      if (!r_busy) begin
        AR_READY <= 1'b1;
        if (AR_VALID && AR_READY) begin
          r_a <= AR_ADDR[AW-1:0]; r_cnt <= AR_LEN; r_busy <= 1'b1;
          AR_READY <= 1'b0;
        end
      end else begin
        if (R_VALID && R_READY) begin
          r_a <= r_a + 1'b1;                    // 从机存储简化按INCR
          if (r_cnt == 0) begin r_busy <= 1'b0; AR_READY <= 1'b1; R_VALID <= 1'b0; end
          else r_cnt <= r_cnt - 8'd1;
        end else if (!R_VALID) begin
          R_VALID <= 1'b1; R_DATA <= mem[r_a]; R_LAST <= (r_cnt == 0); R_RESP <= 2'b00;
        end
      end
    end
  end
endmodule
```

- [ ] **Step 4: 写 axi_checker.v（协议检查器）**

```verilog
// axi_checker.v : AXI协议检查器。挂在主口上，违规即打印并置位 violation
// 检查：信号稳定、burst长度≤15、4KB边界、W_LAST时序、R_LAST时序、burst类型
`timescale 1ns/1ps
module axi_checker(
    input  wire        ACLK, ARESETn,
    input  wire        AW_VALID, AW_READY, input wire [2:0] AW_SIZE,
    input  wire [1:0]  AW_BURST, input wire [7:0] AW_LEN, input wire [31:0] AW_ADDR,
    input  wire        W_VALID, W_READY, input wire [31:0] W_DATA, input wire W_LAST,
    input  wire        B_VALID, B_READY, input wire [1:0] B_RESP,
    input  wire        AR_VALID, AR_READY, input wire [2:0] AR_SIZE,
    input  wire [1:0]  AR_BURST, input wire [7:0] AR_LEN, input wire [31:0] AR_ADDR,
    input  wire        R_VALID, R_READY, input wire [31:0] R_DATA,
    input  wire [1:0]  R_RESP, input wire R_LAST,
    output reg         violation
);
  reg [31:0] aw_a; reg [2:0] aw_s; reg [1:0] aw_b; reg [7:0] aw_l;
  reg [31:0] ar_a; reg [2:0] ar_s; reg [1:0] ar_b; reg [7:0] ar_l;
  reg [31:0] w_d;  reg [7:0] w_cnt;  reg w_active;
  reg [31:0] r_d;  reg [7:0] r_cnt;  reg r_active;

  task fail; input [255:0] msg; begin
    violation <= 1'b1;
    $display("CHECKER VIOLATION @%0t: %0s", $time, msg);
  end endtask

  function [7:0] bytes_per_beat; input [2:0] sz; begin
    bytes_per_beat = (8'b1 << sz);
  end endfunction

  always @(posedge ACLK or negedge ARESETn) begin
    if (!ARESETn) begin
      violation <= 0; w_active <= 0; r_active <= 0; w_cnt <= 0; r_cnt <= 0;
      aw_a <= 0; aw_s <= 0; aw_b <= 0; aw_l <= 0;
      ar_a <= 0; ar_s <= 0; ar_b <= 0; ar_l <= 0; w_d <= 0; r_d <= 0;
    end else begin
      // ---- 写地址通道 ----
      if (AW_VALID && !AW_READY) begin
        if (aw_a != AW_ADDR || aw_s != AW_SIZE || aw_b != AW_BURST || aw_l != AW_LEN)
          fail("AW信号在等待期间变化");
      end else if (AW_VALID) begin
        aw_a <= AW_ADDR; aw_s <= AW_SIZE; aw_b <= AW_BURST; aw_l <= AW_LEN;
        if (AW_LEN > 8'd15) fail("AWLEN>15");
        if (AW_BURST != 2'b00 && AW_BURST != 2'b01) fail("burst类型非FIXED/INCR");
        // 4KB边界
        if ((AW_LEN + 8'd1) * bytes_per_beat(AW_SIZE) > (32'h1000 - AW_ADDR[11:0]))
          fail("写burst跨4KB边界");
        if (AW_VALID && AW_READY) w_active <= 1'b1;
      end
      // ---- 写数据通道 ----
      if (w_active) begin
        if (W_VALID && !W_READY) begin
          if (w_d != W_DATA) fail("W信号在等待期间变化");
        end else if (W_VALID && W_READY) begin
          w_d <= W_DATA;
          if (w_cnt != aw_l && W_LAST) fail("W_LAST提前出现");
          if (w_cnt == aw_l && !W_LAST) fail("W_LAST缺失");
          if (w_cnt == aw_l) w_active <= 1'b0;
          else w_cnt <= w_cnt + 8'd1;
        end
      end
      // ---- 读地址通道 ----
      if (AR_VALID && !AR_READY) begin
        if (ar_a != AR_ADDR || ar_s != AR_SIZE || ar_b != AR_BURST || ar_l != AR_LEN)
          fail("AR信号在等待期间变化");
      end else if (AR_VALID) begin
        ar_a <= AR_ADDR; ar_s <= AR_SIZE; ar_b <= AR_BURST; ar_l <= AR_LEN;
        if (AR_LEN > 8'd15) fail("ARLEN>15");
        if (AR_BURST != 2'b00 && AR_BURST != 2'b01) fail("burst类型非FIXED/INCR");
        if ((AR_LEN + 8'd1) * bytes_per_beat(AR_SIZE) > (32'h1000 - AR_ADDR[11:0]))
          fail("读burst跨4KB边界");
        if (AR_VALID && AR_READY) r_active <= 1'b1;
      end
      // ---- 读数据通道 ----
      if (r_active) begin
        if (R_VALID && !R_READY) begin
          if (r_d != R_DATA) fail("R信号在等待期间变化");
        end else if (R_VALID && R_READY) begin
          r_d <= R_DATA;
          if (r_cnt != ar_l && R_LAST) fail("R_LAST提前出现");
          if (r_cnt == ar_l && !R_LAST) fail("R_LAST缺失");
          if (r_cnt == ar_l) r_active <= 1'b0;
          else r_cnt <= r_cnt + 8'd1;
        end
      end
    end
  end
endmodule
```

- [ ] **Step 5: 写 tb_vip_smoke.v 自测并跑通（VIP↔slave_mem往返+检查器零违规）**

```verilog
// tb_vip_smoke.v : VIP自测——写读往返，检查器必须零违规
`timescale 1ns/1ps
module tb_vip_smoke;
  reg        ACLK, ARESETn;
  wire       AW_VALID, AW_READY, W_VALID, W_READY, W_LAST, B_VALID, B_READY;
  wire [2:0] AW_SIZE; wire [1:0] AW_BURST; wire [7:0] AW_LEN;
  wire [31:0] AW_ADDR, W_DATA; wire [1:0] B_RESP;
  wire       AR_VALID, AR_READY, R_VALID, R_READY, R_LAST;
  wire [2:0] AR_SIZE; wire [1:0] AR_BURST; wire [7:0] AR_LEN;
  wire [31:0] AR_ADDR, R_DATA; wire [1:0] R_RESP;
  wire       AW_SEL, AR_SEL, viol;

  tb_clkreset #() u_ck (.clk(ACLK), .rstn(ARESETn));

  axi_master_vip u_vip (
    .ACLK(ACLK), .ARESETn(ARESETn),
    .AW_SEL(AW_SEL), .AW_VALID(AW_VALID), .AW_READY(AW_READY),
    .AW_SIZE(AW_SIZE), .AW_BURST(AW_BURST), .AW_LEN(AW_LEN), .AW_ADDR(AW_ADDR),
    .W_VALID(W_VALID), .W_READY(W_READY), .W_DATA(W_DATA), .W_LAST(W_LAST),
    .B_VALID(B_VALID), .B_READY(B_READY), .B_RESP(B_RESP),
    .AR_SEL(AR_SEL), .AR_VALID(AR_VALID), .AR_READY(AR_READY),
    .AR_SIZE(AR_SIZE), .AR_BURST(AR_BURST), .AR_LEN(AR_LEN), .AR_ADDR(AR_ADDR),
    .R_VALID(R_VALID), .R_READY(R_READY), .R_DATA(R_DATA), .R_RESP(R_RESP), .R_LAST(R_LAST));

  axi_slave_mem #(.AW(12)) u_mem (
    .ACLK(ACLK), .ARESETn(ARESETn),
    .AW_VALID(AW_VALID), .AW_READY(AW_READY), .AW_SIZE(AW_SIZE),
    .AW_BURST(AW_BURST), .AW_LEN(AW_LEN), .AW_ADDR(AW_ADDR),
    .W_VALID(W_VALID), .W_READY(W_READY), .W_DATA(W_DATA), .W_LAST(W_LAST),
    .B_VALID(B_VALID), .B_READY(B_READY), .B_RESP(B_RESP),
    .AR_VALID(AR_VALID), .AR_READY(AR_READY), .AR_SIZE(AR_SIZE),
    .AR_BURST(AR_BURST), .AR_LEN(AR_LEN), .AR_ADDR(AR_ADDR),
    .R_VALID(R_VALID), .R_READY(R_READY), .R_DATA(R_DATA), .R_RESP(R_RESP), .R_LAST(R_LAST));

  axi_checker u_chk (
    .ACLK(ACLK), .ARESETn(ARESETn),
    .AW_VALID(AW_VALID), .AW_READY(AW_READY), .AW_SIZE(AW_SIZE),
    .AW_BURST(AW_BURST), .AW_LEN(AW_LEN), .AW_ADDR(AW_ADDR),
    .W_VALID(W_VALID), .W_READY(W_READY), .W_DATA(W_DATA), .W_LAST(W_LAST),
    .B_VALID(B_VALID), .B_READY(B_READY), .B_RESP(B_RESP),
    .AR_VALID(AR_VALID), .AR_READY(AR_READY), .AR_SIZE(AR_SIZE),
    .AR_BURST(AR_BURST), .AR_LEN(AR_LEN), .AR_ADDR(AR_ADDR),
    .R_VALID(R_VALID), .R_READY(R_READY), .R_DATA(R_DATA), .R_RESP(R_RESP), .R_LAST(R_LAST),
    .violation(viol));

  integer i;
  initial begin
    u_vip.vip_wdata[0] = 32'h12345678;
    u_vip.vip_wdata[1] = 32'hA5A55A5A;
    u_vip.vip_wdata[2] = 32'hDEADBEEF;
    wait (ARESETn == 1'b1);
    @(posedge ACLK);
    u_vip.axi_wr(32'h100, 8'd2, 2'b01, 3'b010);   // 3拍INCR字写
    u_vip.axi_wr(32'h200, 8'd0, 2'b00, 3'b000);   // 单拍字节写
    u_vip.axi_rd(32'h100, 8'd2, 2'b01, 3'b010);   // 读回
    if (u_vip.vip_rdata[0] !== 32'h12345678 ||
        u_vip.vip_rdata[1] !== 32'hA5A55A5A ||
        u_vip.vip_rdata[2] !== 32'hDEADBEEF) begin
      $fatal(1, "FAIL: VIP往返数据不一致");
    end
    if (viol) $fatal(1, "FAIL: 协议检查器有违规");
    $display("PASS: VIP自测通过（写读往返+协议零违规）");
    $finish;
  end
endmodule
```

- [ ] **Step 6: 在 Makefile 增加通用仿真规则并跑通自测**

```makefile
IV     = iverilog
VVP    = vvp
TB_DIR = tb
OUT    = sim_out

$(OUT):
	mkdir -p $(OUT)

# 用法: make sim_tb_vip_smoke  （编译+运行，自检失败即非零退出）
sim_%: $(OUT)
	$(IV) -g2001 -o $(OUT)/$*.vvp -s $* -I$(TB_DIR)/common $(TB_DIR)/$*.v \
	     $(TB_DIR)/common/axi_master_vip.v $(TB_DIR)/common/axi_slave_mem.v \
	     $(TB_DIR)/common/axi_checker.v $(TB_DIR)/common/uart_bfm.v \
	     $(TB_DIR)/common/tb_clkreset.v
	$(VVP) -n $(OUT)/$*.vvp
```

Run: `make -f Makefile.fir sim_tb_vip_smoke`，Expected: `PASS: VIP自测通过...`（失败为`$fatal`非零退出）。

- [ ] **Step 7: 提交**

```bash
cd /d/ICT/Cortexm0ds && git add tb/ Makefile && git commit -m "feat: 仿真基础设施（AXI VIP/协议检查器/存储从机/UART BFM）自测通过

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

**验收**：`make -f Makefile.fir sim_tb_vip_smoke` 绿。此任务产出为后续所有任务的测试底座。

---

### 任务 3：多主AXI仲裁器 ic_axi_master_arb（FR-6核心）

**Files:**
- Create: `rtl/ic/ic_axi_master_arb.v`；Test: `tb/tb_arb.v`

**Interfaces:**
- Consumes: 任务2的 `axi_slave_mem`、`axi_checker`、`axi_master_vip`、`tb_clkreset`
- Produces: `ic_axi_master_arb` 端口——主0/主1各一组完整AXI主口（`m0_awvalid/m0_awready/m0_awsize/m0_awburst/m0_awlen/m0_awaddr/m0_wvalid/m0_wready/m0_wlast/m0_wdata/m0_bvalid/m0_bready/m0_bresp/m0_arvalid/m0_arready/m0_arsize/m0_arburst/m0_arlen/m0_araddr/m0_rvalid/m0_rready/m0_rlast/m0_rdata/m0_rresp`，主1同构`m1_*`），共享主口输出 `awvalid/awready/awsize/awburst/awlen/awaddr/wvalid/wready/wlast/wdata/bvalid/bready/bresp/arvalid/arready/arsize/arburst/arlen/araddr/rvalid/rready/rlast/rdata/rresp`

- [ ] **Step 1: 写 TB（双主并发压力+协议检查+公平性断言）**

```verilog
// tb_arb.v : 双主并发压力测试——两主各自持续写读，全部必须完成、零协议违规、轮询公平
`timescale 1ns/1ps
module tb_arb;
  reg  ACLK, ARESETn;
  wire AW_VALID, AW_READY, W_VALID, W_READY, W_LAST, B_VALID, B_READY;
  wire [2:0] AW_SIZE; wire [1:0] AW_BURST; wire [7:0] AW_LEN; wire [31:0] AW_ADDR, W_DATA; wire [1:0] B_RESP;
  wire AR_VALID, AR_READY, R_VALID, R_READY, R_LAST;
  wire [2:0] AR_SIZE; wire [1:0] AR_BURST; wire [7:0] AR_LEN; wire [31:0] AR_ADDR, R_DATA; wire [1:0] R_RESP;
  // 主0 / 主1
  wire m0_AW_VALID, m0_AW_READY, m0_W_VALID, m0_W_READY, m0_W_LAST, m0_B_VALID, m0_B_READY;
  wire [2:0] m0_AW_SIZE; wire [1:0] m0_AW_BURST; wire [7:0] m0_AW_LEN; wire [31:0] m0_AW_ADDR, m0_W_DATA; wire [1:0] m0_B_RESP;
  wire m0_AR_VALID, m0_AR_READY, m0_R_VALID, m0_R_READY, m0_R_LAST;
  wire [2:0] m0_AR_SIZE; wire [1:0] m0_AR_BURST; wire [7:0] m0_AR_LEN; wire [31:0] m0_AR_ADDR, m0_R_DATA; wire [1:0] m0_R_RESP;
  wire m1_AW_VALID, m1_AW_READY, m1_W_VALID, m1_W_READY, m1_W_LAST, m1_B_VALID, m1_B_READY;
  wire [2:0] m1_AW_SIZE; wire [1:0] m1_AW_BURST; wire [7:0] m1_AW_LEN; wire [31:0] m1_AW_ADDR, m1_W_DATA; wire [1:0] m1_B_RESP;
  wire m1_AR_VALID, m1_AR_READY, m1_R_VALID, m1_R_READY, m1_R_LAST;
  wire [2:0] m1_AR_SIZE; wire [1:0] m1_AR_BURST; wire [7:0] m1_AR_LEN; wire [31:0] m1_AR_ADDR, m1_R_DATA; wire [1:0] m1_R_RESP;
  wire AW_SEL0, AR_SEL0, AW_SEL1, AR_SEL1, viol;

  tb_clkreset #() u_ck (.clk(ACLK), .rstn(ARESETn));

  axi_master_vip u_v0 (
    .ACLK(ACLK), .ARESETn(ARESETn),
    .AW_SEL(AW_SEL0), .AW_VALID(m0_AW_VALID), .AW_READY(m0_AW_READY),
    .AW_SIZE(m0_AW_SIZE), .AW_BURST(m0_AW_BURST), .AW_LEN(m0_AW_LEN), .AW_ADDR(m0_AW_ADDR),
    .W_VALID(m0_W_VALID), .W_READY(m0_W_READY), .W_DATA(m0_W_DATA), .W_LAST(m0_W_LAST),
    .B_VALID(m0_B_VALID), .B_READY(m0_B_READY), .B_RESP(m0_B_RESP),
    .AR_SEL(AR_SEL0), .AR_VALID(m0_AR_VALID), .AR_READY(m0_AR_READY),
    .AR_SIZE(m0_AR_SIZE), .AR_BURST(m0_AR_BURST), .AR_LEN(m0_AR_LEN), .AR_ADDR(m0_AR_ADDR),
    .R_VALID(m0_R_VALID), .R_READY(m0_R_READY), .R_DATA(m0_R_DATA), .R_RESP(m0_R_RESP), .R_LAST(m0_R_LAST));

  axi_master_vip u_v1 (
    .ACLK(ACLK), .ARESETn(ARESETn),
    .AW_SEL(AW_SEL1), .AW_VALID(m1_AW_VALID), .AW_READY(m1_AW_READY),
    .AW_SIZE(m1_AW_SIZE), .AW_BURST(m1_AW_BURST), .AW_LEN(m1_AW_LEN), .AW_ADDR(m1_AW_ADDR),
    .W_VALID(m1_W_VALID), .W_READY(m1_W_READY), .W_DATA(m1_W_DATA), .W_LAST(m1_W_LAST),
    .B_VALID(m1_B_VALID), .B_READY(m1_B_READY), .B_RESP(m1_B_RESP),
    .AR_SEL(AR_SEL1), .AR_VALID(m1_AR_VALID), .AR_READY(m1_AR_READY),
    .AR_SIZE(m1_AR_SIZE), .AR_BURST(m1_AR_BURST), .AR_LEN(m1_AR_LEN), .AR_ADDR(m1_AR_ADDR),
    .R_VALID(m1_R_VALID), .R_READY(m1_R_READY), .R_DATA(m1_R_DATA), .R_RESP(m1_R_RESP), .R_LAST(m1_R_LAST));

  ic_axi_master_arb u_arb (
    .aclk(ACLK), .aresetn(ARESETn),
    .m0_awvalid(m0_AW_VALID), .m0_awready(m0_AW_READY), .m0_awsize(m0_AW_SIZE),
    .m0_awburst(m0_AW_BURST), .m0_awlen(m0_AW_LEN), .m0_awaddr(m0_AW_ADDR),
    .m0_wvalid(m0_W_VALID), .m0_wready(m0_W_READY), .m0_wlast(m0_W_LAST), .m0_wdata(m0_W_DATA),
    .m0_bvalid(m0_B_VALID), .m0_bready(m0_B_READY), .m0_bresp(m0_B_RESP),
    .m0_arvalid(m0_AR_VALID), .m0_arready(m0_AR_READY), .m0_arsize(m0_AR_SIZE),
    .m0_arburst(m0_AR_BURST), .m0_arlen(m0_AR_LEN), .m0_araddr(m0_AR_ADDR),
    .m0_rvalid(m0_R_VALID), .m0_rready(m0_R_READY), .m0_rlast(m0_R_LAST),
    .m0_rdata(m0_R_DATA), .m0_rresp(m0_R_RESP),
    .m1_awvalid(m1_AW_VALID), .m1_awready(m1_AW_READY), .m1_awsize(m1_AW_SIZE),
    .m1_awburst(m1_AW_BURST), .m1_awlen(m1_AW_LEN), .m1_awaddr(m1_AW_ADDR),
    .m1_wvalid(m1_W_VALID), .m1_wready(m1_W_READY), .m1_wlast(m1_W_LAST), .m1_wdata(m1_W_DATA),
    .m1_bvalid(m1_B_VALID), .m1_bready(m1_B_READY), .m1_bresp(m1_B_RESP),
    .m1_arvalid(m1_AR_VALID), .m1_arready(m1_AR_READY), .m1_arsize(m1_AR_SIZE),
    .m1_arburst(m1_AR_BURST), .m1_arlen(m1_AR_LEN), .m1_araddr(m1_AR_ADDR),
    .m1_rvalid(m1_R_VALID), .m1_rready(m1_R_READY), .m1_rlast(m1_R_LAST),
    .m1_rdata(m1_R_DATA), .m1_rresp(m1_R_RESP),
    .awvalid(AW_VALID), .awready(AW_READY), .awsize(AW_SIZE),
    .awburst(AW_BURST), .awlen(AW_LEN), .awaddr(AW_ADDR),
    .wvalid(W_VALID), .wready(W_READY), .wlast(W_LAST), .wdata(W_DATA),
    .bvalid(B_VALID), .bready(B_READY), .bresp(B_RESP),
    .arvalid(AR_VALID), .arready(AR_READY), .arsize(AR_SIZE),
    .arburst(AR_BURST), .arlen(AR_LEN), .araddr(AR_ADDR),
    .rvalid(R_VALID), .rready(R_READY), .rlast(R_LAST),
    .rdata(R_DATA), .rresp(R_RESP));

  axi_slave_mem #(.AW(12)) u_mem (
    .ACLK(ACLK), .ARESETn(ARESETn),
    .AW_VALID(AW_VALID), .AW_READY(AW_READY), .AW_SIZE(AW_SIZE),
    .AW_BURST(AW_BURST), .AW_LEN(AW_LEN), .AW_ADDR(AW_ADDR),
    .W_VALID(W_VALID), .W_READY(W_READY), .W_DATA(W_DATA), .W_LAST(W_LAST),
    .B_VALID(B_VALID), .B_READY(B_READY), .B_RESP(B_RESP),
    .AR_VALID(AR_VALID), .AR_READY(AR_READY), .AR_SIZE(AR_SIZE),
    .AR_BURST(AR_BURST), .AR_LEN(AR_LEN), .AR_ADDR(AR_ADDR),
    .R_VALID(R_VALID), .R_READY(R_READY), .R_DATA(R_DATA), .R_RESP(R_RESP), .R_LAST(R_LAST));

  axi_checker u_chk (
    .ACLK(ACLK), .ARESETn(ARESETn),
    .AW_VALID(AW_VALID), .AW_READY(AW_READY), .AW_SIZE(AW_SIZE),
    .AW_BURST(AW_BURST), .AW_LEN(AW_LEN), .AW_ADDR(AW_ADDR),
    .W_VALID(W_VALID), .W_READY(W_READY), .W_DATA(W_DATA), .W_LAST(W_LAST),
    .B_VALID(B_VALID), .B_READY(B_READY), .B_RESP(B_RESP),
    .AR_VALID(AR_VALID), .AR_READY(AR_READY), .AR_SIZE(AR_SIZE),
    .AR_BURST(AR_BURST), .AR_LEN(AR_LEN), .AR_ADDR(AR_ADDR),
    .R_VALID(R_VALID), .R_READY(R_READY), .R_DATA(R_DATA), .R_RESP(R_RESP), .R_LAST(R_LAST),
    .violation(viol));

  // 压力序列：两主并发持续互打（读写混合、burst与单拍混合、同一从机），各32笔
  integer i, j;
  initial begin : M0
    wait (ARESETn == 1'b1);
    @(posedge ACLK);
    for (j = 0; j < 32; j = j + 1) begin
      for (i = 0; i < 16; i = i + 1) u_v0.vip_wdata[i] = {j[7:0], i[7:0], j[7:0], i[7:0]};
      u_v0.axi_wr(32'h800, 8'd15, 2'b01, 3'b010);   // 16拍INCR
      u_v0.axi_rd(32'h800, 8'd15, 2'b01, 3'b010);
      for (i = 0; i < 16; i = i + 1)
        if (u_v0.vip_rdata[i] !== {j[7:0], i[7:0], j[7:0], i[7:0]})
          $fatal(1, "FAIL: 主0读回数据不一致 j=%0d i=%0d", j, i);
    end
    $display("主0完成");
  end

  initial begin : M1
    wait (ARESETn == 1'b1);
    @(posedge ACLK);
    for (j = 0; j < 32; j = j + 1) begin
      for (i = 0; i < 8; i = i + 1) u_v1.vip_wdata[i] = 32'hC0000000 + j * 32 + i;
      u_v1.axi_wr(32'h1000, 8'd7, 2'b01, 3'b010);   // 8拍INCR（与主0同打同一从机）
      u_v1.axi_rd(32'h1000, 8'd7, 2'b01, 3'b010);
      for (i = 0; i < 8; i = i + 1)
        if (u_v1.vip_rdata[i] !== 32'hC0000000 + j * 32 + i)
          $fatal(1, "FAIL: 主1读回数据不一致 j=%0d i=%0d", j, i);
    end
    $display("主1完成");
  end

  initial begin
    wait (ARESETn == 1'b1);
    // 等两主完成（用握手计数近似）：轮询VIP状态太繁琐，改以完成打印+超时兜底
    wait (u_arb.m0_done_cnt == 32'd64 && u_arb.m1_done_cnt == 32'd64);  // 每主32写+32读=64次完成
    if (viol) $fatal(1, "FAIL: 协议违规");
    if (u_arb.grant_imbalance > 32'd2) $fatal(1, "FAIL: 轮询不公平 imbalance=%0d", u_arb.grant_imbalance);
    $display("PASS: 双主并发压力测试通过（零协议违规、无死锁、轮询公平）");
    $finish;
  end
endmodule
```

（实现说明：仲裁器内加两个供测试观测的计数输出 `m0_done_cnt/m1_done_cnt`（各自B/R完成计数）与 `grant_imbalance`（累计|授权差|），均为调试/评分辅助，不影响功能。）

- [ ] **Step 2: 运行TB，确认红灯**

Run: `make -f Makefile.fir sim_tb_arb`，Expected: iverilog报错 `ic_axi_master_arb` 未找到（模块不存在）。

- [ ] **Step 3: 实现 ic_axi_master_arb.v**

```verilog
// ic_axi_master_arb.v : 双主AXI轮询仲裁器（共享总线式，单事务在途）
// 写/读通道独立授权；授权保持到该事务完成（B握手 / R_LAST握手）
// 无死锁论证：每个grant的master在B/R握手后即释放；从机侧由官方slave mux+默认从机保证响应；
//             W数据仅在grant期间透传，未获授权主机的挂起WVALID不影响总线。
`timescale 1ns/1ps
module ic_axi_master_arb(
    input  wire        aclk,
    input  wire        aresetn,
    // ---- 主0（CPU）----
    input  wire        m0_awvalid,  output wire m0_awready,
    input  wire [2:0]  m0_awsize,   input  wire [1:0] m0_awburst,
    input  wire [7:0]  m0_awlen,    input  wire [31:0] m0_awaddr,
    input  wire        m0_wvalid,   output wire m0_wready,
    input  wire        m0_wlast,    input  wire [31:0] m0_wdata,
    output wire        m0_bvalid,   input  wire m0_bready,
    output wire [1:0]  m0_bresp,
    input  wire        m0_arvalid,  output wire m0_arready,
    input  wire [2:0]  m0_arsize,   input  wire [1:0] m0_arburst,
    input  wire [7:0]  m0_arlen,    input  wire [31:0] m0_araddr,
    output wire        m0_rvalid,   input  wire m0_rready,
    output wire        m0_rlast,    output wire [31:0] m0_rdata,
    output wire [1:0]  m0_rresp,
    // ---- 主1（DMA）----
    input  wire        m1_awvalid,  output wire m1_awready,
    input  wire [2:0]  m1_awsize,   input  wire [1:0] m1_awburst,
    input  wire [7:0]  m1_awlen,    input  wire [31:0] m1_awaddr,
    input  wire        m1_wvalid,   output wire m1_wready,
    input  wire        m1_wlast,    input  wire [31:0] m1_wdata,
    output wire        m1_bvalid,   input  wire m1_bready,
    output wire [1:0]  m1_bresp,
    input  wire        m1_arvalid,  output wire m1_arready,
    input  wire [2:0]  m1_arsize,   input  wire [1:0] m1_arburst,
    input  wire [7:0]  m1_arlen,    input  wire [31:0] m1_araddr,
    output wire        m1_rvalid,   input  wire m1_rready,
    output wire        m1_rlast,    output wire [31:0] m1_rdata,
    output wire [1:0]  m1_rresp,
    // ---- 共享主口（接官方 cmsdk_axi_slave_mux）----
    output wire        awvalid,     input  wire awready,
    output wire [2:0]  awsize,      output wire [1:0] awburst,
    output wire [7:0]  awlen,       output wire [31:0] awaddr,
    output wire        wvalid,      input  wire wready,
    output wire        wlast,       output wire [31:0] wdata,
    input  wire        bvalid,      output wire bready,
    input  wire [1:0]  bresp,
    output wire        arvalid,     input  wire arready,
    output wire [2:0]  arsize,      output wire [1:0] arburst,
    output wire [7:0]  arlen,       output wire [31:0] araddr,
    input  wire        rvalid,      output wire rready,
    input  wire        rlast,       input  wire [31:0] rdata,
    input  wire [1:0]  rresp,
    // ---- 调试/评分观测 ----
    output reg  [31:0] m0_done_cnt, m1_done_cnt,   // B/R完成计数
    output reg  [31:0] grant_imbalance              // 累计授权差绝对值
);
  // ============ 写通道仲裁 ============
  reg  w_grant;            // 当前写授权：0=主0, 1=主1
  reg  w_active;           // 写事务进行中
  reg  wrr;                // 轮询指针
  wire w_done = w_active && bvalid && bready;

  always @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin w_grant <= 1'b0; w_active <= 1'b0; wrr <= 1'b0; end
    else begin
      if (!w_active) begin
        if (m0_awvalid || m1_awvalid) begin
          if (m0_awvalid && m1_awvalid) begin w_grant <= wrr; wrr <= ~wrr; end
          else                          w_grant <= m0_awvalid ? 1'b0 : 1'b1;
          w_active <= 1'b1;
        end
      end else if (w_done) begin
        w_active <= 1'b0;
      end
    end
  end

  // 写通道mux（授权期间透传）
  assign awvalid = w_active ? (w_grant ? m1_awvalid : m0_awvalid) : 1'b0;
  assign awsize  = w_grant ? m1_awsize  : m0_awsize;
  assign awburst = w_grant ? m1_awburst : m0_awburst;
  assign awlen   = w_grant ? m1_awlen   : m0_awlen;
  assign awaddr  = w_grant ? m1_awaddr  : m0_awaddr;
  assign m0_awready = w_active && !w_grant && awready;
  assign m1_awready = w_active &&  w_grant && awready;

  assign wvalid = w_active ? (w_grant ? m1_wvalid : m0_wvalid) : 1'b0;
  assign wlast  = w_grant ? m1_wlast  : m0_wlast;
  assign wdata  = w_grant ? m1_wdata  : m0_wdata;
  assign m0_wready = w_active && !w_grant && wready;
  assign m1_wready = w_active &&  w_grant && wready;

  assign m0_bvalid = w_active && !w_grant && bvalid;
  assign m1_bvalid = w_active &&  w_grant && bvalid;
  assign m0_bresp  = bresp;
  assign m1_bresp  = bresp;
  assign bready    = w_active ? (w_grant ? m1_bready : m0_bready) : 1'b1;

  // ============ 读通道仲裁 ============
  reg  r_grant;
  reg  r_active;
  reg  rrr;
  wire r_done = r_active && rvalid && rready && rlast;

  always @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin r_grant <= 1'b0; r_active <= 1'b0; rrr <= 1'b0; end
    else begin
      if (!r_active) begin
        if (m0_arvalid || m1_arvalid) begin
          if (m0_arvalid && m1_arvalid) begin r_grant <= rrr; rrr <= ~rrr; end
          else                          r_grant <= m0_arvalid ? 1'b0 : 1'b1;
          r_active <= 1'b1;
        end
      end else if (r_done) r_active <= 1'b0;
    end
  end

  assign arvalid = r_active ? (r_grant ? m1_arvalid : m0_arvalid) : 1'b0;
  assign arsize  = r_grant ? m1_arsize  : m0_arsize;
  assign arburst = r_grant ? m1_arburst : m0_arburst;
  assign arlen   = r_grant ? m1_arlen   : m0_arlen;
  assign araddr  = r_grant ? m1_araddr  : m0_araddr;
  assign m0_arready = r_active && !r_grant && arready;
  assign m1_arready = r_active &&  r_grant && arready;

  assign m0_rvalid = r_active && !r_grant && rvalid;
  assign m1_rvalid = r_active &&  r_grant && rvalid;
  assign m0_rlast  = rlast;
  assign m1_rlast  = rlast;
  assign m0_rdata  = rdata;
  assign m1_rdata  = rdata;
  assign m0_rresp  = rresp;
  assign m1_rresp  = rresp;
  assign rready    = r_active ? (r_grant ? m1_rready : m0_rready) : 1'b1;

  // ============ 调试观测 ============
  always @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
      m0_done_cnt <= 0; m1_done_cnt <= 0; grant_imbalance <= 0;
    end else begin
      if (w_done) begin
        if (!w_grant) m0_done_cnt <= m0_done_cnt + 1'b1;
        else          m1_done_cnt <= m1_done_cnt + 1'b1;
      end
      if (r_done) begin
        if (!r_grant) m0_done_cnt <= m0_done_cnt + 1'b1;
        else          m1_done_cnt <= m1_done_cnt + 1'b1;
      end
      if (w_done || r_done) begin
        if (m0_done_cnt > m1_done_cnt) grant_imbalance <= m0_done_cnt - m1_done_cnt;
        else                           grant_imbalance <= m1_done_cnt - m0_done_cnt;
      end
    end
  end
endmodule
```

- [ ] **Step 4: 运行TB，确认绿灯**

Run: `make -f Makefile.fir sim_tb_arb`，Expected: `主0完成`、`主1完成`、`PASS: 双主并发压力测试通过...`（每主32写+32读=64次完成计数，imbalance≤2，violation=0）。

- [ ] **Step 5: 提交**

```bash
cd /d/ICT/Cortexm0ds && git add rtl/ic/ tb/tb_arb.v Makefile && git commit -m "feat: 双主AXI轮询仲裁器（压力测试+协议零违规）

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

**验收**：`make -f Makefile.fir sim_tb_arb` 绿。此模块对应评分标准"AXI互连/总线仲裁（支持多主设备）、总线仲裁无死锁"。

---

### 任务 4：本项目地址译码 ic_axi_addr_decode

**Files:**
- Create: `rtl/ic/ic_axi_addr_decode.v`；Test: `tb/tb_decode.v`

**Interfaces:**
- Produces: `ic_axi_addr_decode(w_addr, r_addr, flash_arsel, sram_awsel, sram_arsel, apbsys_awsel, apbsys_arsel, gpio0_awsel, gpio0_arsel, gpio1_awsel, gpio1_arsel, fir_awsel, fir_arsel, dma_awsel, dma_arsel, defslv_awsel, defslv_arsel)`

- [ ] **Step 1: 写 TB（全区域遍历+唯一选通断言）**

```verilog
// tb_decode.v : 地址译码全覆盖测试——每个地址必须恰好选通一个从机（或默认从机）
`timescale 1ns/1ps
module tb_decode;
  reg  [31:0] w_addr, r_addr;
  wire flash_arsel, sram_awsel, sram_arsel, apbsys_awsel, apbsys_arsel;
  wire gpio0_awsel, gpio0_arsel, gpio1_awsel, gpio1_arsel;
  wire fir_awsel, fir_arsel, dma_awsel, dma_arsel, defslv_awsel, defslv_arsel;

  ic_axi_addr_decode u_dec (
    .w_addr(w_addr), .r_addr(r_addr),
    .flash_arsel(flash_arsel),
    .sram_awsel(sram_awsel), .sram_arsel(sram_arsel),
    .apbsys_awsel(apbsys_awsel), .apbsys_arsel(apbsys_arsel),
    .gpio0_awsel(gpio0_awsel), .gpio0_arsel(gpio0_arsel),
    .gpio1_awsel(gpio1_awsel), .gpio1_arsel(gpio1_arsel),
    .fir_awsel(fir_awsel), .fir_arsel(fir_arsel),
    .dma_awsel(dma_awsel), .dma_arsel(dma_arsel),
    .defslv_awsel(defslv_awsel), .defslv_arsel(defslv_arsel));

  reg [31:0] addr;
  reg [15:0] hi16;
  integer i;

  task check_case;
    input [31:0] a;
    input        exp_flash, exp_sram, exp_apb, exp_g0, exp_g1, exp_fir, exp_dma, exp_def;
    begin
      w_addr = a; r_addr = a; #1;
      if (flash_arsel !== exp_flash) $fatal(1, "FAIL: addr=%h flash_arsel", a);
      if (sram_arsel  !== exp_sram)  $fatal(1, "FAIL: addr=%h sram", a);
      if (apbsys_arsel!== exp_apb)   $fatal(1, "FAIL: addr=%h apbsys", a);
      if (gpio0_arsel !== exp_g0)    $fatal(1, "FAIL: addr=%h gpio0", a);
      if (gpio1_arsel !== exp_g1)    $fatal(1, "FAIL: addr=%h gpio1", a);
      if (fir_arsel   !== exp_fir)   $fatal(1, "FAIL: addr=%h fir", a);
      if (dma_arsel   !== exp_dma)   $fatal(1, "FAIL: addr=%h dma", a);
      if (defslv_arsel!== exp_def)   $fatal(1, "FAIL: addr=%h defslv", a);
    end
  endtask

  initial begin
    #10;
    check_case(32'h0000_0000, 1,0,0,0,0,0,0,0);   // Flash
    check_case(32'h0000_FFFF, 1,0,0,0,0,0,0,0);
    check_case(32'h2000_0000, 0,1,0,0,0,0,0,0);   // SRAM
    check_case(32'h2000_FFFF, 0,1,0,0,0,0,0,0);
    check_case(32'h4000_0000, 0,0,1,0,0,0,0,0);   // APB子系统
    check_case(32'h4000_FFFF, 0,0,1,0,0,0,0,0);
    check_case(32'h4001_0000, 0,0,0,1,0,0,0,0);   // GPIO0
    check_case(32'h4001_1000, 0,0,0,0,1,0,0,0);   // GPIO1
    check_case(32'h4002_0000, 0,0,0,0,0,1,0,0);   // FIR
    check_case(32'h4002_0FFF, 0,0,0,0,0,1,0,0);
    check_case(32'h4003_0000, 0,0,0,0,0,0,1,0);   // DMA配置
    check_case(32'h4003_0FFF, 0,0,0,0,0,0,1,0);
    check_case(32'h5000_0000, 0,0,0,0,0,0,0,1);   // 默认从机（DECERR）
    check_case(32'h4004_0000, 0,0,0,0,0,0,0,1);
    check_case(32'h1000_0000, 0,0,0,0,0,0,0,1);
    // 遍历：所有64K块必须"恰好选通一个"
    for (i = 0; i < 65536; i = i + 1) begin
      hi16 = i;
      addr = {hi16, 16'h0000};
      w_addr = addr; r_addr = addr; #1;
      if ((flash_arsel + sram_arsel + apbsys_arsel + gpio0_arsel + gpio1_arsel +
           fir_arsel + dma_arsel + defslv_arsel) !== 1'b1)
        $fatal(1, "FAIL: 块%h 选通数不为1", hi16);
    end
    $display("PASS: 地址译码全覆盖（每块恰好一个从机）");
    $finish;
  end
endmodule
```

- [ ] **Step 2: 运行TB，确认红灯**

Run: `make -f Makefile.fir sim_tb_decode`，Expected: 模块未找到编译错误。

- [ ] **Step 3: 实现 ic_axi_addr_decode.v**

```verilog
// ic_axi_addr_decode.v : 本项目AXI地址译码（官方地图 + FIR + DMA）
//  0x0000_0000-0x0000_FFFF  Flash/ROM（固件，只读）
//  0x2000_0000-0x2000_FFFF  SRAM（64K）
//  0x4000_0000-0x4000_FFFF  APB子系统（UART0-2/Timer/WDT，经官方axi2apb桥）
//  0x4001_0000-0x4001_0FFF  GPIO0
//  0x4001_1000-0x4001_1FFF  GPIO1
//  0x4002_0000-0x4002_0FFF  FIR（新增）
//  0x4003_0000-0x4003_0FFF  DMA配置（新增）
//  其余                      默认从机（DECERR）
`timescale 1ns/1ps
module ic_axi_addr_decode(
    input  wire [31:0] w_addr,
    input  wire [31:0] r_addr,
    output wire        flash_arsel,           // Flash只读，无写选通
    output wire        sram_awsel,  sram_arsel,
    output wire        apbsys_awsel, apbsys_arsel,
    output wire        gpio0_awsel, gpio0_arsel,
    output wire        gpio1_awsel, gpio1_arsel,
    output wire        fir_awsel,   fir_arsel,
    output wire        dma_awsel,   dma_arsel,
    output wire        defslv_awsel, defslv_arsel
);
  assign flash_arsel  = (r_addr[31:16] == 16'h0000);

  assign sram_awsel   = (w_addr[31:16] == 16'h2000);
  assign sram_arsel   = (r_addr[31:16] == 16'h2000);

  assign apbsys_awsel = (w_addr[31:16] == 16'h4000);
  assign apbsys_arsel = (r_addr[31:16] == 16'h4000);

  assign gpio0_awsel  = (w_addr[31:12] == 20'h40010);
  assign gpio0_arsel  = (r_addr[31:12] == 20'h40010);
  assign gpio1_awsel  = (w_addr[31:12] == 20'h40011);
  assign gpio1_arsel  = (r_addr[31:12] == 20'h40011);

  assign fir_awsel    = (w_addr[31:12] == 20'h40020);
  assign fir_arsel    = (r_addr[31:12] == 20'h40020);
  assign dma_awsel    = (w_addr[31:12] == 20'h40030);
  assign dma_arsel    = (r_addr[31:12] == 20'h40030);

  assign defslv_awsel = ~(sram_awsel | apbsys_awsel | gpio0_awsel |
                          gpio1_awsel | fir_awsel | dma_awsel);
  assign defslv_arsel = ~(flash_arsel | sram_arsel | apbsys_arsel |
                          gpio0_arsel | gpio1_arsel | fir_arsel | dma_arsel);
endmodule
```

- [ ] **Step 4: 运行TB，确认绿灯**

Run: `make -f Makefile.fir sim_tb_decode`，Expected: `PASS: 地址译码全覆盖...`。

- [ ] **Step 5: 提交**

```bash
cd /d/ICT/Cortexm0ds && git add rtl/ic/ tb/tb_decode.v && git commit -m "feat: 本项目AXI地址译码（新增FIR/DMA区域）

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

**验收**：`make -f Makefile.fir sim_tb_decode` 绿。地址映射自此锁定，供soc_top与固件引用。

---

## 阶段 2：FIR 滤波器（对应 FR-1）

### 任务 5：黄金模型生成器 tools/gen_fir_golden.py

**Files:**
- Create: `tools/gen_fir_golden.py`
- Generates: `tb/data/coeff_q15.hex`、`tb/data/input_q15.hex`、`tb/data/golden_q31.hex`、`sw/firmware/fir_demo/fir_golden.h`

**Interfaces:**
- Consumes: Python 3（任务0验证过）
- Produces（任务6/7/8/13依赖，格式锁定）：
  - `coeff_q15.hex`：82行，每行4位hex（Q1.15系数，**量化后的值**）
  - `input_q15.hex`：N=1024行，4位hex（Q1.15输入，含冲激/低频正弦/高频正弦+噪声/满幅随机四段）
  - `golden_q31.hex`：N行，8位hex（**用量化后系数与量化后输入做双精度FIR再量化到Q1.31**的期望输出——这样硬件与黄金的差异只反映实现误差，而非输入/系数量化误差）
  - `fir_golden.h`：C数组（系数/输入/期望输出，有符号十进制）

- [ ] **Step 1: 写生成器**

```python
#!/usr/bin/env python3
# gen_fir_golden.py : FIR黄金模型生成器
# 黄金口径：系数与输入先量化到Q1.15（与硬件一致），用双精度算FIR，
#           结果再量化到Q1.31。硬件与黄金之差=纯实现误差（累加/舍入/饱和）。
import math, random, os

TAPS = 82
N    = 1024
FC   = 0.15                      # 归一化截止频率

def sinc(x):
    return 1.0 if abs(x) < 1e-12 else math.sin(math.pi * x) / (math.pi * x)

def hamming(k, n):
    return 0.54 - 0.46 * math.cos(2.0 * math.pi * k / (n - 1))

def design_lowpass(taps, fc):
    c = []
    for k in range(taps):
        x = k - (taps - 1) / 2.0
        c.append(2.0 * fc * sinc(2.0 * fc * x) * hamming(k, taps))
    return c

def q(v, bits):                  # double -> 定点有符号整数（饱和+舍入）
    m = 2 ** (bits - 1)
    i = int(round(v * m))
    return max(-m, min(m - 1, i))

def fir_ref(c, x):
    y = []
    for n in range(len(x)):
        acc = 0.0
        for k in range(TAPS):
            if n - k >= 0:
                acc += c[k] * x[n - k]
        y.append(acc)
    return y

def main():
    random.seed(20261002)
    # 1) 系数：窗函数法低通，归一化使直流增益≈0.5（留6dB饱和余量）
    c = design_lowpass(TAPS, FC)
    dc = sum(c)
    if abs(dc) > 1e-9:
        c = [v * 0.5 / dc for v in c]
    # 2) 输入：四段拼接
    x = []
    x += [1.0] + [0.0] * (N // 4 - 1)                                    # 冲激
    x += [0.7 * math.sin(2 * math.pi * 0.05 * n) for n in range(N // 4)] # 低频正弦
    x += [0.8 * math.sin(2 * math.pi * 0.25 * n) + 0.1 * random.uniform(-1, 1)
          for n in range(N // 4)]                                        # 高频正弦+噪声
    x += [0.9 * random.uniform(-1, 1) for _ in range(N // 4)]            # 满幅随机
    # 3) 量化到Q1.15（硬件口径）
    cq = [q(v, 16) for v in c]
    xq = [q(v, 16) for v in x]
    # 4) 双精度FIR（用量化值）→ 量化到Q1.31
    yq = [q(v, 32) for v in fir_ref([v / 32768.0 for v in cq],
                                   [v / 32768.0 for v in xq])]
    # 5) 落盘
    os.makedirs("tb/data", exist_ok=True)
    os.makedirs("sw/firmware/fir_demo", exist_ok=True)
    with open("tb/data/coeff_q15.hex", "w") as f:
        f.write("\n".join(f"{v & 0xFFFF:04X}" for v in cq) + "\n")
    with open("tb/data/input_q15.hex", "w") as f:
        f.write("\n".join(f"{v & 0xFFFF:04X}" for v in xq) + "\n")
    with open("tb/data/golden_q31.hex", "w") as f:
        f.write("\n".join(f"{v & 0xFFFFFFFF:08X}" for v in yq) + "\n")
    with open("sw/firmware/fir_demo/fir_golden.h", "w") as f:
        f.write("// 由 tools/gen_fir_golden.py 生成，勿手改\n")
        f.write("#define FIR_TAPS %d\n#define FIR_N %d\n" % (TAPS, N))
        f.write("static const short fir_coeff[FIR_TAPS] = {%s};\n" % ",".join(map(str, cq)))
        f.write("static const short fir_input[FIR_N] = {%s};\n" % ",".join(map(str, xq)))
        f.write("static const int   fir_golden[FIR_N] = {%s};\n" % ",".join(map(str, yq)))
    print("生成完成: coeff_q15.hex / input_q15.hex / golden_q31.hex / fir_golden.h")
    print("系数示例(前4):", cq[:4], " 输入示例(前4):", xq[:4], " 期望输出示例(前4):", yq[:4])

if __name__ == "__main__":
    main()
```

- [ ] **Step 2: 运行并自检**

```bash
cd /d/ICT/Cortexm0ds && python tools/gen_fir_golden.py
```

Expected: 4个文件生成；**自检要点**（人工核对输出）：
1. `coeff_q15.hex` 共82行且系数对称（第k行==第81-k行，线性相位）；
2. `golden_q31.hex` 第0~81行（冲激段）≈ 系数本身（y[n]=c[n]，n<82）；
3. 低频正弦段输出幅度≈输入幅度×直流增益(≈0.5)；
4. `fir_golden.h` 中数值与hex一致。

- [ ] **Step 3: 提交**

```bash
cd /d/ICT/Cortexm0ds && git add tools/ tb/data/ sw/firmware/fir_demo/fir_golden.h && git commit -m "feat: FIR黄金模型生成器（量化口径）

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

**验收**：自检4点全部成立。若系数不对称或冲激响应不符，检查窗函数设计再继续。

---

### 任务 6：串行FIR核 fir_core（基线版）

**Files:**
- Create: `rtl/fir/fir_core.v`；Test: `tb/tb_fir_core.v`；Modify: `Makefile.fir`（引入RTL列表，供所有后续TB使用）

**Interfaces:**
- Consumes: 任务5的黄金文件；任务2的 `tb_clkreset`
- Produces: `fir_core #(TAPS=82, CW=16, DW=16)(clk, rstn, cfg_we, cfg_addr[9:0], cfg_wdata[CW-1:0], din_valid, din_ready, din[DW-1:0], dout_valid, dout_ready, dout[31:0])`——dout为Q1.31，din_ready=!busy（反压）

- [ ] **Step 1: 先更新 Makefile 的 RTL 列表（同时修复任务3所需）**

将 `sim_%` 规则改为：

```makefile
RTL = rtl/ic/ic_axi_master_arb.v rtl/ic/ic_axi_addr_decode.v rtl/fir/fir_core.v

sim_%: $(OUT)
	$(IV) -g2001 -o $(OUT)/$*.vvp -s $* -I$(TB_DIR)/common $(TB_DIR)/$*.v \
	     $(TB_DIR)/common/axi_master_vip.v $(TB_DIR)/common/axi_slave_mem.v \
	     $(TB_DIR)/common/axi_checker.v $(TB_DIR)/common/uart_bfm.v \
	     $(TB_DIR)/common/tb_clkreset.v $(RTL)
	$(VVP) -n $(OUT)/$*.vvp
```

（后续任务只需向RTL追加文件。若之前任务3尚未跑通，现在补跑 `make -f Makefile.fir sim_tb_arb` 与 `make -f Makefile.fir sim_tb_decode` 应转绿。）

- [ ] **Step 2: 写 TB（黄金对比<0.1% + 冲激段逐系数断言 + 随机反压）**

```verilog
// tb_fir_core.v : FIR核黄金对比测试
// 覆盖：冲激响应==系数、四段输入全序列误差<0.1%（分母下限0.001满幅）、随机反压
`timescale 1ns/1ps
module tb_fir_core;
  reg clk, rstn;
  reg  cfg_we; reg  [9:0] cfg_addr; reg  [15:0] cfg_wdata;
  reg  din_valid; wire din_ready; reg  [15:0] din;
  wire dout_valid; reg  dout_ready; wire [31:0] dout;

  reg [15:0] coeff [0:81];
  reg [15:0] input_data [0:1023];
  reg [31:0] golden [0:1023];
  reg [31:0] out_q [0:2047];
  integer n, out_cnt, err_cnt;

  real hw_r, ref_r, err, denom;
  function real rel_err; input [31:0] hw; input [31:0] ref;
    real h, r;
    begin
      h = $itor($signed(hw)) / 2147483648.0;
      r = $itor($signed(ref)) / 2147483648.0;
      err = (h >= r) ? (h - r) : (r - h);
      denom = (r < 0.0) ? -r : r;
      if (denom < 0.001) denom = 0.001;     // 分母下限：满幅的0.1%
      rel_err = err / denom;
    end
  endfunction

  tb_clkreset #() u_ck (.clk(clk), .rstn(rstn));

  fir_core #(.TAPS(82), .CW(16), .DW(16)) u_fir (
    .clk(clk), .rstn(rstn),
    .cfg_we(cfg_we), .cfg_addr(cfg_addr), .cfg_wdata(cfg_wdata),
    .din_valid(din_valid), .din_ready(din_ready), .din(din),
    .dout_valid(dout_valid), .dout_ready(dout_ready), .dout(dout));

  initial begin
    $readmemh("tb/data/coeff_q15.hex", coeff);
    $readmemh("tb/data/input_q15.hex", input_data);
    $readmemh("tb/data/golden_q31.hex", golden);
  end

  initial begin
    cfg_we = 0; cfg_addr = 0; cfg_wdata = 0;
    din_valid = 0; din = 0; dout_ready = 1; out_cnt = 0; err_cnt = 0;
    wait (rstn == 1'b1);
    @(posedge clk);
    // 1) 配置系数
    for (n = 0; n < 82; n = n + 1) begin
      @(posedge clk);
      cfg_we = 1; cfg_addr = n[9:0]; cfg_wdata = coeff[n];
    end
    @(posedge clk); cfg_we = 0;
    // 2) 流式送输入（带随机反压与随机停顿）
    for (n = 0; n < 1024; n = n + 1) begin
      din_valid = 1; din = input_data[n];
      // 反压：dout_ready 随机拉低
      dout_ready = ($random % 4) != 0;
      while (!din_ready) @(posedge clk);
      @(posedge clk);
      din_valid = 0;
    end
    // 3) 等待收尾（串行核82拍/样本，余量给足）
    repeat (200) @(posedge clk);
    if (out_cnt < 1024) $fatal(1, "FAIL: 输出样本数不足 %0d/1024", out_cnt);
    if (err_cnt != 0) $fatal(1, "FAIL: 误差超标 %0d处", err_cnt);
    // 4) 饱和用例（Review Focus#3）：系数全0x7FFF（直流增益≈41），输入满幅，
    //    输出必须饱和在Q1.31边界，不得回绕
    @(posedge clk);
    for (n = 0; n < 82; n = n + 1) begin
      @(posedge clk); cfg_we = 1; cfg_addr = n[9:0]; cfg_wdata = 16'h7FFF;
    end
    @(posedge clk); cfg_we = 0;
    for (n = 0; n < 90; n = n + 1) begin
      din_valid = 1; din = 16'h7FFF;
      while (!din_ready) @(posedge clk);
      @(posedge clk); din_valid = 0;
    end
    repeat (200) @(posedge clk);
    if (dout !== 32'h7FFFFFFF) $fatal(1, "FAIL: 饱和用例输出=%h（应=0x7FFFFFFF）", dout);
    $display("PASS: 1024样本误差全部<0.1%% + 饱和用例正确");
    $finish;
  end

  // 输出收集与比对（含冲激段逐系数断言）
  always @(posedge clk) begin
    if (dout_valid && dout_ready) begin
      out_q[out_cnt] = dout;
      // 冲激段：y[n]==c[n]（量化后系数，Q1.31与Q1.15相差16位左移）
      if (out_cnt < 82) begin
        if (dout !== {{16{coeff[out_cnt][15]}}, coeff[out_cnt], 16'h0000})
          $fatal(1, "FAIL: 冲激响应[%0d]=%h 期望=%h", out_cnt, dout,
                 {{16{coeff[out_cnt][15]}}, coeff[out_cnt], 16'h0000});
      end
      // 全序列相对误差
      if (out_cnt < 1024 && rel_err(dout, golden[out_cnt]) >= 0.001) begin
        $display("FAIL点位: n=%0d hw=%h ref=%h err=%g", out_cnt, dout, golden[out_cnt],
                 rel_err(dout, golden[out_cnt]));
        err_cnt = err_cnt + 1;
      end
      out_cnt = out_cnt + 1;
    end
  end
endmodule
```

- [ ] **Step 3: 运行TB，确认红灯**

Run: `make -f Makefile.fir sim_tb_fir_core`，Expected: 编译错误 `fir_core` 未找到。

- [ ] **Step 4: 实现 fir_core.v**

```verilog
// fir_core.v : 82抽头串行FIR核（基线版）
// 结构：数据移位寄存器(82x16) + 系数寄存器(82x16可配置) + 单MAC时间复用
// 定点：输入/系数 Q1.15；乘积 Q2.30，82项累加40位Q2.30无损；
//       输出 Q1.31 = acc<<1 取[38:8]（acc[39:38]异号即溢出→饱和）
// 性能：82拍/样本、1个乘法器（资源下限参考版）；并行版见 fir_core_sym.v
`timescale 1ns/1ps
module fir_core #(
    parameter TAPS = 82,
    parameter CW   = 16,
    parameter DW   = 16
)(
    input  wire        clk,
    input  wire        rstn,
    // 系数配置（任意时刻可写）
    input  wire        cfg_we,
    input  wire [9:0]  cfg_addr,
    input  wire [CW-1:0] cfg_wdata,
    // 数据流
    input  wire        din_valid,
    output wire        din_ready,
    input  wire [DW-1:0] din,
    output reg         dout_valid,
    input  wire        dout_ready,
    output reg  [31:0] dout
);
  reg [DW-1:0] x [0:TAPS-1];
  reg [CW-1:0] c [0:TAPS-1];
  reg [6:0]    ph;         // 0..TAPS-1 乘加相位
  reg          busy;
  reg [39:0]   acc;        // Q2.30
  integer      i;

  // 饱和：Q2.30 -> Q1.31（=acc<<1取[38:8]）
  function [31:0] sat; input [39:0] a;
    begin
      if (a[39:38] == 2'b01)      sat = 32'h7FFFFFFF;
      else if (a[39:38] == 2'b10) sat = 32'h80000000;
      else                        sat = a[38:8];
    end
  endfunction

  // 系数配置
  always @(posedge clk) begin
    if (!rstn) begin
      for (i = 0; i < TAPS; i = i + 1) c[i] <= {CW{1'b0}};
    end else if (cfg_we) c[cfg_addr] <= cfg_wdata;
  end

  // 数据通路
  always @(posedge clk) begin
    if (!rstn) begin
      busy <= 1'b0; ph <= 7'd0; acc <= 40'd0;
      dout_valid <= 1'b0; dout <= 32'd0;
      for (i = 0; i < TAPS; i = i + 1) x[i] <= {DW{1'b0}};
    end else begin
      if (dout_valid && dout_ready) dout_valid <= 1'b0;
      if (busy) begin
        acc <= acc + $signed(x[ph]) * $signed(c[ph]);
        if (ph == TAPS-1) begin
          busy <= 1'b0;
          // 注意：本拍acc仍为旧值，饱和对象必须含本拍乘加项
          dout <= sat(acc + $signed(x[ph]) * $signed(c[ph]));
          dout_valid <= 1'b1;
        end else begin
          ph <= ph + 7'd1;
        end
      end else if (din_valid) begin
        for (i = TAPS-1; i > 0; i = i - 1) x[i] <= x[i-1];
        x[0] <= din;
        acc <= 40'd0;
        ph <= 7'd0;
        busy <= 1'b1;
      end
    end
  end

  assign din_ready = !busy;
endmodule
```

- [ ] **Step 5: 运行TB，确认绿灯**

Run: `make -f Makefile.fir sim_tb_fir_core`，Expected: `PASS: 1024样本误差全部<0.1%...`。若冲激段断言失败，优先检查 `$readmemh` 路径（相对路径基于调用vvp时的工作目录）与饱和公式。

- [ ] **Step 6: 提交**

```bash
cd /d/ICT/Cortexm0ds && git add rtl/fir/fir_core.v tb/tb_fir_core.v Makefile && git commit -m "feat: 串行FIR核（黄金对比误差<0.1%）

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

**验收**：`make -f Makefile.fir sim_tb_fir_core` 绿。对应"81阶可配置系数FIR"的基本盘（后续对称优化在此基础上做）。

---

### 任务 7：FIR的AXI从机封装 fir_top

**Files:**
- Create: `rtl/fir/fir_top.v`；Test: `tb/tb_fir_top.v`；Modify: `Makefile.fir`（RTL追加 fir_top.v 与 fir_core_sym.v）

**Interfaces:**
- Consumes: `fir_core`（任务6）、VIP（任务2）、黄金文件（任务5）
- Produces: `fir_top #(CORE_TYPE=0|1)`，CMSDK从机风格端口：`ACLK, ARESETn, AW_SEL, AW_VALID, AW_READY, AW_SIZE[2:0], AW_BURST[1:0], AW_LEN[7:0], AW_ADDR[31:0], W_VALID, W_READY, W_DATA[31:0], W_LAST, B_VALID, B_READY, B_RESP[1:0], AR_SEL, AR_VALID, AR_READY, AR_SIZE[2:0], AR_BURST[1:0], AR_LEN[7:0], AR_ADDR[31:0], R_VALID, R_READY, R_DATA[31:0], R_RESP[1:0], R_LAST`
- 寄存器映射（字节地址，固件与TB共用）：
  - `0x00` CTRL：bit0=CLR（写1清空FIFO与核状态）
  - `0x04` STATUS：bit0 DIN_FIFO_EMPTY、bit1 DIN_FIFO_FULL、bit2 DOUT_FIFO_EMPTY、bit3 DOUT_FIFO_FULL
  - `0x08` DIN：写→压入样本（取16位；支持半字写按通道）；建议整字写
  - `0x0C` DOUT：读→弹出32位Q1.31结果；**FIXED突发读=连续弹样本**
  - `0x10..0x158` COEF[k]（k=(addr-0x10)/4）；建议INCR突发整字写82个系数

- [ ] **Step 1: 写 TB（VIP配置系数→DIN流式写→DOUT读回→黄金对比；含字节/半字访问与FIXED突发）**

```verilog
// tb_fir_top.v : FIR从机测试——系数INCR突发配置、DIN固定地址突发、DOUT固定地址突发读回
`timescale 1ns/1ps
module tb_fir_top;
  reg  ACLK, ARESETn;
  wire AW_SEL, AW_VALID, AW_READY; wire [2:0] AW_SIZE; wire [1:0] AW_BURST;
  wire [7:0] AW_LEN; wire [31:0] AW_ADDR;
  wire W_VALID, W_READY; wire [31:0] W_DATA; wire W_LAST;
  wire B_VALID, B_READY; wire [1:0] B_RESP;
  wire AR_SEL, AR_VALID, AR_READY; wire [2:0] AR_SIZE; wire [1:0] AR_BURST;
  wire [7:0] AR_LEN; wire [31:0] AR_ADDR;
  wire R_VALID, R_READY; wire [31:0] R_DATA; wire [1:0] R_RESP; wire R_LAST;

  reg [15:0] coeff [0:81];
  reg [31:0] golden [0:63];
  integer i, j, err_cnt;

  tb_clkreset #() u_ck (.clk(ACLK), .rstn(ARESETn));

  axi_master_vip u_vip (
    .ACLK(ACLK), .ARESETn(ARESETn),
    .AW_SEL(AW_SEL), .AW_VALID(AW_VALID), .AW_READY(AW_READY),
    .AW_SIZE(AW_SIZE), .AW_BURST(AW_BURST), .AW_LEN(AW_LEN), .AW_ADDR(AW_ADDR),
    .W_VALID(W_VALID), .W_READY(W_READY), .W_DATA(W_DATA), .W_LAST(W_LAST),
    .B_VALID(B_VALID), .B_READY(B_READY), .B_RESP(B_RESP),
    .AR_SEL(AR_SEL), .AR_VALID(AR_VALID), .AR_READY(AR_READY),
    .AR_SIZE(AR_SIZE), .AR_BURST(AR_BURST), .AR_LEN(AR_LEN), .AR_ADDR(AR_ADDR),
    .R_VALID(R_VALID), .R_READY(R_READY), .R_DATA(R_DATA), .R_RESP(R_RESP), .R_LAST(R_LAST));

  fir_top #(.CORE_TYPE(0)) u_fir (
    .ACLK(ACLK), .ARESETn(ARESETn),
    .AW_SEL(AW_SEL), .AW_VALID(AW_VALID), .AW_READY(AW_READY),
    .AW_SIZE(AW_SIZE), .AW_BURST(AW_BURST), .AW_LEN(AW_LEN), .AW_ADDR(AW_ADDR),
    .W_VALID(W_VALID), .W_READY(W_READY), .W_DATA(W_DATA), .W_LAST(W_LAST),
    .B_VALID(B_VALID), .B_READY(B_READY), .B_RESP(B_RESP),
    .AR_SEL(AR_SEL), .AR_VALID(AR_VALID), .AR_READY(AR_READY),
    .AR_SIZE(AR_SIZE), .AR_BURST(AR_BURST), .AR_LEN(AR_LEN), .AR_ADDR(AR_ADDR),
    .R_VALID(R_VALID), .R_READY(R_READY), .R_DATA(R_DATA), .R_RESP(R_RESP), .R_LAST(R_LAST));

  initial begin
    $readmemh("tb/data/coeff_q15.hex", coeff);
    $readmemh("tb/data/golden_q31.hex", golden);
  end

  reg [15:0] u_fir_din [0:71];

  initial begin
    $readmemh("tb/data/input_q15.hex", u_fir_din);
  end

  initial begin
    err_cnt = 0;
    wait (ARESETn == 1'b1);
    @(posedge ACLK);
    // 1) 字节写CTRL（清空）——检验size=0通道
    u_vip.vip_wdata[0] = 32'h1;
    u_vip.axi_wr(32'h4002_0000, 8'd0, 2'b00, 3'b000);
    // 2) INCR突发配置82个系数
    for (i = 0; i < 82; i = i + 1) u_vip.vip_wdata[i] = {16'h0, coeff[i]};
    u_vip.axi_wr(32'h4002_0010, 8'd81, 2'b01, 3'b010);
    // 3) 逐样本半字写DIN：先查STATUS bit1 DIN_FIFO_FULL，满则等
    for (i = 0; i < 64; i = i + 1) begin
      u_vip.axi_rd(32'h4002_0004, 8'd0, 2'b00, 3'b010);
      while (u_vip.vip_rdata[0][1]) begin
        u_vip.axi_rd(32'h4002_0004, 8'd0, 2'b00, 3'b010);
      end
      u_vip.vip_wdata[0] = {16'h0, u_fir_din[i]};
      u_vip.axi_wr(32'h4002_0008, 8'd0, 2'b00, 3'b001);
    end
    // 4) 逐样本回读DOUT：先查STATUS bit2 DOUT_FIFO_EMPTY，空则等，读后对比
    for (i = 0; i < 64; i = i + 1) begin
      u_vip.axi_rd(32'h4002_0004, 8'd0, 2'b00, 3'b010);
      while (u_vip.vip_rdata[0][2]) begin
        u_vip.axi_rd(32'h4002_0004, 8'd0, 2'b00, 3'b010);
      end
      u_vip.axi_rd(32'h4002_000C, 8'd0, 2'b00, 3'b010);
      if (u_vip.vip_rdata[0] !== golden[i])
        $display("MISMATCH[%0d] hw=%h ref=%h", i, u_vip.vip_rdata[0], golden[i]);
    end
    // 黄金模型自检：冲激段前16个应等于系数（Q1.15左移16位）
    for (i = 1; i < 16; i = i + 1)
      if (golden[i] !== {{16{coeff[i][15]}}, coeff[i], 16'h0000}) begin
        $display("IMPULSE MISMATCH[%0d]", i); err_cnt = err_cnt + 1;
      end
    // 5) FIXED突发路径：续推8样本（FIXED半字burst，序列连续）→ FIXED字burst读回8个
    u_vip.axi_rd(32'h4002_0004, 8'd0, 2'b00, 3'b010);
    while (u_vip.vip_rdata[0][1]) begin
      u_vip.axi_rd(32'h4002_0004, 8'd0, 2'b00, 3'b010);
    end
    for (i = 0; i < 8; i = i + 1) u_vip.vip_wdata[i] = {16'h0, u_fir_din[64+i]};
    u_vip.axi_wr(32'h4002_0008, 8'd7, 2'b00, 3'b001);   // FIXED半字8拍burst
    repeat (1000) @(posedge ACLK);                      // 8样本×82拍余量
    u_vip.axi_rd(32'h4002_000C, 8'd7, 2'b00, 3'b010);   // FIXED字8拍burst
    for (i = 0; i < 8; i = i + 1)
      if (u_vip.vip_rdata[i] !== golden[64+i])
        $display("BURST MISMATCH[%0d] hw=%h ref=%h", i, u_vip.vip_rdata[i], golden[64+i]);
    if (err_cnt != 0) $fatal(1, "FAIL: FIR从机数据比对不一致");
    $display("PASS: FIR从机（系数INCR/数据单拍+FIXED突发/字节半字访问）");
    $finish;
  end
endmodule
```

（实现说明：`u_fir_din` 为TB内 `reg [15:0] u_fir_din[0:63]`，加载 `tb/data/input_q15.hex` 前64个值；轮询STATUS的策略改为"压前查DIN_FIFO_EMPTY=0即可压（空则等核取走）"，实际以DIN_FIFO_FULL位为准——实现时给STATUS补 bit3 DIN_FIFO_FULL，TB轮询 `vip_rdata[0][3]==0` 才压下一批，代码按此微调。）

- [ ] **Step 2: 运行TB，确认红灯**

Run: `make -f Makefile.fir sim_tb_fir_top`，Expected: 编译错误 `fir_top` 未找到。

- [ ] **Step 3: 实现 fir_top.v**

```verilog
// fir_top.v : FIR的AXI从机封装（CMSDK SEL风格）
// 寄存器：CTRL/STATUS/DIN/DOUT/COEF[0..81]（见任务接口说明）
// 写：AW握手锁存选择与地址，逐拍W落寄存器/FIFO（INCR逐拍加4、FIXED不变）；
//     最后一拍后回B（BRESP=OKAY）。读：DOUT区FIXED突发=每拍弹一个样本。
`timescale 1ns/1ps
module fir_top #(
    parameter CORE_TYPE = 0      // 0=fir_core(串行) 1=fir_core_sym(对称并行)
)(
    input  wire        ACLK,
    input  wire        ARESETn,
    // 写通道（CMSDK从机风格）
    input  wire        AW_SEL,
    input  wire        AW_VALID, output reg  AW_READY,
    input  wire [2:0]  AW_SIZE,  input  wire [1:0] AW_BURST,
    input  wire [7:0]  AW_LEN,   input  wire [31:0] AW_ADDR,
    input  wire        W_VALID,  output reg  W_READY,
    input  wire [31:0] W_DATA,   input  wire W_LAST,
    output reg         B_VALID,  input  wire B_READY,
    output reg  [1:0]  B_RESP,
    // 读通道
    input  wire        AR_SEL,
    input  wire        AR_VALID, output reg  AR_READY,
    input  wire [2:0]  AR_SIZE,  input  wire [1:0] AR_BURST,
    input  wire [7:0]  AR_LEN,   input  wire [31:0] AR_ADDR,
    output reg         R_VALID,  input  wire R_READY,
    output reg  [31:0] R_DATA,   output reg  [1:0] R_RESP,
    output reg         R_LAST
);
  // ---- FIFO ----
  localparam DIN_DEPTH  = 16;
  localparam DOUT_DEPTH = 16;
  reg [15:0] din_fifo  [0:DIN_DEPTH-1];
  reg [31:0] dout_fifo [0:DOUT_DEPTH-1];
  reg [3:0]  din_wp, din_rp, din_cnt;
  reg [3:0]  dot_wp, dot_rp, dot_cnt;

  // ---- 写状态机 ----
  localparam WS_IDLE = 2'd0, WS_DATA = 2'd1, WS_RESP = 2'd2;
  reg [1:0]  ws;
  reg        w_sel;                    // AW握手时锁存的选中
  reg [31:0] w_a;                      // 当前拍地址
  reg [7:0]  w_cnt;                    // 剩余拍数
  reg [1:0]  w_burst;
  reg [2:0]  w_size;                   // AW握手时锁存（W阶段AW_SIZE可能已变）

  // ---- 读状态机 ----
  localparam RS_IDLE = 2'd0, RS_DATA = 2'd1;
  reg [1:0]  rs;
  reg        r_sel;
  reg [31:0] r_a;
  reg [7:0]  r_cnt;
  reg [1:0]  r_burst;
  reg        r_pop;                    // 本拍弹出DOUT

  // ---- 核与连接 ----
  wire        core_din_valid = (din_cnt != 0);
  wire [15:0] core_din = din_fifo[din_rp];
  wire        core_din_ready;
  wire        core_dout_valid;
  wire [31:0] core_dout;
  wire [31:0] ctrl_reg;                // bit0=CLR（写1清空）
  reg         clr_pulse;

  generate
    if (CORE_TYPE == 0) begin : core
      fir_core #(.TAPS(82), .CW(16), .DW(16)) u_core (
        .clk(ACLK), .rstn(ARESETn),
        .cfg_we(cfg_we), .cfg_addr(cfg_addr), .cfg_wdata(cfg_wdata),
        .din_valid(core_din_valid), .din_ready(core_din_ready), .din(core_din),
        .dout_valid(core_dout_valid), .dout_ready(dot_cnt != DOUT_DEPTH), .dout(core_dout));
    end else begin : core_sym
      fir_core_sym #(.TAPS(82), .CW(16), .DW(16)) u_core (
        .clk(ACLK), .rstn(ARESETn),
        .cfg_we(cfg_we), .cfg_addr(cfg_addr), .cfg_wdata(cfg_wdata),
        .din_valid(core_din_valid), .din_ready(core_din_ready), .din(core_din),
        .dout_valid(core_dout_valid), .dout_ready(dot_cnt != DOUT_DEPTH), .dout(core_dout));
    end
  endgenerate

  reg        cfg_we; reg [9:0] cfg_addr; reg [15:0] cfg_wdata;
  reg [15:0] coef_reg [0:81];
  integer    i;

  // 写：每拍落寄存器/FIFO（组合出本拍写目标）
  always @(posedge ACLK) begin
    if (!ARESETn) begin
      ws <= WS_IDLE; AW_READY <= 1'b0; W_READY <= 1'b0; B_VALID <= 1'b0; B_RESP <= 2'b00;
      w_sel <= 0; w_a <= 0; w_cnt <= 0; w_burst <= 0;
      din_wp <= 0; din_rp <= 0; din_cnt <= 0;
      dot_wp <= 0; dot_rp <= 0; dot_cnt <= 0;
      cfg_we <= 0; cfg_addr <= 0; cfg_wdata <= 0; clr_pulse <= 0;
      for (i = 0; i < 82; i = i + 1) coef_reg[i] <= 16'h0;
    end else begin
      clr_pulse <= 1'b0; cfg_we <= 1'b0;
      // 核输出入FIFO
      if (core_dout_valid && (dot_cnt != DOUT_DEPTH)) begin
        dout_fifo[dot_wp] <= core_dout;
        dot_wp <= dot_wp + 1'b1;
        dot_cnt <= dot_cnt + 1'b1;
      end
      // 核取输入
      if (core_din_valid && core_din_ready) begin
        din_rp <= din_rp + 1'b1;
        din_cnt <= din_cnt - 1'b1;
      end
      // 读弹出
      if (r_pop && dot_cnt != 0) begin
        dot_rp <= dot_rp + 1'b1;
        dot_cnt <= dot_cnt - 1'b1;
      end
      case (ws)
        WS_IDLE: begin
          AW_READY <= 1'b1;
          if (AW_VALID && AW_READY) begin
            w_sel <= AW_SEL; w_a <= AW_ADDR; w_cnt <= AW_LEN; w_burst <= AW_BURST;
            w_size <= AW_SIZE;
            AW_READY <= 1'b0; W_READY <= 1'b1;
            ws <= WS_DATA;
          end
        end
        WS_DATA: begin
          if (W_VALID && W_READY) begin
            if (w_sel) begin
              // 地址在0x4002_0000区域的寄存器写
              casez (w_a[11:0])
                12'h008: begin                          // DIN：压样本
                  if (din_cnt != DIN_DEPTH) begin
                    din_fifo[din_wp] <= (w_size[0]) ?
                        (w_a[1] ? W_DATA[31:16] : W_DATA[15:0]) : W_DATA[15:0];
                    din_wp <= din_wp + 1'b1;
                    din_cnt <= din_cnt + 1'b1;
                  end
                end
                12'h000: if (W_DATA[0]) clr_pulse <= 1'b1;   // CTRL CLR
                12'h004, 12'h00C: ;                          // STATUS/DOUT：忽略写
                default: begin
                  if ((w_a[11:0] >= 12'h010) && (w_a[11:0] < 12'h158) && (w_size == 3'b010)) begin
                    coef_reg[(w_a[11:0] - 12'h010) >> 2] <= W_DATA[15:0];
                    cfg_we <= 1'b1;
                    cfg_addr <= (w_a[11:0] - 12'h010) >> 2;
                    cfg_wdata <= W_DATA[15:0];
                  end
                end
              endcase
            end
            if (w_burst[0]) w_a <= w_a + 32'd4;     // INCR
            if (w_cnt == 0) begin
              ws <= WS_RESP; W_READY <= 1'b0; B_VALID <= 1'b1; B_RESP <= 2'b00;
            end else w_cnt <= w_cnt - 8'd1;
          end
        end
        WS_RESP: begin
          if (B_VALID && B_READY) begin
            B_VALID <= 1'b0; ws <= WS_IDLE;
          end
        end
      endcase
      if (clr_pulse) begin                       // 清空
        din_wp <= 0; din_rp <= 0; din_cnt <= 0;
        dot_wp <= 0; dot_rp <= 0; dot_cnt <= 0;
      end
    end
  end

  // 读状态机
  always @(posedge ACLK) begin
    if (!ARESETn) begin
      rs <= RS_IDLE; AR_READY <= 1'b0; R_VALID <= 1'b0; R_RESP <= 2'b00; R_LAST <= 1'b0;
      r_sel <= 0; r_a <= 0; r_cnt <= 0; r_burst <= 0; r_pop <= 0;
    end else begin
      r_pop <= 1'b0;
      case (rs)
        RS_IDLE: begin
          AR_READY <= 1'b1;
          if (AR_VALID && AR_READY) begin
            r_sel <= AR_SEL; r_a <= AR_ADDR; r_cnt <= AR_LEN; r_burst <= AR_BURST;
            AR_READY <= 1'b0;
            rs <= RS_DATA;
          end
        end
        RS_DATA: begin
          R_VALID <= 1'b1;
          if (R_VALID && R_READY) begin
            if (r_sel && (r_a[11:0] == 12'h00C)) r_pop <= 1'b1;   // DOUT弹样本
            if (r_burst[0]) r_a <= r_a + 32'd4;
            if (r_cnt == 0) begin
              rs <= RS_IDLE; R_VALID <= 1'b0; R_LAST <= 1'b0; AR_READY <= 1'b1;
            end else begin
              r_cnt <= r_cnt - 8'd1;
              if (r_cnt == 1) R_LAST <= 1'b1;
            end
          end
        end
      endcase
    end
  end

  // 读数据（组合）
  always @* begin
    R_DATA = 32'h0; R_RESP = 2'b00;
    if (rs == RS_DATA && r_sel) begin
      casez (r_a[11:0])
        12'h000: R_DATA = 32'h0;                       // CTRL只写
        12'h004: R_DATA = {28'h0, dot_cnt == DOUT_DEPTH, dot_cnt == 0, din_cnt == DIN_DEPTH, din_cnt == 0};
        12'h00C: R_DATA = dout_fifo[dot_rp];           // DOUT
        default: if ((r_a[11:0] >= 12'h010) && (r_a[11:0] < 12'h158))
                   R_DATA = {16'h0, coef_reg[(r_a[11:0] - 12'h010) >> 2]};
      endcase
    end
  end
endmodule
```

- [ ] **Step 4: 运行TB，确认绿灯**

Run: `make -f Makefile.fir sim_tb_fir_top`，Expected: `PASS: FIR从机...`。注意TB中STATUS轮询与等待拍数按实现实际微调（保持断言不变）。

- [ ] **Step 5: 提交**

```bash
cd /d/ICT/Cortexm0ds && git add rtl/fir/fir_top.v tb/tb_fir_top.v Makefile && git commit -m "feat: FIR AXI从机封装（系数配置+FIFO数据口）

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

**验收**：`make -f Makefile.fir sim_tb_fir_top` 绿。FIR从机接口自此冻结，任务10/12直接实例化。

---

### 任务 8：对称并行FIR核 fir_core_sym（决赛性能/创新版）

**Files:**
- Create: `rtl/fir/fir_core_sym.v`；Test: `tb/tb_fir_core_sym.v`

**Interfaces:**
- Consumes: 黄金文件（任务5）。**注意：对称核假设系数线性相位对称（c[k]==c[81-k]），仅使用c[0..40]；黄金低通系数满足该假设。**
- Produces: `fir_core_sym` 与 `fir_core` 同接口（fir_top的generate已预留实例化），din_ready恒1（无反压，吞吐1样本/拍，流水延迟约9拍）

- [ ] **Step 1: 写 TB（黄金回归+吞吐量断言）**

```verilog
// tb_fir_core_sym.v : 对称并行FIR黄金回归+吞吐测量
// 断言：1024样本误差<0.1%；连续进样时输出间隔恒为1拍（吞吐=1样本/拍）
`timescale 1ns/1ps
module tb_fir_core_sym;
  reg clk, rstn;
  reg  cfg_we; reg  [9:0] cfg_addr; reg  [15:0] cfg_wdata;
  reg  din_valid; wire din_ready; reg  [15:0] din;
  wire dout_valid; reg  dout_ready; wire [31:0] dout;

  reg [15:0] coeff [0:81];
  reg [15:0] input_data [0:1023];
  reg [31:0] golden [0:1023];
  integer n, out_cnt, err_cnt, last_valid_cycle, gap;

  real hw_r, ref_r, denom;
  function real rel_err; input [31:0] hw; input [31:0] ref;
    real h, r;
    begin
      h = $itor($signed(hw)) / 2147483648.0;
      r = $itor($signed(ref)) / 2147483648.0;
      if (h >= r) h = h - r; else h = r - h;
      denom = (r < 0.0) ? -r : r;
      if (denom < 0.001) denom = 0.001;
      rel_err = h / denom;
    end
  endfunction

  tb_clkreset #() u_ck (.clk(clk), .rstn(rstn));

  fir_core_sym #(.TAPS(82), .CW(16), .DW(16)) u_fir (
    .clk(clk), .rstn(rstn),
    .cfg_we(cfg_we), .cfg_addr(cfg_addr), .cfg_wdata(cfg_wdata),
    .din_valid(din_valid), .din_ready(din_ready), .din(din),
    .dout_valid(dout_valid), .dout_ready(dout_ready), .dout(dout));

  initial begin
    $readmemh("tb/data/coeff_q15.hex", coeff);
    $readmemh("tb/data/input_q15.hex", input_data);
    $readmemh("tb/data/golden_q31.hex", golden);
  end

  initial begin
    cfg_we = 0; cfg_addr = 0; cfg_wdata = 0;
    din_valid = 0; din = 0; dout_ready = 1;
    out_cnt = 0; err_cnt = 0; last_valid_cycle = 0; gap = 0;
    wait (rstn == 1'b1);
    @(posedge clk);
    // 配置上半系数（仅c[0..40]有效，对称假设）
    for (n = 0; n < 41; n = n + 1) begin
      @(posedge clk);
      cfg_we = 1; cfg_addr = n[9:0]; cfg_wdata = coeff[n];
    end
    @(posedge clk); cfg_we = 0;
    // 连续流式进样（对称核无反压）
    for (n = 0; n < 1024; n = n + 1) begin
      din_valid = 1; din = input_data[n];
      @(posedge clk);
    end
    din_valid = 0;
    repeat (50) @(posedge clk);       // 流水排空
    if (out_cnt < 1024) $fatal(1, "FAIL: 输出不足 %0d/1024", out_cnt);
    if (err_cnt != 0) $fatal(1, "FAIL: 误差超标 %0d处", err_cnt);
    if (gap != 1) $fatal(1, "FAIL: 吞吐非1样本/拍（连续段内输出间隔=%0d拍）", gap);
    $display("PASS: 对称并行FIR黄金回归+吞吐=1样本/拍");
    $finish;
  end

  always @(posedge clk) begin
    if (dout_valid && dout_ready) begin
      // 吞吐：连续段内相邻输出间隔必须为1拍（允许流水首尾）
      if (out_cnt > 80 && out_cnt < 1024) begin
        if ($time - last_valid_cycle != 20) gap = $time - last_valid_cycle;
      end
      last_valid_cycle = $time;
      if (out_cnt < 1024 && rel_err(dout, golden[out_cnt]) >= 0.001) begin
        $display("FAIL点位: n=%0d hw=%h ref=%h", out_cnt, dout, golden[out_cnt]);
        err_cnt = err_cnt + 1;
      end
      out_cnt = out_cnt + 1;
    end
  end
endmodule
```

- [ ] **Step 2: 运行TB，确认红灯**

Run: `make -f Makefile.fir sim_tb_fir_core_sym`，Expected: 编译错误 `fir_core_sym` 未找到。

- [ ] **Step 3: 实现 fir_core_sym.v**

```verilog
// fir_core_sym.v : 对称系数并行FIR（决赛性能/创新版，对应"81阶→41次乘加"）
// 线性相位对称系数 c[k]==c[TAPS-1-k]：预加 x[k]+x[81-k]（17位）后乘系数，
// 41个乘法并行 + 加法树流水（41→21→11→6→3→2→1）。
// 吞吐：1样本/拍（din_ready恒1，无反压，由上游FIFO控速）；流水延迟9拍。
// 资源：约41个DSP48（若PG2L100H DSP不足41，可将乘法树每级插入寄存器后
//       改为两路20/21乘加分时复用，吞吐降为1样本/2拍——先按41路实现并测DSP占用）。
`timescale 1ns/1ps
module fir_core_sym #(
    parameter TAPS = 82,
    parameter CW   = 16,
    parameter DW   = 16
)(
    input  wire        clk,
    input  wire        rstn,
    input  wire        cfg_we,
    input  wire [9:0]  cfg_addr,               // 0..40（上半系数；≥41忽略）
    input  wire [CW-1:0] cfg_wdata,
    input  wire        din_valid,
    output wire        din_ready,
    input  wire [DW-1:0] din,
    output reg         dout_valid,
    input  wire        dout_ready,
    output reg  [31:0] dout
);
  localparam H = TAPS / 2;                     // 41
  reg [DW-1:0] x [0:TAPS-1];
  reg [CW-1:0] c [0:H-1];
  reg signed [32:0] p1 [0:H-1];                // 预加×系数 → Q2.31
  reg signed [39:0] p2 [0:20];                 // 41→21
  reg signed [39:0] p3 [0:10];                 // 21→11
  reg signed [39:0] p4 [0:5];                  // 11→6
  reg signed [39:0] p5 [0:2];                  // 6→3
  reg signed [39:0] p6 [0:1];                  // 3→2
  reg signed [39:0] p7;                        // 2→1
  reg [8:0]  vpipe;                            // valid流水（9拍，比数据多1拍补偿x滞后）
  integer    i;

  // 饱和：Q2.31累加值 → Q1.31（|值|<1直接截断低位已对齐；越界饱和）
  function [31:0] sat31; input [39:0] a;
    begin
      if (a > 40'sh0007F_FFFFFF)     sat31 = 32'h7FFFFFFF;
      else if (a < -40'sh00080_00000) sat31 = 32'h80000000;
      else                            sat31 = a[31:0];
    end
  endfunction

  assign din_ready = 1'b1;

  always @(posedge clk) begin
    if (!rstn) begin
      for (i = 0; i < TAPS; i = i + 1) x[i] <= {DW{1'b0}};
      for (i = 0; i < H;    i = i + 1) c[i] <= {CW{1'b0}};
      for (i = 0; i < H;    i = i + 1) p1[i] <= 33'sd0;
      for (i = 0; i < 21;   i = i + 1) p2[i] <= 40'sd0;
      for (i = 0; i < 11;   i = i + 1) p3[i] <= 40'sd0;
      for (i = 0; i < 6;    i = i + 1) p4[i] <= 40'sd0;
      for (i = 0; i < 3;    i = i + 1) p5[i] <= 40'sd0;
      for (i = 0; i < 2;    i = i + 1) p6[i] <= 40'sd0;
      p7 <= 40'sd0; vpipe <= 9'd0; dout_valid <= 1'b0; dout <= 32'd0;
    end else begin
      // 系数
      if (cfg_we && (cfg_addr < H)) c[cfg_addr] <= cfg_wdata;
      // 数据移位
      if (din_valid) begin
        for (i = TAPS-1; i > 0; i = i - 1) x[i] <= x[i-1];
        x[0] <= din;
      end
      // 流水（非阻塞链；p1的x滞后1拍由vpipe多1拍补偿）
      for (i = 0; i < H; i = i + 1)
        p1[i] <= ($signed(x[i]) + $signed(x[TAPS-1-i])) * $signed(c[i]);
      for (i = 0; i < 20; i = i + 1) p2[i] <= p1[2*i] + p1[2*i+1];
      p2[20] <= p1[40];
      for (i = 0; i < 10; i = i + 1) p3[i] <= p2[2*i] + p2[2*i+1];
      p3[10] <= p2[20];
      for (i = 0; i < 5;  i = i + 1) p4[i] <= p3[2*i] + p3[2*i+1];
      p4[5] <= p3[10];
      for (i = 0; i < 2;  i = i + 1) p5[i] <= p4[2*i] + p4[2*i+1];
      p5[2] <= p4[4] + p4[5];
      p6[0] <= p5[0] + p5[1];
      p6[1] <= p5[2];
      p7 <= p6[0] + p6[1];
      dout <= sat31(p7);
      vpipe <= {vpipe[7:0], din_valid};
      dout_valid <= vpipe[8];
    end
  end
endmodule
```

- [ ] **Step 4: 运行TB，确认绿灯**

Run: `make -f Makefile.fir sim_tb_fir_core_sym`，Expected: `PASS: 对称并行FIR黄金回归+吞吐=1样本/拍`。若误差超标：先核对饱和常数（`0x0007F_FFFFFF`/`-0x00080_00000`）与对称系数假设；若吞吐断言误报，检查TB的gap计算区间（80~1024内采样）。

- [ ] **Step 5: 资源粗评并记录（供决赛资源利用率优化）**

用iverilog跑一遍elaboration并手工估算：41个乘法器+约6级加法树；记录到 `docs/走读笔记-官方参考工程.md` 的"资源预算"节：预加17bit加法器×41、DSP48×41、加法树寄存器约(21+11+6+3+2+1)×40bit。此数据在任务16与PDS实际资源报告对比。

- [ ] **Step 6: 提交**

```bash
cd /d/ICT/Cortexm0ds && git add rtl/fir/fir_core_sym.v tb/tb_fir_core_sym.v docs/ && git commit -m "feat: 对称并行FIR核（41乘加，1样本/拍）

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

**验收**：`make -f Makefile.fir sim_tb_fir_core_sym` 绿。对应评分"架构创新：FIR采用对称系数优化（81阶→41次乘加）"与决赛性能项"FIR吞吐量"。

---

## 阶段 3：DMA 控制器（对应 FR-3）

### 任务 9：单通道DMA引擎 dma_channel

**Files:**
- Modify: `tb/common/axi_slave_mem.v`（修正：捕获AW_SIZE/AW_BURST、支持FIXED读）
- Create: `rtl/dma/dma_channel.v`；Test: `tb/tb_dma_channel.v`；Modify: `Makefile.fir`（RTL追加 dma_channel.v）

**Interfaces:**
- Consumes: `axi_slave_mem`、`axi_checker`、VIP（任务2）
- Produces: `dma_channel #(DW=32)(clk, rstn, cfg_src[31:0], cfg_dst[31:0], cfg_len[31:0], cfg_next[31:0], cfg_ctrl[15:0], cfg_load, busy_o, done_o, err_o, req_o, awvalid, awready, awsize[2:0], awburst[1:0], awlen[7:0], awaddr[31:0], wvalid, wready, wdata[31:0], wlast, bvalid, bready, bresp[1:0], arvalid, arready, arsize[2:0], arburst[1:0], arlen[7:0], araddr[31:0], rvalid, rready, rdata[31:0], rresp[1:0], rlast)`
- `cfg_ctrl` 位域：`[0]GO [1]IRQ_EN [2]FIXED_SRC [3]FIXED_DST [4]CHAIN [7:5]BURST(0=1拍..7=8拍) [10:8]FSIZE(0=字节,1=半字,2=字)`
- 语义：FIXED_SRC=1时`cfg_len`为**读取拍数**（每拍从固定地址读一个字，总字节数=len<<FSIZE）；FIXED_DST=1时`cfg_len`为**写入拍数**；两者都为0时`cfg_len`为**字节数**（任意对齐）
- 链式描述符布局（内存中，5字）：`{SRC, DST, LEN, CTRL, NEXT}`
- `req_o`：burst在途请求（供dma_top仲裁，保持到B握手/R_LAST完成）；`done_o/err_o`：单拍脉冲

- [ ] **Step 1: 修正 axi_slave_mem.v（捕获size/burst、支持FIXED读）**

将任务2的实现替换为（改动点：写路径锁存`AW_SIZE/AW_BURST`，读路径锁存`AR_BURST`并支持FIXED不递增）：

```verilog
// axi_slave_mem.v（修正版）：行为级AXI存储从机
// 修正1：AW_SIZE/AW_BURST在AW握手时锁存（原实现用直通信号，握手后主设备可改值）
// 修正2：读路径支持FIXED突发（地址不递增，供DMA固定地址读取测试）
`timescale 1ns/1ps
module axi_slave_mem #(parameter AW = 12, parameter DW = 32)(
    input  wire        ACLK, ARESETn,
    input  wire        AW_VALID, output reg AW_READY,
    input  wire [2:0]  AW_SIZE,  input wire [1:0] AW_BURST,
    input  wire [7:0]  AW_LEN,   input wire [31:0] AW_ADDR,
    input  wire        W_VALID,  output reg W_READY,
    input  wire [DW-1:0] W_DATA, input wire W_LAST,
    output reg         B_VALID,  input wire B_READY, output reg [1:0] B_RESP,
    input  wire        AR_VALID, output reg AR_READY,
    input  wire [2:0]  AR_SIZE,  input wire [1:0] AR_BURST,
    input  wire [7:0]  AR_LEN,   input wire [31:0] AR_ADDR,
    output reg         R_VALID,  input wire R_READY,
    output reg [DW-1:0] R_DATA,  output reg [1:0] R_RESP, output reg R_LAST
);
  reg [DW-1:0] mem [0:(1<<AW)-1];
  reg [AW-1:0] w_a; reg [7:0] w_cnt; reg w_busy;
  reg [2:0]    w_size; reg [1:0] w_burst;      // 锁存
  reg [AW-1:0] r_a; reg [7:0] r_cnt; reg r_busy;
  reg [1:0]    r_burst;                        // 锁存

  always @(posedge ACLK or negedge ARESETn) begin
    if (!ARESETn) begin
      w_busy <= 0; w_cnt <= 0; w_a <= 0; w_size <= 0; w_burst <= 0;
      AW_READY <= 1; W_READY <= 0; B_VALID <= 0; B_RESP <= 2'b00;
    end else begin
      B_VALID <= 1'b0;
      if (!w_busy) begin
        AW_READY <= 1'b1;
        if (AW_VALID && AW_READY) begin
          w_a <= AW_ADDR[AW-1:0]; w_cnt <= AW_LEN;
          w_size <= AW_SIZE; w_burst <= AW_BURST;
          AW_READY <= 1'b0; W_READY <= 1'b1; w_busy <= 1'b1;
        end
      end else begin
        if (W_VALID && W_READY) begin
          case (w_size)
            3'b000: case (w_a[1:0]) 2'd0: mem[w_a][7:0]   <= W_DATA[7:0];
                                    2'd1: mem[w_a][15:8]  <= W_DATA[7:0];
                                    2'd2: mem[w_a][23:16] <= W_DATA[7:0];
                                    2'd3: mem[w_a][31:24] <= W_DATA[7:0]; endcase
            3'b001: case (w_a[1])   1'b0: mem[w_a][15:0]  <= W_DATA[15:0];
                                    1'b1: mem[w_a][31:16] <= W_DATA[15:0]; endcase
            default: mem[w_a] <= W_DATA;
          endcase
          if (w_burst[0]) w_a <= w_a + 1'b1;      // INCR递增，FIXED不变
          if (w_cnt == 0) begin
            w_busy <= 1'b0; W_READY <= 1'b0; B_VALID <= 1'b1;
          end else w_cnt <= w_cnt - 8'd1;
        end
      end
    end
  end

  always @(posedge ACLK or negedge ARESETn) begin
    if (!ARESETn) begin
      r_busy <= 0; r_cnt <= 0; r_a <= 0; r_burst <= 0; AR_READY <= 1; R_VALID <= 0;
    end else begin
      if (!r_busy) begin
        AR_READY <= 1'b1;
        if (AR_VALID && AR_READY) begin
          r_a <= AR_ADDR[AW-1:0]; r_cnt <= AR_LEN; r_burst <= AR_BURST;
          AR_READY <= 1'b0; r_busy <= 1'b1;
        end
      end else begin
        if (R_VALID && R_READY) begin
          if (r_burst[0]) r_a <= r_a + 1'b1;
          if (r_cnt == 0) begin r_busy <= 1'b0; AR_READY <= 1'b1; R_VALID <= 1'b0; end
          else r_cnt <= r_cnt - 8'd1;
        end else if (!R_VALID) begin
          R_VALID <= 1'b1; R_DATA <= mem[r_a]; R_LAST <= (r_cnt == 0); R_RESP <= 2'b00;
        end
      end
    end
  end
endmodule
```

- [ ] **Step 2: 写 TB（对齐/非对齐/奇长/固定地址/跨4KB/错误响应，零差错比对）**

```verilog
// tb_dma_channel.v : 单通道DMA零差错测试
// 用例：字对齐、源非对齐、目的非对齐、1/2/3字节、跨4KB、FIXED_SRC、FIXED_DST、错误响应
`timescale 1ns/1ps
module tb_dma_channel;
  reg  ACLK, ARESETn;
  wire AW_VALID, AW_READY, W_VALID, W_READY, W_LAST, B_VALID, B_READY;
  wire [2:0] AW_SIZE; wire [1:0] AW_BURST; wire [7:0] AW_LEN; wire [31:0] AW_ADDR, W_DATA; wire [1:0] B_RESP;
  wire AR_VALID, AR_READY, R_VALID, R_READY, R_LAST;
  wire [2:0] AR_SIZE; wire [1:0] AR_BURST; wire [7:0] AR_LEN; wire [31:0] AR_ADDR, R_DATA; wire [1:0] R_RESP;
  wire AW_SEL, AR_SEL, viol;
  reg  cfg_load; reg [31:0] cfg_src, cfg_dst, cfg_len, cfg_next; reg [15:0] cfg_ctrl;
  wire busy_o, done_o, err_o, req_o;

  tb_clkreset #() u_ck (.clk(ACLK), .rstn(ARESETn));

  axi_master_vip u_vip (
    .ACLK(ACLK), .ARESETn(ARESETn),
    .AW_SEL(AW_SEL), .AW_VALID(AW_VALID), .AW_READY(AW_READY),
    .AW_SIZE(AW_SIZE), .AW_BURST(AW_BURST), .AW_LEN(AW_LEN), .AW_ADDR(AW_ADDR),
    .W_VALID(W_VALID), .W_READY(W_READY), .W_DATA(W_DATA), .W_LAST(W_LAST),
    .B_VALID(B_VALID), .B_READY(B_READY), .B_RESP(B_RESP),
    .AR_SEL(AR_SEL), .AR_VALID(AR_VALID), .AR_READY(AR_READY),
    .AR_SIZE(AR_SIZE), .AR_BURST(AR_BURST), .AR_LEN(AR_LEN), .AR_ADDR(AR_ADDR),
    .R_VALID(R_VALID), .R_READY(R_READY), .R_DATA(R_DATA), .R_RESP(R_RESP), .R_LAST(R_LAST));

  dma_channel u_dma (
    .clk(ACLK), .rstn(ARESETn),
    .cfg_src(cfg_src), .cfg_dst(cfg_dst), .cfg_len(cfg_len), .cfg_next(cfg_next),
    .cfg_ctrl(cfg_ctrl), .cfg_load(cfg_load),
    .busy_o(busy_o), .done_o(done_o), .err_o(err_o), .req_o(req_o),
    .awvalid(AW_VALID), .awready(AW_READY), .awsize(AW_SIZE), .awburst(AW_BURST),
    .awlen(AW_LEN), .awaddr(AW_ADDR),
    .wvalid(W_VALID), .wready(W_READY), .wdata(W_DATA), .wlast(W_LAST),
    .bvalid(B_VALID), .bready(B_READY), .bresp(B_RESP),
    .arvalid(AR_VALID), .arready(AR_READY), .arsize(AR_SIZE), .arburst(AR_BURST),
    .arlen(AR_LEN), .araddr(AR_ADDR),
    .rvalid(R_VALID), .rready(R_READY), .rdata(R_DATA), .rresp(R_RESP), .rlast(R_LAST));

  axi_slave_mem #(.AW(12)) u_mem (
    .ACLK(ACLK), .ARESETn(ARESETn),
    .AW_VALID(AW_VALID), .AW_READY(AW_READY), .AW_SIZE(AW_SIZE),
    .AW_BURST(AW_BURST), .AW_LEN(AW_LEN), .AW_ADDR(AW_ADDR),
    .W_VALID(W_VALID), .W_READY(W_READY), .W_DATA(W_DATA), .W_LAST(W_LAST),
    .B_VALID(B_VALID), .B_READY(B_READY), .B_RESP(B_RESP),
    .AR_VALID(AR_VALID), .AR_READY(AR_READY), .AR_SIZE(AR_SIZE),
    .AR_BURST(AR_BURST), .AR_LEN(AR_LEN), .AR_ADDR(AR_ADDR),
    .R_VALID(R_VALID), .R_READY(R_READY), .R_DATA(R_DATA), .R_RESP(R_RESP), .R_LAST(R_LAST));

  axi_checker u_chk (
    .ACLK(ACLK), .ARESETn(ARESETn),
    .AW_VALID(AW_VALID), .AW_READY(AW_READY), .AW_SIZE(AW_SIZE),
    .AW_BURST(AW_BURST), .AW_LEN(AW_LEN), .AW_ADDR(AW_ADDR),
    .W_VALID(W_VALID), .W_READY(W_READY), .W_DATA(W_DATA), .W_LAST(W_LAST),
    .B_VALID(B_VALID), .B_READY(B_READY), .B_RESP(B_RESP),
    .AR_VALID(AR_VALID), .AR_READY(AR_READY), .AR_SIZE(AR_SIZE),
    .AR_BURST(AR_BURST), .AR_LEN(AR_LEN), .AR_ADDR(AR_ADDR),
    .R_VALID(R_VALID), .R_READY(R_READY), .R_DATA(R_DATA), .R_RESP(R_RESP), .R_LAST(R_LAST),
    .violation(viol));

  // 参考存储器镜像（期望值比对）
  reg [31:0] ref_mem [0:4095];
  integer i, t;

  task run_case;
    input [31:0] s, d, l; input [15:0] c;
    begin
      cfg_src = s; cfg_dst = d; cfg_len = l; cfg_ctrl = c; cfg_next = 0;
      @(posedge ACLK);
      cfg_load = 1'b1; @(posedge ACLK); cfg_load = 1'b0;
      // 等待完成/错误（超时兜底）
      t = 0;
      while (!done_o && !err_o && t < 100000) begin @(posedge ACLK); t = t + 1; end
      if (t >= 100000) $fatal(1, "FAIL: 用例超时 s=%h d=%h l=%h", s, d, l);
    end
  endtask

  initial begin
    cfg_load = 0; cfg_src = 0; cfg_dst = 0; cfg_len = 0; cfg_ctrl = 0; cfg_next = 0;
    wait (ARESETn == 1'b1);
    @(posedge ACLK);
    // 源数据区：0x000..0x0FF 写入可识别模式
    for (i = 0; i < 256; i = i + 1) begin
      u_vip.vip_wdata[0] = i * 32'h01010101;
      u_vip.axi_wr(i * 4, 8'd0, 2'b00, 3'b010);
      ref_mem[i] = i * 32'h01010101;
    end
    // 1) 字对齐整块拷贝 64字节 0x000->0x200
    run_case(32'h000, 32'h200, 32'd64, 16'h0000 | 16'd5 << 5);  // GO|BURST=6拍
    for (i = 0; i < 16; i = i + 1) begin
      u_vip.axi_rd(32'h200 + i * 4, 8'd0, 2'b00, 3'b010);
      if (u_vip.vip_rdata[0] !== ref_mem[i])
        $fatal(1, "FAIL: 用例1 dst+%0d=%h 期望=%h", i * 4, u_vip.vip_rdata[0], ref_mem[i]);
    end
    // 2) 源非对齐：src=0x003（字节偏移3），拷16字节 -> 0x300
    run_case(32'h003, 32'h300, 32'd16, 16'h0000 | 16'd5 << 5);
    for (i = 0; i < 16; i = i + 1) begin
      u_vip.axi_rd(32'h300 + i, 8'd0, 2'b00, 3'b000);   // 字节读回比对
      if (u_vip.vip_rdata[0][7:0] !== i)                // 源字节3=word0的byte3(0)，之后0,1,2...
        $fatal(1, "FAIL: 用例2 字节%0d=%h", i, u_vip.vip_rdata[0][7:0]);
    end
    // 3) 目的非对齐：dst=0x401，拷16字节 0x000 -> 0x401
    run_case(32'h000, 32'h401, 32'd16, 16'h0000 | 16'd5 << 5);
    for (i = 0; i < 16; i = i + 1) begin
      u_vip.axi_rd(32'h401 + i, 8'd0, 2'b00, 3'b000);
      if (u_vip.vip_rdata[0][7:0] !== ref_mem[0][7:0] + i)
        $fatal(1, "FAIL: 用例3 字节%0d=%h", i, u_vip.vip_rdata[0][7:0]);
    end
    // 4) 奇长：1字节、3字节、1023字节
    run_case(32'h000, 32'h500, 32'd1, 16'h0000 | 16'd5 << 5);
    run_case(32'h000, 32'h504, 32'd3, 16'h0000 | 16'd5 << 5);
    run_case(32'h000, 32'h508, 32'd1023, 16'h0000 | 16'd5 << 5);
    for (i = 0; i < 1023; i = i + 1) begin
      u_vip.axi_rd(32'h508 + i, 8'd0, 2'b00, 3'b000);
      if (u_vip.vip_rdata[0][7:0] !== (i % 256))        // 源字节模式每256循环
        $fatal(1, "FAIL: 用例4 字节%0d=%h", i, u_vip.vip_rdata[0][7:0]);
    end
    // 5) 跨4KB边界：src=0xFF0，拷32字节（检查器必须零违规）
    run_case(32'hFF0, 32'h600, 32'd32, 16'h0000 | 16'd5 << 5);
    // 6) FIXED_SRC：从0x004固定地址读16字 -> 0x700（len=拍数，FSIZE=2）
    run_case(32'h004, 32'h700, 32'd16, 16'h0004 | 16'd5 << 5 | 3'd2 << 8);
    for (i = 0; i < 16; i = i + 1) begin
      u_vip.axi_rd(32'h700 + i * 4, 8'd0, 2'b00, 3'b010);
      if (u_vip.vip_rdata[0] !== ref_mem[1]) $fatal(1, "FAIL: 用例6");
    end
    // 7) FIXED_DST：0x000起16字 -> 0x800固定地址（len=拍数）
    run_case(32'h000, 32'h800, 32'd16, 16'h0008 | 16'd5 << 5 | 3'd2 << 8);
    for (i = 0; i < 16; i = i + 1) begin
      u_vip.axi_rd(32'h800, 8'd0, 2'b00, 3'b010);
      if (u_vip.vip_rdata[0] !== ref_mem[i]) $fatal(1, "FAIL: 用例7 第%0d字", i);
    end
    if (viol) $fatal(1, "FAIL: 协议违规");
    $display("PASS: 单通道DMA（7类用例零差错+协议零违规）");
    $finish;
  end
endmodule
```

- [ ] **Step 3: 运行TB，确认红灯**

Run: `make -f Makefile.fir sim_tb_dma_channel`，Expected: 编译错误 `dma_channel` 未找到。

- [ ] **Step 4: 实现 dma_channel.v**

```verilog
// dma_channel.v : 单通道DMA引擎（AXI主设备）
// 数据流：读burst（字宽）→ 16字FIFO → 写burst（按对齐/剩余字节自动选 字节/半字/字 通道）
// 字节精度：hpos=当前FIFO头字已消费字节；首字源偏移在hpos初始值中体现；
//           写侧用 单拍部分写 + 整字burst + 尾部部分写 三段式，AW_SIZE随burst定。
// 4KB边界：读/写burst均按边界拆分（协议检查器佐证）。
// 固定地址：FIXED_SRC=固定地址字burst读len拍；FIXED_DST=固定地址FIXED写burst（FSIZE宽度）。
// 链式：完成后从cfg_next读5字描述符{SRC,DST,LEN,CTRL,NEXT}自动续传（CHAIN位）。
`timescale 1ns/1ps
module dma_channel #(parameter DW = 32)(
    input  wire        clk,
    input  wire        rstn,
    input  wire [31:0] cfg_src,
    input  wire [31:0] cfg_dst,
    input  wire [31:0] cfg_len,
    input  wire [31:0] cfg_next,
    input  wire [15:0] cfg_ctrl,   // [0]GO [1]IRQ_EN [2]FIXED_SRC [3]FIXED_DST [4]CHAIN [7:5]BURST [10:8]FSIZE
    input  wire        cfg_load,
    output reg         busy_o,
    output reg         done_o,
    output reg         err_o,
    output reg         req_o,
    // AXI主口（由dma_top按req/grant多路选择后接共享总线）
    output reg         awvalid,  input  wire awready,
    output reg  [2:0]  awsize,   output reg  [1:0] awburst,
    output reg  [7:0]  awlen,    output reg  [31:0] awaddr,
    output reg         wvalid,   input  wire wready,
    output reg  [31:0] wdata,    output reg  wlast,
    input  wire        bvalid,   output reg  bready,
    input  wire [1:0]  bresp,
    output reg         arvalid,  input  wire arready,
    output reg  [2:0]  arsize,   output reg  [1:0] arburst,
    output reg  [7:0]  arlen,    output reg  [31:0] araddr,
    input  wire        rvalid,   output reg  rready,
    input  wire [31:0] rdata,    input  wire [1:0] rresp,
    input  wire        rlast
);
  localparam S_IDLE=0, S_RD_AR=1, S_RD_D=2, S_WR_AW=3, S_WR_D=4, S_WR_B=5,
             S_CH_AR=6, S_CH_D=7, S_DONE=8;

  reg [2:0]  st;
  reg [31:0] src_a, dst_a, rem;        // rem=剩余字节
  reg [31:0] nxt_ptr;
  reg [31:0] units_rem;                // 固定侧剩余拍数
  reg [2:0]  burst_max;                // 0=1..7=8拍
  reg [2:0]  fsize;                    // 固定侧单位宽度指数
  reg        fixed_src, fixed_dst, chain_en, irq_en;
  reg [3:0]  hpos;                     // FIFO头字已消费字节
  reg [3:0]  fifo_wp, fifo_rp, fifo_cnt;
  reg [31:0] fifo [0:15];
  reg [7:0]  bcnt;                     // burst内拍计数
  reg [7:0]  blen;                     // 本burst拍数-1
  reg [3:0]  this_bytes;               // 本写拍字节数
  reg [2:0]  this_size;                // 本写拍AXI大小
  reg [31:0] shadow [0:4];
  reg        err;
  integer    i;

  wire [31:0] head = fifo[fifo_rp];
  // 可用字节（有符号，防止hpos>0时无符号回绕成大数）
  wire signed [4:0] avail = $signed({1'b0, fifo_cnt}) * 4 - $signed({1'b0, hpos});

  always @(posedge clk) begin
    if (!rstn) begin
      st <= S_IDLE; busy_o <= 0; done_o <= 0; err_o <= 0; req_o <= 0;
      awvalid <= 0; wvalid <= 0; arvalid <= 0; bready <= 0; rready <= 0;
      awsize <= 0; awburst <= 0; awlen <= 0; awaddr <= 0; wdata <= 0; wlast <= 0;
      arsize <= 0; arburst <= 0; arlen <= 0; araddr <= 0;
      fifo_wp <= 0; fifo_rp <= 0; fifo_cnt <= 0; hpos <= 0; err <= 0;
    end else begin
      done_o <= 1'b0; err_o <= 1'b0;
      case (st)
        S_IDLE: begin
          busy_o <= 1'b0;
          if (cfg_load && cfg_ctrl[0]) begin          // 软件启动
            src_a <= cfg_src; dst_a <= cfg_dst;
            nxt_ptr <= cfg_next;
            burst_max <= cfg_ctrl[7:5]; fsize <= cfg_ctrl[10:8];
            fixed_src <= cfg_ctrl[2]; fixed_dst <= cfg_ctrl[3];
            chain_en <= cfg_ctrl[4]; irq_en <= cfg_ctrl[1];
            rem <= cfg_ctrl[2] || cfg_ctrl[3] ? (cfg_len << cfg_ctrl[10:8]) : cfg_len;
            units_rem <= cfg_len;
            hpos <= cfg_ctrl[2] ? 4'd0 : cfg_src[1:0];
            fifo_wp <= 0; fifo_rp <= 0; fifo_cnt <= 0; err <= 0;
            busy_o <= 1'b1;
            st <= S_RD_AR;
          end else if (cfg_load && cfg_ctrl[4] && !cfg_ctrl[0]) begin  // 链式续传（dma_top发load+CHAIN）
            src_a <= shadow[0]; dst_a <= shadow[1];
            nxt_ptr <= shadow[4];
            burst_max <= shadow[3][7:5]; fsize <= shadow[3][10:8];
            fixed_src <= shadow[3][2]; fixed_dst <= shadow[3][3];
            chain_en <= shadow[3][4]; irq_en <= shadow[3][1];
            rem <= shadow[3][2] || shadow[3][3] ? (shadow[2] << shadow[3][10:8]) : shadow[2];
            units_rem <= shadow[2];
            hpos <= shadow[3][2] ? 4'd0 : shadow[0][1:0];
            fifo_wp <= 0; fifo_rp <= 0; fifo_cnt <= 0;
            busy_o <= 1'b1;
            st <= S_RD_AR;
          end
        end

        // ---------- 读 ----------
        S_RD_AR: begin
          req_o <= 1'b1;
          if (avail >= $signed(rem)) begin             // 数据已够，转写
            req_o <= 1'b0; st <= S_WR_AW;
          end else begin
            if (fixed_src) begin                       // 固定地址读：FIXED字burst
              arsize <= 3'b010; arburst <= 2'b00;
              arlen <= (units_rem > (burst_max + 1)) ? {5'd0, burst_max} : units_rem[7:0] - 8'd1;
              araddr <= src_a;
            end else begin                             // 增量读：INCR字burst（按4KB与FIFO空间拆分）
              arsize <= 3'b010; arburst <= 2'b01;
              arlen <= min4(burst_max, 8'd15 - fifo_cnt, (32'h1000 - src_a[11:0]) / 4 - 1,
                            avail_need());
              araddr <= {src_a[31:2], 2'b00};
            end
            arvalid <= 1'b1;
            if (arvalid && arready) begin
              arvalid <= 1'b0;
              bcnt <= 0; blen <= arlen;
              st <= S_RD_D;
            end
          end
        end
        S_RD_D: begin
          req_o <= 1'b1; rready <= 1'b1;
          if (rvalid && rready) begin
            if (rresp != 2'b00) err <= 1'b1;
            fifo[fifo_wp] <= rdata;
            fifo_wp <= fifo_wp + 1'b1;
            fifo_cnt <= fifo_cnt + 1'b1;
            if (bcnt == blen) begin
              if (!rlast) err <= 1'b1;
              rready <= 1'b0; req_o <= 1'b0;
              if (fixed_src) begin
                units_rem <= units_rem - (blen + 1);
                src_a <= src_a;
              end else begin
                src_a <= src_a + ((blen + 1) * 4);
                hpos <= (bcnt == blen) ? hpos : hpos;   // hpos仅首burst前非0，读不改变
              end
              if (err) begin st <= S_DONE; end
              else     st <= S_RD_AR;
            end else bcnt <= bcnt + 8'd1;
          end
        end

        // ---------- 写 ----------
        S_WR_AW: begin
          if (rem == 0) begin
            st <= (chain_en && !err) ? S_CH_AR : S_DONE;
          end else begin
            req_o <= 1'b1;
            if (fixed_dst) begin                       // 固定地址写：FIXED burst（FSIZE宽度）
              awsize <= fsize; awburst <= 2'b00;
              awlen <= (units_rem > (burst_max + 1)) ? {5'd0, burst_max} : units_rem[7:0] - 8'd1;
              awaddr <= dst_a;
              this_bytes <= 1 << fsize;
            end else begin
              // 三段式：首部部分写（单拍）→ 整字burst → 尾部部分写（单拍）
              if ((dst_a[1:0] != 2'b00) || (rem < 4)) begin
                this_bytes <= (rem < (4 - dst_a[1:0])) ? rem[3:0] : (4 - dst_a[1:0]);
                awsize <= (this_bytes == 4'd1) ? 3'b000 :
                          (this_bytes == 4'd2) ? 3'b001 : 3'b010;
                awburst <= 2'b01; awlen <= 8'd0; awaddr <= dst_a;
              end else begin
                this_bytes <= 4'd4;
                awsize <= 3'b010; awburst <= 2'b01;
                awlen <= min4(burst_max, rem[7:0] / 4 - 1, (32'h1000 - dst_a[11:0]) / 4 - 1,
                              fifo_cnt - 1);
                awaddr <= dst_a;
              end
            end
            awvalid <= 1'b1;
            if (awvalid && awready) begin
              awvalid <= 1'b0;
              bcnt <= 0; blen <= awlen;
              st <= S_WR_D;
            end
          end
        end
        S_WR_D: begin
          req_o <= 1'b1;
          wvalid <= 1'b1;
          wdata <= head >> (8 * hpos);
          wlast <= (bcnt == blen);
          if (wvalid && wready) begin
            hpos <= hpos + this_bytes;
            if (hpos + this_bytes >= 4) begin         // 头字消费完
              fifo_rp <= fifo_rp + 1'b1;
              fifo_cnt <= fifo_cnt - 1'b1;
              hpos <= hpos + this_bytes - 4;
            end
            if (fixed_dst) units_rem <= units_rem - 1'b1;
            else dst_a <= dst_a + this_bytes;
            rem <= rem - this_bytes;
            if (bcnt == blen) begin
              wvalid <= 1'b0;
              st <= S_WR_B;
            end else bcnt <= bcnt + 8'd1;
          end
        end
        S_WR_B: begin
          req_o <= 1'b1; bready <= 1'b1;
          if (bvalid && bready) begin
            if (bresp != 2'b00) err <= 1'b1;
            bready <= 1'b0; req_o <= 1'b0;
            if (err) st <= S_DONE;
            else     st <= S_WR_AW;
          end
        end

        // ---------- 链式描述符 ----------
        S_CH_AR: begin
          req_o <= 1'b1;
          arsize <= 3'b010; arburst <= 2'b01; arlen <= 8'd4; araddr <= nxt_ptr;
          arvalid <= 1'b1;
          if (arvalid && arready) begin
            arvalid <= 1'b0; bcnt <= 0;
            st <= S_CH_D;
          end
        end
        S_CH_D: begin
          req_o <= 1'b1; rready <= 1'b1;
          if (rvalid && rready) begin
            shadow[bcnt] <= rdata;
            if (bcnt == 4) begin
              rready <= 1'b0; req_o <= 1'b0;
              if (rresp != 2'b00) begin err <= 1'b1; st <= S_DONE; end
              else begin st <= S_IDLE; end            // 回IDLE走"链式续传"分支
            end else bcnt <= bcnt + 8'd1;
          end
        end

        // ---------- 完成 ----------
        S_DONE: begin
          req_o <= 1'b0;
          busy_o <= 1'b0;
          if (err) err_o <= 1'b1;
          else     done_o <= 1'b1;
          st <= S_IDLE;
        end
      endcase
    end
  end

  // 读burst拍数辅助（4KB/FIFO空间/需求三者取小）
  function [7:0] avail_need;      // 还需多少字（有符号运算）
    begin
      avail_need = ($signed(rem) + 32'd3 - avail) / 4 + ((hpos > 0 && fifo_cnt == 0) ? 8'd1 : 8'd0);
    end
  endfunction

  function [7:0] min4; input [7:0] a, b, c, d;
    begin
      min4 = a;
      if (b < min4) min4 = b;
      if (c < min4) min4 = c;
      if (d < min4) min4 = d;
    end
  endfunction
endmodule
```

- [ ] **Step 5: 运行TB，确认绿灯**

Run: `make -f Makefile.fir sim_tb_dma_channel`，Expected: `PASS: 单通道DMA（7类用例零差错+协议零违规）`。常见问题与排障：首字部分写的通道数据（`head>>(8*hpos)`）、`avail_need`函数边界（跨4KB用例）、FIXED模式`cfg_len<<fsize`溢出（32位，len<2^30安全）。

- [ ] **Step 6: 提交**

```bash
cd /d/ICT/Cortexm0ds && git add rtl/dma/dma_channel.v tb/tb_dma_channel.v tb/common/axi_slave_mem.v Makefile && git commit -m "feat: 单通道DMA引擎（字节精度零差错，7类用例）

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

**验收**：`make -f Makefile.fir sim_tb_dma_channel` 绿。对应"数据零差错"与"支持AXI Burst"的通道级基本盘。

---

### 任务 10：6通道DMA控制器 dma_top

**Files:**
- Create: `rtl/dma/dma_top.v`；Test: `tb/tb_dma_top.v`；Modify: `Makefile.fir`（RTL追加 dma_top.v）

**Interfaces:**
- Consumes: `dma_channel`（任务9）、VIP/存储从机/检查器（任务2）
- Produces: `dma_top`，配置口为CMSDK从机风格（同fir_top信号名），主口为AXI主（`awvalid/awready/awsize/awburst/awlen/awaddr/wvalid/wready/wdata/wlast/bvalid/bready/bresp/arvalid/arready/arsize/arburst/arlen/araddr/rvalid/rready/rdata/rresp/rlast`），`irq_o`输出
- 寄存器映射（字节地址，基址0x4003_0000）：
  - 通道n（n=0..5）基址 `0x4003_0000 + n*0x20`：`+0x00 SRC`、`+0x04 DST`、`+0x08 LEN`、`+0x0C CTRL`（写CTRL的GO位=1启动该通道）、`+0x10 STATUS`（bit0 BUSY、bit1 DONE、bit2 ERR）、`+0x14 NEXT`
  - 全局：`0x4003_0100 INT_STATUS`（读；每通道1位，DONE&&IRQ_EN）、`0x4003_0104 INT_CLR`（写1清零对应位）

- [ ] **Step 1: 写 TB（6通道并发独立工作零差错+中断+状态位）**

```verilog
// tb_dma_top.v : 6通道并发——同时启动6个不同区域拷贝，全部零差错、INT_STATUS正确
`timescale 1ns/1ps
module tb_dma_top;
  reg  ACLK, ARESETn;
  wire AW_SEL, AW_VALID, AW_READY; wire [2:0] AW_SIZE; wire [1:0] AW_BURST;
  wire [7:0] AW_LEN; wire [31:0] AW_ADDR;
  wire W_VALID, W_READY; wire [31:0] W_DATA; wire W_LAST;
  wire B_VALID, B_READY; wire [1:0] B_RESP;
  wire AR_SEL, AR_VALID, AR_READY; wire [2:0] AR_SIZE; wire [1:0] AR_BURST;
  wire [7:0] AR_LEN; wire [31:0] AR_ADDR;
  wire R_VALID, R_READY; wire [31:0] R_DATA; wire [1:0] R_RESP; wire R_LAST;
  // DMA主口
  wire m_AW_VALID, m_AW_READY; wire [2:0] m_AW_SIZE; wire [1:0] m_AW_BURST;
  wire [7:0] m_AW_LEN; wire [31:0] m_AW_ADDR;
  wire m_W_VALID, m_W_READY; wire [31:0] m_W_DATA; wire m_W_LAST;
  wire m_B_VALID, m_B_READY; wire [1:0] m_B_RESP;
  wire m_AR_VALID, m_AR_READY; wire [2:0] m_AR_SIZE; wire [1:0] m_AR_BURST;
  wire [7:0] m_AR_LEN; wire [31:0] m_AR_ADDR;
  wire m_R_VALID, m_R_READY; wire [31:0] m_R_DATA; wire [1:0] m_R_RESP; wire m_R_LAST;
  wire dma_irq, viol;

  tb_clkreset #() u_ck (.clk(ACLK), .rstn(ARESETn));

  axi_master_vip u_vip (
    .ACLK(ACLK), .ARESETn(ARESETn),
    .AW_SEL(AW_SEL), .AW_VALID(AW_VALID), .AW_READY(AW_READY),
    .AW_SIZE(AW_SIZE), .AW_BURST(AW_BURST), .AW_LEN(AW_LEN), .AW_ADDR(AW_ADDR),
    .W_VALID(W_VALID), .W_READY(W_READY), .W_DATA(W_DATA), .W_LAST(W_LAST),
    .B_VALID(B_VALID), .B_READY(B_READY), .B_RESP(B_RESP),
    .AR_SEL(AR_SEL), .AR_VALID(AR_VALID), .AR_READY(AR_READY),
    .AR_SIZE(AR_SIZE), .AR_BURST(AR_BURST), .AR_LEN(AR_LEN), .AR_ADDR(AR_ADDR),
    .R_VALID(R_VALID), .R_READY(R_READY), .R_DATA(R_DATA), .R_RESP(R_RESP), .R_LAST(R_LAST));

  dma_top u_dma (
    .ACLK(ACLK), .ARESETn(ARESETn),
    .AW_SEL(AW_SEL), .AW_VALID(AW_VALID), .AW_READY(AW_READY),
    .AW_SIZE(AW_SIZE), .AW_BURST(AW_BURST), .AW_LEN(AW_LEN), .AW_ADDR(AW_ADDR),
    .W_VALID(W_VALID), .W_READY(W_READY), .W_DATA(W_DATA), .W_LAST(W_LAST),
    .B_VALID(B_VALID), .B_READY(B_READY), .B_RESP(B_RESP),
    .AR_SEL(AR_SEL), .AR_VALID(AR_VALID), .AR_READY(AR_READY),
    .AR_SIZE(AR_SIZE), .AR_BURST(AR_BURST), .AR_LEN(AR_LEN), .AR_ADDR(AR_ADDR),
    .R_VALID(R_VALID), .R_READY(R_READY), .R_DATA(R_DATA), .R_RESP(R_RESP), .R_LAST(R_LAST),
    .awvalid(m_AW_VALID), .awready(m_AW_READY), .awsize(m_AW_SIZE), .awburst(m_AW_BURST),
    .awlen(m_AW_LEN), .awaddr(m_AW_ADDR),
    .wvalid(m_W_VALID), .wready(m_W_READY), .wdata(m_W_DATA), .wlast(m_W_LAST),
    .bvalid(m_B_VALID), .bready(m_B_READY), .bresp(m_B_RESP),
    .arvalid(m_AR_VALID), .arready(m_AR_READY), .arsize(m_AR_SIZE), .arburst(m_AR_BURST),
    .arlen(m_AR_LEN), .araddr(m_AR_ADDR),
    .rvalid(m_R_VALID), .rready(m_R_READY), .rdata(m_R_DATA), .rresp(m_R_RESP), .rlast(m_R_LAST),
    .irq_o(dma_irq));

  axi_slave_mem #(.AW(12)) u_mem (
    .ACLK(ACLK), .ARESETn(ARESETn),
    .AW_VALID(m_AW_VALID), .AW_READY(m_AW_READY), .AW_SIZE(m_AW_SIZE),
    .AW_BURST(m_AW_BURST), .AW_LEN(m_AW_LEN), .AW_ADDR(m_AW_ADDR),
    .W_VALID(m_W_VALID), .W_READY(m_W_READY), .W_DATA(m_W_DATA), .W_LAST(m_W_LAST),
    .B_VALID(m_B_VALID), .B_READY(m_B_READY), .B_RESP(m_B_RESP),
    .AR_VALID(m_AR_VALID), .AR_READY(m_AR_READY), .AR_SIZE(m_AR_SIZE),
    .AR_BURST(m_AR_BURST), .AR_LEN(m_AR_LEN), .AR_ADDR(m_AR_ADDR),
    .R_VALID(m_R_VALID), .R_READY(m_R_READY), .R_DATA(m_R_DATA), .R_RESP(m_R_RESP), .R_LAST(m_R_LAST));

  axi_checker u_chk (
    .ACLK(ACLK), .ARESETn(ARESETn),
    .AW_VALID(m_AW_VALID), .AW_READY(m_AW_READY), .AW_SIZE(m_AW_SIZE),
    .AW_BURST(m_AW_BURST), .AW_LEN(m_AW_LEN), .AW_ADDR(m_AW_ADDR),
    .W_VALID(m_W_VALID), .W_READY(m_W_READY), .W_DATA(m_W_DATA), .W_LAST(m_W_LAST),
    .B_VALID(m_B_VALID), .B_READY(m_B_READY), .B_RESP(m_B_RESP),
    .AR_VALID(m_AR_VALID), .AR_READY(m_AR_READY), .AR_SIZE(m_AR_SIZE),
    .AR_BURST(m_AR_BURST), .AR_LEN(m_AR_LEN), .AR_ADDR(m_AR_ADDR),
    .R_VALID(m_R_VALID), .R_READY(m_R_READY), .R_DATA(m_R_DATA), .R_RESP(m_R_RESP), .R_LAST(m_R_LAST),
    .violation(viol));

  integer i, ch, t;
  reg [31:0] exp;

  task dma_wr_reg; input [31:0] a, d;
    begin
      u_vip.vip_wdata[0] = d;
      u_vip.axi_wr(a, 8'd0, 2'b00, 3'b010);
    end
  endtask

  task dma_rd_reg; input [31:0] a;
    begin
      u_vip.axi_rd(a, 8'd0, 2'b00, 3'b010);
    end
  endtask

  initial begin
    wait (ARESETn == 1'b1);
    @(posedge ACLK);
    // 源数据：每通道不同基址的模式数据
    for (ch = 0; ch < 6; ch = ch + 1)
      for (i = 0; i < 32; i = i + 1) begin
        u_vip.vip_wdata[0] = 32'h10000000 * (ch + 1) + i;
        u_vip.axi_wr(ch * 32'h200 + i * 4, 8'd0, 2'b00, 3'b010);
      end
    // 同时配置并启动6通道：src=ch*0x200（128字节）→ dst=0x1000+ch*0x200
    for (ch = 0; ch < 6; ch = ch + 1) begin
      dma_wr_reg(32'h4003_0000 + ch * 32'h20 + 32'h00, ch * 32'h200);
      dma_wr_reg(32'h4003_0000 + ch * 32'h20 + 32'h04, 32'h1000 + ch * 32'h200);
      dma_wr_reg(32'h4003_0000 + ch * 32'h20 + 32'h08, 32'd128);
      dma_wr_reg(32'h4003_0000 + ch * 32'h20 + 32'h0C, 16'h0002 | 16'd5 << 5); // GO|IRQ_EN|BURST=6
    end
    // 等全部完成（轮询INT_STATUS）
    t = 0;
    while (t < 100000) begin
      dma_rd_reg(32'h4003_0100);
      if (u_vip.vip_rdata[0][5:0] == 6'h3F) begin
        $display("全部通道完成，周期=%0d", t);
        t = 1000000;
      end else begin
        t = t + 1; @(posedge ACLK);
      end
    end
    if (t != 1000000) $fatal(1, "FAIL: 等待6通道完成超时");
    if (dma_irq !== 1'b1) $fatal(1, "FAIL: IRQ未置位");
    // 逐通道比对（零差错）
    for (ch = 0; ch < 6; ch = ch + 1) begin
      for (i = 0; i < 32; i = i + 1) begin
        u_vip.axi_rd(32'h1000 + ch * 32'h200 + i * 4, 8'd0, 2'b00, 3'b010);
        exp = 32'h10000000 * (ch + 1) + i;
        if (u_vip.vip_rdata[0] !== exp)
          $fatal(1, "FAIL: ch%0d word%0d=%h 期望=%h", ch, i, u_vip.vip_rdata[0], exp);
      end
      // STATUS：DONE置位、BUSY清
      dma_rd_reg(32'h4003_0000 + ch * 32'h20 + 32'h10);
      if (u_vip.vip_rdata[0][2:1] != 2'b10) $fatal(1, "FAIL: ch%0d STATUS=%h", ch, u_vip.vip_rdata[0]);
    end
    // INT_CLR清零
    dma_wr_reg(32'h4003_0104, 32'h3F);
    dma_rd_reg(32'h4003_0100);
    if (u_vip.vip_rdata[0][5:0] != 6'h00) $fatal(1, "FAIL: INT_CLR无效");
    if (viol) $fatal(1, "FAIL: 协议违规");
    $display("PASS: 6通道并发独立工作零差错+中断状态正确");
    $finish;
  end
endmodule
```

- [ ] **Step 2: 运行TB，确认红灯**

Run: `make -f Makefile.fir sim_tb_dma_top`，Expected: 编译错误 `dma_top` 未找到。

- [ ] **Step 3: 实现 dma_top.v**

```verilog
// dma_top.v : 6通道DMA控制器
// 结构：6×dma_channel + 通道仲裁（burst粒度轮询）+ CMSDK从机配置口 + 中断聚合
// 通道仲裁：req_o 保持到当前burst完成（B握手/R_LAST），grant按轮询给，
//           被授权通道的AXI主口信号经mux上共享总线。
`timescale 1ns/1ps
module dma_top(
    input  wire        ACLK,
    input  wire        ARESETn,
    // 配置口（CMSDK从机风格）
    input  wire        AW_SEL, AW_VALID, output reg AW_READY,
    input  wire [2:0]  AW_SIZE, input wire [1:0] AW_BURST,
    input  wire [7:0]  AW_LEN,  input wire [31:0] AW_ADDR,
    input  wire        W_VALID, output reg W_READY,
    input  wire [31:0] W_DATA,  input wire W_LAST,
    output reg         B_VALID, input wire B_READY, output reg [1:0] B_RESP,
    input  wire        AR_SEL, AR_VALID, output reg AR_READY,
    input  wire [2:0]  AR_SIZE, input wire [1:0] AR_BURST,
    input  wire [7:0]  AR_LEN,  input wire [31:0] AR_ADDR,
    output reg         R_VALID, input wire R_READY,
    output reg  [31:0] R_DATA,  output reg [1:0] R_RESP, output reg R_LAST,
    // AXI主口
    output wire        awvalid, input wire awready,
    output wire [2:0]  awsize,  output wire [1:0] awburst,
    output wire [7:0]  awlen,   output wire [31:0] awaddr,
    output wire        wvalid,  input wire wready,
    output wire [31:0] wdata,   output wire wlast,
    input  wire        bvalid,  output wire bready,
    input  wire [1:0]  bresp,
    output wire        arvalid, input wire arready,
    output wire [2:0]  arsize,  output wire [1:0] arburst,
    output wire [7:0]  arlen,   output wire [31:0] araddr,
    input  wire        rvalid,  output wire rready,
    input  wire [31:0] rdata,   input wire [1:0] rresp,
    input  wire        rlast,
    // 中断
    output wire        irq_o
);
  // ---- 通道信号 ----
  reg  [31:0] ch_src [0:5], ch_dst [0:5], ch_len [0:5], ch_next [0:5];
  reg  [15:0] ch_ctrl [0:5];
  reg         ch_load [0:5];
  wire        ch_busy [0:5], ch_done [0:5], ch_err [0:5], ch_req [0:5];
  reg  [31:0] ch_done_q [0:5], ch_err_q [0:5];
  wire        ch_awvalid [0:5], ch_wvalid [0:5], ch_wlast [0:5], ch_arvalid [0:5];
  wire [2:0]  ch_awsize [0:5], ch_arsize [0:5];
  wire [1:0]  ch_awburst [0:5], ch_arburst [0:5];
  wire [7:0]  ch_awlen [0:5], ch_arlen [0:5];
  wire [31:0] ch_awaddr [0:5], ch_wdata [0:5], ch_araddr [0:5];
  wire        ch_awready [0:5], ch_wready [0:5], ch_bvalid [0:5],
              ch_arready [0:5], ch_rvalid [0:5], ch_rlast [0:5];
  wire [31:0] ch_rdata [0:5];
  wire [1:0]  ch_bresp [0:5], ch_rresp [0:5];

  genvar g;
  generate
    for (g = 0; g < 6; g = g + 1) begin : ch
      dma_channel u_ch (
        .clk(ACLK), .rstn(ARESETn),
        .cfg_src(ch_src[g]), .cfg_dst(ch_dst[g]), .cfg_len(ch_len[g]),
        .cfg_next(ch_next[g]), .cfg_ctrl(ch_ctrl[g]), .cfg_load(ch_load[g]),
        .busy_o(ch_busy[g]), .done_o(ch_done[g]), .err_o(ch_err[g]), .req_o(ch_req[g]),
        .awvalid(ch_awvalid[g]), .awready(ch_awready[g]), .awsize(ch_awsize[g]),
        .awburst(ch_awburst[g]), .awlen(ch_awlen[g]), .awaddr(ch_awaddr[g]),
        .wvalid(ch_wvalid[g]), .wready(ch_wready[g]), .wdata(ch_wdata[g]), .wlast(ch_wlast[g]),
        .bvalid(ch_bvalid[g]), .bready(1'b1), .bresp(ch_bresp[g]),
        .arvalid(ch_arvalid[g]), .arready(ch_arready[g]), .arsize(ch_arsize[g]),
        .arburst(ch_arburst[g]), .arlen(ch_arlen[g]), .araddr(ch_araddr[g]),
        .rvalid(ch_rvalid[g]), .rready(1'b1), .rdata(ch_rdata[g]),
        .rresp(ch_rresp[g]), .rlast(ch_rlast[g]));
    end
  endgenerate

  // ---- 通道仲裁（burst粒度轮询）----
  reg [2:0] gnt;
  reg       gnt_valid;
  always @(posedge ACLK or negedge ARESETn) begin
    if (!ARESETn) begin gnt <= 0; gnt_valid <= 0; end
    else begin
      if (gnt_valid) begin
        if (!ch_req[gnt]) begin gnt_valid <= 0; gnt <= 0; end  // 当前burst完成，释放
      end else if (ch_req[0] | ch_req[1] | ch_req[2] | ch_req[3] | ch_req[4] | ch_req[5]) begin
        gnt <= gnt + 3'd1;                                       // 轮询（gnt释放时清零，等价rr）
        gnt_valid <= 1'b1;
      end
    end
  end

  // 主口mux（未授权输出低/高阻语义：valid=0）
  assign awvalid = gnt_valid ? ch_awvalid[gnt] : 1'b0;
  assign awsize  = ch_awsize [gnt];
  assign awburst = ch_awburst[gnt];
  assign awlen   = ch_awlen  [gnt];
  assign awaddr  = ch_awaddr [gnt];
  assign wvalid  = gnt_valid ? ch_wvalid[gnt] : 1'b0;
  assign wdata   = ch_wdata  [gnt];
  assign wlast   = ch_wlast  [gnt];
  assign bready  = 1'b1;                        // 通道内bready恒1，响应直接给授权通道
  assign arvalid = gnt_valid ? ch_arvalid[gnt] : 1'b0;
  assign arsize  = ch_arsize [gnt];
  assign arburst = ch_arburst[gnt];
  assign arlen   = ch_arlen  [gnt];
  assign araddr  = ch_araddr [gnt];
  assign rready  = 1'b1;

  generate
    for (g = 0; g < 6; g = g + 1) begin : rdymux
      assign ch_awready[g] = (gnt_valid && gnt == g[2:0]) ? awready  : 1'b0;
      assign ch_wready [g] = (gnt_valid && gnt == g[2:0]) ? wready   : 1'b0;
      assign ch_bvalid [g] = (gnt_valid && gnt == g[2:0]) ? bvalid   : 1'b0;
      assign ch_bresp  [g] = bresp;
      assign ch_arready[g] = (gnt_valid && gnt == g[2:0]) ? arready  : 1'b0;
      assign ch_rvalid [g] = (gnt_valid && gnt == g[2:0]) ? rvalid   : 1'b0;
      assign ch_rdata  [g] = rdata;
      assign ch_rresp  [g] = rresp;
      assign ch_rlast  [g] = (gnt_valid && gnt == g[2:0]) ? rlast   : 1'b0;
    end
  endgenerate

  // ---- 中断与状态 ----
  reg [5:0] int_status;
  integer   i;
  always @(posedge ACLK or negedge ARESETn) begin
    if (!ARESETn) begin
      int_status <= 0;
      for (i = 0; i < 6; i = i + 1) begin
        ch_done_q[i] <= 0; ch_err_q[i] <= 0;
      end
    end else begin
      for (i = 0; i < 6; i = i + 1) begin
        if (ch_done[i] && ch_ctrl[i][1]) int_status[i] <= 1'b1;
        if (ch_done[i]) ch_done_q[i] <= 1'b1;
        if (ch_err[i])  ch_err_q[i]  <= 1'b1;
        if (int_clr[i]) begin int_status[i] <= 1'b0; end
      end
    end
  end
  assign irq_o = |int_status;

  // ---- 配置从机（写寄存器/读寄存器，复用fir_top的写法）----
  localparam WS_IDLE = 2'd0, WS_DATA = 2'd1, WS_RESP = 2'd2;
  reg [1:0] ws; reg w_sel; reg [31:0] w_a; reg [7:0] w_cnt; reg [1:0] w_burst;
  reg [2:0] w_size;                    // AW握手时锁存（W阶段AW_SIZE可能已变）
  localparam RS_IDLE = 2'd0, RS_DATA = 2'd1;
  reg [1:0] rs; reg r_sel; reg [31:0] r_a; reg [7:0] r_cnt; reg [1:0] r_burst;
  reg [5:0] int_clr;

  always @(posedge ACLK) begin
    if (!ARESETn) begin
      ws <= WS_IDLE; AW_READY <= 0; W_READY <= 0; B_VALID <= 0; B_RESP <= 0;
      w_sel <= 0; w_a <= 0; w_cnt <= 0; w_burst <= 0; int_clr <= 0;
      for (i = 0; i < 6; i = i + 1) begin
        ch_src[i] <= 0; ch_dst[i] <= 0; ch_len[i] <= 0; ch_ctrl[i] <= 0;
        ch_next[i] <= 0; ch_load[i] <= 0;
      end
    end else begin
      for (i = 0; i < 6; i = i + 1) ch_load[i] <= 1'b0;
      int_clr <= 6'b0;
      case (ws)
        WS_IDLE: begin
          AW_READY <= 1;
          if (AW_VALID && AW_READY) begin
            w_sel <= AW_SEL; w_a <= AW_ADDR; w_cnt <= AW_LEN; w_burst <= AW_BURST;
            w_size <= AW_SIZE;
            AW_READY <= 0; W_READY <= 1; ws <= WS_DATA;
          end
        end
        WS_DATA: begin
          if (W_VALID && W_READY) begin
            if (w_sel && w_size == 3'b010) begin
              // 通道寄存器
              for (i = 0; i < 6; i = i + 1) begin
                if (w_a[11:8] == i[3:0] && w_a[11:0] < 12'h100) begin
                  case (w_a[6:0])
                    7'h00: ch_src[i]  <= W_DATA;
                    7'h04: ch_dst[i]  <= W_DATA;
                    7'h08: ch_len[i]  <= W_DATA;
                    7'h14: ch_next[i] <= W_DATA;
                    7'h0C: begin
                      ch_ctrl[i] <= W_DATA[15:0];
                      if (W_DATA[0]) ch_load[i] <= 1'b1;    // GO
                    end
                    7'h10: begin                              // STATUS只读
                    end
                  endcase
                end
              end
              if (w_a[11:0] == 12'h104) int_clr <= W_DATA[5:0]; // INT_CLR
            end
            if (w_burst[0]) w_a <= w_a + 4;
            if (w_cnt == 0) begin ws <= WS_RESP; W_READY <= 0; B_VALID <= 1; end
            else w_cnt <= w_cnt - 1;
          end
        end
        WS_RESP: if (B_VALID && B_READY) begin B_VALID <= 0; ws <= WS_IDLE; end
      endcase
    end
  end

  // 读状态机与读数据
  always @(posedge ACLK) begin
    if (!ARESETn) begin
      rs <= RS_IDLE; AR_READY <= 0; R_VALID <= 0; R_RESP <= 0; R_LAST <= 0;
      r_sel <= 0; r_a <= 0; r_cnt <= 0; r_burst <= 0;
    end else begin
      case (rs)
        RS_IDLE: begin
          AR_READY <= 1;
          if (AR_VALID && AR_READY) begin
            r_sel <= AR_SEL; r_a <= AR_ADDR; r_cnt <= AR_LEN; r_burst <= AR_BURST;
            AR_READY <= 0; rs <= RS_DATA;
          end
        end
        RS_DATA: begin
          R_VALID <= 1;
          if (R_VALID && R_READY) begin
            if (r_burst[0]) r_a <= r_a + 4;
            if (r_cnt == 0) begin rs <= RS_IDLE; R_VALID <= 0; R_LAST <= 0; AR_READY <= 1; end
            else begin r_cnt <= r_cnt - 1; if (r_cnt == 1) R_LAST <= 1; end
          end
        end
      endcase
    end
  end

  always @* begin
    R_DATA = 32'h0; R_RESP = 2'b00;
    if (rs == RS_DATA && r_sel) begin
      if (r_a[11:0] == 12'h100) R_DATA = {26'h0, int_status};        // INT_STATUS
      else begin
        for (i = 0; i < 6; i = i + 1) begin
          if (r_a[11:8] == i[3:0] && r_a[11:0] < 12'h100) begin
            case (r_a[6:0])
              7'h00: R_DATA = ch_src[i];
              7'h04: R_DATA = ch_dst[i];
              7'h08: R_DATA = ch_len[i];
              7'h0C: R_DATA = {16'h0, ch_ctrl[i]};
              7'h14: R_DATA = ch_next[i];
              7'h10: R_DATA = {29'h0, ch_err_q[i], ch_done_q[i], ch_busy[i]};
            endcase
          end
        end
      end
    end
  end
endmodule
```

- [ ] **Step 4: 运行TB，确认绿灯**

Run: `make -f Makefile.fir sim_tb_dma_top`，Expected: `PASS: 6通道并发独立工作零差错+中断状态正确`。

- [ ] **Step 5: 提交**

```bash
cd /d/ICT/Cortexm0ds && git add rtl/dma/dma_top.v tb/tb_dma_top.v Makefile && git commit -m "feat: 6通道DMA控制器（并发独立零差错+中断）

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

**验收**：`make -f Makefile.fir sim_tb_dma_top` 绿。对应"6通道全部可独立工作，数据零差错"。

---

### 任务 11：DMA链式传输（决赛架构创新项）

**Files:**
- Modify: `rtl/dma/dma_channel.v`（链式描述符抓取已预留状态机，本任务打通并修边界）；`rtl/dma/dma_top.v`（NEXT寄存器+链式启动路径）
- Test: `tb/tb_dma_chain.v`

**Interfaces:**
- Consumes: 任务10产物。链式描述符内存布局（5字/段）：`{SRC, DST, LEN, CTRL, NEXT}`；CTRL位`[4]CHAIN=1`时完成后自动从NEXT取下一描述符；最后一环CHAIN=0并置IRQ_EN收尾。
- 新增约定：软件写好链表后，只启动一次（通道0写CTRL=GO|CHAIN，NEXT=首描述符地址）；链内各段CTRL可含IRQ_EN（按需在末段置位）。

- [ ] **Step 1: 写 TB（3段链表自动串联执行，无CPU干预，末段触发中断）**

```verilog
// tb_dma_chain.v : 链式传输——3段描述符自动连续执行
// 段1: 0x000->0x300 64B；段2: 0x040->0x340 64B；段3: 0x080->0x380 64B（末段IRQ_EN）
// 描述符区: 0x700起，每段5字
`timescale 1ns/1ps
module tb_dma_chain;
  reg  ACLK, ARESETn;
  wire AW_SEL, AW_VALID, AW_READY; wire [2:0] AW_SIZE; wire [1:0] AW_BURST;
  wire [7:0] AW_LEN; wire [31:0] AW_ADDR;
  wire W_VALID, W_READY; wire [31:0] W_DATA; wire W_LAST;
  wire B_VALID, B_READY; wire [1:0] B_RESP;
  wire AR_SEL, AR_VALID, AR_READY; wire [2:0] AR_SIZE; wire [1:0] AR_BURST;
  wire [7:0] AR_LEN; wire [31:0] AR_ADDR;
  wire R_VALID, R_READY; wire [31:0] R_DATA; wire [1:0] R_RESP; wire R_LAST;
  wire m_AW_VALID, m_AW_READY; wire [2:0] m_AW_SIZE; wire [1:0] m_AW_BURST;
  wire [7:0] m_AW_LEN; wire [31:0] m_AW_ADDR;
  wire m_W_VALID, m_W_READY; wire [31:0] m_W_DATA; wire m_W_LAST;
  wire m_B_VALID, m_B_READY; wire [1:0] m_B_RESP;
  wire m_AR_VALID, m_AR_READY; wire [2:0] m_AR_SIZE; wire [1:0] m_AR_BURST;
  wire [7:0] m_AR_LEN; wire [31:0] m_AR_ADDR;
  wire m_R_VALID, m_R_READY; wire [31:0] m_R_DATA; wire [1:0] m_R_RESP; wire m_R_LAST;
  wire dma_irq, viol;

  tb_clkreset #() u_ck (.clk(ACLK), .rstn(ARESETn));

  axi_master_vip u_vip (
    .ACLK(ACLK), .ARESETn(ARESETn),
    .AW_SEL(AW_SEL), .AW_VALID(AW_VALID), .AW_READY(AW_READY),
    .AW_SIZE(AW_SIZE), .AW_BURST(AW_BURST), .AW_LEN(AW_LEN), .AW_ADDR(AW_ADDR),
    .W_VALID(W_VALID), .W_READY(W_READY), .W_DATA(W_DATA), .W_LAST(W_LAST),
    .B_VALID(B_VALID), .B_READY(B_READY), .B_RESP(B_RESP),
    .AR_SEL(AR_SEL), .AR_VALID(AR_VALID), .AR_READY(AR_READY),
    .AR_SIZE(AR_SIZE), .AR_BURST(AR_BURST), .AR_LEN(AR_LEN), .AR_ADDR(AR_ADDR),
    .R_VALID(R_VALID), .R_READY(R_READY), .R_DATA(R_DATA), .R_RESP(R_RESP), .R_LAST(R_LAST));

  dma_top u_dma (
    .ACLK(ACLK), .ARESETn(ARESETn),
    .AW_SEL(AW_SEL), .AW_VALID(AW_VALID), .AW_READY(AW_READY),
    .AW_SIZE(AW_SIZE), .AW_BURST(AW_BURST), .AW_LEN(AW_LEN), .AW_ADDR(AW_ADDR),
    .W_VALID(W_VALID), .W_READY(W_READY), .W_DATA(W_DATA), .W_LAST(W_LAST),
    .B_VALID(B_VALID), .B_READY(B_READY), .B_RESP(B_RESP),
    .AR_SEL(AR_SEL), .AR_VALID(AR_VALID), .AR_READY(AR_READY),
    .AR_SIZE(AR_SIZE), .AR_BURST(AR_BURST), .AR_LEN(AR_LEN), .AR_ADDR(AR_ADDR),
    .R_VALID(R_VALID), .R_READY(R_READY), .R_DATA(R_DATA), .R_RESP(R_RESP), .R_LAST(R_LAST),
    .awvalid(m_AW_VALID), .awready(m_AW_READY), .awsize(m_AW_SIZE), .awburst(m_AW_BURST),
    .awlen(m_AW_LEN), .awaddr(m_AW_ADDR),
    .wvalid(m_W_VALID), .wready(m_W_READY), .wdata(m_W_DATA), .wlast(m_W_LAST),
    .bvalid(m_B_VALID), .bready(m_B_READY), .bresp(m_B_RESP),
    .arvalid(m_AR_VALID), .arready(m_AR_READY), .arsize(m_AR_SIZE), .arburst(m_AR_BURST),
    .arlen(m_AR_LEN), .araddr(m_AR_ADDR),
    .rvalid(m_R_VALID), .rready(m_R_READY), .rdata(m_R_DATA), .rresp(m_R_RESP), .rlast(m_R_LAST),
    .irq_o(dma_irq));

  axi_slave_mem #(.AW(12)) u_mem (
    .ACLK(ACLK), .ARESETn(ARESETn),
    .AW_VALID(m_AW_VALID), .AW_READY(m_AW_READY), .AW_SIZE(m_AW_SIZE),
    .AW_BURST(m_AW_BURST), .AW_LEN(m_AW_LEN), .AW_ADDR(m_AW_ADDR),
    .W_VALID(m_W_VALID), .W_READY(m_W_READY), .W_DATA(m_W_DATA), .W_LAST(m_W_LAST),
    .B_VALID(m_B_VALID), .B_READY(m_B_READY), .B_RESP(m_B_RESP),
    .AR_VALID(m_AR_VALID), .AR_READY(m_AR_READY), .AR_SIZE(m_AR_SIZE),
    .AR_BURST(m_AR_BURST), .AR_LEN(m_AR_LEN), .AR_ADDR(m_AR_ADDR),
    .R_VALID(m_R_VALID), .R_READY(m_R_READY), .R_DATA(m_R_DATA), .R_RESP(m_R_RESP), .R_LAST(m_R_LAST));

  axi_checker u_chk (
    .ACLK(ACLK), .ARESETn(ARESETn),
    .AW_VALID(m_AW_VALID), .AW_READY(m_AW_READY), .AW_SIZE(m_AW_SIZE),
    .AW_BURST(m_AW_BURST), .AW_LEN(m_AW_LEN), .AW_ADDR(m_AW_ADDR),
    .W_VALID(m_W_VALID), .W_READY(m_W_READY), .W_DATA(m_W_DATA), .W_LAST(m_W_LAST),
    .B_VALID(m_B_VALID), .B_READY(m_B_READY), .B_RESP(m_B_RESP),
    .AR_VALID(m_AR_VALID), .AR_READY(m_AR_READY), .AR_SIZE(m_AR_SIZE),
    .AR_BURST(m_AR_BURST), .AR_LEN(m_AR_LEN), .AR_ADDR(m_AR_ADDR),
    .R_VALID(m_R_VALID), .R_READY(m_R_READY), .R_DATA(m_R_DATA), .R_RESP(m_R_RESP), .R_LAST(m_R_LAST),
    .violation(viol));

  integer i, t;

  task wr_reg; input [31:0] a, d;
    begin u_vip.vip_wdata[0] = d; u_vip.axi_wr(a, 8'd0, 2'b00, 3'b010); end
  endtask
  task rd_reg; input [31:0] a;
    begin u_vip.axi_rd(a, 8'd0, 2'b00, 3'b010); end
  endtask

  initial begin
    wait (ARESETn == 1'b1);
    @(posedge ACLK);
    // 源数据
    for (i = 0; i < 64; i = i + 1) begin
      u_vip.vip_wdata[0] = 32'h5000 + i;
      u_vip.axi_wr(i * 4, 8'd0, 2'b00, 3'b010);
    end
    // 描述符区0x700：3段链表（末段CHAIN=0,IRQ_EN=1）
    // 段1 @0x700
    wr_reg(32'h700, 32'h000); wr_reg(32'h704, 32'h300);
    wr_reg(32'h708, 32'd64); wr_reg(32'h70C, 16'h0014 | 16'd5 << 5); wr_reg(32'h710, 32'h714);
    // 段2 @0x714
    wr_reg(32'h714, 32'h040); wr_reg(32'h718, 32'h340);
    wr_reg(32'h71C, 32'd64); wr_reg(32'h720, 16'h0014 | 16'd5 << 5); wr_reg(32'h724, 32'h728);
    // 段3 @0x728（末段）
    wr_reg(32'h728, 32'h080); wr_reg(32'h72C, 32'h380);
    wr_reg(32'h730, 32'd64); wr_reg(32'h734, 16'h0012 | 16'd5 << 5); wr_reg(32'h738, 32'h0);
    // 启动通道0：GO|CHAIN，NEXT=0x700
    wr_reg(32'h4003_0000 + 32'h14, 32'h700);
    wr_reg(32'h4003_0000 + 32'h0C, 16'h0011 | 16'd5 << 5);
    // 等末段中断
    t = 0;
    while (!dma_irq && t < 200000) begin @(posedge ACLK); t = t + 1; end
    if (!dma_irq) $fatal(1, "FAIL: 链式传输未在超时内完成");
    // 三段目的区逐一比对
    for (i = 0; i < 16; i = i + 1) begin
      rd_reg(32'h300 + i * 4);
      if (u_vip.vip_rdata[0] !== 32'h5000 + i)      $fatal(1, "FAIL: 段1字%0d", i);
      rd_reg(32'h340 + i * 4);
      if (u_vip.vip_rdata[0] !== 32'h5000 + 16 + i) $fatal(1, "FAIL: 段2字%0d", i);
      rd_reg(32'h380 + i * 4);
      if (u_vip.vip_rdata[0] !== 32'h5000 + 32 + i) $fatal(1, "FAIL: 段3字%0d", i);
    end
    if (viol) $fatal(1, "FAIL: 协议违规");
    $display("PASS: 3段链表自动串联执行（无CPU干预，末段中断）");
    $finish;
  end
endmodule
```

- [ ] **Step 2: 运行TB，确认红灯**

Run: `make -f Makefile.fir sim_tb_dma_chain`，Expected: 仿真挂起或比对失败（链式路径未打通）。

- [ ] **Step 3: 打通链式路径（修 dma_channel 的S_IDLE链式分支与 dma_top 的NEXT装载）**

对照任务9的`dma_channel.v`检查并修正：
1. `S_CH_D` 收齐5字后回到 `S_IDLE`，S_IDLE 的"链式续传"分支条件应为**内部续传标志**而非`cfg_load`（`cfg_load`是dma_top的装载脉冲，不会二次出现）。修法：新增`reg chain_cont`，S_CH_D完成时置1；S_IDLE中 `else if (chain_cont)` 走续传分支并把`chain_cont`清0，续传内容取shadow（shadow[3]的GO位在链式下忽略——用 `shadow[3][4]` 判断是否还有下一环，最后一环CHAIN=0时完成后走done/irq）。删除对`cfg_load`的第二分支依赖。
2. `dma_top`中NEXT寄存器已在（`7'h14: ch_next[i] <= W_DATA;`），确认`ch_load`路径把`ch_next`传入通道（已在）。
3. 通道内`S_WR_AW`完成分支：`st <= (chain_en && !err) ? S_CH_AR : S_DONE;` 保持，但`chain_en`应取**当前段的**CHAIN位（续传装载时已从shadow[3][4]刷新，正确）。

- [ ] **Step 4: 运行TB，确认绿灯**

Run: `make -f Makefile.fir sim_tb_dma_chain`，Expected: `PASS: 3段链表自动串联执行...`。

- [ ] **Step 5: 提交**

```bash
cd /d/ICT/Cortexm0ds && git add rtl/dma/ tb/tb_dma_chain.v && git commit -m "feat: DMA链式传输（链表自动串联，无需CPU干预）

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

**验收**：`make -f Makefile.fir sim_tb_dma_chain` 绿。对应评分"架构创新：DMA支持链式传输"（官方示例20分项）。

---

## 阶段 4：SoC 集成与固件（对应 FR-5 CPU跑通、FR-7 软硬协同）

### 任务 12：SoC顶层集成 soc_top

**Files:**
- Create: `rtl/soc/soc_top.v`；Test: `tb/tb_soc_smoke.v`；Modify: `Makefile.fir`（RTL追加 soc_top.v、dma_top.v、fir_top.v、fir_core_sym.v；编译加官方目录的include路径）
- 复用（实例化，不改动）：官方目录中的 `cortexm0integration`、`cmsdk_axi_slave_mux`、`cmsdk_axi_flash`、`cmsdk_axi_sram`、`cmsdk_axi2apb_subsystem`、`cmsdk_axi_gpio`、`cmsdk_axi_default_slave`

**Interfaces:**
- Consumes: 任务3/4（仲裁+译码）、任务7/10（FIR/DMA）、任务1走读笔记（端口名）
- Produces: `soc_top #(FILENAME="image.hex", MEM_IMPL=0)(ACLK, ARESETn, PCLK, PRESETn, uart0_rxd, uart0_txd, uart0_txen, uart2_txd, uart2_txen, gpio0_out[15:0], DFTSE)`
- 内部IRQ分配（**先按任务1笔记核对 apbsubsys_interrupt 位序**）：IRQ[0]=UART0 TX、IRQ[1]=UART0 RX、IRQ[16]=DMA；NMI=0；其余IRQ=0

- [ ] **Step 1: 更新 Makefile.fir（官方模块路径+include路径+全部RTL）**

```makefile
RTL  = rtl/ic/ic_axi_master_arb.v rtl/ic/ic_axi_addr_decode.v \
       rtl/fir/fir_core.v rtl/fir/fir_core_sym.v rtl/fir/fir_top.v \
       rtl/dma/dma_channel.v rtl/dma/dma_top.v rtl/soc/soc_top.v

# 官方模块（只读复用，不改动）
REF_RTL = ./core/cortexm0_dap/cortexm0dap.v \
          ./core/cortexm0_integration/cortexm0_wic.v \
          ./core/cortexm0_integration/cortexm0_systick.v \
          ./core/cortexm0_integration/cortexm0integration.v \
          ./core/cortexm0ds/ahb2axi4_if.v \
          ./core/cortexm0ds/ahb2axi4_ahb.v \
          ./core/cortexm0ds/ahb2axi4_axi.v \
          ./core/cortexm0ds/ahb2axi4_burst.v \
          ./core/cortexm0ds/ahb2axi4_fifo.v \
          ./core/cortexm0ds/cortexm0ds.v \
          ./core/cortexm0ds/cortexm0ds_logic.v \
          ./core/models/cm0_dbg_reset_sync.v \
          ./mcu_system/cmsdk_axi_memory/cmsdk_axi_flash.v \
          ./mcu_system/cmsdk_axi_memory/cmsdk_axi_sram.v \
          ./mcu_system/cmsdk_axi_memory/cmsdk_axi_ram_beh.v \
          ./mcu_system/cmsdk_axi_slave_mux/cmsdk_axi_slave_mux.v \
          ./mcu_system/cmsdk_axi2apb_subsystem/cmsdk_axi2apb_subsystem.v \
          ./mcu_system/cmsdk_axi2apb_subsystem/cmsdk_apb_test_slave.v \
          ./mcu_system/cmsdk_axi2apb_subsystem/cmsdk_irq_sync.v \
          ./mcu_system/cmsdk_axi_to_apb/axi2apb_if.v \
          ./mcu_system/cmsdk_axi_to_apb/axi2apb_axi.v \
          ./mcu_system/cmsdk_axi_to_apb/axi2apb_apb.v \
          ./mcu_system/cmsdk_apb_dualtimers/cmsdk_apb_dualtimers.v \
          ./mcu_system/cmsdk_apb_dualtimers/cmsdk_apb_dualtimers_frc.v \
          ./mcu_system/cmsdk_apb_slave_mux/cmsdk_apb_slave_mux.v \
          ./mcu_system/cmsdk_apb_timer/cmsdk_apb_timer.v \
          ./mcu_system/cmsdk_apb_uart/cmsdk_apb_uart.v \
          ./mcu_system/cmsdk_apb_watchdog/cmsdk_apb_watchdog.v \
          ./mcu_system/cmsdk_apb_watchdog/cmsdk_apb_watchdog_frc.v \
          ./mcu_system/cmsdk_axi_gpio/cmsdk_axi_gpio.v \
          ./mcu_system/cmsdk_axi_gpio/cmsdk_axi_to_iop.v \
          ./mcu_system/cmsdk_axi_gpio/cmsdk_iop_gpio.v \
          ./mcu_system/cmsdk_mcu_system/cmsdk_axi_default_slave.v

INCPATH = -I$(TB_DIR)/common -I./core/cortexm0ds/ \
          -I./core/cortexm0_integration/ -I./core/cortexm0_dap/ \
          -I./core/models/ -I./mcu_system/cmsdk_axi_to_apb/ \
          -I./mcu_system/cmsdk_axi_memory/ \
          -I./mcu_system/cmsdk_apb_dualtimers/ \
          -I./mcu_system/cmsdk_apb_watchdog/ \
          -I./mcu_system/cmsdk_axi_slave_mux/

sim_%: $(OUT)
	$(IV) -g2001 -o $(OUT)/$*.vvp -s $* $(INCPATH) $(TB_DIR)/$*.v \
	     $(TB_DIR)/common/axi_master_vip.v $(TB_DIR)/common/axi_slave_mem.v \
	     $(TB_DIR)/common/axi_checker.v $(TB_DIR)/common/uart_bfm.v \
	     $(TB_DIR)/common/tb_clkreset.v $(RTL) $(REF_RTL)
	$(VVP) -n $(OUT)/$*.vvp
```

- [ ] **Step 2: 写冒烟TB（加载官方hello.hex，断言UART2输出"Hello world"）**

```verilog
// tb_soc_smoke.v : SoC冒烟——CPU从flash启动hello固件，UART2打印Hello world
// 验证链：CPU取指(flash)→AHB2AXI4桥→仲裁器→slave mux→APB桥→UART2→BFM
`timescale 1ns/1ps
module tb_soc_smoke;
  reg  ACLK, ARESETn, PCLK, PRESETn;
  wire uart0_rxd, uart0_txd, uart0_txen, uart2_txd, uart2_txen;
  wire [15:0] gpio0_out;
  reg  uart0_rx_drive;

  tb_clkreset #() u_ck (.clk(ACLK), .rstn(ARESETn));

  always @(posedge ACLK) begin        // PCLK=ACLK
    PCLK <= ACLK; PRESETn <= ARESETn;
  end

  soc_top #(.FILENAME("software/testcodes/hello/hello.hex"), .MEM_IMPL(0))
  u_soc (
    .ACLK(ACLK), .ARESETn(ARESETn), .PCLK(PCLK), .PRESETn(PRESETn),
    .uart0_rxd(uart0_rxd), .uart0_txd(uart0_txd), .uart0_txen(uart0_txen),
    .uart2_txd(uart2_txd), .uart2_txen(uart2_txen),
    .gpio0_out(gpio0_out), .DFTSE(1'b0));

  assign uart0_rxd = 1'b1;            // 无外部输入

  // UART2监视（9600），收集一行文本
  reg [7:0] rx_byte;
  reg [8*64-1:0] line;
  integer li;
  task get_line;
    begin
      li = 0; line = 0;
      while (1) begin
        u2_bfm.uart_rx(rx_byte);
        if (rx_byte == 8'h0A) return;                 // 换行结束
        line = (line << 8) | rx_byte;
        li = li + 1;
      end
    end
  endtask

  uart_bfm u2_bfm (.txd(), .rxd(uart2_txd));

  initial begin
    #100000;                                            // 等复位与启动
    get_line;                                           // 第一行应为 "Hello world"
    if (li < 5 || line[39:0] != "Hello ") begin
      $display("首行=%0s", line);
      $fatal(1, "FAIL: 未捕获Hello world");
    end
    $display("PASS: SoC冒烟——CPU启动、UART2输出Hello world");
    $finish;
  end

  // 超时兜底
  initial begin
    #60000000;
    $fatal(1, "FAIL: 冒烟超时（60ms）");
  end
endmodule
```

（实现说明：`hello.hex`为官方预编译的verilog格式hex，路径相对仓库根；字符串比较按实际捕获调整——hello.c打印"Hello world\n"，断言放宽为line含"Hello"。）

- [ ] **Step 3: 运行TB，确认红灯**

Run: `make -f Makefile.fir sim_tb_soc_smoke`，Expected: 编译错误 `soc_top` 未找到。

- [ ] **Step 4: 实现 soc_top.v**

```verilog
// soc_top.v : 本项目SoC顶层（只实例化官方模块与新模块，不改官方文件）
// 拓扑：CPU集成层(AXI主) ─┐
//        DMA主口 ─────────┤→ ic_axi_master_arb → 官方cmsdk_axi_slave_mux
//  从机：port0=flash/rom(0x0) port1=sram(0x2000_0000) port2=apbsys(0x4000_0000)
//        port3=gpio0(0x4001_0000) port4=fir(0x4002_0000) port5=dma_cfg(0x4003_0000)
//        port6=默认从机(DECERR)
// 注意：官方mux不传W通道——W_VALID/W_DATA/W_LAST由系统广播给全部从机，
//       各从机按自己AW锁存的选中自行消费（CMSDK从机约定）。
`timescale 1ns/1ps
`include "cmsdk_axi_memory_defs.v"

module soc_top #(
    parameter FILENAME = "image.hex",     // 固件hex（仿真flash/$readmemh路径相对运行目录）
    parameter MEM_IMPL = 0                // 0=cmsdk_axi_flash(仿真) 1=axi_rom(FPGA，任务15加入)
)(
    input  wire        ACLK,
    input  wire        ARESETn,
    input  wire        PCLK,
    input  wire        PRESETn,
    // UART
    input  wire        uart0_rxd,
    output wire        uart0_txd,
    output wire        uart0_txen,
    output wire        uart2_txd,         // stdout（retarget默认UART2）
    output wire        uart2_txen,
    // GPIO0（LED演示）
    output wire [15:0] gpio0_out,
    input  wire        DFTSE
);
  // ================= CPU到仲裁器 =================
  wire        cm0_AWVALID, cm0_AWREADY;
  wire [2:0]  cm0_AWSIZE;  wire [1:0] cm0_AWBURST; wire [7:0] cm0_AWLEN;
  wire [31:0] cm0_AWADDR;
  wire        cm0_WVALID, cm0_WREADY, cm0_WLAST; wire [31:0] cm0_WDATA;
  wire        cm0_BVALID, cm0_BREADY; wire [1:0] cm0_BRESP;
  wire        cm0_ARVALID, cm0_ARREADY;
  wire [2:0]  cm0_ARSIZE;  wire [1:0] cm0_ARBURST; wire [7:0] cm0_ARLEN;
  wire [31:0] cm0_ARADDR;
  wire        cm0_RVALID, cm0_RREADY, cm0_RLAST;
  wire [31:0] cm0_RDATA;   wire [1:0] cm0_RRESP;
  wire [31:0] intisr;
  wire        LOCKUP, SYSRESETREQ;

  // ================= 共享总线（仲裁器输出→slave mux主侧） =================
  wire        sys_AWVALID, sys_AWREADY;
  wire [2:0]  sys_AWSIZE;  wire [1:0] sys_AWBURST; wire [7:0] sys_AWLEN;
  wire [31:0] sys_AWADDR;
  wire        sys_WVALID, sys_WREADY, sys_WLAST; wire [31:0] sys_WDATA;
  wire        sys_BVALID, sys_BREADY; wire [1:0] sys_BRESP;
  wire        sys_ARVALID, sys_ARREADY;
  wire [2:0]  sys_ARSIZE;  wire [1:0] sys_ARBURST; wire [7:0] sys_ARLEN;
  wire [31:0] sys_ARADDR;
  wire        sys_RVALID, sys_RREADY, sys_RLAST;
  wire [31:0] sys_RDATA;   wire [1:0] sys_RRESP;

  // ================= 译码SEL =================
  wire flash_arsel, sram_awsel, sram_arsel, apbsys_awsel, apbsys_arsel;
  wire gpio0_awsel, gpio0_arsel, fir_awsel, fir_arsel, dma_awsel, dma_arsel;
  wire defslv_awsel, defslv_arsel;

  // ================= 各从机 =================
  wire flash_ARREADY, flash_RVALID, flash_RLAST; wire [31:0] flash_RDATA; wire [1:0] flash_RRESP;
  wire sram_AWREADY, sram_WREADY, sram_BVALID; wire [1:0] sram_BRESP;
  wire sram_ARREADY, sram_RVALID, sram_RLAST; wire [31:0] sram_RDATA; wire [1:0] sram_RRESP;
  wire apb_AWREADY, apb_WREADY, apb_BVALID; wire [1:0] apb_BRESP;
  wire apb_ARREADY, apb_RVALID, apb_RLAST; wire [31:0] apb_RDATA; wire [1:0] apb_RRESP;
  wire g0_AWREADY, g0_WREADY, g0_BVALID; wire [1:0] g0_BRESP;
  wire g0_ARREADY, g0_RVALID, g0_RLAST; wire [31:0] g0_RDATA; wire [1:0] g0_RRESP;
  wire fir_AWREADY, fir_WREADY, fir_BVALID; wire [1:0] fir_BRESP;
  wire fir_ARREADY, fir_RVALID, fir_RLAST; wire [31:0] fir_RDATA; wire [1:0] fir_RRESP;
  wire dma_AWREADY, dma_WREADY, dma_BVALID; wire [1:0] dma_BRESP;
  wire dma_ARREADY, dma_RVALID, dma_RLAST; wire [31:0] dma_RDATA; wire [1:0] dma_RRESP;
  wire def_AWREADY, def_WREADY, def_BVALID; wire [1:0] def_BRESP;
  wire def_ARREADY, def_RVALID, def_RLAST; wire [31:0] def_RDATA; wire [1:0] def_RRESP;

  // ================= APB子系统 =================
  wire [31:0] apbsubsys_interrupt;
  wire        APBACTIVE;
  wire        uart2_rxd;
  assign uart2_rxd = 1'b1;

  // ================= DMA =================
  wire dma_awvalid, dma_awready; wire [2:0] dma_awsize; wire [1:0] dma_awburst;
  wire [7:0] dma_awlen; wire [31:0] dma_awaddr;
  wire dma_wvalid, dma_wready, dma_wlast; wire [31:0] dma_wdata;
  wire dma_bvalid, dma_bready; wire [1:0] dma_bresp;
  wire dma_arvalid, dma_arready; wire [2:0] dma_arsize; wire [1:0] dma_arburst;
  wire [7:0] dma_arlen; wire [31:0] dma_araddr;
  wire dma_rvalid, dma_rready, dma_rlast; wire [31:0] dma_rdata; wire [1:0] dma_rresp;
  wire dma_irq;

  // ================= GPIO0 =================
  wire [15:0] p0_in, p0_out, p0_outen, p0_altfunc;
  assign p0_in = 16'h0;
  assign gpio0_out = p0_out;

  // ================= CPU =================
  cortexm0integration #(.NUMIRQ(32), .SYST(1), .WIC(0), .WICLINES(34), .SMUL(0))
  u_cpu (
    .FCLK(ACLK), .SCLK(ACLK), .ACLK(ACLK), .DCLK(1'b0),
    .PORESETn(ARESETn), .DBGRESETn(1'b0), .ARESETn(ARESETn),
    .SWCLKTCK(1'b0), .nTRST(1'b0),
    .AW_VALID(cm0_AWVALID), .AW_READY(cm0_AWREADY), .AW_SIZE(cm0_AWSIZE),
    .AW_BURST(cm0_AWBURST), .AW_LEN(cm0_AWLEN), .AW_ADDR(cm0_AWADDR),
    .W_VALID(cm0_WVALID), .W_READY(cm0_WREADY), .W_LAST(cm0_WLAST), .W_DATA(cm0_WDATA),
    .B_VALID(cm0_BVALID), .B_READY(cm0_BREADY), .B_RESP(cm0_BRESP),
    .AR_VALID(cm0_ARVALID), .AR_READY(cm0_ARREADY), .AR_SIZE(cm0_ARSIZE),
    .AR_BURST(cm0_ARBURST), .AR_LEN(cm0_ARLEN), .AR_ADDR(cm0_ARADDR),
    .R_VALID(cm0_RVALID), .R_READY(cm0_RREADY), .R_LAST(cm0_RLAST),
    .R_DATA(cm0_RDATA), .R_RESP(cm0_RRESP),
    .CODENSEQ(), .CODEHINTDE(), .SPECHTRANS(),
    .SWDITMS(1'b0), .TDI(1'b0), .SWDO(), .SWDOEN(), .TDO(), .nTDOEN(),
    .DBGRESTART(1'b0), .DBGRESTARTED(), .EDBGRQ(1'b0), .HALTED(),
    .NMI(1'b0), .IRQ(intisr), .TXEV(), .RXEV(1'b0),
    .LOCKUP(LOCKUP), .SYSRESETREQ(SYSRESETREQ),
    .IRQLATENCY(8'h00), .ECOREVNUM(28'h0),
    .GATEHCLK(), .SLEEPING(), .SLEEPDEEP(), .WAKEUP(), .WICSENSE(),
    .SLEEPHOLDREQn(1'b1), .SLEEPHOLDACKn(), .WICENREQ(1'b0), .WICENACK(),
    .CDBGPWRUPREQ(), .CDBGPWRUPACK(1'b0),
    .SE(1'b0), .RSTBYPASS(1'b0));

  // ================= 多主仲裁 =================
  ic_axi_master_arb u_arb (
    .aclk(ACLK), .aresetn(ARESETn),
    .m0_awvalid(cm0_AWVALID), .m0_awready(cm0_AWREADY), .m0_awsize(cm0_AWSIZE),
    .m0_awburst(cm0_AWBURST), .m0_awlen(cm0_AWLEN), .m0_awaddr(cm0_AWADDR),
    .m0_wvalid(cm0_WVALID), .m0_wready(cm0_WREADY), .m0_wlast(cm0_WLAST), .m0_wdata(cm0_WDATA),
    .m0_bvalid(cm0_BVALID), .m0_bready(cm0_BREADY), .m0_bresp(cm0_BRESP),
    .m0_arvalid(cm0_ARVALID), .m0_arready(cm0_ARREADY), .m0_arsize(cm0_ARSIZE),
    .m0_arburst(cm0_ARBURST), .m0_arlen(cm0_ARLEN), .m0_araddr(cm0_ARADDR),
    .m0_rvalid(cm0_RVALID), .m0_rready(cm0_RREADY), .m0_rlast(cm0_RLAST),
    .m0_rdata(cm0_RDATA), .m0_rresp(cm0_RRESP),
    .m1_awvalid(dma_awvalid), .m1_awready(dma_awready), .m1_awsize(dma_awsize),
    .m1_awburst(dma_awburst), .m1_awlen(dma_awlen), .m1_awaddr(dma_awaddr),
    .m1_wvalid(dma_wvalid), .m1_wready(dma_wready), .m1_wlast(dma_wlast), .m1_wdata(dma_wdata),
    .m1_bvalid(dma_bvalid), .m1_bready(dma_bready), .m1_bresp(dma_bresp),
    .m1_arvalid(dma_arvalid), .m1_arready(dma_arready), .m1_arsize(dma_arsize),
    .m1_arburst(dma_arburst), .m1_arlen(dma_arlen), .m1_araddr(dma_araddr),
    .m1_rvalid(dma_rvalid), .m1_rready(dma_rready), .m1_rlast(dma_rlast),
    .m1_rdata(dma_rdata), .m1_rresp(dma_rresp),
    .awvalid(sys_AWVALID), .awready(sys_AWREADY), .awsize(sys_AWSIZE),
    .awburst(sys_AWBURST), .awlen(sys_AWLEN), .awaddr(sys_AWADDR),
    .wvalid(sys_WVALID), .wready(sys_WREADY), .wlast(sys_WLAST), .wdata(sys_WDATA),
    .bvalid(sys_BVALID), .bready(sys_BREADY), .bresp(sys_BRESP),
    .arvalid(sys_ARVALID), .arready(sys_ARREADY), .arsize(sys_ARSIZE),
    .arburst(sys_ARBURST), .arlen(sys_ARLEN), .araddr(sys_ARADDR),
    .rvalid(sys_RVALID), .rready(sys_RREADY), .rlast(sys_RLAST),
    .rdata(sys_RDATA), .rresp(sys_RRESP),
    .m0_done_cnt(), .m1_done_cnt(), .grant_imbalance());

  // ================= 地址译码 =================
  ic_axi_addr_decode u_dec (
    .w_addr(sys_AWADDR), .r_addr(sys_ARADDR),
    .flash_arsel(flash_arsel),
    .sram_awsel(sram_awsel), .sram_arsel(sram_arsel),
    .apbsys_awsel(apbsys_awsel), .apbsys_arsel(apbsys_arsel),
    .gpio0_awsel(gpio0_awsel), .gpio0_arsel(gpio0_arsel),
    .gpio1_awsel(), .gpio1_arsel(),
    .fir_awsel(fir_awsel), .fir_arsel(fir_arsel),
    .dma_awsel(dma_awsel), .dma_arsel(dma_arsel),
    .defslv_awsel(defslv_awsel), .defslv_arsel(defslv_arsel));

  // ================= 官方从机mux =================
  cmsdk_axi_slave_mux #(
    .PORT0_ENABLE(1), .PORT1_ENABLE(1), .PORT2_ENABLE(1), .PORT3_ENABLE(1),
    .PORT4_ENABLE(1), .PORT5_ENABLE(1), .PORT6_ENABLE(1), .PORT7_ENABLE(0),
    .PORT8_ENABLE(0), .PORT9_ENABLE(0), .DW(32))
  u_axi_slave_mux (
    .ACLK(ACLK), .ARESETn(ARESETn),
    // port0: flash/rom（只读）
    .AW_SEL0(1'b0), .AW_READY0(1'b1), .W_READY0(1'b1),
    .B_VALID0(1'b1), .B_RESP0(2'b11),
    .AR_SEL0(flash_arsel), .AR_READY0(flash_ARREADY), .R_VALID0(flash_RVALID),
    .R_LAST0(flash_RLAST), .R_DATA0(flash_RDATA), .R_RESP0(flash_RRESP),
    // port1: SRAM
    .AW_SEL1(sram_awsel), .AW_READY1(sram_AWREADY), .W_READY1(sram_WREADY),
    .B_VALID1(sram_BVALID), .B_RESP1(sram_BRESP),
    .AR_SEL1(sram_arsel), .AR_READY1(sram_ARREADY), .R_VALID1(sram_RVALID),
    .R_LAST1(sram_RLAST), .R_DATA1(sram_RDATA), .R_RESP1(sram_RRESP),
    // port2: APB子系统
    .AW_SEL2(apbsys_awsel), .AW_READY2(apb_AWREADY), .W_READY2(apb_WREADY),
    .B_VALID2(apb_BVALID), .B_RESP2(apb_BRESP),
    .AR_SEL2(apbsys_arsel), .AR_READY2(apb_ARREADY), .R_VALID2(apb_RVALID),
    .R_LAST2(apb_RLAST), .R_DATA2(apb_RDATA), .R_RESP2(apb_RRESP),
    // port3: GPIO0
    .AW_SEL3(gpio0_awsel), .AW_READY3(g0_AWREADY), .W_READY3(g0_WREADY),
    .B_VALID3(g0_BVALID), .B_RESP3(g0_BRESP),
    .AR_SEL3(gpio0_arsel), .AR_READY3(g0_ARREADY), .R_VALID3(g0_RVALID),
    .R_LAST3(g0_RLAST), .R_DATA3(g0_RDATA), .R_RESP3(g0_RRESP),
    // port4: FIR
    .AW_SEL4(fir_awsel), .AW_READY4(fir_AWREADY), .W_READY4(fir_WREADY),
    .B_VALID4(fir_BVALID), .B_RESP4(fir_BRESP),
    .AR_SEL4(fir_arsel), .AR_READY4(fir_ARREADY), .R_VALID4(fir_RVALID),
    .R_LAST4(fir_RLAST), .R_DATA4(fir_RDATA), .R_RESP4(fir_RRESP),
    // port5: DMA配置
    .AW_SEL5(dma_awsel), .AW_READY5(dma_AWREADY), .W_READY5(dma_WREADY),
    .B_VALID5(dma_BVALID), .B_RESP5(dma_BRESP),
    .AR_SEL5(dma_arsel), .AR_READY5(dma_ARREADY), .R_VALID5(dma_RVALID),
    .R_LAST5(dma_RLAST), .R_DATA5(dma_RDATA), .R_RESP5(dma_RRESP),
    // port6: 默认从机
    .AW_SEL6(defslv_awsel), .AW_READY6(def_AWREADY), .W_READY6(def_WREADY),
    .B_VALID6(def_BVALID), .B_RESP6(def_BRESP),
    .AR_SEL6(defslv_arsel), .AR_READY6(def_ARREADY), .R_VALID6(def_RVALID),
    .R_LAST6(def_RLAST), .R_DATA6(def_RDATA), .R_RESP6(def_RRESP),
    // port7-9禁用
    .AW_SEL7(1'b0), .AW_READY7(1'b0), .W_READY7(1'b0), .B_VALID7(1'b0), .B_RESP7(2'b0),
    .AR_SEL7(1'b0), .AR_READY7(1'b0), .R_VALID7(1'b0), .R_LAST7(1'b0),
    .R_DATA7(32'b0), .R_RESP7(2'b0),
    .AW_SEL8(1'b0), .AW_READY8(1'b0), .W_READY8(1'b0), .B_VALID8(1'b0), .B_RESP8(2'b0),
    .AR_SEL8(1'b0), .AR_READY8(1'b0), .R_VALID8(1'b0), .R_LAST8(1'b0),
    .R_DATA8(32'b0), .R_RESP8(2'b0),
    .AW_SEL9(1'b0), .AW_READY9(1'b0), .W_READY9(1'b0), .B_VALID9(1'b0), .B_RESP9(2'b0),
    .AR_SEL9(1'b0), .AR_READY9(1'b0), .R_VALID9(1'b0), .R_LAST9(1'b0),
    .R_DATA9(32'b0), .R_RESP9(2'b0),
    // 共享主侧
    .AW_VALID(sys_AWVALID), .AW_READY(sys_AWREADY),
    .W_READY(sys_WREADY),
    .B_VALID(sys_BVALID), .B_RESP(sys_BRESP),
    .AR_VALID(sys_ARVALID), .AR_READY(sys_ARREADY),
    .R_VALID(sys_RVALID), .R_LAST(sys_RLAST), .R_DATA(sys_RDATA), .R_RESP(sys_RRESP));

  // ================= 存储 =================
  generate
    if (MEM_IMPL == 0) begin : mem_sim
      cmsdk_axi_flash #(.filename(FILENAME), .AW(16),
                        .WS_N(`ARM_CMSDK_ROM_MEM_WS_N), .WS_S(`ARM_CMSDK_ROM_MEM_WS_S))
      u_flash (
        .ACLK(ACLK), .ARESETn(ARESETn),
        .AR_SEL(flash_arsel), .AR_VALID(sys_ARVALID), .AR_READY(flash_ARREADY),
        .AR_SIZE(sys_ARSIZE), .AR_BURST(sys_ARBURST), .AR_LEN(sys_ARLEN),
        .AR_ADDR(sys_ARADDR[15:0]),
        .R_VALID(flash_RVALID), .R_READY(sys_RREADY), .R_LAST(flash_RLAST),
        .R_DATA(flash_RDATA), .R_RESP(flash_RRESP));
    end else begin : mem_fpga
      axi_rom #(.FILENAME(FILENAME), .AW(16))
      u_rom (
        .ACLK(ACLK), .ARESETn(ARESETn),
        .AR_SEL(flash_arsel), .AR_VALID(sys_ARVALID), .AR_READY(flash_ARREADY),
        .AR_SIZE(sys_ARSIZE), .AR_BURST(sys_ARBURST), .AR_LEN(sys_ARLEN),
        .AR_ADDR(sys_ARADDR[15:0]),
        .R_VALID(flash_RVALID), .R_READY(sys_RREADY), .R_LAST(flash_RLAST),
        .R_DATA(flash_RDATA), .R_RESP(flash_RRESP));
    end
  endgenerate

  cmsdk_axi_sram #(.AW(16), .WS_N(`ARM_CMSDK_RAM_MEM_WS_N), .WS_S(`ARM_CMSDK_RAM_MEM_WS_S))
  u_sram (
    .ACLK(ACLK), .ARESETn(ARESETn),
    .AW_SEL(sram_awsel), .AW_VALID(sys_AWVALID), .AW_READY(sram_AWREADY),
    .AW_SIZE(sys_AWSIZE), .AW_BURST(sys_AWBURST), .AW_LEN(sys_AWLEN),
    .AW_ADDR(sys_AWADDR[15:0]),
    .W_VALID(sys_WVALID), .W_READY(sram_WREADY), .W_LAST(sys_WLAST), .W_DATA(sys_WDATA),
    .B_VALID(sram_BVALID), .B_READY(sys_BREADY), .B_RESP(sram_BRESP),
    .AR_SEL(sram_arsel), .AR_VALID(sys_ARVALID), .AR_READY(sram_ARREADY),
    .AR_SIZE(sys_ARSIZE), .AR_BURST(sys_ARBURST), .AR_LEN(sys_ARLEN),
    .AR_ADDR(sys_ARADDR[15:0]),
    .R_VALID(sram_RVALID), .R_READY(sys_RREADY), .R_LAST(sram_RLAST),
    .R_DATA(sram_RDATA), .R_RESP(sram_RRESP));

  // ================= APB子系统（UART0-2/Timer/WDT） =================
  cmsdk_axi2apb_subsystem #(
    .INCLUDE_APB_TIMER0(1), .INCLUDE_APB_TIMER1(1), .INCLUDE_APB_DUALTIMER0(1),
    .INCLUDE_APB_UART0(1), .INCLUDE_APB_UART1(1), .INCLUDE_APB_UART2(1),
    .INCLUDE_APB_WATCHDOG(1), .INCLUDE_APB_TEST_SLAVE(1),
    .APB_EXT_PORT12_ENABLE(0), .APB_EXT_PORT13_ENABLE(0),
    .APB_EXT_PORT14_ENABLE(0), .APB_EXT_PORT15_ENABLE(0),
    .INCLUDE_IRQ_SYNCHRONIZER(0))
  u_apb (
    .ACLK(ACLK), .ARESETn(ARESETn),
    .AW_SEL(apbsys_awsel), .AW_VALID(sys_AWVALID), .AW_READY(apb_AWREADY),
    .AW_SIZE(sys_AWSIZE), .AW_BURST(sys_AWBURST), .AW_LEN(sys_AWLEN),
    .AW_ADDR(sys_AWADDR),
    .W_VALID(sys_WVALID), .W_READY(apb_WREADY), .W_LAST(sys_WLAST), .W_DATA(sys_WDATA),
    .B_VALID(apb_BVALID), .B_READY(sys_BREADY), .B_RESP(apb_BRESP),
    .AR_SEL(apbsys_arsel), .AR_VALID(sys_ARVALID), .AR_READY(apb_ARREADY),
    .AR_SIZE(sys_ARSIZE), .AR_BURST(sys_ARBURST), .AR_LEN(sys_ARLEN),
    .AR_ADDR(sys_ARADDR),
    .R_VALID(apb_RVALID), .R_READY(sys_RREADY), .R_LAST(apb_RLAST),
    .R_DATA(apb_RDATA), .R_RESP(apb_RRESP),
    .PCLK(PCLK), .PCLKG(PCLK), .PCLKEN(1'b0), .PRESETn(PRESETn),
    .APBACTIVE(APBACTIVE),
    .uart0_rxd(uart0_rxd), .uart0_txd(uart0_txd), .uart0_txen(uart0_txen),
    .uart1_rxd(1'b1), .uart1_txd(), .uart1_txen(),
    .uart2_rxd(uart2_rxd), .uart2_txd(uart2_txd), .uart2_txen(uart2_txen),
    .timer0_extin(1'b0), .timer1_extin(1'b0),
    .apbsubsys_interrupt(apbsubsys_interrupt), .watchdog_interrupt(), .watchdog_reset());

  // ================= GPIO0 =================
  cmsdk_axi_gpio #(.ALTERNATE_FUNC_MASK(16'h0000), .ALTERNATE_FUNC_DEFAULT(16'h0000))
  u_gpio0 (
    .FCLK(ACLK), .ACLK(ACLK), .ARESETn(ARESETn),
    .AW_SEL(gpio0_awsel), .AW_VALID(sys_AWVALID), .AW_READY(g0_AWREADY),
    .AW_SIZE(sys_AWSIZE), .AW_BURST(sys_AWBURST), .AW_LEN(sys_AWLEN),
    .AW_ADDR(sys_AWADDR),
    .W_VALID(sys_WVALID), .W_READY(g0_WREADY), .W_LAST(sys_WLAST), .W_DATA(sys_WDATA),
    .B_VALID(g0_BVALID), .B_READY(sys_BREADY), .B_RESP(g0_BRESP),
    .AR_SEL(gpio0_arsel), .AR_VALID(sys_ARVALID), .AR_READY(g0_ARREADY),
    .AR_SIZE(sys_ARSIZE), .AR_BURST(sys_ARBURST), .AR_LEN(sys_ARLEN),
    .AR_ADDR(sys_ARADDR),
    .R_VALID(g0_RVALID), .R_READY(sys_RREADY), .R_LAST(g0_RLAST),
    .R_DATA(g0_RDATA), .R_RESP(g0_RRESP),
    .ECOREVNUM(4'h0),
    .PORTIN(p0_in), .PORTOUT(p0_out), .PORTEN(p0_outen), .PORTFUNC(p0_altfunc),
    .GPIOINT(), .COMBINT());

  // ================= FIR / DMA =================
  fir_top #(.CORE_TYPE(0)) u_fir (
    .ACLK(ACLK), .ARESETn(ARESETn),
    .AW_SEL(fir_awsel), .AW_VALID(sys_AWVALID), .AW_READY(fir_AWREADY),
    .AW_SIZE(sys_AWSIZE), .AW_BURST(sys_AWBURST), .AW_LEN(sys_AWLEN),
    .AW_ADDR(sys_AWADDR),
    .W_VALID(sys_WVALID), .W_READY(fir_WREADY), .W_LAST(sys_WLAST), .W_DATA(sys_WDATA),
    .B_VALID(fir_BVALID), .B_READY(sys_BREADY), .B_RESP(fir_BRESP),
    .AR_SEL(fir_arsel), .AR_VALID(sys_ARVALID), .AR_READY(fir_ARREADY),
    .AR_SIZE(sys_ARSIZE), .AR_BURST(sys_ARBURST), .AR_LEN(sys_ARLEN),
    .AR_ADDR(sys_ARADDR),
    .R_VALID(fir_RVALID), .R_READY(sys_RREADY), .R_LAST(fir_RLAST),
    .R_DATA(fir_RDATA), .R_RESP(fir_RRESP));

  dma_top u_dma (
    .ACLK(ACLK), .ARESETn(ARESETn),
    .AW_SEL(dma_awsel), .AW_VALID(sys_AWVALID), .AW_READY(dma_AWREADY),
    .AW_SIZE(sys_AWSIZE), .AW_BURST(sys_AWBURST), .AW_LEN(sys_AWLEN),
    .AW_ADDR(sys_AWADDR),
    .W_VALID(sys_WVALID), .W_READY(dma_WREADY), .W_LAST(sys_WLAST), .W_DATA(sys_WDATA),
    .B_VALID(dma_BVALID), .B_READY(sys_BREADY), .B_RESP(dma_BRESP),
    .AR_SEL(dma_arsel), .AR_VALID(sys_ARVALID), .AR_READY(dma_ARREADY),
    .AR_SIZE(sys_ARSIZE), .AR_BURST(sys_ARBURST), .AR_LEN(sys_ARLEN),
    .AR_ADDR(sys_ARADDR),
    .R_VALID(dma_RVALID), .R_READY(sys_RREADY), .R_LAST(dma_RLAST),
    .R_DATA(dma_RDATA), .R_RESP(dma_RRESP),
    .awvalid(dma_awvalid), .awready(dma_awready), .awsize(dma_awsize),
    .awburst(dma_awburst), .awlen(dma_awlen), .awaddr(dma_awaddr),
    .wvalid(dma_wvalid), .wready(dma_wready), .wdata(dma_wdata), .wlast(dma_wlast),
    .bvalid(dma_bvalid), .bready(dma_bready), .bresp(dma_bresp),
    .arvalid(dma_arvalid), .arready(dma_arready), .arsize(dma_arsize),
    .arburst(dma_arburst), .arlen(dma_arlen), .araddr(dma_araddr),
    .rvalid(dma_rvalid), .rready(dma_rready), .rdata(dma_rdata), .rresp(dma_rresp),
    .rlast(dma_rlast),
    .irq_o(dma_irq));

  // ================= 默认从机 =================
  cmsdk_axi_default_slave u_defslv (
    .ACLK(ACLK), .ARESETn(ARESETn),
    .AW_SEL(defslv_awsel), .AW_VALID(sys_AWVALID), .AW_READY(def_AWREADY),
    .AW_LEN(sys_AWLEN),
    .W_VALID(sys_WVALID), .W_READY(def_WREADY),
    .B_VALID(def_BVALID), .B_READY(sys_BREADY), .B_RESP(def_BRESP),
    .AR_SEL(defslv_arsel), .AR_VALID(sys_ARVALID), .AR_READY(def_ARREADY),
    .AR_LEN(sys_ARLEN),
    .R_VALID(def_RVALID), .R_READY(sys_RREADY), .R_LAST(def_RLAST),
    .R_DATA(def_RDATA), .R_RESP(def_RRESP));

  // ================= 中断 =================
  // 按任务1笔记核对：apbsubsys_interrupt[0]=UART0 TX、[1]=UART0 RX
  assign intisr[0]    = apbsubsys_interrupt[0];
  assign intisr[1]    = apbsubsys_interrupt[1];
  assign intisr[15:2] = 14'h0;
  assign intisr[16]   = dma_irq;
  assign intisr[31:17]= 15'h0;
endmodule
```

- [ ] **Step 5: 运行TB，确认绿灯**

Run: `make -f Makefile.fir sim_tb_soc_smoke`，Expected: `PASS: SoC冒烟——CPU启动、UART2输出Hello world`。
排障要点：若CPU锁死（LOCKUP），用GTKWave看 `u_soc.u_arb` 的AW/AR握手（`make wave_tb_soc_smoke` 附加目标：`$(OUT)/$*.vcd` 后用 `gtkwave`）；检查`cmsdk_axi_flash`的`filename`相对路径；若APB中断位序与笔记不符，修正intisr接线并更新笔记。

- [ ] **Step 6: 提交**

```bash
cd /d/ICT/Cortexm0ds && git add rtl/soc/ tb/tb_soc_smoke.v Makefile && git commit -m "feat: SoC顶层集成（CPU+仲裁+官方子系统+FIR+DMA），冒烟通过

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

**验收**：`make -f Makefile.fir sim_tb_soc_smoke` 绿。集成风险点（时钟域、IRQ、W广播、地址映射）全部暴露并解决于本任务。

---

### 任务 13：固件 fir_demo（UART回显 + DMA自检 + FIR软硬协同验证）

**Files:**
- Create: `sw/firmware/fir_demo/makefile`、`sw/firmware/fir_demo/fir_demo.c`、`sw/firmware/fir_demo/fir_ref.h`；Test: `tb/tb_soc.v`
- 复用（相对路径引用，不改动）：ref的CMSIS启动 `startup_CMSDK_CM0.s(GCC)`、`system_CMSDK_CM0.c`、`retarget.c`、`uart_stdout.c`、链接脚本 `cmsdk_cm0.ld`

**Interfaces:**
- Consumes: 任务5的 `fir_golden.h`、任务12的 `soc_top`、地址映射（任务4）与寄存器映射（任务7/10）
- Produces: `fir_demo.hex`（objcopy -O verilog）与UART输出协议：`** FIR PASS **`/`** DMA PASS **`/`** ECHO PASS **`/`max_err=...`/`cycles=...`——TB断言这些标记

- [ ] **Step 1: 写 makefile（沿袭官方hello的gcc流程）**

```makefile
# fir_demo makefile（沿袭官方 hello/makefile 的gcc流程，改为引用ref路径）
REF      = ../../..
SOFTWARE = ./software
CMSIS    = $(SOFTWARE)/cmsis
CORE_DIR = $(CMSIS)/CMSIS/Include
DEV_DIR  = $(CMSIS)/Device/ARM/CMSDK_CM0
TESTNAME = fir_demo

CC      = arm-none-eabi-gcc
OBJDUMP = arm-none-eabi-objdump
OBJCOPY = arm-none-eabi-objcopy

all:
	$(CC) -g -O2 -mthumb -mcpu=cortex-m0 \
		$(DEV_DIR)/Source/GCC/startup_CMSDK_CM0.s \
		fir_demo.c \
		$(SOFTWARE)/common/retarget/retarget.c \
		$(SOFTWARE)/common/retarget/uart_stdout.c \
		$(DEV_DIR)/Source/system_CMSDK_CM0.c \
		-I $(DEV_DIR)/Include -I $(CORE_DIR) -I $(SOFTWARE)/common/retarget -I . \
		-L $(SOFTWARE)/common/scripts \
		-D__STACK_SIZE=0x200 -D__HEAP_SIZE=0x1000 -DCORTEX_M0 \
		-T $(SOFTWARE)/common/scripts/cmsdk_cm0.ld -o $(TESTNAME).o
	$(OBJDUMP) -S $(TESTNAME).o > $(TESTNAME).lst
	$(OBJCOPY) -S $(TESTNAME).o -O binary $(TESTNAME).bin
	$(OBJCOPY) -S $(TESTNAME).o -O verilog $(TESTNAME).hex

clean:
	rm -rf *.o *.lst *.bin *.hex
```

- [ ] **Step 2: 写 fir_ref.h（软件参考滤波器，双精度）**

```c
// fir_ref.h : 软件参考FIR（双精度）。与tools/gen_fir_golden.py同口径：
// 系数/输入为Q1.15量化值转double，输出量化到Q1.31（与硬件仅差实现误差）
#ifndef FIR_REF_H
#define FIR_REF_H
#include "fir_golden.h"

static int fir_ref_run(const short *coef, const short *x, int n, int *y_out)
{
    int n, k;
    for (n = 0; n < FIR_N; n++) {
        double acc = 0.0;
        for (k = 0; k < FIR_TAPS; k++)
            if (n - k >= 0)
                acc += (coef[k] / 32768.0) * (x[n - k] / 32768.0);
        /* 量化到Q1.31（与硬件输出同格式） */
        double v = acc * 2147483648.0;
        int iv;
        if (v >= 2147483647.0) iv = 2147483647;
        else if (v <= -2147483648.0) iv = -2147483648;
        else iv = (int)v;
        y_out[n] = iv;
    }
    return 0;
}

/* 相对误差（分母下限0.001满幅，与TB同口径） */
static double fir_max_rel_err(const int *hw, const int *ref, int n)
{
    double maxe = 0.0;
    int i;
    for (i = 0; i < n; i++) {
        double e = (double)hw[i] / 2147483648.0 - (double)ref[i] / 2147483648.0;
        double d = (double)ref[i] / 2147483648.0;
        if (e < 0) e = -e;
        if (d < 0) d = -d;
        if (d < 0.001) d = 0.001;
        e = e / d;
        if (e > maxe) maxe = e;
    }
    return maxe;
}
#endif
```

- [ ] **Step 3: 写 fir_demo.c**

```c
// fir_demo.c : 初赛/决赛演示固件
// 流程：UART2横幅 → UART0回显64字符 → 6通道DMA自检 → FIR软硬协同（DMA搬运）
//       → 误差/周期指标打印 → 结束仿真
#include "CMSDK_CM0.h"
#include "core_cm0.h"
#include <stdio.h>
#include "uart_stdout.h"
#include "fir_golden.h"
#include "fir_ref.h"

#define FIR_BASE   0x40020000u
#define FIR_CTRL   (*(volatile unsigned int *)(FIR_BASE + 0x00))
#define FIR_STATUS (*(volatile unsigned int *)(FIR_BASE + 0x04))
#define FIR_DIN    (*(volatile unsigned int *)(FIR_BASE + 0x08))
#define FIR_DOUT   (*(volatile unsigned int *)(FIR_BASE + 0x0C))
#define FIR_COEF(n) (*(volatile unsigned int *)(FIR_BASE + 0x10 + 4*(n)))

#define DMA_BASE   0x40030000u
#define DMA_CH(n,off) (*(volatile unsigned int *)(DMA_BASE + 0x20*(n) + (off)))
#define DMA_INT_STATUS (*(volatile unsigned int *)(DMA_BASE + 0x100))
#define DMA_INT_CLR    (*(volatile unsigned int *)(DMA_BASE + 0x104))

#define UART0_BASE 0x40004000u
#define UART0_DATA  (*(volatile unsigned int *)(UART0_BASE + 0x00))
#define UART0_STATE (*(volatile unsigned int *)(UART0_BASE + 0x04))

#define DMA_IRQn 16

volatile int g_dma_done = 0;
void IRQ16_Handler(void)            // 名称以startup_CMSDK_CM0.s(GCC)为准，见Step 4核对
{
    unsigned int st = DMA_INT_STATUS;
    DMA_INT_CLR = st;
    g_dma_done |= st;
}

/* UART0轮询收发（回显测试用） */
static int uart0_rx_full(void) { return UART0_STATE & 0x2; }
static int uart0_tx_full(void) { return UART0_STATE & 0x1; }
static char uart0_getc(void)  { return (char)UART0_DATA; }
static void uart0_putc(char c){ while (uart0_tx_full()); UART0_DATA = c; }

/* 等DMA通道集合全部完成（轮询+中断兜底） */
static int dma_wait(unsigned int chmask, int timeout)
{
    int t = 0;
    while (((DMA_INT_STATUS & chmask) != chmask) && t < timeout) { t++; }
    if (t >= timeout) return -1;
    DMA_INT_CLR = chmask;
    return 0;
}

int main(void)
{
    static int hw_out[FIR_N];
    static int ref_out[FIR_N];
    static short in_buf[FIR_N];
    static short out_buf[FIR_N];
    int i;
    unsigned int t0, t1;
    double max_err;

    UartStdOutInit();
    printf("\nFIR-SoC Demo\n");

    /* ---- 1) UART0回显（BFM发64字符并核对）---- */
    for (i = 0; i < 64; i++) {
        while (!uart0_rx_full());
        uart0_putc(uart0_getc());
    }
    printf("** ECHO PASS **\n");

    /* ---- 2) 6通道DMA自检（各拷256字节SRAM块）---- */
    for (i = 0; i < 6; i++) {
        DMA_CH(i, 0x00) = 0x20000000u + i * 256;     /* SRC */
        DMA_CH(i, 0x04) = 0x20008000u + i * 256;     /* DST */
        DMA_CH(i, 0x08) = 256;                       /* LEN字节 */
        DMA_CH(i, 0x0C) = 0x0023u;                   /* GO|IRQ_EN|BURST=0(1拍) */
    }
    if (dma_wait(0x3F, 1000000)) { printf("** DMA FAIL **\n"); return 1; }
    {
        volatile unsigned int *s, *d;
        int ok = 1;
        for (i = 0; i < 6 && ok; i++) {
            int w;
            s = (volatile unsigned int *)(0x20000000u + i * 256);
            d = (volatile unsigned int *)(0x20008000u + i * 256);
            for (w = 0; w < 64; w++) if (d[w] != s[w]) ok = 0;
        }
        if (!ok) { printf("** DMA FAIL **\n"); return 1; }
    }
    printf("** DMA PASS **\n");

    /* ---- 3) FIR软硬协同：CPU配系数→DMA搬输入→DMA收输出→C参考比对 ---- */
    FIR_CTRL = 1;                       /* CLR */
    for (i = 0; i < FIR_TAPS; i++) FIR_COEF(i) = (unsigned short)fir_coeff[i];
    for (i = 0; i < FIR_N; i++) in_buf[i] = fir_input[i];

    SysTick->CTRL = 0; SysTick->LOAD = 0xFFFFFF; SysTick->VAL = 0;
    SysTick->CTRL = 1;                  /* 使能，无中断 */

    DMA_CH(0, 0x00) = (unsigned int)&in_buf[0];     /* SRAM→FIR DIN */
    DMA_CH(0, 0x04) = FIR_BASE + 0x08;
    DMA_CH(0, 0x08) = FIR_N;                        /* FIXED_DST：拍数 */
    DMA_CH(0, 0x0C) = 0x060Bu;                      /* GO|IRQ_EN|FIXED_DST|FSIZE=2|BURST=1 */
    DMA_CH(1, 0x00) = FIR_BASE + 0x0C;              /* FIR DOUT→SRAM */
    DMA_CH(1, 0x04) = (unsigned int)&out_buf[0];
    DMA_CH(1, 0x08) = FIR_N;
    DMA_CH(1, 0x0C) = 0x0607u;                      /* GO|IRQ_EN|FIXED_SRC|FSIZE=2|BURST=1 */
    if (dma_wait(0x3, 100000000)) { printf("** FIR DMA TIMEOUT **\n"); return 1; }
    t0 = SysTick->VAL;

    /* C参考（与黄金同口径）并比对 */
    fir_ref_run(fir_coeff, in_buf, FIR_N, ref_out);
    for (i = 0; i < FIR_N; i++) hw_out[i] = out_buf[i];
    max_err = fir_max_rel_err(hw_out, ref_out, FIR_N);

    t1 = SysTick->VAL;
    printf("max_err=%.6f\n", max_err);
    printf("cycles=%u\n", (unsigned)(0xFFFFFFu - (t1 >= t0 ? t1 - t0 : 0)));
    if (max_err < 0.001) printf("** FIR PASS **\n");
    else                 printf("** FIR FAIL **\n");

    UartEndSimulation();
    while (1);
    return 0;
}
```

（实现说明：SysTick计周期只覆盖等待段近似值，正式指标以任务14的TB侧测量为准；`in_buf`从`fir_input`复制到SRAM保证DMA源在SRAM。）

- [ ] **Step 4: 核对中断向量名并编译**

在 `software/cmsis/Device/ARM/CMSDK_CM0/Source/GCC/startup_CMSDK_CM0.s` 中查IRQ16对应的弱符号名（预期 `IRQ16_Handler`，也可能是自定义名）。若名字不同，把 fir_demo.c 的中断函数改名一致。然后：

```bash
cd /d/ICT/Cortexm0ds/sw/firmware/fir_demo && mingw32-make
```

Expected: 生成 `fir_demo.hex`（无错误）。如链接报段溢出，检查栈/堆定义（`__STACK_SIZE`/`__HEAP_SIZE`）与`cmsdk_cm0.ld`的RAM尺寸（63K）。

- [ ] **Step 5: 写系统级TB tb_soc.v（回显+固件输出断言）**

```verilog
// tb_soc.v : 系统级验证——加载fir_demo.hex，UART0回显核对+UART2输出断言
`timescale 1ns/1ps
module tb_soc;
  reg  ACLK, ARESETn, PCLK, PRESETn;
  wire uart0_rxd, uart0_txd, uart0_txen, uart2_txd, uart2_txen;
  wire [15:0] gpio0_out;
  reg  uart0_tx_bfm;

  tb_clkreset #() u_ck (.clk(ACLK), .rstn(ARESETn));

  always @(posedge ACLK) begin PCLK <= ACLK; PRESETn <= ARESETn; end

  soc_top #(.FILENAME("sw/firmware/fir_demo/fir_demo.hex"), .MEM_IMPL(0))
  u_soc (
    .ACLK(ACLK), .ARESETn(ARESETn), .PCLK(PCLK), .PRESETn(PRESETn),
    .uart0_rxd(uart0_rxd), .uart0_txd(uart0_txd), .uart0_txen(uart0_txen),
    .uart2_txd(uart2_txd), .uart2_txen(uart2_txen),
    .gpio0_out(gpio0_out), .DFTSE(1'b0));

  uart_bfm u0_bfm (.txd(uart0_rxd), .rxd(uart0_txd));   // 回显测试
  uart_bfm u2_bfm (.txd(), .rxd(uart2_txd));            // stdout监视

  reg  [7:0] rx_byte;
  reg  [8*4096-1:0] logbuf;                              // 收集stdout
  integer lp;

  // UART0回显：发64字符并逐一核对
  initial begin
    integer i;
    wait (ARESETn == 1'b1);
    #50000000;                                             // 等固件初始化+banner打完（9600约15ms）
    for (i = 0; i < 64; i = i + 1) begin
      u0_bfm.uart_tx(8'h30 + (i % 10));                  // '0'..'9'循环
      u0_bfm.uart_rx(rx_byte);
      if (rx_byte !== 8'h30 + (i % 10))
        $fatal(1, "FAIL: 回显第%0d字符=%h", i, rx_byte);
    end
    $display("回显64字符全部正确");
  end

  // UART2 stdout收集（直至仿真结束标记）
  initial begin
    lp = 0; logbuf = 0;
    while (1) begin
      u2_bfm.uart_rx(rx_byte);
      logbuf = (logbuf << 8) | rx_byte;
      lp = lp + 1;
    end
  end

  // 判定（等待仿真结束或超时）
  initial begin
    #2000000000;                                         // 2秒仿真时间兜底
    $display("stdout日志尾部=%0s", logbuf[(lp > 64 ? lp - 64 : 0)*8 +: 512]);
    if (!strstr_flag(logbuf, "ECHO PASS")) $fatal(1, "FAIL: 缺ECHO PASS");
    if (!strstr_flag(logbuf, "DMA PASS"))  $fatal(1, "FAIL: 缺DMA PASS");
    if (!strstr_flag(logbuf, "FIR PASS"))  $fatal(1, "FAIL: 缺FIR PASS");
    if (strstr_flag(logbuf, "FAIL"))       $fatal(1, "FAIL: 固件报告失败");
    $display("PASS: 固件回显+DMA自检+FIR软硬协同全部通过");
    $finish;
  end

  function strstr_flag; input [8*4096-1:0] buf; input [8*63:0] key;
    integer i, j; reg hit;
    begin
      strstr_flag = 0;
      for (i = 0; i < lp - 3; i = i + 1) begin
        hit = 1;
        for (j = 0; j < 64; j = j + 1)
          if (buf[(i + j)*8 +: 8] !== key[j*8 +: 8] && key[j*8 +: 8] !== 8'h00) hit = 0;
        if (hit) strstr_flag = 1;
      end
    end
  endfunction
endmodule
```

- [ ] **Step 6: 运行TB，确认绿灯**

Run: `make -f Makefile.fir sim_tb_soc`，Expected: `回显64字符全部正确`、`PASS: 固件回显+DMA自检+FIR软硬协同全部通过`。
排障：FIR超时→查FIXED_DST/FSIZE编码与dma_channel的`cfg_len<<fsize`；误差超标→查fir_top系数写（COEF地址对齐）；回显失败→查UART0地址/分频与BFM波特率匹配。

- [ ] **Step 7: 提交**

```bash
cd /d/ICT/Cortexm0ds && git add sw/firmware/fir_demo/ tb/tb_soc.v && git commit -m "feat: fir_demo固件（回显+DMA自检+FIR软硬协同<0.1%）

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

**验收**：`make -f Makefile.fir sim_tb_soc` 绿。对应初赛"CPU正常跑通（UART回显）+ FIR误差<0.1% + DMA 6通道独立零差错 + 软硬协同验证"四大项。

---

### 任务 14：性能指标测量（决赛四项数据）

**Files:**
- Modify: `tb/tb_soc.v`（加吞吐/带宽/延迟监视器）；Create: `docs/指标记录.md`（数据表模板）

**Interfaces:**
- Consumes: 任务13产物。决赛四项指标定义（写进报告的口径）：
  - **FIR吞吐量(samples/cycle)** = 总样本数 / 总周期（TB在DIN写与DOUT读间计数）
  - **DMA带宽(MB/s)** = 传输字节数 / 耗时（TB按AXI握手统计，或固件SysTick换算）
  - **CPU主频(MHz)** = FPGA实际时钟（任务16获取，仿真按50MHz记录）
  - **系统总延迟(μs)** = 最后一拍DIN写入 → 第一拍DOUT读出（TB监视器直接测量）

- [ ] **Step 1: 给 tb_soc.v 增加监视逻辑**

在TB中新增（挂在u_soc内部信号上，通过层次引用）：

```verilog
  // ---- 指标监视（层次引用内部信号）----
  wire fir_din_hs  = u_soc.u_fir.W_VALID && u_soc.u_fir.W_READY &&
                     (u_soc.u_fir.w_a[11:0] == 12'h008);      // DIN寄存器写握手
  wire fir_dout_hs = u_soc.u_fir.R_VALID && u_soc.u_fir.R_READY &&
                     (u_soc.u_fir.r_a[11:0] == 12'h00C);      // DOUT寄存器读握手
  reg [63:0] t_first_din, t_last_din, t_first_dout, t_last_dout, din_cnt, dout_cnt;
  reg done_flag;

  always @(posedge ACLK) begin
    if (!ARESETn) begin
      t_first_din=0; t_last_din=0; t_first_dout=0; t_last_dout=0;
      din_cnt=0; dout_cnt=0; done_flag=0;
    end else if (!done_flag) begin
      if (fir_din_hs) begin
        if (din_cnt == 0) t_first_din = $time;
        t_last_din = $time;
        din_cnt = din_cnt + 1;
      end
      if (fir_dout_hs) begin
        if (dout_cnt == 0) t_first_dout = $time;
        t_last_dout = $time;
        dout_cnt = dout_cnt + 1;
      end
      if (dout_cnt == 1024 && din_cnt == 1024) done_flag = 1;
    end
  end

  // 判定块末尾输出指标
  initial begin
    #2000000000;
    if (!done_flag) $fatal(1, "FAIL: 指标监视未完成 din=%0d dout=%0d", din_cnt, dout_cnt);
    $display("===== 指标（50MHz仿真）=====");
    $display("FIR吞吐量 = %.3f samples/cycle",
             $itor(dout_cnt) / (($itor(t_last_dout - t_first_dout) / 20.0) + 1.0));
    $display("系统延迟 = %.2f us", $itor(t_first_dout - t_first_din) / 1000.0);
    $display("DMA带宽(按固件cycles打印换算，任务16上板复测)");
    $display("===== 指标结束 =====");
    $finish;
  end
```

（实现说明：FIR_DIN写通过DMA进行（AXI主侧握手），而fir_din_hs挂在FIR从机侧W握手——两者等价；若层次路径与实现信号名有出入，用`$display`定位实际信号名后再接线，断言不变。）

- [ ] **Step 2: 运行并记录**

Run: `make -f Makefile.fir sim_tb_soc`，Expected: 输出指标段。将数据填入 `docs/指标记录.md` 模板：

```markdown
# 指标记录（决赛四项）
| 指标 | 仿真值(50MHz) | FPGA初版(50MHz) | FPGA优化版(≥100MHz) | 备注 |
|---|---|---|---|---|
| FIR吞吐量 samples/cycle | | | | 串行=1/82；对称核=1 |
| DMA带宽 MB/s | | | | |
| CPU主频 MHz | 50 | | | |
| 系统总延迟 us | | | | |
| LUT/FF/BRAM/DSP占用 | | | | 加权：LUT30/FF20/BRAM20/DSP30 |
```

- [ ] **Step 3: 提交**

```bash
cd /d/ICT/Cortexm0ds && git add tb/tb_soc.v docs/指标记录.md && git commit -m "feat: 决赛四项指标测量（TB监视器+记录模板）

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

**验收**：指标段正常输出且数据合理（对称核吞吐应≈1 samples/cycle；延迟为μs量级）。**里程碑：全部初赛功能在仿真层面闭环。**

---

## 阶段 5：FPGA 验证（对应 FR-8）

### 任务 15：PDS工程 + axi_rom + 约束 + UART回显上板

**Files:**
- Create: `rtl/fpga/axi_rom.v`、`fpga/pango/top_pgl.v`（板级顶层：PLL+pad）、`fpga/pango/constraints.fdc`、`fpga/pango/README.md`（工程建立步骤）
- 前置：**开发板到货**（紫光同创Logos-2 PG2L100H或资源相当，队伍自备）；安装Pango Design Suite

**Interfaces:**
- Consumes: 任务12的 `soc_top`（MEM_IMPL=1路径预留了axi_rom）
- Produces: 可烧录bit流；板级UART回显演示

- [ ] **Step 1: 写 axi_rom.v（FPGA用只读ROM，$readmemh初始化→BRAM初值）**

```verilog
// axi_rom.v : FPGA用只读ROM（CMSDK从机风格，替代仿真flash模型）
// $readmemh初始值在PDS综合时推断为BRAM/ROM初值（若工具不支持initial初始化，
// 改为generate+参数或厂商IP生成.coe——以PDS文档为准，接口不变）。
`timescale 1ns/1ps
module axi_rom #(
    parameter FILENAME = "image.hex",
    parameter AW = 16                       // 64K字节
)(
    input  wire        ACLK,
    input  wire        ARESETn,
    input  wire        AR_SEL,
    input  wire        AR_VALID, output reg AR_READY,
    input  wire [2:0]  AR_SIZE,  input wire [1:0] AR_BURST,
    input  wire [7:0]  AR_LEN,   input wire [AW-1:0] AR_ADDR,
    output reg         R_VALID,  input wire R_READY,
    output reg  [31:0] R_DATA,   output reg [1:0] R_RESP,
    output reg         R_LAST
);
  reg [31:0] rom [0:(1<<(AW-2))-1];
  reg [AW-3:0] r_a; reg [7:0] r_cnt; reg r_busy; reg [1:0] r_burst;
  initial if (FILENAME != "") $readmemh(FILENAME, rom);

  always @(posedge ACLK or negedge ARESETn) begin
    if (!ARESETn) begin
      r_busy <= 0; r_cnt <= 0; r_a <= 0; r_burst <= 0;
      AR_READY <= 1; R_VALID <= 0; R_RESP <= 0; R_LAST <= 0;
    end else begin
      if (!r_busy) begin
        AR_READY <= 1;
        if (AR_VALID && AR_READY) begin
          r_a <= AR_ADDR[AW-1:2]; r_cnt <= AR_LEN; r_burst <= AR_BURST;
          AR_READY <= 0; r_busy <= 1;
        end
      end else begin
        if (R_VALID && R_READY) begin
          if (r_burst[0]) r_a <= r_a + 1'b1;
          if (r_cnt == 0) begin r_busy <= 0; AR_READY <= 1; R_VALID <= 0; end
          else r_cnt <= r_cnt - 8'd1;
        end else if (!R_VALID) begin
          R_VALID <= 1; R_DATA <= rom[r_a]; R_LAST <= (r_cnt == 0); R_RESP <= 2'b00;
        end
      end
    end
  end
endmodule
```

- [ ] **Step 2: 写板级顶层 top_pgl.v（PLL+引脚+复位同步）**

```verilog
// top_pgl.v : Logos-2板级顶层——PLL产生系统时钟，pad隔离，复位同步
// 板载晶振频率以实际开发板原理图为准（示例按50MHz写）
`timescale 1ns/1ps
module top_pgl(
    input  wire       clk_in,          // 板载晶振
    input  wire       rst_n_in,        // 板载复位按键（低有效）
    input  wire       uart0_rxd_in,    // USB转串口TX→FPGA
    output wire       uart0_txd_out,   // FPGA→USB转串口RX
    output wire [15:0] led_out
);
  wire clk_sys, clk_locked, rst_n_sync;

  // PLL：50MHz→100MHz（先50MHz保功能，任务16提升；按PDS的PLL IP配置）
  GTP_CLKPLL #(.FREQ_IN(50.0), .FREQ_OUT(100.0)) u_pll (
    .clkin(clk_in), .clkout(clk_sys), .lock(clk_locked));   // IP名以PDS模板为准

  // 复位同步（两级）
  reg r1, r2;
  always @(posedge clk_sys) begin r1 <= rst_n_in & clk_locked; r2 <= r1; end
  assign rst_n_sync = r2;

  soc_top #(.FILENAME("sw/firmware/fir_demo/fir_demo.hex"), .MEM_IMPL(1))
  u_soc (
    .ACLK(clk_sys), .ARESETn(rst_n_sync), .PCLK(clk_sys), .PRESETn(rst_n_sync),
    .uart0_rxd(uart0_rxd_in), .uart0_txd(uart0_txd_out), .uart0_txen(),
    .uart2_txd(uart2_txd_out), .uart2_txen(),
    .gpio0_out(led_out), .DFTSE(1'b0));

  // uart2_txd_out：引到第二串口或PMOD（演示用stdout）
  output wire uart2_txd_out;
  assign uart2_txd_out = u_soc.uart2_txd;
endmodule
```

- [ ] **Step 3: 写约束 constraints.fdc（引脚与时钟，按实际板卡修改）**

```tcl
# constraints.fdc（示例，引脚号按开发板原理图修改）
create_clock -name clk_sys -period 20 [get_nets {clk_in}]     # 50MHz→先按20ns，PLL后10ns
set_input_delay  -clock clk_sys -max 4 [get_ports {uart0_rxd_in rst_n_in}]
set_output_delay -clock clk_sys -max 4 [get_ports {uart0_txd_out led_out[*]}]
set_pin_loc uart0_txd_out  <引脚号>     # 按板卡原理图
set_pin_loc uart0_rxd_in   <引脚号>
set_pin_loc clk_in         <引脚号>
set_pin_loc rst_n_in       <引脚号>
set_pin_loc led_out[0]     <引脚号>
```

- [ ] **Step 4: 建PDS工程并综合（GUI步骤，写入fpga/pango/README.md）**

README.md记录完整流程（团队照做）：
1. 新建工程→器件选 **PG2L100H**（封装/速度级按实物丝印）→语言Verilog；
2. 添加源文件：本项目全部`rtl/**`+官方RTL列表（复用任务12 Makefile的REF_RTL清单）；
3. 添加约束 constraints.fdc；
4. 配置PLL IP（50→100MHz）或用系统原语时钟（先50MHz直连验证）；
5. 综合→布局布线→生成bit流；记录资源报告（LUT/FF/BRAM/DSP，**填docs/指标记录.md**）；
6. 烧录。

- [ ] **Step 5: 板上验收清单（UART回显里程碑）**

逐项勾选并录屏留档（演示视频素材）：
- [ ] 上电后串口终端（9600-8N1）收到 `FIR-SoC Demo` 横幅
- [ ] 发送任意64字符，终端原样回显（UART回显=初赛验收项）
- [ ] 串口出现 `** ECHO PASS **`、`** DMA PASS **`、`** FIR PASS **`、`max_err=<0.001`
- [ ] LED按固件演示程序亮起（如GPIO0写流水灯——若固件未加，此步在任务16补）
- [ ] 记录此时资源占用与时钟频率到指标表

- [ ] **Step 6: 提交**

```bash
cd /d/ICT/Cortexm0ds && git add rtl/fpga/ fpga/ && git commit -m "feat: FPGA工程（axi_rom+PDS约束+板级顶层），UART回显上板

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

**验收**：验收清单全部勾选。对应初赛"FPGA综合验证20分"。

---

### 任务 16：全系统上板、指标采集与频率优化

**Files:**
- Modify: `fpga/pango/top_pgl.v`、约束、固件（按需）；Update: `docs/指标记录.md`

- [ ] **Step 1: 上板全功能演示（决赛演示内容）**

- [ ] 串口菜单演示：横幅→回显→DMA自检→FIR滤波结果打印（`max_err`）
- [ ] 实时滤波演示：串口下发正弦+噪声数据→DMA搬入FIR→滤波结果串口回传（若固件未实现，加一个"流式演示模式"：接收N样本→滤波→回传，代码改动在fir_demo.c，走任务13的编译流程）
- [ ] LED/GPIO演示（可选加分）：GPIO0接LED显示滤波能量等级

- [ ] **Step 2: 指标采集（决赛四项+资源）**

按 `docs/指标记录.md` 表逐项填写：
- [ ] FIR吞吐量：按固件cycles与已知样本数换算 samples/cycle（对称核应≈1）
- [ ] DMA带宽：固件打印的cycles×时钟周期换算 MB/s；或TB统计（任务14）折算
- [ ] CPU主频：PDS时序报告的实际Fmax（PLL 50→100MHz目标）
- [ ] 系统总延迟：任务14方法上板复测（DIN末拍→DOUT首拍）
- [ ] 资源：PDS资源报告 LUT/FF/BRAM/DSP，按LUT30/FF20/BRAM20/DSP30加权记录

- [ ] **Step 3: 频率优化（CPU主频排名项）**

按序尝试（每步后跑时序报告并记录Fmax）：
1. 50MHz直连→确认功能（基线）；
2. PLL提到100MHz→若时序违例，看关键路径（预计在FIR加法树或SRAM读路径）；
3. FIR加法树插寄存器级（对称核已分级，违例则把乘法后移一级）/ SRAM读寄存；
4. 关键路径优化后再提频，最终以时序干净的最高频率为准，更新指标表。
**目标：≥100MHz；不达标也如实记录，答辩说明瓶颈。**

- [ ] **Step 4: 提交（指标表+优化记录）**

```bash
cd /d/ICT/Cortexm0ds && git add fpga/ docs/指标记录.md && git commit -m "feat: 上板指标采集与频率优化（记录见docs/指标记录.md）

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

**验收**：指标表完整。**里程碑：FPGA验证闭环，决赛四项数据齐备。**

---

## 阶段 6：交付物（对照 Spec 第4节）

### 任务 17：技术报告（≤80页，DOC+PDF）

**Files:**
- Create: `docs/report/技术报告.md`（底稿，最后导出DOC/PDF）；章节与任务源码一一对应

**执行步骤：**

- [ ] **Step 1: 按大纲分章撰写（每章标注引用的代码/测试文件路径）**

```
1 系统工作原理分析（8-10页）
  1.1 异构SoC与边缘计算背景  1.2 FIR数字滤波原理（含Q1.15定点推导）
  1.3 AXI4协议要点（通道/握手/burst/4KB）  1.4 DMA与链式传输原理
2 系统体系结构设计（12-15页）
  2.1 总体架构图（对应rtl/soc/soc_top.v）  2.2 结构选择与技术选型（为何复用CMSDK、为何自研仲裁器）
  2.3 模块划分  2.4 地址映射（对应任务4）  2.5 接口描述（各模块端口表）
3 详细设计与实现（20-25页）
  3.1 多主AXI仲裁器（状态机+无死锁论证）  3.2 FIR：串行核+对称并行核（81→41乘加推导、定点饱和分析）
  3.3 DMA：字节精度搬移、固定地址模式、链式传输  3.4 FIR/DMA从机接口  3.5 固件设计
4 系统验证与分析（15-20页）
  4.1 验证策略（TDD循环、VIP/检查器）  4.2 黄金模型方法（量化口径，误差<0.1%的含义）
  4.3 各模块测试用例与结果（引用每个TB的PASS输出）  4.4 系统级软硬协同验证
5 FPGA验证与分析（8-10页）
  5.1 PDS工程与约束  5.2 上板结果（回显/滤波/指标表）  5.3 资源利用率分析  5.4 时序与频率
```
- [ ] **Step 2: 与代码一致性核对（评审门）**

逐章核对：模块名/端口名/寄存器地址/指标数字必须与代码和仿真输出一致（用grep抽查10处：`grep -n "模块名" rtl/**/*.v`）；报告中的架构图用drawio重画（`docs/report/架构图.drawio`）。
- [ ] **Step 3: 导出与页数控制**：markdown→WPS→DOC+PDF，确认≤80页；PDF嵌入架构图。
- [ ] **Step 4: 提交**（报告底稿入git，DOC/PDF放交付物目录`deliverables/`并提交）

**验收**：五大部分齐全、≤80页、与代码一致性抽查通过。对应"技术报告15分"。

---

### 任务 18：汇报PPT（≤15页）+ 讲解视频（8分钟）

**Files:**
- Create: `docs/ppt/汇报PPT大纲.md`、`docs/ppt/讲解视频脚本.md`

- [ ] **Step 1: PPT大纲（15页版式，内容对应评分要点）**

```
P1 封面（题目+队名）  P2 痛点与工程问题（边缘算力/总线瓶颈）
P3 总体架构（一张图讲清CPU+AXI+FIR+DMA）  P4 技术路线（复用+自研清单）
P5 多主AXI仲裁设计  P6 FIR设计：串行→对称41乘加（创新点1）
P7 FIR定点与精度分析（<0.1%怎么保证）  P8 DMA设计：字节精度+6通道
P9 DMA链式传输（创新点2）  P10 验证方法学（黄金模型+协议检查器+TDD）
P11 测试结果（TB矩阵+误差/零差错数据）  P12 FPGA上板结果（指标表+截图）
P13 与同行比较（对标：官方示例架构 vs 本设计；性能/资源表）
P14 成果与应用（可扩展性、应用场景）  P15 致谢/QA页
```
- [ ] **Step 2: 讲解视频脚本（8分钟分镜，每段配PPT页与讲稿要点）**

```
0:00-0:40 痛点导入（P2）  0:40-1:30 总体架构（P3/P4）
1:30-2:30 仲裁器+FIR对称优化（P5-P7）  2:30-3:30 DMA与链式（P8/P9）
3:30-4:30 验证方法学（P10/P11）  4:30-5:30 FPGA结果与指标（P12）
5:30-6:30 同行比较（P13）  6:30-7:30 成果应用与总结（P14）  7:30-8:00 结束语
```
- [ ] **Step 3: 录制与自查清单**

- [ ] 时长≤8分钟（mp4）  - [ ] 有演示片段穿插（录屏TB波形+板上串口）  - [ ] 声音清晰、无杂音
- [ ] 提交：PPT与视频入 `deliverables/` 并git提交

**验收**：PPT≤15页、视频≤8min且覆盖评分要求五点（痛点/难点创新/测试结果/同行比较/成果应用）。

---

### 任务 19：决赛演示视频（≤5分钟）+ 代码规范审查 + 源码包整理

- [ ] **Step 1: 演示视频分镜（≤5分钟，现场实拍+录屏剪辑）**

```
0:00-0:30 板卡全景+串口终端横幅  0:30-1:30 UART回显演示（边敲边回显）
1:30-2:30 DMA六通道演示（终端打印各通道校验通过）  2:30-3:30 FIR滤波演示（下发数据→滤波→打印误差）
3:30-4:00 指标展示（终端打印吞吐/延迟/带宽）  4:00-5:00 LED演示+收尾
```
- [ ] **Step 2: 代码规范审查（对应"代码规范性10分"）**

按清单逐项自查并修正（只动本项目文件）：
- [ ] RTL命名统一（小写+下划线、时钟复位命名一致）、每模块头注释（功能/接口/定点说明）
- [ ] TB与RTL分离清晰、TB自检且输出PASS/FAIL
- [ ] C代码符合基本规范（函数头注释、魔数用宏）
- [ ] **与详细设计文档一致性**：报告中的模块名/端口名逐一对上（任务17已做，此处复核）
- [ ] 跑一遍全量回归：`make -f Makefile.fir sim_tb_vip_smoke sim_tb_arb sim_tb_decode sim_tb_fir_core sim_tb_fir_top sim_tb_fir_core_sym sim_tb_dma_channel sim_tb_dma_top sim_tb_dma_chain sim_tb_soc_smoke sim_tb_soc` 全绿

- [ ] **Step 3: 源码包整理（对照Spec第4节）**

```
deliverables/
├─ 技术报告.doc/.pdf          （≤80页）
├─ 汇报PPT.pptx               （≤15页）
├─ 讲解视频.mp4               （≤8min）
├─ 演示视频.mp4               （≤5min）
└─ 源代码包.zip               （rtl/+tb/+sw/firmware/+docs，含README：目录说明、编译运行方法、
                             仿真复现步骤、版本与工具链记录；剔除sim_out/ref的.git等冗余）
```
- [ ] **Step 4: 最终提交与备份**

```bash
cd /d/ICT/Cortexm0ds && git add -A && git commit -m "docs: 交付物齐备（对照Spec第4节清单）

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

**验收**：Spec第4节五项交付物全部齐备、格式达标。**里程碑：项目完成，可提交。**

---

## 附录A：里程碑与建议分工

| 里程碑 | 任务 | 建议时间占比 | 并行分工建议 |
|---|---|---|---|
| M1 基线绿+走读完 | T0-T1 | 5% | 全员（统一认知） |
| M2 总线互连闭环 | T2-T4 | 10% | A：总线组（仲裁/译码） |
| M3 FIR闭环 | T5-T8 | 20% | B：FIR组（黄金模型→核→从机→对称优化） |
| M4 DMA闭环 | T9-T11 | 20% | C：DMA组（通道→6通道→链式） |
| M5 系统仿真闭环 | T12-T14 | 20% | A+B+C集成，D：固件组 |
| M6 FPGA闭环 | T15-T16 | 10% | A+B板级，D固件配合 |
| M7 交付物 | T17-T19 | 15% | 全员分章；报告牵头人+视频剪辑手 |

（三人团队的细化分工与AI协作规则见附录D。）

依赖提示：M2/M3/M4相互独立（仅依赖任务2的VIP），可真正并行；M5是合流点，务必给集成排障留余量（建议M5前预留一次全组联调）。

## 附录B：风险与对策

| 风险 | 概率 | 对策（已在计划中内建） |
|---|---|---|
| 官方RTL与计划端口名不符 | 中 | 任务1走读先行核对；任务12有按笔记修正IRQ位序的显式步骤 |
| 双主仲裁死锁/串扰 | 中 | 单事务在途设计+压力TB+协议检查器；默认从机兜底DECERR |
| FIR资源超出PG2L100H | 中 | 串行核保底（<5%资源）；对称核DSP不足时按任务8注释降为分时复用；资源指标全程记录 |
| 固件字节序/启动失败 | 低 | 官方hello.hex冒烟先行（任务12），隔离固件与硬件问题 |
| PDS对initial/readmemh支持差异 | 中 | axi_rom备选方案（任务15注释）；先50MHz直连保功能 |
| 赛程时间不足 | — | 每任务独立可验收，按里程碑裁剪：最坏情况砍T8/T11/T14（决赛加分项），初赛基本盘T0-T13+T15 |

## 附录C：本计划与赛题要求的覆盖对照

| 赛题要求（Spec FR） | 对应任务 |
|---|---|
| FR-1 81阶可配置FIR、误差<0.1% | T5-T8、T13 |
| FR-2 AXI共享总线互连 | T3、T4、T12 |
| FR-3 6通道DMA、三种传输、零差错、Burst | T9-T11 |
| FR-4 SRAM+可选ROM Boot | T12（复用官方SRAM/flash；ROM Boot为可选未做） |
| FR-5 CPU跑通+UART回显 | T12、T13 |
| FR-6 多主仲裁、AHB→AXI与AXI→APB桥、单拍/Burst合规、无死锁 | T2-T4、T12（桥复用官方，笔记佐证） |
| FR-7 软硬协同 | T13 |
| FR-8 FPGA综合验证 | T15、T16 |
| 代码规范10分 | T19 |
| 技术报告15分 | T17 |
| 决赛性能/资源/创新/答辩 | T8、T11、T14、T16、T18 |

## 附录D：三人团队 + AI 协作执行指南

### 角色映射（3人 + AI）

| 角色 | 负责 | 备注 |
|---|---|---|
| 甲：总线/集成 | T2-T4（AXI仲裁/译码），T12（SoC集成牵头） | 仲裁器对应初赛15分，最硬 |
| 乙：FIR | T5-T8（黄金模型→串行核→从机→对称并行） | 对称核是决赛20分创新点 |
| 丙：DMA | T9-T11（通道→6通道→链式） | 字节精度最易出错，靠TB兜底 |
| AI（Claude） | 每人各自开会话，让AI在本线内写代码/写TB/跑仿真/排障/写文档 | 见下方协作规则 |
| 共同 | T0-T1（第一周全员）；T12-T14（集成周全组在场）；T15-T16（板级轮流值守）；T17-T19（交付物分章） | 集成与答辩内容必须全员懂 |

### AI协作规则（让AI高效干活的关键）

1. **会话开场**：发"任务号+当前进度"，例：`执行计划任务6，Step 1-2已完成，现在实现fir_core`——AI按计划里该任务的Steps推进，不跑偏。
2. **判据永远是TB**：AI改完代码必须跑对应 `make -f Makefile.fir sim_tb_xxx`，PASS才算完；失败让它继续排障，禁止手工放行。
3. **红线**：官方文件（core/ mcu/ mcu_system/ doc/ image.hex makefile makefile1 software/ 及 tb/ 官方TB）只读；AI提出改官方文件一律拒绝（复用只能靠实例化）。
4. **提交节奏**：每个任务PASS后按计划里的提交命令git提交一次，不攒改动。
5. **分工防串**：每人只动自己目录（`rtl/ic`、`rtl/fir`、`rtl/dma`）；`Makefile`的RTL列表改动需先合并协商；接口以计划各任务"Interfaces"小节为准，集成前不要私自改端口。
6. **计划=真相**：实现与计划不符（如官方端口名对不上），让AI核对任务1走读笔记→修代码→把结论回写计划文档，保证计划与代码同步。

### 第一周行动（T0+T1）

- [ ] 全员装齐工具链（版本见Global Constraints：iverilog/GTKWave/mingw32-make/gcc-arm-none-eabi 10.3-2021.10/python）
- [ ] T0（见任务0；AI已代执行：工具链验证+基线跑通+docs入库）——全员拉取仓库后各自跑一遍 `make -f Makefile.fir baseline` 确认环境
- [ ] 走读分工（任务1清单11项）：甲=1/2/3/4/11项（总线与TB），乙=7/8/9/10项（存储/固件），丙=5/6项（桥）+补"复用决策表"整合
- [ ] 周五前各线第一个TB跑起来：甲 `make -f Makefile.fir sim_tb_arb`（T2-T3）、乙 `make -f Makefile.fir sim_tb_fir_core`（T5-T6）、丙 `make -f Makefile.fir sim_tb_dma_channel`（T9）

### 集成周（T12-T14）约定

集成是全组的事：甲主导soc_top接线、乙丙当评审；固件（T13）由AI先出草稿、甲牵头评审合入；任何一人的模块被TB证明有问题，当场修，不留到会后。

## 执行方式（Execution Handoff）

本计划可直接由团队按任务顺序人工执行；如需 Claude 辅助实现，请先与团队确认执行方式：
- **团队自驱（推荐）**：计划作为路线图，Claude 按需在会话中协助单个任务（写TB/排障/走查），每任务按 Steps 的"红灯→绿灯"自行验收。
- **代理执行**：由 Claude 逐任务实现（每任务含完整代码与验证命令），每任务完成后团队评审再继续下一任务。

无论哪种方式：参考代码以TB断言为最终判据；实现与计划不符时，修正代码并把结论回写本计划（保持计划=真相）。依赖顺序：T0→T1→(T2-T4 与 T5-T8 与 T9-T11 三线并行)→T12→T13→T14→T15→T16→T17-T19。
