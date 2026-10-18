# 合规修复计划：任意非对称系数 FIR + 口径修正（依据官方答疑 Excel）

> 来源：`D:\ICT\1792338991775_赛题三：芯片设计与应用赛道 — 带高阶FIR数字滤波器的SoC处理器设计（飞腾信息技术有限公司.xlsx`（官方答疑，2026-10 提取，全文见 `sim_out/xlsx_qa.txt`）
> 创建：2026-10-19。执行方式：新开会话按本计划逐任务执行（TDD：先TB红灯→实现→绿灯→提交）。
> **提交约定：提交信息不加 Co-Authored-By 行（用户已明确要求并在历史中清理过）。**
> 命名约定：时钟/复位一律 `ACLK/ARESETn`（已全局统一）；全部 RTL 限 Verilog-2001 可综合子集（iverilog -g2001）。

## 背景：答疑带来的三个问题

### 问题1【重大，必修】：必须支持任意非对称系数（答疑#18）

官方答复原文："赛题要求做一个81阶可配置系数FIR，**支持任意非对称系数**，对称优化只能作为可选加速/资源优化分支"。

- 现状：`soc_top` 实例化 `fir_top #(.CORE_TYPE(1))` = **对称核 fir_core_sym**（41 预加器+41 乘法器，硬件结构假设 h[k]=h[81−k]）。评委若写非对称系数 → 输出错误。
- 串行核 `fir_core`（CORE_TYPE=0）系数任意正确，但吞吐 1/82，违背设计要求"吞吐量≥1 sample/cycle"（答疑#8：指 FIR 中 MAC 单元的频率）。
- **结论：必须新增"通用全并行核"**（82 乘法器+加法树，任意系数、1样本/拍）作为基本架构主核；对称核降级为"可选加速/资源优化分支"（运行时可选，演示用）。

### 问题2【小修】：误差口径 = 相对均方根误差（答疑#19）

答复原文："**相对均方根误差**"。现状：我们的判据是逐样本相对误差 <0.0977%（|hw−ref|>|ref|/1024 判超标）——这是点态上界，**蕴含 RMSE<0.1%，比要求更严**，判据本身不用改；但技术报告/PPT 的措辞要改成"相对均方根误差"口径并注明"我们以逐样本 0.0977% 上界验证，强于 RMSE 要求"。

### 问题3【流程修正】：计分项不能使用厂商原语/IP 核（答疑#5）

答复原文："记分项不能使用厂商提供的原语或IP核"。我们的计分模块（FIR/DMA/仲裁/互连/存储模型）全部自研 RTL 无原语 ✓；但两处流程文档要避嫌：
1. `fpga/pango/top_pgl.v` 的 PLL（GTP_CLKPLL）——**改为板载 50MHz 直连**（满足 ≥25MHz/目标50MHz，不用厂商 IP）
2. `rtl/fpga/axi_rom.v` 头注释的备选方案"厂商 IP 生成 .coe"——**改为"Python 脚本生成纯 RTL case-ROM"**（tools/gen_rom_rtl.py，输出 Verilog case 语句的 ROM 模块）

### 板子结论（答疑#3/#4/#7/#14）

Artix-200T、Zynq-7020（纯PL）、Vivado 官方均答复可以，"差不多就行"；初赛建议提前准备板子（FPGA综合验证 20 分）。**板卡已定案：盘古50K（PGL50H，Logos 一代，84 个 APM 乘法器，42,800 LUT5）**——用户确认不换板。

## 设计决策（2026-10-19 细化已确认，执行时不许推翻）

1. **CLR 修复**：现有核（fir_core/fir_core_sym）没有 clr 输入——fir_top 的 CTRL 清零只清 FIFO，核内 82 级移位寄存器和流水线保留旧样本（当前单轮演示未暴露；双核切换必暴露）。**三个核统一加 `clr` 输入**（1 拍脉冲清移位寄存器+流水线），fir_top 的 CLR 脉冲同时打给核与 FIFO。
2. **模式切换语义**：CTRL bit1（0=通用核，1=对称核）**在 CLR 脉冲时锁存生效**——切换必然伴随全清，硬件上杜绝"切模式不清理"；fir_top CORE_TYPE=3 双核，0/1/2 单核行为不变。
3. **对称核实现载体（受 PGL50H 84 APM 约束）**：双核 82+41=123 乘法器 > 84 放不下。**采用方案 ii**：通用核 82 个乘法器走 DSP（82/84=97.6%，已尽人事）；**对称核 41 个乘法器走 LUT 实现**（~6K LUT5，LUT 总利用率 ~45%）——加 PDS 综合属性禁止对称核乘法器推断为 DSP；若属性不被 PDS 认可（推断后爆仓），**备选=手写乘法器结构**（参数化 carry-save 乘法器模块）。对称核做成独立 generate 块，接口不变——未来换 PG2L100H 可零改动换回全 DSP 双核。
4. **非对称黄金数据两套**（gen_fir_golden.py 扩展）：①随机系数（固定 seed，均匀分布）；②**大系数集**（直流增益>1，专压饱和路径）。同一四段输入分别生成 golden。
5. **cfg 广播**：双核各存系数副本，cfg 写同时打两核（对称核天然忽略 cfg_addr≥41，两核系数一致）。

---

## 任务 20：通用全并行核 fir_core_para（新模块，TDD）

**Files:** Create: `rtl/fir/fir_core_para.v`；Test: `tb/tb_fir_core_para.v`；数据：`tb/data/coeff_asym_q15.hex`、`tb/data/golden_asym_q31.hex`（工具生成）

**Interfaces（与 fir_core_sym 同构+新增 clr，直接替换可用）：**
```verilog
module fir_core_para #(parameter TAPS = 82, CW = 16, DW = 16)(
    input  wire        ACLK, ARESETn,
    input  wire        clr,                // 1拍脉冲：清移位寄存器+流水线（设计决策1）
    input  wire        cfg_we,             // 系数配置写使能
    input  wire [9:0]  cfg_addr,           // 系数序号 0..81（注意：sym核只认0..40，本核必须全82）
    input  wire [15:0] cfg_wdata,          // Q1.15 系数
    input  wire        din_valid,
    output wire        din_ready,          // =!stall（与sym核同语义）
    input  wire [15:0] din,                // Q1.15 输入
    output reg         dout_valid,
    input  wire        dout_ready,
    output reg  [31:0] dout                // Q1.31 输出
);
```
（clr 为新增端口；fir_core/fir_core_sym 也同步加 clr——接口小改，现有 TB 实例化处补连接）

**实现要点（照抄/移植 fir_core_sym 的成熟结构，台账 T8 裁决已验）：**
- 82 深移位寄存器链 x[0..81]（每拍 din_valid 时移入新样本）
- 82 个乘法器 c[k]×x[k]（17×16？不——通用核无预加器：16×16 乘法，40bit 积扩展）
- 加法树：82→41→21→11→6→3→2→1，参考 sym 核的流水结构；**输出随流水打拍对齐 dout_valid**（sym 核用 vpipe 对齐，注意 T8 裁决"dout_valid 取 vpipe[7] 与数据同沿可见"）
- 定点口径（T6/T8 裁决，不许再踩）：
  - 累加器 40bit Q10.30；**必须声明 `reg signed [40:0]` 类有符号**（Verilog-2001 含乘法表达式按无符号求值——实测陷阱）
  - 溢出判据：`acc[39:30] != acc[30] 的符号扩展`（82 项可超 ±4，只查 [39:38] 会漏判）
  - 输出取 `{acc[30:0], 1'b0}`（=acc×2 低 32 位，Q1.31），饱和钳位
- 反压语义照抄 sym 核（T13 裁决）：`stall = dout_valid && !dout_ready` 冻结整条流水 + `din_ready = !stall`；释放沿同值带 valid 重放一拍（**不能在释放沿清 valid**——连续流会每两个输出丢一个，实测）
- 系数配置：cfg_we 时 `coef[cfg_addr] <= cfg_wdata`（82 个独立寄存器，任意非对称 ✓）

**测试（TDD 循环，Step 1 TB 先行）：**
1. 写 `tools/gen_fir_golden.py` 扩展：新增**两套非对称系数集**（设计决策4）——①随机 Q1.15（固定 seed，均匀分布）→ `tb/data/coeff_asym_q15.hex`+`golden_asym_q31.hex`；②大系数集（直流增益>1，压饱和路径）→ `coeff_gain_q15.hex`+`golden_gain_q31.hex`。原对称系数与 golden 保留
2. `tb/tb_fir_core_para.v`：参考 tb_fir_core_sym 结构（always 块 NBA 逐沿推进 din——T8 裁决：阻塞赋值会丢首样本；dout_ready 每拍随机 always 驱动+排空 force_accept——T6 裁决）
   - 用例A：对称系数集（coeff_q15.hex+golden_q31.hex）1024 样本 <0.1%
   - 用例B：**非对称随机系数集** 1024 样本 <0.1%——本任务的核心证明
   - 用例C：**大系数集**（饱和路径+溢出钳位断言）
   - 用例D：吞吐断言 gap_bad（连续段输出间隔恒 1 拍，T8 裁决的断言结构）
   - 用例E：**中途 CLR**——跑一段后 clr 脉冲，再跑全序列，黄金比对不受污染（验证设计决策1）
   - 用例F：cfg 逐系数写与回归读（cfg 时序 2 沿保持——T6 裁决：cfg 推送要跨完整时钟沿稳定）
3. 红灯：`mingw32-make -f Makefile.fir sim_tb_fir_core_para` → module not found
4. 实现 → 绿灯；RTL 加入 Makefile.fir 的 RTL 列表
5. 提交：`feat: 通用全并行FIR核（82乘加，任意系数1样本/拍，非对称黄金回归）`

**验收：** sim_tb_fir_core_para 全绿（对称+非对称+大系数三套黄金 1024 样本 <0.1% + 吞吐 1 样本/拍 + CLR 无污染）。

---

## 任务 21：fir_top 双核模式（运行时可选，TDD）

**Files:** Modify: `rtl/fir/fir_top.v`；Test: Modify `tb/tb_fir_top.v`（补双模用例）

**设计：**
- `CORE_TYPE` 参数扩展：`0=serial（串行核）1=sym（对称核）2=para（通用并行核）3=dual（para+sym 运行时可选）`
- CORE_TYPE=3 时同时例化 para 与 sym 两个核（**对称核为独立 generate 块，实现载体=设计决策3：LUT 乘法器+PDS 禁止 DSP 推断属性，备选手写乘法器结构**）：
  - din 扇出到两核（din_valid 只给**当前选中**核——未选中核 din_valid 恒 0，防止其空转；cfg 写同时打到两核各自的系数副本，保证切换后系数一致——设计决策5）
  - dout 按模式位 mux；dout_ready 反压只回给当前选中核（未选中核 dout_ready 接 0 使其冻结，不产生伪输出）
  - 模式选择：CTRL 寄存器 bit1（bit0=CLR 已有）：0=para（**默认，合规主路径**），1=sym（创新优化分支）；**模式位在 CLR 脉冲时锁存生效**（设计决策2——切换必然全清双核，杜绝脏历史样本）
  - CLR 清零范围（设计决策1）：FIFO（原有）+ 两个核的 clr 输入（新增——核内移位寄存器/流水线全清；fir_core/fir_core_sym 也补 clr 端口）
- CORE_TYPE=0/1/2 行为不变（单核，现有 TB 回归必须保持绿；因核接口加了 clr，现有 TB 实例化处补 `.clr(1'b0)` 或相应连接）

**测试：**
- tb_fir_top 增补：CORE_TYPE=3 实例——①默认模式（para）非对称随机系数黄金回归；②写 CTRL bit1+CLR 切 sym 模式，对称系数黄金回归+吞吐；③CLR 切回 para 再验一次（验证切换无污染）；④大系数集饱和用例；⑤现有 CORE_TYPE=1 用例不动
- 红灯→绿灯；提交：`feat: FIR从机双核模式（通用并行核默认+对称核可选优化分支，CLR语义扩展）`

**验收：** sim_tb_fir_top 全绿（含双模切换与非对称用例）。

---

## 任务 22：系统集成与回归

**Files:** Modify: `rtl/soc/soc_top.v`（`CORE_TYPE(3)`）、固件按需（默认不动）、`tb/tb_integ.v`（增补非对称用例）、`Makefile.fir`（回归目标）

**步骤：**
1. soc_top 的 fir_top 实例改 `#(.CORE_TYPE(3))`；固件不改（对称系数，默认 para 模式跑通即证明兼容；若固件要演示对称优化分支，加一行 CTRL bit1 写 1——可选）
2. tb_integ 增补：**非对称系数系统级用例**——VIP 配 coeff_asym_q15.hex → 1024 样本 → DMA 搬运 → 读回与 golden_asym_q31.hex 比对 <0.1%（这就是评委可能的验收路径，必须系统级证明）
3. tb_soc 回归（固件路径不动，必须保持绿——注意 tb_soc 的 out_buf 黄金比对用 golden_q31.hex，对称系数，para 模式结果与 sym 模式一致，比对应仍全过）
4. **CORE_TYPE 决策矩阵写进 fpga/pango/README.md**（板卡已定案 PGL50H，见设计决策3）：
   | 板卡 | 乘法器预算 | 推荐 CORE_TYPE |
   |---|---|---|
   | **PGL50H（盘古50K，已定案）** | 84 APM | 3（双核：para 82 走 DSP + sym 41 走 LUT；若 LUT 乘法器推断失败→备选手写乘法器结构；再不行→2） |
   | PG2L100H（Logos-2） | ~180 APM | 3（双核全 DSP，零改动切换） |
   | A7-35T（90 DSP） | 紧 | 2（82 乘法器 ≤90） |
   注意：PGL50H 上通用核独占 82/84=97.6% DSP，决赛资源利用率 DSP 项（30% 权重）必然难看——如实记录到指标表，答辩口径"82 乘法器为满足'任意非对称系数+1样本/拍'的架构下限"。
5. 全量回归：`mingw32-make -f Makefile.fir regression`（15 个 TB 全绿）
6. 提交：`feat: 系统集成通用并行FIR核（非对称系数系统级黄金回归）`

**验收：** tb_soc + tb_integ（含非对称）+ 全量回归全绿。

---

## 任务 23：文档口径修正（Q5/Q19）

**Files:** Modify: `docs/report/技术报告.md`、`docs/ppt/汇报PPT大纲.md`、`fpga/pango/top_pgl.v`、`fpga/pango/README.md`、`rtl/fpga/axi_rom.v`（头注释）、`docs/指标记录.md`；Create: `tools/gen_rom_rtl.py`

**步骤：**
1. 技术报告：
   - 误差口径：所有"误差<0.1%"处改为"**相对均方根误差<0.1%**（官方答疑口径），本设计以逐样本相对误差 0.0977% 点态上界验证——数学上强于 RMSE 要求"
   - FIR 章节重写架构描述：基本架构=通用全并行核（82 乘加，任意系数 1 样本/拍，满足答疑#18"支持任意非对称系数"）；对称核=可选优化分支（41 乘加，CTRL 模式位切换，决赛资源创新项）；串行核=资源下限保底
   - 新增"非对称系数验证"测试条目（tb_fir_core_para/tb_fir_top 双模/tb_integ 非对称用例）
   - 4.3 测试矩阵表更新
2. PPT 大纲 P6/P7 同步改写（非对称=合规基本盘，对称=创新分支的口径）
3. top_pgl.v：删 PLL，`assign clk_sys = clk_in;`（50MHz 直连），复位同步保留；注释注明"计分项不使用厂商 IP/原语（答疑#5），主频=板载晶振 50MHz（设计要求 ≥25MHz，目标 50MHz）"
4. README：删 PLL 步骤；CORE_TYPE 决策矩阵（任务 22）；ROM 备选方案改 gen_rom_rtl.py
5. tools/gen_rom_rtl.py：读 hex → 输出纯 RTL case-ROM 模块（无 IP）；axi_rom.v 头注释指向它
6. 指标记录：吞吐口径注明"通用核任意系数 1 样本/拍；对称模式 41 乘加资源优化"
7. 提交：`docs: 合规口径修正（相对均方根误差/非对称架构/无厂商IP流程）`

**验收：** 文档与实现一致（grep 抽查 5 处）；top_pgl 无 PLL 例化。

---

## 任务 24（可选）：固件非对称演示模式

**Files:** Modify: `sw/firmware/fir_demo/fir_demo.c`

若答辩想现场演示"任意系数可配"：固件加一个演示段——CPU 写一套非对称系数（fir_golden.h 增加 asym 数组，由 gen_fir_golden.py 生成）→ 跑一遍 FIR → 打印完成标记（结果核对仍在 TB 侧）。**默认不做**（T13 教训：固件侧长循环校验会触发 CPU 停发取指未解之谜，演示只打印标记不校验）。

---

## 全局注意事项（新会话必读）

- **红灯绿灯**：每任务先跑 TB 看红灯（module not found/断言失败），再实现看绿灯；失败排查用 systematic-debugging，不许手工放行
- **已锁定的裁决**（不要重新推翻，详见台账 `.superpowers/sdd/2026-10-02-fir-soc-implementation/progress.md`）：
  - DMA 固件 BURST=0（多拍 FIXED 读写死锁，T14 实证）；本计划不动 DMA
  - fir_top 的 AW/AR 按 SEL 门控、FIFO 计数 5 位、推/弹互斥更新、R_LAST 组合逻辑——新加的 dual 逻辑不得破坏这些
  - 官方文件（core/ mcu_system/ software/ 等）只读
- **命名**：ACLK/ARESETn；小写+下划线；每模块头注释
- **提交**：每任务一次提交；**不加 Co-Authored-By**
- **验证命令**：`mingw32-make -f Makefile.fir sim_tb_xxx`；全量 `... regression`；固件重建 `cd sw/firmware/fir_demo && mingw32-make all`
- 工具：iverilog 12.0 / GNU Make 4.2.1 / arm-none-eabi-gcc 10.3-2021.10 / Python 3（pypdf、openpyxl 已装；matplotlib 未装，绘图用 tools/plot_waveforms.py 纯标准库 SVG）
- 本计划执行时的台账：新会话用 executing-plans 技能时自动建新 workspace（`.superpowers/sdd/2026-10-19-fir-asymmetric-compliance-fix/`），旧计划台账只读参考
