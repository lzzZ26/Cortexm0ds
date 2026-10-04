# Makefile.fir —— 本项目仿真入口（官方makefile保持不动，故用独立文件名）
# 用法：mingw32-make -f Makefile.fir <目标>
MAKE ?= mingw32-make

# 官方基线（跑官方makefile的compile+run）
baseline:
	$(MAKE) compile
	vvp -n run.out | tail -5

IV     = iverilog
VVP    = vvp
TB_DIR = tb
OUT    = sim_out
RTL    = rtl/ic/ic_axi_master_arb.v rtl/ic/ic_axi_addr_decode.v rtl/ic/ic_axi_slave_mux.v rtl/fir/fir_core.v \
         rtl/fir/fir_top.v rtl/fir/fir_core_sym.v rtl/dma/dma_channel.v \
         rtl/dma/dma_top.v rtl/soc/soc_top.v rtl/soc/axi_sram_sim.v rtl/fpga/axi_rom.v

# 官方模块（只读复用，不改动）——官方makefile MODULES清单去掉本项目未实例化的
# 系统级模块（cmsdk_mcu_system/cmsdk_mcu/clkctrl/pin_mux/clock_gate/
# sysctrl/sysrom_table/官方addr_decode，后者由ic_axi_addr_decode取代；
# cmsdk_axi_sram由本项目axi_sram_sim取代——官方ram_beh写锁存带读写互斥，
# 读在途时写AW被静默丢弃（B仍OKAY），详见axi_sram_sim.v；
# cmsdk_axi_slave_mux由本项目ic_axi_slave_mux取代——官方mux的B/R路由
# 选择寄存器按VALID电平锁存（非握手），多主并发下路由被其它主机的请求
# 刷新，DMA收到错误从机的R/R_LAST，详见ic_axi_slave_mux.v）
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
          ./mcu_system/cmsdk_axi_gpio/cmsdk_axi_gpio.v \
          ./mcu_system/cmsdk_axi_gpio/cmsdk_axi_to_iop.v \
          ./mcu_system/cmsdk_axi_gpio/cmsdk_iop_gpio.v \
          ./mcu_system/cmsdk_axi_memory/cmsdk_axi_flash.v \
          ./mcu_system/cmsdk_axi_memory/cmsdk_axi_ram_beh.v \
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
          ./mcu_system/cmsdk_mcu_system/cmsdk_axi_default_slave.v

INCPATH = -I$(TB_DIR)/common -I./core/cortexm0ds/ \
          -I./core/cortexm0_integration/ -I./core/cortexm0_dap/ \
          -I./core/models/ -I./mcu_system/cmsdk_axi_to_apb/ \
          -I./mcu_system/cmsdk_axi_memory/ \
          -I./mcu_system/cmsdk_apb_dualtimers/ \
          -I./mcu_system/cmsdk_apb_watchdog/ \
          -I./mcu_system/cmsdk_axi_slave_mux/

$(OUT):
	mkdir -p $(OUT)

# 用法: make sim_tb_vip_smoke  （编译+运行，自检失败即非零退出）
sim_%: $(OUT)
	$(IV) -g2001 -o $(OUT)/$*.vvp -s $* $(INCPATH) $(TB_DIR)/$*.v \
	     $(TB_DIR)/common/axi_master_vip.v $(TB_DIR)/common/axi_slave_mem.v \
	     $(TB_DIR)/common/axi_checker.v $(TB_DIR)/common/uart_bfm.v \
	     $(TB_DIR)/common/tb_clkreset.v $(RTL) $(REF_RTL)
	$(VVP) -n $(OUT)/$*.vvp

# MEM_IMPL=1冒烟（axi_rom FPGA路径）：与sim_tb_soc_smoke同源，仅参数不同
sim_tb_soc_smoke_rom: $(OUT)
	$(IV) -g2001 -o $(OUT)/tb_soc_smoke_rom.vvp -s tb_soc_smoke \
	     -Ptb_soc_smoke.MEM_IMPL=1 $(INCPATH) $(TB_DIR)/tb_soc_smoke.v \
	     $(TB_DIR)/common/axi_master_vip.v $(TB_DIR)/common/axi_slave_mem.v \
	     $(TB_DIR)/common/axi_checker.v $(TB_DIR)/common/uart_bfm.v \
	     $(TB_DIR)/common/tb_clkreset.v $(RTL) $(REF_RTL)
	$(VVP) -n $(OUT)/tb_soc_smoke_rom.vvp
