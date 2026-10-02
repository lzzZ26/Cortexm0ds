# 赛题规格说明（Spec）：带高阶FIR数字滤波器的SoC处理器设计

- **来源**：中国电子杯高校ICT产教融合创新大赛——飞腾企业命题赛题讲解PPT V1.00
- **原文**：`D:\ICT\Cortexm0ds\yaoqiu\中国电子杯飞腾赛道赛题讲解PPT V1.00.pdf`
- **整理日期**：2026-10-02
- **注意**：本Spec为PPT原文整理。**赛程时间节点以大赛官网/官方群公告为准**，本Spec未包含截止日期。

## 1. 赛题概述

| 项目 | 内容 |
|---|---|
| 赛题名称 | 带高阶FIR数字滤波器的SoC处理器设计 |
| 命题方 | 飞腾信息技术有限公司 |
| 目标专业 | 计算机、集成电路、电子、通信等 |
| 能力层级 | 能完成SoC级RTL设计与板级验证 |
| 基础知识 | 计算机组成原理（CPU数据通路、总线协议）、C语言程序设计（嵌入式驱动开发）、Verilog HDL（RTL设计与仿真）、数字信号处理（FIR滤波器原理） |
| 赛题背景 | 物联网边缘计算、智能传感器及工业控制等领域，异构SoC架构成为主流：CPU承担系统控制与任务调度，专用硬件加速器负责高吞吐量数据运算 |

## 2. 功能需求（验收标准）

### FR-1 FIR滤波器
- 在**指定的CPU（基于Cortex-M0核的32位CPU）**中设计并集成 **81阶可配置系数FIR滤波器**。
- 验收：FIR滤波结果与相关软件算法参考值**误差 < 0.1%**。

### FR-2 互连结构
- 基于 **AXI协议**的共享总线互连结构。

### FR-3 DMA控制器
- **6通道独立DMA**，支持 存储器↔FIR、存储器↔存储器、UART↔存储器 等传输；支持 **AXI Burst**。
- 验收：**6通道全部可独立工作，数据零差错**。

### FR-4 存储系统
- 片内SRAM（指令+数据）+ **可选**ROM Boot，通过AXI互连。

### FR-5 CPU与系统
- CPU（Cortex-M0）正常跑通，**UART回显**正常（初赛验收项）。

### FR-6 AXI协议合规
- AXI互连/总线仲裁（**支持多主设备**）；**AHB→AXI**以及**AXI→APB**接口的桥。
- 验收：**单拍与Burst传输均无协议错误；总线仲裁无死锁**。

### FR-7 软硬协同验证
- CPU固件（软件）与FIR/DMA硬件加速器协同工作，完成端到端验证。

### FR-8 FPGA综合验证
- 在FPGA上完成综合、实现与板级验证。

## 3. 平台与工具约束

| 维度 | 要求 |
|---|---|
| EDA工具（前端） | 推荐开源工具：VS Code + Icarus Verilog + GTKWave + git |
| FPGA平台 | 紫光同创 **Logos-2 PG2L100H** 或资源相当开发板（**参赛队伍自行准备**），综合验证使用相关厂商EDA工具（Pango Design Suite） |
| 项目管理 | mingw64（make） |
| 交叉编译 | gcc-arm-none-eabi（PPT给定版本链接：10.3-2021.10） |
| 指定CPU源码 | Cortex-M0 RTL（ARM免费评估版）：https://www.arm.com/resources/free-evaluation-arm-cpus |

## 4. 交付物

| 交付物 | 格式与篇幅 | 内容要求 |
|---|---|---|
| 技术报告 | WPS/DOC及PDF，一个文档，**≤80页** | 系统工作原理分析（基本概念、处理流程等）；系统体系结构设计（结构选择、模块划分、技术选型、接口描述）；详细设计与实现；系统验证与分析（RTL仿真与测试）；FPGA验证与分析 |
| 源代码包 | RTL源码 | 编码风格规范、**详细注释**、**与详细设计一致** |
| 汇报PPT | **≤15页** | — |
| 讲解视频 | mp4，**8分钟** | 痛点与工程问题、技术难点与创新点、测试结果与同行比较、成果与应用 |
| 演示视频（决赛） | mp4，**≤5分钟** | 系统现场演示 |

## 5. 评分标准

### 5.1 初赛（总分100）

| 大项 | 内容 | 分值 | 评分要求 |
|---|---|---|---|
| 功能正确性 | FIR滤波器 | 20 | CPU正常跑通（UART回显）；FIR滤波结果与软件算法参考值误差<0.1%；DMA 6通道全部可独立工作，数据零差错 |
| | DMA控制器 | 10 | 6通道独立工作 |
| | 软硬协同验证 | 10 | — |
| | FPGA综合验证 | 20 | — |
| AXI协议合规 | AXI互连/总线仲裁（支持多主设备）、AHB到AXI以及AXI到APB接口的桥 | 15 | 单拍与Burst传输均无协议错误；总线仲裁无死锁 |
| 代码规范性 | RTL源码 + Testbench + C驱动源码 | 10 | RTL代码风格统一（命名、注释、模块化）；C代码符合基本规范 |
| 技术报告 | 基本结构 | 15 | 架构图清晰、模块说明完整、测试用例覆盖主要场景 |

### 5.2 决赛（总分100）

| 大项 | 内容 | 分值 | 评分要求 |
|---|---|---|---|
| 性能指标 | FIR吞吐量（samples/cycle） | 10 | 以各专项排名第一者为10分、最末者为0分（未完成者不计分、不参与排名），中间按线性关系映射 |
| | DMA带宽（MB/s） | 10 | 同上 |
| | CPU主频（MHz） | 10 | 同上 |
| | 系统总延迟（μs） | 10 | 同上 |
| 资源利用率 | LUT/FF/BRAM/DSP占用率 | 20 | 同等功能下硬件资源占用越少分数越高；加权平均：**LUT 30%、FF 20%、BRAM 20%、DSP 30%** |
| 架构创新 | 例如：FIR采用对称系数优化（81阶→41次乘加）；DMA支持链式传输 | 20 | DMA链式传输：多个DMA通道可以通过"链表"方式串联，前一个通道传输完成后自动触发下一个通道，无需CPU干预 |
| 现场答辩 | — | 20 | PPT讲解清晰流畅；基本功能演示正确；额外功能演示符合设计；现场演示流畅；专家提问回答情况 |

## 6. 赛事支持渠道

- 答疑邮箱1：zhangyouzhi1859@phytium.com.cn；答疑邮箱2：wangsufeng1177@phytium.com.cn
- QQ群：芯片设计与应用赛道赛题3-飞腾
- 技术交流社区（注册登录→加入小组→发表话题）：https://edu.phytium.com.cn/group/18
- 参赛价值：奖金支持 + 面试支持（校招岗位：芯片研发/架构验证/硬件开发/软件开发/算子开发工程师，天津、西安、成都、长沙）

## 7. 本计划锁定的技术决策（Spec未明说、由计划确定）

以下决策在实施计划中锁定并给出理由，供评审调整：

1. **总线拓扑**：CPU（AHB-Lite主）→AHB2AXI桥→AXI互连；DMA→AXI互连；AXI互连→{SRAM, FIR, DMA配置口, APB桥(UART+TIMER)}。单主单事务在途（single outstanding），无乱序，从协议层面杜绝死锁。
2. **AHB2AXI桥**：CM0每拍独立单拍AXI事务（CM0本身每拍等HREADY，合并burst无收益）。
3. **APB采用APB4（带PSTRB）**：避免对FIFO类寄存器做读改写（RMW会破坏UART RX FIFO）。
4. **FIR两版实现**：串行MAC基线版（保证正确性与资源下限）+ 对称并行版（41乘加、≥1 sample/cycle，决赛性能/创新项），同一套黄金测试回归。
5. **FIR数据格式**：输入/系数16bit Q1.15，累加器40bit Q2.30，输出32bit Q1.31（饱和+舍入），保证<0.1%误差有数可依。
6. **DMA**：6通道内部轮询仲裁共用1个AXI主口；支持固定地址（FIXED突发，用于FIR/外设）与增量地址（INCR突发，任意字节对齐零差错）；链式传输作为决赛加分项在基线完成后实现。
7. **固件**：裸机C（gcc-arm-none-eabi，-mcpu=cortex-m0），SRAM直接初始化启动（$readmemh / BRAM初值），ROM Boot为可选不做。
8. **统一使用Verilog-2001可综合子集**（iverilog与PDS均支持，避免SystemVerilog兼容风险）。

## 8. 官方参考工程（D:\ICT\Cortexm0ds）

官方另提供初始项目代码：ARM Cortex-M0 DesignStart r1p0 完整工程（自带git仓库，基线UART测试已跑通，见其 Cortexm0ds.txt 日志 `** TEST PASSED **`）。走读要点：

- **CPU**：`cortexm0integration`（对外为 AXI-Lite 主口；AHB→AXI4 桥内建于 core/cortexm0ds/ahb2axi4_*.v，对应FR-6桥要求）
- **总线**：`cmsdk_axi_slave_mux`（单主、SEL选择线风格、**无WSTRB**，字节/半字写靠 AWSIZE+低位地址通道表达）+ `cmsdk_axi_addr_decode`；**缺多主仲裁**（源码注释"No DMA controller - no need to have master multiplexer"），这是本项目要补的核心
- **从机**：Flash 0x0（只读，`filename`参数+$readmemh加载固件hex）、SRAM 0x2000_0000（64K）、APB子系统 0x4000_0000（UART0-2/Timer×2/DualTimer/WDT，经官方 axi2apb 桥，对应FR-6桥要求）、GPIO×2（0x4001_0000/0x4001_1000）、SYSCTRL、System ROM Table、默认从机（DECERR）
- **固件**：CMSIS + startup_GCC + retarget（printf→UART2）+ 链接脚本 cmsdk_cm0.ld（Flash 0x0 64K / RAM 0x20000000 63K，注释已为DMA结构预留空间）；编译流程 gcc → objcopy -O verilog hex
- **仿真**：iverilog+vvp+gtkwave；tb_cmsdk_mcu + cmsdk_uart_capture

**约束（用户明确要求）**：官方代码**只读不改**；项目工作在官方仓库根目录进行（**单仓库模式**）：官方模块以实例化方式复用，新设计（FIR/DMA/多主仲裁/译码/SoC顶层/FPGA ROM）写在新增目录 `rtl/ tb/common/ tb/tb_*.v sw/ tools/ fpga/ docs/` 中，与官方文件同仓提交、共享（github.com/lzzZ26/Cortexm0ds）。
