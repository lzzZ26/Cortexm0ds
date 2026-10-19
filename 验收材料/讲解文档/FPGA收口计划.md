# FPGA 板级收口计划：Q18「任意非对称系数」验证移交

> 读者：接手板级验证的同学（现有 PDS 工程基于 **q18 改动之前** 的 RTL，旧固件已上板跑通）。
> 目标：在新版 RTL 上完成 **Q18 任意非对称系数** 的板级验证，交回可验收证据。
> RTL 版本锚点：`git commit 08c7174`（2026-10-19，合规修复计划任务20–23 + 评审修复）。
> 相关文档：`docs/superpowers/plans/2026-10-19-fir-asymmetric-compliance-fix.md`（我方改动依据）。

---

## 0. 一句话

**用新版 RTL 重建 PDS 工程 → 烧 `fir_demo_asym.hex`（与对称固件同一流程，仅系数表换成非对称）→ 抓 FIR DOUT 的冲激响应前 82 个样本 → 与本文期望值比对。** 波形/数据即 Q18 证据。

---

## 1. 背景与验收目标

- 官方答疑 #18：赛题要求 81 阶 FIR **支持任意非对称系数**，对称优化只能作为可选分支。
- 我方已完成 RTL：通用全并行核（82 独立系数寄存器 × 82 乘法器，任意系数、1 样本/拍）为默认主路径；对称核为可选分支。
- 板级验收证据（本题交付）：
  1. **非对称系数输出正确的波形截图/数据**（冲激响应前 82 样本与期望值一致）；
  2. 资源报告（APM/LUT/FF/BRAM）；
  3. 所用工程/RTL 版本与固件 hex 版本说明。

> 说明：固件流程与对称版完全相同（CPU 配系数 → DMA 搬 1024 输入 → DMA 收 1024 输出 → SRAM out_buf）。**非对称版只换系数数组**，不新增外设、不改 DMA、不改寄存器序列。

---

## 2. 分工与交付物

### A. 我方（先做，交付给板级）

| 编号 | 交付物 | 状态 |
|---|---|---|
| A1 | `rtl/fir/fir_core_para.v`（新增）+ 三个核/top 的 clr/双核改动（见 §3） | ✅ 已完成（commit 08c7174） |
| A2 | `fir_golden.h` 增加 `fir_coeff_asym[82]`（`gen_fir_golden.py` 生成） | ✅ 已完成（原4文件逐字节未变） |
| A3 | `fir_demo_asym.hex`（非对称演示固件，同一流程仅换系数表） | ✅ 已完成（18826 B，md5 `2d947a9fa0b3a11897be10fafe00acd5`） |
| A4 | 仿真先行验证 `sim_tb_soc_asym` 全绿（证明 hex 在系统中正确） | ✅ 已完成（标记+1024样本<0.1%） |
| A5 | 期望值表（本文 §6；完整 1024 样本见 `tb/data/golden_asym_q31.hex`） | ✅ 已有 |

### B. 板级同学（拿到 A2–A4 后）

| 编号 | 事项 | 产出 |
|---|---|---|
| B1 | 更新 PDS 工程 RTL（§3 清单，替换+新增） | 工程编译通过 |
| B2 | CORE_TYPE 选择（§5，PGL50H 资源约束） | 综合报告 |
| B3 | 去 PLL（答疑 #5：计分项不用厂商 IP/原语），50MHz 直连 | 工程/说明 |
| B4 | 烧录 `fir_demo_asym.hex`（ROM/flash 初值） | 上板运行 |
| B5 | 抓取 DOUT 冲激响应前 82 样本（§6/§7） | 波形截图/数据文件 |
| B6 | 资源报告 + 版本说明 | LUT/FF/BRAM/APM、commit、hex 校验和 |

---

## 3. RTL 变更清单（相对你手上的旧版）

> **必须全部替换/新增**。只换 `fir_top.v` 而漏掉新核/clr 端口会导致 elaboration 报错。

| 文件 | 动作 | 变更内容 |
|---|---|---|
| `rtl/fir/fir_core_para.v` | **新增** | 通用全并行核（82 独立系数+82 乘法器+加法树，含 clr） |
| `rtl/fir/fir_core.v` | 替换 | 新增 `clr` 输入端口（清移位寄存器/相位/输出，系数保持） |
| `rtl/fir/fir_core_sym.v` | 替换 | 新增 `clr` 输入端口；`(* use_dsp = "no" *)` 属性 |
| `rtl/fir/fir_top.v` | 替换 | CORE_TYPE 0/1/2/3；CTRL bit1 模式位（CLR 拍锁存）；clr 同时打核与 FIFO |
| `rtl/soc/soc_top.v` | 替换 | FIR 实例改为 `CORE_TYPE(3)`（双核，para 默认） |
| `fpga/pango/top_pgl.v` | 替换（若用我们的板级顶层） | 删除 PLL，板载 50MHz 直连 |
| `fpga/pango/constraints.fdc` | 可选 | 仅注释同步（时钟 20ns） |
| `rtl/fpga/axi_rom.v` | 可选 | 仅头注释（ROM 备选方案改纯 RTL case-ROM） |
| `Makefile.fir` | 参考 | RTL 列表新增 `fir_core_para.v`（仿真用；PDS 工程请手动添加该文件） |
| `tools/gen_rom_rtl.py` | 新增（可选工具） | 固件 hex → 纯 RTL case-ROM（不用厂商 IP） |

**接口变化提示**：
- `fir_core`/`fir_core_sym`/`fir_core_para` 均新增 `clr`；`fir_top` 内部已连接，直接使用即可。
- 旧的自建 TB/顶层若直接例化核，需要补 `.clr(1'b0)`（板级顶层不涉及）。

---

## 4. 非对称演示固件（我方实现，与对称版同一流程）

### 4.1 实现方式（最小改动）

1. `tools/gen_fir_golden.py`：在生成 `fir_golden.h` 时**追加** `fir_coeff_asym[FIR_TAPS]`
   （值来自 `tb/data/coeff_asym_q15.hex`；原 `fir_coeff`/`fir_input`/`fir_golden` 保持逐字节不变）。
2. `sw/firmware/fir_demo/fir_demo.c`：
   ```c
   #ifdef FIR_ASYM
   #define FIR_COEFF_TABLE fir_coeff_asym
   #else
   #define FIR_COEFF_TABLE fir_coeff
   #endif
   ```
   FIR 段其余代码**一字不改**（同一 `FIR_CTRL=1` 清空 → 逐项写 82 系数 →
   `in_buf` 打包 → ch0 FIXED_DST 送 DIN → 等首样本 → ch1 FIXED_SRC 收 DOUT →
   `** FIR DONE **`）。非对称版额外打印一行 `** FIR ASYM MODE **` 便于现场区分。
3. `sw/firmware/fir_demo/makefile`：新增目标 `asym`，以 `-DFIR_ASYM` 编译，
   输出 `fir_demo_asym.hex/.bin/.lst`；原 `all` 输出保持 `fir_demo.hex` 不变。
4. 约束（沿用 T13/T14 裁决，**不要改**）：
   - DMA `BURST=0`（单拍 FIXED）；多拍会死锁（已实证）。
   - ch1 必须等 ch0 首样本入 DIN 后再 GO（防 DOUT 空读死锁）。
   - 固件不做长循环误差校验（会触发 CPU 停发取指的未解问题）；输出留在
     SRAM `out_buf`，由仿真 TB 或板上抓取核对。

### 4.2 我方仿真先行验证（交付前必须绿）

新增 `sim_tb_soc_asym`（tb_soc 参数化固件/黄金文件）：
- 加载 `sw/firmware/fir_demo/fir_demo_asym.hex`；
- 断言 UART 标记：横幅 / `** ECHO PASS **` / `** DMA PASS **` / `** FIR ASYM MODE **` / `** FIR DONE **`；
- 读 SRAM `out_buf`（地址由固件 `out=` 行给出）与 `tb/data/golden_asym_q31.hex`
  逐样本比对（阈值 `|hw-ref| > |ref|/1024`，即 0.0977% 点态上界，强于 RMSE 0.1%）；
- 全量回归保持绿。

### 4.3 固件构建命令（我方）

```bash
cd sw/firmware/fir_demo
mingw32-make all     # 对称版 fir_demo.hex（保持现状）
mingw32-make asym    # 非对称版 fir_demo_asym.hex
cd ../../..
mingw32-make -f Makefile.fir sim_tb_soc_asym   # 仿真验证
```

---

## 5. CORE_TYPE 选择（PGL50H：84 APM）

| 方案 | 乘法器占用 | 适用 |
|---|---|---|
| **CORE_TYPE=2**（仅通用并行核） | 82/84 APM | **只做 Q18 板级证据时首选**，资源最稳，任意非对称系数+1样本/拍 |
| CORE_TYPE=3（para+sym 双核） | para 82 APM + sym 41 乘法器（需走 LUT） | 想同时演示对称优化分支时用；**前提**：PDS 认可 `(* use_dsp = "no" *)`，否则 123 个 DSP 超过 84 会爆 |
| CORE_TYPE=0/1 | 1 / 41 乘法器 | 仅对照，不满足"任意非对称系数"默认路径 |

**建议**：板级 Q18 验收先做 **CORE_TYPE=2**（改动最小、证据最硬）。若时间允许再做 CORE_TYPE=3 的对称分支演示；若 PDS 资源爆仓，回退 2——**Q18 证据不受影响**（Q18 只要求任意非对称系数）。

> 注：`soc_top.v` 当前默认 `CORE_TYPE(3)`；板级工程可在自己的顶层把实例参数改为 `2`，无需改 RTL 逻辑。

---

## 6. 板上验收：期望值（冲激响应）

固件输入 `fir_input[0]=0x7FFF`（+1.0 冲激），其后为 0。FIR 输出前 82 个样本
即冲激响应：**`y[n] = c_asym[n] × 0x7FFF`（Q1.31）**，`n=0..81`；`n≥82` 为 0。

抽头示例（完整 82 项见 `tb/data/golden_asym_q31.hex` 前 82 行）：

| n | 系数 c[n] (Q1.15) | 期望输出 y[n] (Q1.31) |
|---|---|---|
| 0 | `0x16C2` (5826, +0.1778) | `0x16C1D27C` |
| 1 | `0x76C9` (30409, +0.9279) | `0x76C8126E` |
| 2 | `0x73FF` (29695, +0.9062) | `0x73FE1802` |
| … | … | … |
| 78 | `0x5ACD` (23245, +0.7094) | `0x5ACC4A66` |
| 79 | `0x7699` (30361, +0.9265) | `0x769812CE` |
| 80 | `0x33F7` (13303, +0.4060) | `0x33F69812` |
| 81 | `0xA633` (−22989, −0.7016) | `0xA633B39A` |

**判读要点**：`y[0] = 0x16C1D27C`（正、小）与 `y[81] = 0xA633B39A`（负、大）
明显不同 → 系数非对称的直接证据。若误跑对称固件，冲激响应会左右镜像
（y[0] 与 y[81] 接近相等），一眼可辨。

---

## 7. 板级操作步骤（勾选式）

1. [ ] **更新 RTL**：按 §3 替换/新增文件，PDS 工程源文件列表加入 `rtl/fir/fir_core_para.v`；确认工程中 `fir_top` 实例参数（§5）。
2. [ ] **去 PLL**：使用新版 `fpga/pango/top_pgl.v`（50MHz 直连）或从自建顶层删除厂商 PLL；约束时钟 20ns。
3. [ ] **加载固件**：ROM/flash 初值使用 `fir_demo_asym.hex`（我方提供，附校验和）；若 PDS 不支持 `$readmemh` 初始化，用 `tools/gen_rom_rtl.py` 生成纯 RTL case-ROM（无厂商 IP）。
4. [ ] **综合/布局布线**：记录资源报告（APM/LUT/FF/BRAM）与最高频率。
5. [ ] **上板运行**：串口应依次出现
       `FIR-SoC Demo` → `** ECHO PASS **` → `** DMA PASS **` →
       `** FIR ASYM MODE **` → `out=2000xxxx` → `** FIR DONE **`。
6. [ ] **抓取证据**（二选一，优先 ①）：
   - ① 逻辑分析仪/PDS 在线调试抓 **ch1 DMA 读 FIR DOUT** 的 AXI R 通道：
     `R_DATA` 连续 1024 个 32 位字，前 82 个即 y[0..81]；
   - ② 调试器读 SRAM `out_buf`（固件 `out=` 行给出的地址，通常 `0x20002000` 起）
     前 82 个字。
7. [ ] **比对**：与 §6 期望值逐项核对（至少抽 y[0]/y[1]/y[80]/y[81] 与
       左右镜像关系）；保存截图/数据文件。
8. [ ] **可选对照**：同一工程烧对称版 `fir_demo.hex`，抓同样的冲激响应，
       两张图并排——对称 vs 非对称，答辩最直观。
9. [ ] **交付**：波形截图/数据、资源报告、工程 RTL 版本（commit 08c7174 或你
       实际使用的版本）、hex 校验和（md5/sha256）。

---

## 8. 风险与回退

| 风险 | 处理 |
|---|---|
| PGL50H 84 APM 放不下 CORE_TYPE=3（sym 乘法器被推断为 DSP） | 回退 **CORE_TYPE=2**；Q18 证据不受影响 |
| PDS 不支持/忽略 `use_dsp="no"` | 同上回退；手写 carry-save 乘法器列为后续工作 |
| PDS 不支持 `$readmemh` 初始化 ROM | 用 `tools/gen_rom_rtl.py` 生成纯 RTL case-ROM（无 IP/原语） |
| 板上抓不到 DOUT 总线 | 用调试器读 SRAM out_buf；或外接逻辑分析仪接 AXI R 通道 |
| 非对称系数导致输出饱和 | 冲激响应前 82 项在 Q1.31 范围内（见 §6）；完整 1024 序列部分饱和属预期（大系数集专压饱和路径，黄金模型同口径钳位） |
| 固件打印/长循环风险 | 非对称版仅打印标记与 `out=` 地址，不做误差校验（T13 教训） |

---

## 9. 我方执行顺序（A2–A4）与验收

1. **A2**：扩展 `gen_fir_golden.py` → `fir_coeff_asym` 入 `fir_golden.h`；验证原有 4 个生成文件逐字节不变。
2. **A3**：`fir_demo.c` 加 `FIR_ASYM` 选择 + makefile `asym` 目标 → 生成 `fir_demo_asym.hex`（记录大小/校验和）。
3. **A4**：tb_soc 参数化固件/黄金文件，新增 `sim_tb_soc_asym`；先红灯（hex 未生成/标记缺失）→ 绿灯（标记+1024 样本<0.1%）；全量回归保持绿。
4. 交付板级：RTL 版本、`fir_demo_asym.hex`、本文期望值表、仿真日志。

**整份收口完成的定义**：板级同学交回 §7.9 的四项材料，且 §6 冲激响应对照通过。

---

## 附：板上关键寄存器/地址（供抓波形对照）

- FIR 基址 `0x4002_0000`：CTRL `0x00`（bit0=CLR，bit1=模式）、STATUS `0x04`、
  DIN `0x08`、DOUT `0x0C`、COEF[n] `0x10+4n`。
- DMA 通道 0 基址 `0x4003_0000`、通道 1 基址 `0x4003_0020`；
  SRC `0x00`、DST `0x04`、LEN `0x08`、CTRL `0x0C`。
- 固件 FIR 段：ch0 `CTRL=0x020B`（FIXED_DST，BURST=0，FSIZE=2），
  ch1 `CTRL=0x0207`（FIXED_SRC，BURST=0，FSIZE=2）。
- 输入/输出缓冲：`in_buf` 在固件 .data；`out_buf` 地址由 `out=` 行打印。
