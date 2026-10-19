# 带高阶 FIR 数字滤波器的 SoC 处理器设计 — 项目收尾报告（评阅版）

> **一句话**：Cortex-M0 + 自研 AXI 多主互连/仲裁 + 自研 6 通道 DMA + **支持任意非对称系数的 81 阶 FIR**（82 抽头，1 sample/cycle），RTL 三层验证全绿，Q18 非对称系数专项已闭环。
>
> 本文件是给评委的**阅读索引与自检报告**：系统结构、每个得分点的代码/证据位置、仿真图目录、复现命令、已知限制，都在这里。

---

## 0. 评委快速导航（3 分钟）

| 想看的 | 去哪里 |
|---|---|
| 系统结构一张图 | [§2.1 架构图](#21-系统架构图) |
| **每个得分点对应的代码/证据** | [§5 得分点对照表](#5-得分点对照表初赛--决赛) |
| 全部仿真图 | [§7.3 图目录](#73-图目录每张图说明什么) 或 [docs/report/figures/index.html](docs/report/figures/index.html) |
| **Q18 任意非对称系数证据** | [§6 Q18 专项](#6-q18-任意非对称系数专项重点) + [对比图](docs/report/figures/q18_impulse_compare.svg) |
| 一键复现 | [§8 复现指南](#8-复现指南) |
| 已知限制与口径说明（如实） | [§8 已知限制与待完成](#8-已知限制与待完成如实说明) |
| 完整技术报告 | [docs/report/技术报告.md](docs/report/技术报告.md) |

---

## 1. 自检结论摘要（对照赛题评分表）

### 初赛（100 分）

| 评分项 | 分值 | 结论 | 说明 |
|---|---:|---|---|
| FIR 滤波器 | 20 | ✅ 仿真完成 | CPU 跑通（UART 回显）；FIR 与软件参考值远优于 0.1%（逐样本点态上界）；任意非对称系数已支持 |
| DMA 控制器 | 10 | ✅ 仿真完成 | 6 通道独立配置，零差错；链式传输额外完成 |
| 软硬协同验证 | 10 | ✅ 仿真完成 | C 驱动 `fir_demo.c`：CPU 配 82 系数、下发 DMA、读回结果 |
| FPGA 综合验证 | 20 | ✅ 已完成 | PDS 综合/布局布线/bit 流完成（MES50HP/PGL50H，50MHz 时序收敛）；板上 UART 回显/DMA/FIR 跑通。数据见 §4.5 |
| AXI 协议合规 | 15 | ✅ 仿真完成 | 多主仲裁、单拍+Burst、4KB 拆分、协议检查器零违规、无死锁 |
| 代码规范性 | 10 | ✅ | 统一 ACLK/ARESETn 命名、模块头注释、Verilog-2001 可综合子集 |
| 技术报告 | 15 | ✅ 底稿完成 | `docs/report/技术报告.md`；DOC/PDF 导出待团队 |

### 决赛（100 分）

| 评分项 | 分值 | 当前值/证据 | 状态 |
|---|---:|---|---|
| FIR 吞吐量 | 10 | **1.0 sample/cycle**（通用核与对称核均断言） | ✅ 仿真实测 |
| DMA 带宽 | 10 | **14.44 MB/s**（FIR 阶段 8KB） | ✅ 仿真实测 |
| CPU 主频 | 10 | 50 MHz（仿真 + 板级时序收敛） | ✅ |
| 系统总延迟 | 10 | **3.04 μs**（首样本 DIN→首样本 DOUT） | ✅ 仿真实测 |
| 资源利用率 | 20 | **LUT 25.2% / FF 10.4% / DRM 47.8% / APM 52.4%**（板级 PDS 实测，加权约 34.9%） | ✅ 板级实测 |
| 架构创新 | 20 | 对称 41 乘加分支 + DMA 链式传输 | ✅ 已实现并验证 |
| 现场答辩 | 20 | PPT 大纲/讲稿已备 | ⏳ 待团队 |

> 口径说明：以上"仿真实测"均来自 `tb_soc`/核级 TB 的断言，记录见 [docs/指标记录.md](docs/指标记录.md)。

---

## 2. 系统结构

### 2.1 系统架构图

```
                    Cortex-M0 (官方 Cortex-M0 DesignStart)
                              │ AHB
                    ahb2axi4 桥（官方，CPU 侧）
                              │ m0
                  ┌───────────▼────────────┐
                  │  ic_axi_master_arb     │  ← 自研：CPU/DMA 双主轮询仲裁
                  │  （单事务在途，无死锁） │
                  └───────────┬────────────┘
                              │ 共享 AXI 主口
                  ┌───────────▼────────────┐
                  │  ic_axi_slave_mux      │  ← 自研：按 SEL 路由握手/响应
                  │  （读/写各深度4路由队列）│
                  └─┬────────┬────────┬────┴───────┬──────────────┐
                    │        │        │            │              │
              ┌─────▼──┐ ┌───▼────┐ ┌─▼─────────┐ ┌▼───────────┐ ┌▼──────────┐
              │ SRAM   │ │ FIR    │ │ DMA 配置口 │ │ 官方APB子系统│ │ 默认从机  │
              │ 0x2000 │ │ 0x4002 │ │ 0x4003     │ │ UART/Timer  │ │ DECERR    │
              │ axi_   │ │ fir_top│ │ dma_top    │ │ AXI→APB桥   │ │           │
              │ sram_  │ │        │ │            │ │ 0x4000      │ │           │
              │ sim    │ │        │ │            │ │             │ │           │
              └────────┘ └───┬────┘ └─────┬──────┘ └─────────────┘ └───────────┘
                               │            │
                     ┌─────────▼──┐   ┌─────▼──────────────────────────┐
                     │ FIR 三核    │   │ DMA 主口 → 仲裁器 m1            │
                     │ para(默认)  │   │ 6 通道，FIXED/INCR/链式         │
                     │ sym(可选)   │   └────────────────────────────────┘
                     │ serial(保底)│
                     └─────────────┘
```

**关键点**：
- CPU 与 DMA 是**两个 AXI 主设备**，经自研仲裁器共享总线（赛题允许共享总线；交叉开关为可选项）。
- CPU 侧 AHB→AXI 桥、低速 IO 侧 AXI→APB 桥复用官方设计（CPU 配套）；**仲裁器、从机 mux、地址译码、SRAM 模型、FIR、DMA、ROM 均为自研**。
- 计分模块不使用厂商 FPGA 原语/IP（PLL 已移除，板级 50MHz 直连；ROM 备选为纯 RTL case-ROM）。

### 2.2 数据流（FIR 软硬协同）

```
SRAM 输入样本 ──DMA ch0（FIXED_DST，单拍）──► FIR DIN FIFO
                                                    │
                                     FIR 核（para/sym/serial）
                                                    │
SRAM 输出结果 ◄──DMA ch1（FIXED_SRC，单拍）── FIR DOUT FIFO
        ▲
        └── CPU：写 82 个系数 → 写 CTRL 启动/清空 → 轮询 STATUS 或中断
```

- DMA 单拍配置是**实测安全配置**（多拍 FIXED 会与核产出率形成循环等待，T14 死锁；分析见技术报告 §3.3）。
- 固件同时演示 6 通道 DMA 自检与链式传输。

### 2.3 模块清单（自研 / 复用）

| 模块 | 文件 | 归属 | 职责 |
|---|---|---|---|
| 多主仲裁器 | [rtl/ic/ic_axi_master_arb.v](rtl/ic/ic_axi_master_arb.v) | 自研 | CPU/DMA 双主轮询，读/写独立授权，单事务在途 |
| 从机复用器 | [rtl/ic/ic_axi_slave_mux.v](rtl/ic/ic_axi_slave_mux.v) | 自研 | 握手入队/响应出队的路由队列，解决多主并发路由刷新 |
| 地址译码 | [rtl/ic/ic_axi_addr_decode.v](rtl/ic/ic_axi_addr_decode.v) | 自研 | 官方地图 + FIR/DMA 区域 |
| SRAM 模型 | [rtl/soc/axi_sram_sim.v](rtl/soc/axi_sram_sim.v) | 自研 | 无读写互斥缺陷的 SRAM 模型 |
| **FIR 通用并行核** | [rtl/fir/fir_core_para.v](rtl/fir/fir_core_para.v) | 自研 | **82 独立系数 × 82 乘法器，任意非对称系数，1 sample/cycle（Q18 主路径）** |
| FIR 对称核 | [rtl/fir/fir_core_sym.v](rtl/fir/fir_core_sym.v) | 自研 | 41 预加 + 41 乘法，对称系数可选优化分支 |
| FIR 串行核 | [rtl/fir/fir_core.v](rtl/fir/fir_core.v) | 自研 | 1 MAC 时间复用，82 拍/样本（资源下限） |
| FIR AXI 封装 | [rtl/fir/fir_top.v](rtl/fir/fir_top.v) | 自研 | 16 深 DIN/DOUT FIFO、CTRL/STATUS、CORE_TYPE 0–3、CLR/模式锁存 |
| DMA 通道 | [rtl/dma/dma_channel.v](rtl/dma/dma_channel.v) | 自研 | 读 burst→FIFO→写 burst；字节精度/FIXED/INCR/链式 |
| DMA 控制器 | [rtl/dma/dma_top.v](rtl/dma/dma_top.v) | 自研 | 6 通道轮询共享 1 主口 + 配置从机 + 中断聚合 |
| SoC 顶层 | [rtl/soc/soc_top.v](rtl/soc/soc_top.v) | 自研 | 全模块接线（官方文件只读） |
| FPGA ROM | [rtl/fpga/axi_rom.v](rtl/fpga/axi_rom.v) | 自研 | 板级只读 ROM（纯 RTL 备选见 `tools/gen_rom_rtl.py`） |
| CPU/AHB2AXI | `core/cortexm0ds/ahb2axi4_*.v` | 官方复用 | 指定 CPU 及桥（赛题提供） |
| APB 子系统/AXI2APB | `mcu_system/cmsdk_axi_to_apb/*` | 官方复用 | UART/Timer/WDT/GPIO + AXI→APB 桥 |

### 2.4 地址映射与关键寄存器

| 区域 | 地址 | 从机 |
|---|---|---|
| Flash/ROM（固件） | `0x0000_0000–0x0000_FFFF` | 仿真 flash / FPGA axi_rom |
| SRAM 64KB | `0x2000_0000–0x2000_FFFF` | axi_sram_sim |
| APB 子系统 | `0x4000_0000–0x4000_FFFF` | 官方 axi2apb（UART0-2/Timer/WDT） |
| GPIO0 | `0x4001_0000` | 官方 cmsdk_axi_gpio |
| **FIR** | `0x4002_0000` | fir_top |
| **DMA 配置** | `0x4003_0000` | dma_top |

FIR 寄存器：`CTRL 0x00`（bit0=CLR，bit1=双核模式）、`STATUS 0x04`（bit3..0=DOUT满/空、DIN满/空）、`DIN 0x08`、`DOUT 0x0C`、`COEF[n] 0x10+4n`（n=0..81）。

DMA 通道 i：基址 `0x4003_0000 + 0x20*i`；`SRC 0x00 / DST 0x04 / LEN 0x08 / CTRL 0x0C`（bit0=GO bit1=IRQ_EN bit2=FIXED_SRC bit3=FIXED_DST bit4=CHAIN bit7:5=BURST bit10:8=FSIZE）。

### 2.5 FIR 三核与 Q18（官方答疑 #18）

| 核 | 乘法器 | 系数范围 | 吞吐 | 角色 |
|---|---:|---|---|---|
| **fir_core_para** | 82 | **任意 0..81（非对称）** | 1 样本/拍 | **默认主路径（合规基本盘）** |
| fir_core_sym | 41 | 仅 0..40（对称假设） | 1 样本/拍 | 可选资源优化分支（CTRL bit1 切换） |
| fir_core | 1 | 任意 | 1/82 样本/拍 | 资源下限保底 |

- Q18 原话："81 阶可配置系数 FIR，**支持任意非对称系数**，对称优化只能作为可选加速/资源优化分支"。本设计严格按此落地。
- "81 阶"实现为 **82 抽头**（阶数 N 对应 N+1 个抽头）；对称分支 41 乘加。
- 输入/系数 16bit（Q1.15）符合要求；输出采用 32bit Q1.31 以保留精度（误差远优于 0.1%）。

---

## 3. 关键设计说明（对应评分点）

1. **任意非对称系数 FIR（Q18）**：`fir_core_para` 82 个独立系数寄存器 + 82 个 16×16 乘法器 + 7 级加法树；`cfg_addr` 0..81 全有效；输出 Q1.31、饱和判据 `acc[39:30]` 符号扩展。
2. **对称优化分支**：`fir_core_sym` 预加对 + 41 乘法；CTRL bit1 在 CLR 拍锁存，切换必然全清双核（模式锁存 + CLR 语义）。
3. **DMA 链式传输**：`dma_channel` 完成后从 NEXT 指针读 5 字描述符自动续传，无需 CPU 干预（创新点，`tb_dma_chain` 验证）。
4. **多主互连**：自研仲裁器单事务在途 + 授权保持；自研从机 mux 用队列路由响应，解决官方 mux 在多主并发下的路由刷新缺陷（实测）。
5. **软硬协同**：`fir_demo.c` 完成 UART 横幅/回显、6 通道 DMA 自检、CPU 配系数、DMA 搬运、结果回读；误差校验在 TB 侧完成（避免 M0 长循环取指异常）。
6. **无厂商 IP/原语**：板级 50MHz 直连（无 PLL）；ROM 初始化备选为纯 RTL case-ROM（`tools/gen_rom_rtl.py`）。

---

## 4. 验证体系

### 4.1 三个层级（对应赛题要求）

| 层级 | TB | 覆盖 |
|---|---|---|
| **单元/模块** | `tb_vip_smoke` / `tb_decode` / `tb_fir_core` / `tb_fir_core_para` / `tb_fir_core_sym` / `tb_fir_top` / `tb_fir_top_dual` / `tb_dma_channel` / `tb_axi_rom` | 各模块独立直测 + 黄金回归 |
| **集成（不含 CPU）** | `tb_arb` / `tb_dma_top` / `tb_dma_chain` / **`tb_integ`** | 真实互连拓扑；VIP 替代 CPU：SRAM 往返 + 82 系数 + 1024 样本 FIR（对称 + 非对称两轮）+ 协议零违规 |
| **系统测试（含 CPU）** | `tb_soc_smoke` / `tb_soc_smoke_rom` / **`tb_soc`** / `tb_soc_asym` | CPU 启动、UART 回显、DMA 自检、软硬协同、1024 样本黄金比对（对称/非对称固件） |

### 4.2 回归清单

`mingw32-make -f Makefile.fir regression` 共 **17 个目标**，全部 PASS（最近一次实测：退出码 0）。

| # | 目标 | 覆盖 |
|---:|---|---|
| 1 | sim_tb_vip_smoke | VIP 写读往返 + 协议零违规 |
| 2 | sim_tb_arb | 双主并发压力 + 公平性 + 零协议违规 |
| 3 | sim_tb_decode | 地址译码全覆盖 |
| 4 | sim_tb_fir_core | 串行核黄金回归 + 随机反压 + 饱和 |
| 5 | sim_tb_fir_top | 系数 INCR / DIN 单拍+FIXED / DOUT 回读 |
| 6 | sim_tb_fir_core_sym | 对称核黄金回归 + 吞吐 + **随机反压** |
| 7 | sim_tb_fir_core_para | **非对称/对称/大系数三套黄金 + 吞吐 + CLR + cfg + 随机反压** |
| 8 | sim_tb_fir_top_dual | 双核模式切换 + 非对称 + 饱和 + **模式判别** |
| 9 | sim_tb_dma_channel | 7 类传输零差错 + 协议零违规 |
| 10 | sim_tb_dma_top | 6 通道并发 + 中断 + 状态位 |
| 11 | sim_tb_dma_chain | 3 段链表自动串联 |
| 12 | sim_tb_soc_smoke | CPU 从 flash 启动输出 Hello world |
| 13 | sim_tb_soc | 回显 + DMA 自检 + FIR 软硬协同 + 黄金比对 |
| 14 | sim_tb_soc_asym | **非对称固件系统级**（含 `** FIR ASYM MODE **` 标记） |
| 15 | sim_tb_axi_rom | ROM 字/窄读/INCR/FIXED + 零违规 |
| 16 | sim_tb_soc_smoke_rom | FPGA ROM 路径冒烟 |
| 17 | sim_tb_integ | 集成验证（含**非对称系统级**用例） |

另有两个**验收波形目标**（不在回归内，按需运行）：
- `sim_tb_fir_para_impulse`：非对称系数+冲激，产出 VCD/CSV；
- `sim_tb_fir_para_impulse_sym`：对称系数+冲激，产出 VCD/CSV。

### 4.3 图目录（每张图说明什么）

| 图 | 说明 | 生成方式 |
|---|---|---|
| [q18_impulse_compare.svg](docs/report/figures/q18_impulse_compare.svg) | **Q18 核心验收图**：上=对称系数冲激响应（左右镜像），下=非对称（左右不同） | `sim_tb_fir_para_impulse(_sym)` + `tools/plot_q18_impulse.py` |
| [q18_impulse_sym.svg](docs/report/figures/q18_impulse_sym.svg) | 对称系数冲激响应：`y[0]=y[81]=0x0004FFF6` | 同上 |
| [q18_impulse_asym.svg](docs/report/figures/q18_impulse_asym.svg) | 非对称系数冲激响应：`y[0]=0x16C1D27C`，`y[81]=0xA633B39A` | 同上 |
| [coeff_sym.svg](docs/report/figures/coeff_sym.svg) | 82 抽头对称低通系数 | `tools/plot_waveforms.py` |
| [mag_response.svg](docs/report/figures/mag_response.svg) | 幅频响应 | 同上 |
| [seg1_impulse.svg](docs/report/figures/seg1_impulse.svg) | 冲激段：滤波前/后 | 同上 |
| [seg2_lowfreq.svg](docs/report/figures/seg2_lowfreq.svg) | 低频正弦段：滤波前/后 | 同上 |
| [seg3_highfreq.svg](docs/report/figures/seg3_highfreq.svg) | 高频正弦+噪声段：滤波前/后 | 同上 |
| [seg4_noise.svg](docs/report/figures/seg4_noise.svg) | 满幅随机段：滤波前/后 | 同上 |
| [index.html](docs/report/figures/index.html) | 图库索引（浏览器打开） | `tools/plot_waveforms.py` |

**GTKWave 数字波形**（按需生成，`sim_out/` 为构建产物目录）：
```bash
mingw32-make -f Makefile.fir sim_tb_fir_para_impulse       # 非对称
mingw32-make -f Makefile.fir sim_tb_fir_para_impulse_sym   # 对称
# 生成 sim_out/q18_impulse.vcd / q18_impulse_sym.vcd
# 打开：gtkwave sim_out/q18_impulse.vcd
```
非对称输出时间点：`y[n]` 在 `350 + 20n ns`，`n=0..81`；`y[0]=16C1D27C`，`y[81]=A633B39A`。

### 4.4 误差口径（官方答疑 #19）

- 赛题口径：**相对均方根误差（RMSE）<0.1%**。
- 本设计判据：逐样本相对误差 `|hw-ref| ≤ |ref|/1024`（0.0977% 点态上界），**数学上强于 RMSE 要求**。
- 黄金模型：系数/输入先量化到 Q1.15 → 双精度 FIR → 量化 Q1.31；硬件与黄金之差=纯实现误差。

### 4.5 FPGA 板级验证结果（已完成）

| 项目 | 结果 |
|---|---|
| 开发板 | MES50HP（PGL50H-6IFBG484），板载 50MHz 直连（无 PLL） |
| 工具链 | Pango Design Suite 2022.2-SP6.1 |
| 综合/布局布线 | 单种子收敛（Seed OK）；bit 流已生成（`generate_bitstream/system_top.sbit` / `.smsk`） |
| 时序（50MHz，20ns 约束） | Setup(Slow) WNS **+1.535 ns**、Hold(Slow) **+0.037 ns**、Setup(Fast) **+6.943 ns** —— 满足 50MHz |
| 资源占用 | LUT **10,772 / 42,800（25.2%）**；FF **6,700 / 64,200（10.4%）**；DRM **64 / 134（47.8%）**；APM **44 / 84（52.4%）**；分布式 RAM 544 / 17,000；USCM 1/30 |
| 加权资源占用 | 按赛题权重（LUT30%/FF20%/BRAM20%/DSP30%）约 **34.9%** |
| 板上功能 | UART 回显、DMA 自检、FIR 滤波均跑通 |

> **口径说明**：板级构建的 FIR 为**对称分支**（41 乘法器，APM 44 中含少量其他逻辑）；**任意非对称系数（Q18）由通用并行核承担，已通过 RTL 三层仿真闭环**。两分支的资源/模式决策见 [fpga/pango/README.md](fpga/pango/README.md) 的 CORE_TYPE 矩阵：PGL50H 上单核 `CORE_TYPE=2` 为 Q18 板级演示的最稳配置（82/84 APM）。

---

## 5. 得分点对照表（初赛 + 决赛）

> 这是本报告最重要的索引：每个评分项 → 代码位置 → 仿真证据/图 → 状态。

### 初赛

| 得分点 | 分值 | 代码/实现位置 | 验证证据 | 状态 |
|---|---:|---|---|---|
| FIR 滤波器 | 20 | [fir_top.v](rtl/fir/fir_top.v)、[fir_core_para.v](rtl/fir/fir_core_para.v)、[fir_core_sym.v](rtl/fir/fir_core_sym.v) | `tb_fir_core_para`（三套黄金+吞吐+CLR）、`tb_fir_core_sym`、`tb_soc`（1024 样本 <0.1%） | ✅ |
| DMA 控制器 | 10 | [dma_top.v](rtl/dma/dma_top.v)、[dma_channel.v](rtl/dma/dma_channel.v) | `tb_dma_top`（6 通道并发）、`tb_dma_chain`（链式）、固件自检 | ✅ |
| 软硬协同验证 | 10 | [fir_demo.c](sw/firmware/fir_demo/fir_demo.c) | `tb_soc`（回显+配系数+DMA+黄金比对）、`tb_soc_asym` | ✅ |
| FPGA 综合验证 | 20 | [fpga/pango/](fpga/pango/)、板级工程（MES50HP/PGL50H） | PDS 综合/布局布线/bit 流完成；50MHz 时序收敛；资源与时序数据见 §4.5；板上 UART/DMA/FIR 跑通 | ✅ |
| AXI 协议合规 | 15 | [ic_axi_master_arb.v](rtl/ic/ic_axi_master_arb.v)、[ic_axi_slave_mux.v](rtl/ic/ic_axi_slave_mux.v)、官方 AHB2AXI/AXI2APB | `tb_arb`、`tb_dma_*`、`tb_integ` 均挂 `axi_checker`：零违规、无死锁 | ✅ |
| 代码规范性 | 10 | 全部 `rtl/`、`tb/`、`sw/` | 统一 `ACLK/ARESETn`、模块头注释、Verilog-2001 子集 | ✅ |
| 技术报告 | 15 | [技术报告.md](docs/report/技术报告.md) | 架构图/模块表/测试矩阵/复用决策表/指标 | ✅ 底稿；PDF 待导出 |

### 决赛

| 得分点 | 分值 | 证据位置 | 当前结果 |
|---|---:|---|---|
| FIR 吞吐量 | 10 | `tb_fir_core_para` / `tb_fir_core_sym` 的间隔断言 | **1.0 sample/cycle** |
| DMA 带宽 | 10 | `tb_soc` 指标监视（FIR 阶段 8KB） | **14.44 MB/s** |
| CPU 主频 | 10 | `tb_clkreset` 20ns；PDS 50MHz 时序收敛 | **50 MHz**（仿真 + 板级） |
| 系统总延迟 | 10 | `tb_soc` 首 DIN→首 DOUT | **3.04 μs** |
| 资源利用率 | 20 | 板级 PDS 实测（§4.5）：LUT 25.2% / FF 10.4% / DRM 47.8% / APM 52.4%，加权约 34.9% | ✅ 板级实测 |
| 架构创新 | 20 | 对称 41 乘加（[fir_core_sym.v](rtl/fir/fir_core_sym.v)）+ DMA 链式（[dma_channel.v](rtl/dma/dma_channel.v)） | 已实现并验证 |
| 现场答辩 | 20 | [汇报PPT大纲.md](docs/ppt/汇报PPT大纲.md)、[讲解视频脚本.md](docs/ppt/讲解视频脚本.md)、[演示视频分镜.md](docs/ppt/演示视频分镜.md) | 待团队 |

---

## 6. Q18 任意非对称系数专项（重点）

### 6.1 要求与实现

官方答疑 #18 明确："81 阶可配置系数 FIR，**支持任意非对称系数**，对称优化只能作为可选加速/资源优化分支。"

实现：
- 默认主路径 `fir_core_para`：82 个独立系数寄存器（`cfg_addr 0..81` 全有效）× 82 个乘法器，**非对称系数直接可用**，1 sample/cycle。
- `fir_top` CORE_TYPE=3 双核：默认 para；CTRL bit1=1 且 bit0=1（CLR）时切对称核，模式位在 CLR 拍锁存；CLR 同时清 FIFO 与两个核的移位寄存器/流水线。
- 对称核只作为可选分支，不再承担合规主路径。

### 6.2 三层证据

| 层级 | 用例 | 证据 |
|---|---|---|
| 核级 | `tb_fir_core_para` 用例 B | 非对称随机系数 1024 样本黄金回归 <0.1%；吞吐 1 样本/拍；中途 CLR 无污染 |
| 从机级 | `tb_fir_top_dual` ①–⑤ | 默认 para 非对称回归；切 sym；切回 para；大系数饱和；**模式判别**（para y[81]=0 / sym y[81]=0x3FFF8000） |
| 系统级 | `tb_integ` 非对称用例；`tb_soc_asym` | VIP 配非对称系数 → DMA 搬运 1024 样本 → 读回与 `golden_asym_q31.hex` 比对；非对称固件系统级黄金比对 |

### 6.3 验收波形（冲激响应）

输入：单冲激 `0x7FFF` + 81 个零；输出前 82 个即冲激响应，`y[n]=c[n]×0x7FFF`。

| 用例 | y[0] | y[81] | 结论 |
|---|---|---|---|
| 对称系数 | `0x0004FFF6` | `0x0004FFF6` | 左右镜像 |
| 非对称系数 | `0x16C1D27C` | `0xA633B39A` | 左右明显不同（Q18 证据） |

- 图：[q18_impulse_compare.svg](docs/report/figures/q18_impulse_compare.svg)（推荐给评委）
- 数据：`sim_out/q18_impulse.csv`（82 行）、`sim_out/q18_impulse_sym.csv`
- 波形：`sim_out/q18_impulse.vcd`、`sim_out/q18_impulse_sym.vcd`（GTKWave）

---

## 7. 复现指南

### 7.1 工具链

| 工具 | 版本 |
|---|---|
| Icarus Verilog / vvp | 12.0 |
| GNU Make | mingw32-make 4.2.1 |
| arm-none-eabi-gcc | 10.3-2021.10 |
| Python | 3（pypdf/openpyxl；绘图为纯标准库） |
| GTKWave | 3.3.100 |

### 7.2 常用命令

```bash
# 全量回归（17 个目标，全部 PASS）
mingw32-make -f Makefile.fir regression

# 系统级软硬协同（固件路径）
mingw32-make -f Makefile.fir sim_tb_soc

# Q18 验收波形（非对称 / 对称）
mingw32-make -f Makefile.fir sim_tb_fir_para_impulse
mingw32-make -f Makefile.fir sim_tb_fir_para_impulse_sym
python tools/plot_q18_impulse.py

# 滤波前后波形图 + 图库
python tools/plot_waveforms.py

# 固件重建（对称 / 非对称）
cd sw/firmware/fir_demo
mingw32-make all      # fir_demo.hex
mingw32-make asym     # fir_demo_asym.hex
```

### 7.3 官方工程放置

官方 Cortex-M0 DesignStart 工程（`core/`、`mcu_system/`、`software/` 等）与本仓库同目录放置；本仓库不修改官方文件（只读复用）。

---

## 8. 已知限制与待完成（如实说明）

1. **FPGA 板级验证已完成**：PDS 2022.2-SP6.1 综合/布局布线/bit 流完成，50MHz 时序收敛；资源见 §4.5；板上 UART 回显、DMA、FIR 均跑通。
2. **Q18 板级演示口径**：板级构建采用对称分支（41 乘法器）；通用并行核（任意非对称系数）已由 RTL 三层仿真验证。如需在板上演示非对称系数，按 `CORE_TYPE=2` 重综合即可（82/84 APM，Q18 证据不受影响）——这是演示口径，不是未完成的验证项。
3. **UART↔memory DMA 专项测试缺失**：DMA 为通用 AXI 主设备，`FIXED_DST/FIXED_SRC` 用例已验证固定地址读写机制（UART DATA 即固定地址寄存器），但尚无 UART 端到端 DMA 用例；如需可补。
4. **报告/PPT/视频导出待团队**：`技术报告.md` 为底稿，DOC/PDF、PPT 成稿、讲解/演示视频尚未导出。
5. **"81 阶"口径**：本设计按"81 阶 = 82 抽头"实现；对称分支为 41 乘加，通用分支为 82 乘法器。
6. **输出位宽**：输入/系数为赛题要求的 16bit；输出采用 32bit Q1.31 以保留精度（误差远优于 0.1%）。
7. **计分项不使用开源/厂商 IP**：计分模块（FIR/DMA/仲裁/mux/译码/SRAM/ROM）均为自研 RTL；仅复用赛题指定 CPU 及其配套 AHB2AXI/AXI2APB 桥。

---

## 9. 目录结构

```
rtl/           自研 RTL（ic/ fir/ dma/ soc/ fpga/）
tb/            Testbench（含 common：VIP/检查器/存储从机/BFM/时钟复位）
sw/firmware/fir_demo/   C 驱动 + 固件（对称 fir_demo.hex / 非对称 fir_demo_asym.hex）
tools/         黄金模型/波形绘图/纯 RTL ROM 生成/打包脚本
docs/report/   技术报告 + figures（全部仿真图 + index.html）
docs/ppt/      PPT 大纲 / 讲解视频脚本 / 演示视频分镜
docs/指标记录.md  决赛四项指标与口径
fpga/pango/    PDS 板级顶层/约束/README（CORE_TYPE 决策矩阵）
Makefile.fir   仿真入口（17 个回归目标 + 波形目标）
```

### 关键文档

- [技术报告](docs/report/技术报告.md)
- [指标记录](docs/指标记录.md)
- [FPGA Q18 收口计划](docs/superpowers/plans/2026-10-19-fpga-q18-handover.md)
- [汇报 PPT 大纲](docs/ppt/汇报PPT大纲.md)

---

## 10. 一句话总结

> 本设计在**任意非对称系数**（Q18）这一合规基本盘上，采用"通用全并行核为默认 + 对称 41 乘加为可选优化分支 + 串行核保底"的三核架构；配合自研多主 AXI 互连与 6 通道 DMA，RTL 三层验证全绿。**FPGA 板级验证已完成**：PDS 综合/布局布线/bit 流完成，50MHz 时序收敛，资源实测见 §4.5。Q18 非对称功能由 RTL 三层仿真闭环；板级构建使用对称分支，如需板上演示非对称系数按 `CORE_TYPE=2` 重综合即可。
