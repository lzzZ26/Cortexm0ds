# FPGA工程建立步骤（Pango Design Suite / 紫光同创 Logos-2 PG2L100H）

> 状态：**工程文件与RTL已就绪，未上板**（用户裁定：仿真正确即完成任务）。
> 板级验证按以下步骤由团队在板卡到位后执行。

## 1. 前置

- 开发板：紫光同创 Logos-2 PG2L100H 或资源相当板（队伍自备）
- Pango Design Suite（版本按板卡厂商要求）
- 固件：`sw/firmware/fir_demo/fir_demo.hex`（gcc编译产物，`cd sw/firmware/fir_demo && mingw32-make all`）

## 2. 建工程

1. 新建工程 → 器件选 **PG2L100H**（封装/速度级按实物丝印）→ 语言 Verilog；
2. 添加源文件：
   - 本项目 RTL：`rtl/ic/*.v rtl/fir/*.v rtl/dma/*.v rtl/soc/*.v rtl/fpga/axi_rom.v`
   - 板级顶层：`fpga/pango/top_pgl.v`
   - 官方 RTL 清单：见 `Makefile.fir` 的 REF_RTL（core/ 与 mcu_system/ 下全部列出文件）
3. 添加约束 `fpga/pango/constraints.fdc`，引脚号按实物板卡原理图替换占位符；
4. 配置 PLL IP（50→100MHz，按 PDS 模板修改 top_pgl.v 中的 GTP_CLKPLL 例化），
   或先用 50MHz 直连验证功能（把 clk_sys 直接接 clk_in）；
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
  按 `rtl/fpga/axi_rom.v` 头注释改用厂商 IP 生成 `.coe`（接口不变）。
- 仿真已验证 ROM 路径（`mingw32-make -f Makefile.fir sim_tb_soc_smoke_rom`，
  CPU 从 axi_rom 启动输出 Hello world），FPGA 侧仅剩工具链与板级流程。
